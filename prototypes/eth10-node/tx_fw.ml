(* 10BASE-T transmit as sequencer firmware, complete: differential drive on two pins, frames with
   TP_IDL, and normal link pulses (NLP) while idle. Base ISA plus master's sub-slot bits (q); no new
   instructions.

   Pins. Output pin 0 is TD+, pin 1 is TD-; both are driven all the time (output enable set once at
   reset). A positive half-bit is (TD+, TD-) = (1, 0), a negative one (0, 1), idle (0, 0), so the
   differential is +V, -V or 0. Input pin 0 is [start] (a frame is ready), input pins 4..7 are
   [end_t] for thread t (the byte just handed to thread t is its last).

   Schedule. As in ../sequencer-ethernet: half-bit k starts at clock S + 3k (S a multiple of 4), and
   thread (3k) mod 4 owns it. Two pins cannot change in one instruction, so each thread also writes
   TD- for the half-bit after its own, one clock later (clock S + 3k + 4 is the same thread's next
   slot). TD+ is written with sub-slot q = 3 and TD- with q = 0, so on the four-phase output stage
   the two legs change a quarter clock apart (4.2 ns); on the plain clock grid they change a clock
   apart. Either way the differential passes through zero for that moment at every transition and
   the zero crossing is on an exact grid. Per thread and 12 clocks: one TD+ write, one TD- write,
   one free slot.

   Accumulator layout: bit 2i is TD+ of pair i, bit 2i+1 is TD- of pair i; four pairs per byte, so
   one IN per four pairs, i.e. per byte of the wire across the four threads.

   Idle: every thread runs the same loop of [nlp_outer] waits on [start] with a deadline of
   [nlp_inner] slots. When all waits time out, thread 0 raises TD+ (q = 3) and thread 2 lowers it in
   its next slot, 6 clocks later: a 100 ns positive pulse. The timer restarts after every pulse and
   after every frame. [start] must change only on clocks that are multiples of 4 (a round
   boundary), so all four threads see the same value in the same round; the feeder guarantees it.

   End of frame: TP_IDL and the return to idle are data (TD+ high for [tp_idl] half-bits after the
   last bit, then idle levels), so the firmware does not time them. Each thread checks its [end_t]
   pin once per byte with WAITP at deadline 0, which is a one-slot conditional branch, and leaves
   the loop after its last byte, padded so all four reach the idle loop in the same slot. *)

let h = 3
let pin_start = 0
let pin_end t = 4 + t

(* the first TD+ slot of thread t, relative to S/4: the first k >= 0 with 3k = t (mod 4) is at clock
   S + 3k, which is slot S/4 + (3k + ... ) *)
let k0 t = let rec f k = if (3 * k) mod 4 = t then k else f (k + 1) in f 0
let first_slot t = (3 * k0 t - t) / 4   (* 0, 2, 1, 0 for t = 0..3 *)

type params = {
  nlp_outer : int;      (* number of deadline waits per link-pulse period *)
  nlp_inner : int;      (* deadline per wait, slots (at most 4095) *)
  nlp_width_slots : int; (* thread 2 lowers TD+ this many of its slots after thread 0 raised it:
                            width = 4 * slots + 2 clocks; 1 gives 6 clocks = 100 ns *)
  tp_idl : int;         (* TP_IDL, half-bits of TD+ high after the last bit *)
  ipg_slots : int;      (* deadline wait after a frame before the next may start: the firmware,
                           not the feeder, keeps the 9.6 us inter-packet gap *)
}

(* 16 ms at 60 MHz is 240,000 slots per thread; measured with the checker, see main.ml *)
let default = { nlp_outer = 60; nlp_inner = 3990; nlp_width_slots = 1; tp_idl = 6; ipg_slots = 113 }

let sho_p0 = Isa.sho ~q:3 ~pin:0 ~msb:0 ()
let sho_p1 = Isa.sho ~q:0 ~pin:1 ~msb:0 ()

(* Code layout, identical slot structure in every thread (addresses are per thread):
     0        init: thread 0 sets both pins driven low; others NOP
     1  I0:   LDC nlp_outer
     2  I1:   LDD nlp_inner
     3  I2:   WAITP start = 1, fail -> T
     4..      TX prologue: LDD 0; IN; NOP x first_slot t; q0 pair; NOP
              L: q1 pair; NOP; q2 pair; WAITP end_t = 0 fail -> X; q3 pair; IN; q0 pair; JMP L
              X: q3 pair; NOP x (2 - first_slot t); LDD ipg; WAITD; JMP I0
     T:       SHI (counts down cnt); JNZ I1; NLP code; JMP I0 *)
let program ?(p = default) ?(late_thread = -1) t =
  let pair = [ sho_p0; sho_p1 ] in
  let code = ref [] and pos = ref 0 in
  let emit l = code := !code @ l; pos := !pos + List.length l in
  let fix = ref [] in   (* (index, label) to patch *)
  let label_of = Hashtbl.create 8 in
  let here name = Hashtbl.replace label_of name !pos in
  let emit_ref mk name = fix := (!pos, mk, name) :: !fix; emit [ Isa.nop ] in
  emit [ (if t = 0 then Isa.setp ~mask:3 ~value:0 ~oe:1 else Isa.nop) ];
  here "I0"; emit [ Isa.ldc p.nlp_outer ];
  here "I1"; emit [ Isa.ldd p.nlp_inner ];
  emit_ref (fun a -> Isa.waitp ~pin:pin_start ~value:1 ~fail:a) "T";
  (* TX prologue *)
  emit [ Isa.ldd 0; Isa.in_ ];
  emit (List.init (first_slot t + if t = late_thread then 1 else 0) (fun _ -> Isa.nop));
  emit pair; emit [ Isa.nop ];
  here "L";
  emit pair; emit [ Isa.nop ]; emit pair;
  emit_ref (fun a -> Isa.waitp ~pin:(pin_end t) ~value:0 ~fail:a) "X";
  emit pair; emit [ Isa.in_ ]; emit pair;
  emit_ref Isa.jmp "L";
  here "X";
  emit pair;
  emit (List.init (2 - first_slot t) (fun _ -> Isa.nop));
  emit [ Isa.ldd p.ipg_slots; Isa.waitd ];
  emit_ref Isa.jmp "I0";
  here "T";
  emit [ Isa.shi ~pin:7 ~msb:0 ];
  emit_ref Isa.jnz "I1";
  (* the link pulse: thread 0 raises TD+ in its first slot here, thread 2 lowers it
     [nlp_width_slots] of its slots later; everyone pads to the same length *)
  let w = p.nlp_width_slots in
  let nlp =
    List.init (w + 1) (fun i ->
        if t = 0 && i = 0 then Isa.setpq ~q:3 ~mask:1 ~value:1 ~oe:1
        else if t = 2 && i = w then Isa.setpq ~q:3 ~mask:1 ~value:0 ~oe:1
        else Isa.nop) in
  emit nlp;
  emit_ref Isa.jmp "I0";
  let arr = Array.of_list !code in
  List.iter (fun (i, mk, name) -> arr.(i) <- mk (Hashtbl.find label_of name)) !fix;
  assert (Array.length arr <= Isa.prog_len);
  Array.init Isa.prog_len (fun i -> if i < Array.length arr then arr.(i) else Isa.halt)

let program_size t = Array.length (Array.of_list (List.filter (fun i -> i <> Isa.halt) (Array.to_list (program t))))

(* ---- precomputation: the per-thread byte streams for one frame ---- *)

(* line level per half-bit: +1, -1 or 0; preamble, SFD, [frame] (with its FCS already appended by
   the caller), then [tp_idl] half-bits high, then idle *)
let levels ?(tp_idl = default.tp_idl) wire_bytes =
  let bits = List.concat_map Eth_model.bits_of_byte wire_bytes in
  let data = List.concat_map (fun b -> if b = 1 then [ -1; 1 ] else [ 1; -1 ]) bits in
  (* four idle half-bits first, so that TD- of the first real half-bit belongs to a pair *)
  Array.of_list (List.init 4 (fun _ -> 0) @ data @ List.init tp_idl (fun _ -> 1))

let wire_of_frame frame = List.init 7 (fun _ -> 0x55) @ [ 0xD5 ] @ frame @ Eth_model.fcs_bytes frame

(* streams.(t).(m): thread t's m-th byte. Pair i of byte m covers TD+ of half-bit
   k = k0 t + 4 (4m + i) and TD- of half-bit k + 1. *)
let streams ?tp_idl wire_bytes =
  let lv = levels ?tp_idl wire_bytes in
  let n = Array.length lv in
  let at k = if k >= 0 && k < n then lv.(k) else 0 in
  let groups = (n + 4 + 15) / 16 + 1 in
  Array.init Isa.n_threads (fun t ->
      Array.init groups (fun m ->
          let b = ref 0 in
          for i = 0 to 3 do
            let k = k0 t + (4 * ((4 * m) + i)) in
            if at k = 1 then b := !b lor (1 lsl (2 * i));
            if at (k + 1) = -1 then b := !b lor (1 lsl ((2 * i) + 1))
          done; !b))

(* ---- reference feeder (OCaml): drives host_in, start and end_t for a queue of frames ---- *)

type feeder = {
  mutable queue : (int * int array array) list;  (* (earliest start clock, streams) *)
  mutable cur : int array array option;
  mutable next : int array;
  mutable start : bool;
  mutable ends : int;          (* bit t: end_t *)
  mutable started_at : int list;  (* clocks at which start rose, newest first *)
}

let feeder frames = { queue = frames; cur = None; next = Array.make 4 0; start = false; ends = 0; started_at = [] }

let pin_in f = (if f.start then 1 lsl pin_start else 0) lor (f.ends lsl 4)

(* inputs for the slot at clock [c] (thread c mod 4) with [thread_pc_is_in] telling whether the
   thread is at an IN; then [after] with the handshake *)
let host_byte f ~thread =
  match f.cur with
  | Some s when f.next.(thread) < Array.length s.(thread) -> Some s.(thread).(f.next.(thread))
  | _ -> None

let before_clock f ~clock =
  (* start may change only at round boundaries *)
  if clock mod 4 = 0 then begin
    match f.cur, f.queue with
    | None, (at, s) :: rest when clock >= at ->
      (* end_t stays set until the new frame's first handshake: the previous frame's threads may
         not have reached their end check yet *)
      f.cur <- Some s; f.queue <- rest; f.next <- Array.make 4 0; f.start <- true;
      f.started_at <- clock :: f.started_at
    | _ -> ()
  end

let after_handshake f ~thread =
  (match f.cur with
   | Some s ->
     if f.start then (f.start <- false; f.ends <- 0);
     f.next.(thread) <- f.next.(thread) + 1;
     if f.next.(thread) = Array.length s.(thread) then f.ends <- f.ends lor (1 lsl thread);
     if Array.for_all2 (fun n a -> n = Array.length a) f.next s then f.cur <- None
   | None -> ())

(* run the interpreter (and optionally the RTL alongside) for [cycles] clocks; returns the TD+/TD-
   levels per quarter clock as run-length encoded differential (level, quarters) *)
type run = { runs : (int * int) list; divergent : int; starts : int list }

let simulate ?(rtl = false) ?(mem = Array.init Isa.n_threads program) ~cycles frames =
  let st = Isa.init () in
  let hs = if rtl then Some (Harness.make mem) else None in
  let f = feeder frames in
  let runs = ref [] and cur_lvl = ref 0 and cur_len = ref 0 in
  let push lvl = if lvl = !cur_lvl then incr cur_len else begin
      if !cur_len > 0 then runs := (!cur_lvl, !cur_len) :: !runs; cur_lvl := lvl; cur_len := 1 end in
  let divergent = ref 0 in
  for c = 0 to cycles - 1 do
    before_clock f ~clock:c;
    let t = st.thread in
    let at_in = mem.(t).(st.pcs.(t)) = Isa.in_ in
    let byte = if at_in then host_byte f ~thread:t else None in
    let valid = byte <> None in
    let hb = Option.value byte ~default:0 in
    let pin_in = pin_in f in
    let eff = Isa.step st ~mem ~pin_in ~host_in:hb ~host_in_valid:valid in
    (match hs with
     | Some hs ->
       let o = Harness.cycle hs ~pin_in ~host_in:hb ~host_in_valid:valid in
       if o.pin_sub <> st.pin_sub || o.pin_oe <> st.pin_oe || o.host_in_ready <> eff.host_in_ready then incr divergent
     | None -> ());
    if eff.host_in_ready then after_handshake f ~thread:t;
    for q = 0 to 3 do
      let p0 = (st.pin_sub lsr q) land 1 and p1 = (st.pin_sub lsr (4 + q)) land 1 in
      push (p0 - p1)
    done
  done;
  if !cur_len > 0 then runs := (!cur_lvl, !cur_len) :: !runs;
  { runs = List.rev !runs; divergent = !divergent; starts = List.rev f.started_at }
