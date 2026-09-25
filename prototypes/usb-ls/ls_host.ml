(* Independent low-speed USB host model, written from the USB 2.0 specification (chapter 7 and
   8), not from any of the devices in this directory.

   Line states are J, K and SE0. At low speed J is D- high (dp 0, dm 1) and K is D+ high; the
   idle bus is J because the device's pull-up sits on D-. [phy] maps states to pins.

   Timing: the simulation clock is 60 MHz and a nominal low-speed bit is 40 clocks. The host has
   its own clock, off by [ppm] parts per million (the tests use up to +-15,000, i.e. the +-1.5 %
   that a low-speed source may be off), so its bit period is 40 * (1 + ppm / 1e6) clocks and
   symbol boundaries fall on the clock nearest the ideal instant.

   Receiving: the host sees the device's line as a list of (clock, state) runs and decodes it by
   run length in its own bit time, the way a DPLL that resynchronises on every edge does. It
   checks each run's length against a whole number of bits (jitter bound [jitter_clocks]), the
   SE0 of the EOP (between 1.5 and 2.5 bits here, generous around the nominal 2), NRZI, bit
   stuffing (six ones, then a zero that is dropped; a seventh one is an error) and whole bytes. *)

type line = J | K | SE0

let clocks_per_bit = 40

let crc5 bits = List.fold_left (fun c b -> if (c land 1) lxor b = 1 then (c lsr 1) lxor 0x14 else c lsr 1) 0x1F bits
let crc16 bits = List.fold_left (fun c b -> if (c land 1) lxor b = 1 then (c lsr 1) lxor 0xA001 else c lsr 1) 0xFFFF bits
let bits_of_byte x = List.init 8 (fun i -> (x lsr i) land 1)
let bits_of_bytes bs = List.concat_map bits_of_byte bs

let pid_out = 0xE1 and pid_in = 0x69 and pid_setup = 0x2D
let pid_data0 = 0xC3 and pid_data1 = 0x4B and pid_ack = 0xD2 and pid_nak = 0x5A and pid_stall = 0x1E

let token ?(corrupt_crc = false) pid ~addr ~ep =
  let f = addr lor (ep lsl 7) in
  let c = (lnot (crc5 (List.init 11 (fun i -> (f lsr i) land 1)))) land 0x1F in
  let c = if corrupt_crc then c lxor 0x04 else c in
  [ pid; f land 0xFF; (f lsr 8) lor (c lsl 3) ]

let data_packet ?(corrupt_crc = false) pid payload =
  let c = (lnot (crc16 (bits_of_bytes payload))) land 0xFFFF in
  let c = if corrupt_crc then c lxor 0x0100 else c in
  pid :: payload @ [ c land 0xFF; c lsr 8 ]

let crc16_ok bytes_after_pid = crc16 (bits_of_bytes bytes_after_pid) = 0xB001

(* bytes -> line states, one per bit: sync (0x80 LSB first), NRZI with bit stuffing, EOP.
   [skip_stuff] omits the n-th stuff bit (a control that a receiver must reject). *)
let encode ?skip_stuff bytes =
  let bits = bits_of_bytes (0x80 :: bytes) in
  let out = ref [] and cur = ref J and ones = ref 0 and nstuff = ref 0 in
  let flip () = cur := (match !cur with J -> K | _ -> J) in
  let emit b =
    if b = 1 then incr ones else ones := 0;
    if b = 0 then flip ();
    out := !cur :: !out;
    if !ones = 6 then begin
      ones := 0;
      if Some !nstuff <> skip_stuff then begin flip (); out := !cur :: !out end;
      incr nstuff
    end in
  List.iter emit bits;
  List.rev !out @ [ SE0; SE0; J ]

(* how many stuff bits a packet carries: used to pick packets for the missing-stuff control *)
let stuff_count bytes =
  let n = ref 0 and ones = ref 0 in
  List.iter (fun b -> if b = 1 then (incr ones; if !ones = 6 then (incr n; ones := 0)) else ones := 0)
    (bits_of_bytes (0x80 :: bytes));
  !n

(* a keep-alive is a bare low-speed EOP *)
let keep_alive = [ SE0; SE0; J ]

let phy = function J -> (0, 1) | K -> (1, 0) | SE0 -> (0, 0)
let of_pins dp dm = match dp, dm with 0, 1 -> Some J | 1, 0 -> Some K | 0, 0 -> Some SE0 | _ -> None

(* symbol boundaries on the simulation clock for a host off by [ppm] *)
let bit_period ppm = float_of_int clocks_per_bit *. (1.0 +. float_of_int ppm /. 1e6)

(* Lay out [states] from clock [start] with the host's bit period. Returns an array of
   (first clock, state) and the clock just after the last state. *)
let schedule ~ppm ~start states =
  let t = bit_period ppm in
  let n = List.length states in
  let starts = Array.init (n + 1) (fun i -> start + int_of_float (Float.round (float_of_int i *. t))) in
  (Array.of_list (List.mapi (fun i s -> (starts.(i), s)) states), starts.(n))

(* ---------- receiving ---------- *)

type rx_result =
  | Packet of int list
  | Bad of string

let jitter_clocks = 8

(* [runs] are (length in clocks, state) of the device's transmission starting at its SOP (the
   first K) and ending with the J after SE0. [t] is the host's bit period. *)
let decode_runs ~t (runs : (int * line) list) =
  let nbits len = int_of_float (Float.round (float_of_int len /. t)) in
  let err = ref None in
  let fail s = if !err = None then err := Some s in
  let states = ref [] and ended = ref false in
  List.iter (fun (len, s) ->
    if not !ended then
      match s with
      | SE0 ->
        let b = float_of_int len /. t in
        if b < 1.5 || b > 2.5 then fail (Printf.sprintf "EOP SE0 of %.2f bits" b);
        ended := true
      | _ ->
        let n = nbits len in
        if n < 1 then fail (Printf.sprintf "runt of %d clocks" len)
        else if abs (len - int_of_float (Float.round (float_of_int n *. t))) > jitter_clocks then
          fail (Printf.sprintf "run of %d clocks is not a whole number of bits" len);
        for _ = 1 to max n 0 do states := s :: !states done) runs;
  if not !ended then fail "no EOP";
  let states = List.rev !states in
  (* NRZI: the line before SOP is J *)
  let bits = ref [] and prev = ref J in
  List.iter (fun s -> bits := (if s = !prev then 1 else 0) :: !bits; prev := s) states;
  let bits = List.rev !bits in
  (* sync: 0000000 1 *)
  let rec take n l = if n = 0 then Some ([], l) else match l with [] -> None | x :: r -> Option.map (fun (a, b) -> (x :: a, b)) (take (n - 1) r) in
  (match take 8 bits with
   | Some (sync, rest) when sync = [ 0; 0; 0; 0; 0; 0; 0; 1 ] ->
     let out = ref [] and ones = ref 1 and skip = ref false in
     List.iter (fun b ->
       if !skip then begin skip := false; ones := 0; if b = 1 then fail "missing stuff bit" end
       else begin
         out := b :: !out;
         if b = 1 then incr ones else ones := 0;
         if !ones = 6 then (skip := true; ones := 0)
       end) rest;
     (* a stuff bit may end the packet (six ones just before EOP); that is legal *)
     let bits = List.rev !out in
     let n = List.length bits in
     if n mod 8 <> 0 then fail (Printf.sprintf "%d bits is not whole bytes" n);
     let bytes = List.init (n / 8) (fun k -> List.fold_left (fun acc i -> acc lor (List.nth bits (8 * k + i) lsl i)) 0 (List.init 8 Fun.id)) in
     (match !err with None -> Packet bytes | Some e -> Bad e)
   | _ -> Bad "bad sync")

(* self-checks against bytes from the specification's examples *)
let self_check () =
  assert (token pid_setup ~addr:0 ~ep:0 = [ 0x2D; 0x00; 0x10 ]);
  assert (data_packet pid_data0 [ 0x80; 0x06; 0x00; 0x01; 0x00; 0x00; 0x40; 0x00 ]
          = [ 0xC3; 0x80; 0x06; 0x00; 0x01; 0x00; 0x00; 0x40; 0x00; 0xDD; 0x94 ]);
  (* round trip through the run-length decoder, with stuffing *)
  let pkt = [ 0xC3; 0xFF; 0xFF; 0x7E; 0x3F ] in
  let states = encode pkt in
  let rec runs acc = function
    | [] -> List.rev acc
    | s :: r -> (match acc with (n, s') :: a when s' = s -> runs ((n + 1, s) :: a) r | _ -> runs ((1, s) :: acc) r) in
  let rs = List.map (fun (n, s) -> (n * clocks_per_bit, s)) (runs [] states) in
  (* drop the idle J before SOP: encode starts with K for sync's first zero *)
  assert (decode_runs ~t:40.0 rs = Packet pkt);
  let bad = encode ~skip_stuff:0 pkt in
  let rs = List.map (fun (n, s) -> (n * clocks_per_bit, s)) (runs [] bad) in
  assert (match decode_runs ~t:40.0 rs with Bad _ -> true | Packet _ -> false)
