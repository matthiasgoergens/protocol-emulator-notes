(* Independent CAN models: a wired-AND bus with propagation delays, and a reference node.

   Written from the classic CAN description (Bosch CAN 2.0 part A; ISO 11898-1 bit timing), not
   from the firmware, and deliberately in a different style: the reference node's bit timing is a
   time-quantum counter with sync / prop / phase1 / phase2 segments and the standard phase-error
   rules, where the firmware uses deadline windows; its encoder stuffs on the fly as bits go out,
   where the firmware's host driver stuffs a whole frame beforehand. *)

(* ------------------------------------------------------------------ bus *)
module Bus = struct
  (* each attached transmitter has a history of (time, level); node i's level reaches node j after
     delay.(i) + delay.(j) (so a node hears itself after twice its delay) *)
  type t = { hist : (int * int) list array; delay : int array }
  let create delays = { hist = Array.map (fun _ -> [ (min_int / 2, 1) ]) delays; delay = delays }
  let drive b i ~now level =
    match b.hist.(i) with
    | (_, l) :: _ when l = level -> ()
    | h ->
      (* keep 20 us of history *)
      let rec prune n = function
        | (t, l) :: rest -> if t < now - Sim.us 20. && n > 0 then [ (t, l) ] else (t, l) :: prune (n + 1) rest
        | [] -> [] in
      b.hist.(i) <- (now, level) :: prune 0 h
  let level_at h t = let rec f = function (ti, l) :: rest -> if ti <= t then l else f rest | [] -> 1 in f h
  let rx b j ~now =
    let v = ref 1 in
    Array.iteri (fun i h -> if level_at h (now - b.delay.(i) - b.delay.(j)) = 0 then v := 0) b.hist;
    !v
end

(* ------------------------------------------------------------------ reference encoder *)
type frame = { id : int; rtr : bool; dlc : int; data : int list }

let pp_frame f =
  Printf.sprintf "%03x%s[%d]%s" f.id (if f.rtr then "r" else "") f.dlc
    (String.concat "" (List.map (Printf.sprintf " %02x" ) f.data))

(* destuffed bits SOF .. data, then the CRC: computed by long division here *)
let ref_crc bits =
  let reg = ref 0 in
  List.iter (fun b ->
    let top = (!reg lsr 14) land 1 in
    reg := (!reg lsl 1) land 0x7FFF;
    if top lxor b = 1 then reg := !reg lxor 0x4599) bits;
  !reg

let ref_bits f =
  let push v w acc = let r = ref acc in for i = w - 1 downto 0 do r := ((v lsr i) land 1) :: !r done; !r in
  let acc = push f.dlc 4 (push 0 1 (push 0 1 (push (if f.rtr then 1 else 0) 1 (push f.id 11 [ 0 ])))) in
  let n = if f.rtr then 0 else min 8 f.dlc in
  let acc = List.fold_left (fun a (i, b) -> if i < n then push b 8 a else a) acc (List.mapi (fun i b -> i, b) f.data) in
  let body = List.rev acc in
  body @ List.rev (push (ref_crc body) 15 [])

(* ------------------------------------------------------------------ reference node *)
type err = Stuff | Crc | Form | Bit | Ack_err
let pp_err = function Stuff -> "stuff" | Crc -> "crc" | Form -> "form" | Bit -> "bit" | Ack_err -> "ack"

type rx_phase =
  | Integrating of int          (* recessive bits seen *)
  | Idle
  | Stuffed                     (* SOF .. CRC *)
  | Delim | Ack_slot | Ack_delim
  | Eof of int
  | Inter of int
  | Err_flag of int             (* dominant bits sent *)
  | Err_wait                    (* waiting for the bus to go recessive *)
  | Err_delim of int

type t = {
  bus : Bus.t; idx : int; name : string;
  prop : int; ph1 : int; ph2 : int; sjw : int;
  (* bit timing *)
  mutable pos : int; mutable len : int; mutable sample_at : int;
  mutable prev_level : int; mutable synced : bool; mutable last_sample : int;
  (* receive *)
  mutable phase : rx_phase;
  mutable rbits : int list;               (* destuffed bits of the frame, newest first *)
  mutable nrb : int;
  mutable run : int; mutable rlast : int; mutable stuff_next : bool;
  mutable expect : int;                   (* destuffed bits expected through the CRC, once known *)
  mutable crc_ok : bool;
  mutable pending_err : err option;       (* error flag starts at the next bit *)
  (* transmit *)
  mutable queue : frame list;
  mutable tx_on : bool;                   (* transmitting the head of queue *)
  mutable tx_bits : int array; mutable tx_i : int; mutable tx_run : int; mutable tx_last : int;
  mutable tx_bit : int;                   (* level driven during the current bit *)
  mutable tx_stuffing : bool;
  mutable ack_drive : bool;
  (* logs *)
  mutable received : (int * frame * bool * bool) list;  (* time, frame, crc ok, own *)
  mutable errors : (int * err) list;
  mutable sent : (int * frame) list;
  mutable lost : int;
  mutable retries : int;
  mutable now : int;
  fault_skip_ack : bool;
}

let create ~bus ~idx ?(name = "ref") ?(prop = 5) ?(ph1 = 6) ?(ph2 = 4) ?(sjw = 3) ?(skip_ack = false) () =
  let len = 1 + prop + ph1 + ph2 in
  { bus; idx; name; prop; ph1; ph2; sjw; pos = 0; len; sample_at = 1 + prop + ph1; prev_level = 1;
    synced = false; last_sample = 1; phase = Integrating 0; rbits = []; nrb = 0; run = 0; rlast = 1;
    stuff_next = false; expect = max_int; crc_ok = false; pending_err = None; queue = []; tx_on = false;
    tx_bits = [||]; tx_i = 0; tx_run = 0; tx_last = 1; tx_bit = 1; tx_stuffing = false; ack_drive = false;
    received = []; errors = []; sent = []; lost = 0; retries = 0; now = 0; fault_skip_ack = skip_ack }

let nominal n = 1 + n.prop + n.ph1 + n.ph2

let error n e =
  n.errors <- (n.now, e) :: n.errors;
  n.pending_err <- Some e;
  if n.tx_on then (n.tx_on <- false; n.retries <- n.retries + 1)

let frame_of_bits bits =
  let a = Array.of_list bits in
  let v i w = let r = ref 0 in for k = 0 to w - 1 do r := (!r lsl 1) lor a.(i + k) done; !r in
  let id = v 1 11 and rtr = a.(12) = 1 and dlc = v 15 4 in
  let nb = if rtr then 0 else min 8 dlc in
  { id; rtr; dlc; data = List.init nb (fun i -> v (19 + 8 * i) 8) }

(* a destuffed bit of the stuffed region *)
let rx_bit n v =
  n.rbits <- v :: n.rbits; n.nrb <- n.nrb + 1;
  if n.nrb = 19 then begin
    let a = Array.of_list (List.rev n.rbits) in
    let rtr = a.(12) = 1 and dlc = (a.(15) lsl 3) lor (a.(16) lsl 2) lor (a.(17) lsl 1) lor a.(18) in
    n.expect <- 19 + (if rtr then 0 else 8 * min 8 dlc) + 15
  end;
  if n.nrb = n.expect then begin
    let bits = List.rev n.rbits in
    let body = List.filteri (fun i _ -> i < n.expect - 15) bits in
    let crc = List.fold_left (fun a b -> (a lsl 1) lor b) 0 (List.filteri (fun i _ -> i >= n.expect - 15) bits) in
    n.crc_ok <- crc = ref_crc body;
    n.phase <- Delim
  end

let start_frame n =
  n.phase <- Stuffed; n.rbits <- []; n.nrb <- 0; n.run <- 0; n.rlast <- 1; n.stuff_next <- false;
  n.expect <- max_int

(* the sampled level at the sample point *)
let on_sample n v =
  (* bit monitoring for our own transmission *)
  if n.tx_on && v <> n.tx_bit then begin
    match n.phase with
    | Stuffed when n.tx_bit = 1 && v = 0 && n.nrb <= 12 && not n.stuff_next -> n.tx_on <- false; n.lost <- n.lost + 1
    | Ack_slot -> ()
    | _ -> error n Bit
  end;
  (match n.phase with
   | Integrating k -> if v = 1 then (if k + 1 >= 11 then n.phase <- Idle else n.phase <- Integrating (k + 1)) else n.phase <- Integrating 0
   | Idle -> ()   (* SOF comes through the hard sync *)
   | Stuffed ->
     if n.stuff_next then begin
       if v = n.rlast then error n Stuff else (n.rlast <- v; n.run <- 1; n.stuff_next <- false)
     end else begin
       if n.nrb = 0 && v = 1 then n.phase <- Idle   (* SOF glitch *)
       else begin
         if v = n.rlast then n.run <- n.run + 1 else (n.rlast <- v; n.run <- 1);
         if n.run = 5 then n.stuff_next <- true;
         rx_bit n v
       end
     end;
     (* a stuff bit may follow the last CRC bit: stay until it is taken *)
     if n.phase = Delim && n.stuff_next then n.phase <- Stuffed
   | Delim -> if v = 0 then error n Form else n.phase <- Ack_slot
   | Ack_slot ->
     if n.tx_on && v = 1 then error n Ack_err;
     n.phase <- Ack_delim
   | Ack_delim ->
     if v = 0 then error n Form
     else if not n.crc_ok then error n Crc
     else n.phase <- Eof 0
   | Eof k ->
     if v = 0 then error n Form
     else if k = 6 then begin
       let f = frame_of_bits (List.rev n.rbits) in
       n.received <- (n.now, f, n.crc_ok, n.tx_on) :: n.received;
       if n.tx_on then (n.sent <- (n.now, f) :: n.sent; n.queue <- List.tl n.queue; n.tx_on <- false);
       n.phase <- Inter 0
     end else n.phase <- Eof (k + 1)
   | Inter k -> if k = 2 then n.phase <- Idle else n.phase <- Inter (k + 1)
   | Err_flag _ -> ()
   | Err_wait -> if v = 1 then n.phase <- Err_delim 1
   | Err_delim k -> if v = 1 then (if k + 1 >= 8 then n.phase <- Inter 0 else n.phase <- Err_delim (k + 1)));
  (* the stuffed region ends once the CRC is in and no stuff bit is due *)
  (match n.phase with Stuffed when n.nrb = n.expect && not n.stuff_next -> n.phase <- Delim | _ -> ())

(* the start of a bit: choose what to drive *)
let on_bit_start n ~hard =
  if hard then begin
    (* SOF: every node hard-syncs; a node with a pending frame transmits in it (possibly joining) *)
    start_frame n;
    if n.queue <> [] then begin
      n.tx_on <- true; n.tx_bits <- Array.of_list (ref_bits (List.hd n.queue)); n.tx_i <- 1;
      n.tx_run <- 1; n.tx_last <- 0; n.tx_bit <- 0
    end else n.tx_bit <- 1
  end else begin
    (match n.pending_err with
     | Some _ -> n.pending_err <- None; n.phase <- Err_flag 0; n.ack_drive <- false
     | None -> ());
    n.ack_drive <- false;
    match n.phase with
    | Err_flag k -> n.tx_bit <- 0; if k + 1 >= 6 then n.phase <- Err_wait else n.phase <- Err_flag (k + 1)
    | Idle when n.queue <> [] ->
      (* start of frame: drive SOF; the hard sync on our own edge makes it the SOF bit *)
      n.tx_bit <- 0
    | Stuffed when n.tx_on ->
      if n.tx_run = 5 then (n.tx_last <- 1 - n.tx_last; n.tx_run <- 1; n.tx_bit <- n.tx_last)
      else if n.tx_i < Array.length n.tx_bits then begin
        let b = n.tx_bits.(n.tx_i) in
        n.tx_i <- n.tx_i + 1;
        if b = n.tx_last then n.tx_run <- n.tx_run + 1 else (n.tx_last <- b; n.tx_run <- 1);
        n.tx_bit <- b
      end else n.tx_bit <- 1
    | Ack_slot when (not n.tx_on) && n.crc_ok && not n.fault_skip_ack -> n.tx_bit <- 0; n.ack_drive <- true
    | _ -> n.tx_bit <- 1
  end;
  Bus.drive n.bus n.idx ~now:n.now n.tx_bit

(* one time quantum *)
let tick n now =
  n.now <- now;
  let level = Bus.rx n.bus n.idx ~now in
  let edge = n.prev_level = 1 && level = 0 in
  let hard = ref false in
  if edge then begin
    (match n.phase with
     | Idle | Inter 2 -> n.pos <- 0; n.len <- nominal n; n.sample_at <- 1 + n.prop + n.ph1; n.synced <- true; hard := true
     | _ ->
       let own_dominant = n.tx_on && n.tx_bit = 0 in
       if (not n.synced) && n.last_sample = 1 && not own_dominant then begin
         n.synced <- true;
         if n.pos = 0 then ()
         else if n.pos <= n.sample_at then begin
           (* late edge: phase error pos; lengthen phase 1 *)
           let a = min n.pos n.sjw in
           n.sample_at <- n.sample_at + a; n.len <- n.len + a
         end else begin
           (* early edge (after the sample point): shorten phase 2 *)
           let e = n.len - n.pos in
           if e <= n.sjw then (n.pos <- 0; n.len <- nominal n; n.sample_at <- 1 + n.prop + n.ph1)
           else n.len <- n.len - n.sjw
         end
       end)
  end;
  if n.pos = 0 then on_bit_start n ~hard:!hard;
  if n.pos = n.sample_at then (on_sample n level; n.last_sample <- level; n.synced <- false);
  n.pos <- n.pos + 1;
  if n.pos >= n.len then (n.pos <- 0; n.len <- nominal n; n.sample_at <- 1 + n.prop + n.ph1);
  n.prev_level <- level
