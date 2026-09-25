(* A behavioural CAN 2.0A stand-in, written from the specification, until the proto-ps2-can
   branch's node firmware can run on the same core (see README: the two ISA variants both use
   opcodes E and F). It produces what that branch's RX thread reports, in the order it reports it,
   as analyser events:

   - one code per bit time on the bus (per sampled bit): bit 0 bus level, bit 1 node A's TXD,
     bit 2 node B's TXD, bit 3 "a stuff bit, or the bit where a node lost arbitration";
   - frame events: 0xA1 c1 c2 c3 after the control field, with c1..c3 packed as the branch's
     DATA tag packs them (3 bits SOF ID10 ID9; ID8..ID1; ID0 RTR IDE r0 DLC3..0); 0xA2 status at the
     end of the frame (0 ok, 1 stuff error).

   Bits: SOF, ID, RTR, IDE, r0, DLC, data, CRC-15 (0x4599) are stuffed (a complement after five
   equal bits); then CRC delimiter, ACK slot (driven dominant by a third node), ACK delimiter,
   EOF, 3 bits of intermission. Arbitration: nodes A and B may start together; the bus is the AND
   of the TXDs; a node that sends recessive and reads dominant in the arbitration field stops
   driving. Error injection: a frame can carry six equal bits where a stuff bit belongs; the
   receivers answer with an error flag (6 dominant) and delimiter (8 recessive). *)

let crc15 bits =
  List.fold_left (fun crc b ->
    let nxt = b lxor ((crc lsr 14) land 1) in
    let crc = (crc lsl 1) land 0x7FFF in
    if nxt = 1 then crc lxor 0x4599 else crc) 0 bits

let bits_of v n = List.init n (fun i -> (v lsr (n - 1 - i)) land 1)

type frame = { id : int; rtr : int; data : int list; stuff_error_at : int option }

(* the unstuffed bits SOF..CRC, and the header fields for the events *)
let raw_bits f =
  let dlc = List.length f.data in
  let pre = [ 0 ] @ bits_of f.id 11 @ [ f.rtr; 0; 0 ] @ bits_of dlc 4 @ List.concat_map (fun d -> bits_of d 8) f.data in
  pre @ bits_of (crc15 pre) 15

(* stuffed stream: list of (bit, is_stuff); an injected error replaces the stuff bit at the
   [k]-th stuff position (or, if there is none, appends five more equal bits) by the same level *)
let stuff ?inject bits =
  let out = ref [] and run = ref 0 and last = ref (-1) and nstuff = ref 0 and broke = ref false in
  List.iter (fun b ->
    if not !broke then begin
      out := (b, false) :: !out;
      if b = !last then incr run else (run := 1; last := b);
      if !run = 5 then begin
        (match inject with
         | Some k when k = !nstuff -> out := (b, false) :: !out; broke := true
         | _ -> out := (1 - b, true) :: !out; run := 1; last := 1 - b);
        incr nstuff
      end
    end) bits;
  List.rev !out, !broke

type bitev = { level : int; ta : int; tb : int; st : bool }

(* One transmission slot: node A's frame (or none) and node B's frame (or none) start together.
   Returns the bit events, the frame events with the index of the bit after which they are
   reported, and the frame that won. *)
let transmit ?a ?b () =
  let enc f = match f with
    | None -> None
    | Some f -> let s, broke = stuff ?inject:f.stuff_error_at (raw_bits f) in Some (f, Array.of_list s, broke) in
  let ea = enc a and eb = enc b in
  let bitevs = ref [] and fevs = ref [] in
  let arb_end = 1 + 11 + 1 in                     (* SOF, ID, RTR: the arbitration field, unstuffed *)
  let alive_a = ref (ea <> None) and alive_b = ref (eb <> None) in
  let pos = ref 0 and unstuffed = ref 0 in
  let winner = ref None in
  let len x = match x with Some (_, s, _) -> Array.length s | None -> 0 in
  let n = max (len ea) (len eb) in
  let header_sent = ref false in
  let err = ref false in
  while !pos < n && not !err do
    let bit_of x alive = match x with Some (_, s, _) when !alive && !pos < Array.length s -> fst s.(!pos) | _ -> 1 in
    let st_of x alive = match x with Some (_, s, _) when !alive && !pos < Array.length s -> snd s.(!pos) | _ -> false in
    let ta = bit_of ea alive_a and tb = bit_of eb alive_b in
    let bus = ta land tb in
    let st = st_of ea alive_a || st_of eb alive_b in
    bitevs := { level = bus; ta; tb; st } :: !bitevs;
    if not st then incr unstuffed;
    if !unstuffed <= arb_end then begin
      let lost = (!alive_a && ta = 1 && bus = 0) || (!alive_b && tb = 1 && bus = 0) in
      if !alive_a && ta = 1 && bus = 0 then alive_a := false;
      if !alive_b && tb = 1 && bus = 0 then alive_b := false;
      (* mark the bit where arbitration was decided (never a stuff bit: the streams differ there) *)
      if lost then bitevs := { (List.hd !bitevs) with st = true } :: List.tl !bitevs
    end;
    (* after the control field (SOF..DLC = 19 unstuffed bits) report the header of whoever is sending *)
    if !unstuffed = 19 && not st && not !header_sent then begin
      header_sent := true;
      let f = match (!alive_a, ea), (!alive_b, eb) with
        | (true, Some (f, _, _)), _ -> f | _, (true, Some (f, _, _)) -> f | _ -> assert false in
      winner := Some f;
      let c1 = (f.id lsr 9) land 3 in
      let c2 = (f.id lsr 1) land 0xFF in
      let c3 = ((f.id land 1) lsl 7) lor (f.rtr lsl 6) lor (List.length f.data land 15) in
      fevs := !fevs @ [ (List.length !bitevs - 1, [ 0xA1; c1; c2; c3 ]) ]
    end;
    incr pos;
    (* a broken stream ends with the sixth equal bit: the receivers flag it *)
    let broke_now = match (!alive_a, ea), (!alive_b, eb) with
      | (true, Some (_, s, true)), _ | _, (true, Some (_, s, true)) -> !pos = Array.length s
      | _ -> false in
    if broke_now then err := true
  done;
  if !err then begin
    for _ = 1 to 6 do bitevs := { level = 0; ta = 1; tb = 1; st = false } :: !bitevs done;
    for _ = 1 to 8 do bitevs := { level = 1; ta = 1; tb = 1; st = false } :: !bitevs done;
    fevs := !fevs @ [ (List.length !bitevs - 1, [ 0xA2; 1 ]) ]
  end else begin
    (* CRC delimiter, ACK slot (another node acknowledges), ACK delimiter, EOF, intermission *)
    let tail = [ 1; 0; 1 ] @ List.init 7 (fun _ -> 1) @ [ 1; 1; 1 ] in
    List.iter (fun l -> bitevs := { level = l; ta = 1; tb = 1; st = false } :: !bitevs) tail;
    fevs := !fevs @ [ (List.length !bitevs - 1, [ 0xA2; 0 ]) ]
  end;
  List.rev !bitevs, !fevs, !winner

let code e = e.level lor (e.ta lsl 1) lor (e.tb lsl 2) lor ((if e.st then 1 else 0) lsl 3)
