(* Edge-tracking sampler: a generic receive front end that recovers bits from a line by timing its
   edges, resynchronising on every edge. It sits between the input pins (1, 2 or 4 samples per
   clock, as the four-phase input stage of ../multiphase delivers them) and whatever consumes bits
   (the systolic matcher, a byte packer, the CRC unit, the sequencer).

   Time is counted in sub-samples (n per clock). An edge is a change between consecutive samples
   while [active] (the squelch or carrier-sense input; tie high where there is none). A burst starts
   at the first edge and ends [timeout] sub-samples after the last anchoring edge. Three modes:

   - Manchester (10BASE-T, MIL-STD-1553, DALI, RC5 infrared, EM4100 RFID): an edge at least
     [holdoff] sub-samples after the previous anchor is a mid-bit edge; it becomes the anchor and
     the bit is the new level. Edges before that are cell boundaries and are ignored.
   - Biphase mark (USB Power Delivery BMC, S/PDIF, FM0/FM1 RFID, DCC): an edge at least [holdoff]
     after the anchor is a cell boundary and becomes the anchor; the bit is 1 if an edge (the
     mid-cell one) happened since the previous anchor.
   - NRZ with resynchronisation (UART, CAN, USB full/low speed before NRZI decoding and
     unstuffing, SWD, PS/2 data): every edge at least [holdoff] after the anchor (a deglitch)
     re-anchors; the line is sampled [offset] sub-samples after the anchor and then every
     [period] until the next edge.

   While [active] is low the sampler neither sees edges nor updates its idea of the line's last
   level, so a short squelch dropout costs at most a late edge, whatever the comparator shows while
   squelched (the question left open by ../ethernet-10base-t's hwfuzz finding).

   [invert] flips emitted bits. At most one bit is emitted per clock (true whenever holdoff, offset
   and period are at least n); a second one in the same clock is dropped and sets [overrun], so a
   configuration outside that range announces itself instead of silently losing bits.

   The model (below, plain integers) and the RTL (further below, signals) implement the same step
   per sub-sample; the RTL unrolls it n times per clock. *)

type mode = Manchester | Biphase_mark | Nrz

let mode_code = function Manchester -> 0 | Biphase_mark -> 1 | Nrz -> 2

type cfg = { mode : mode; holdoff : int; timeout : int; offset : int; period : int; invert : bool }

let since_max = 1023

(* ---- model ---- *)

type st = { mutable prev : int; mutable in_burst : bool; mutable since : int; mutable unq : bool; mutable until : int }

let init () = { prev = 0; in_burst = false; since = 0; unq = false; until = 0 }

(* one sub-sample; returns (emitted bit option, burst ended) *)
let step_sub cfg st ~active s =
  let edge = active && s <> st.prev in
  if active then st.prev <- s;
  let inv b = if cfg.invert then 1 - b else b in
  if not st.in_burst then begin
    if edge then begin st.in_burst <- true; st.since <- 0; st.unq <- false; st.until <- cfg.offset end;
    (None, false)
  end else begin
    let d = min since_max (st.since + 1) in
    let emit = ref None in
    (match cfg.mode with
     | Manchester | Biphase_mark ->
       if edge && d >= cfg.holdoff then begin
         emit := Some (inv (if cfg.mode = Manchester then s else if st.unq then 1 else 0));
         st.since <- 0; st.unq <- false
       end else begin
         if edge then st.unq <- true;
         st.since <- d
       end
     | Nrz ->
       if edge && d >= cfg.holdoff then begin st.since <- 0; st.until <- cfg.offset end
       else begin
         st.since <- d;
         let u = st.until - 1 in
         if u = 0 then begin emit := Some (inv s); st.until <- cfg.period end else st.until <- max 0 u
       end);
    if st.since > cfg.timeout then begin st.in_burst <- false; (!emit, true) end else (!emit, false)
  end

type out = { bit : int; valid : bool; burst_end : bool; overrun : bool }

(* one clock: [samples] is the list of this clock's n samples in time order *)
let step_clock cfg st ~active samples =
  let first = ref None and ended = ref false and over = ref false in
  List.iter (fun s ->
      let e, en = step_sub cfg st ~active s in
      (match e, !first with Some b, None -> first := Some b | Some _, Some _ -> over := true | None, _ -> ());
      if en then ended := true) samples;
  { bit = Option.value !first ~default:0; valid = !first <> None; burst_end = !ended; overrun = !over }

(* ---- RTL ---- *)
open Hardcaml
open Signal

type cfg_signals = { s_mode : Signal.t; s_holdoff : Signal.t; s_timeout : Signal.t; s_offset : Signal.t; s_period : Signal.t; s_invert : Signal.t }

let cfg_consts (c : cfg) =
  { s_mode = of_int ~width:2 (mode_code c.mode); s_holdoff = of_int ~width:10 c.holdoff; s_timeout = of_int ~width:10 c.timeout;
    s_offset = of_int ~width:8 c.offset; s_period = of_int ~width:8 c.period; s_invert = of_bool c.invert }

let cfg_inputs () =
  { s_mode = input "mode" 2; s_holdoff = input "holdoff" 10; s_timeout = input "timeout" 10; s_offset = input "offset" 8;
    s_period = input "period" 8; s_invert = input "invert" 1 }

type rst = { prev : Signal.t; in_burst : Signal.t; since : Signal.t; unq : Signal.t; until : Signal.t }

(* the same step as the model, on signals *)
let step_sub_rtl (c : cfg_signals) (r : rst) ~active s =
  let edge = active &: (s <>: r.prev) in
  let d = mux2 (r.since ==:. since_max) r.since (r.since +:. 1) in
  let is_nrz = c.s_mode ==:. 2 and is_manch = c.s_mode ==:. 0 in
  let qual = edge &: (d >=: c.s_holdoff) in
  (* in burst, Manchester / biphase mark *)
  let mb_bit = mux2 is_manch s r.unq in
  let mb_since = mux2 qual (zero 10) d in
  let mb_unq = mux2 qual gnd (r.unq |: edge) in
  (* in burst, NRZ *)
  let u = r.until -:. 1 in
  let u_zero = (r.until ==:. 1) in
  let nrz_emit = ~:qual &: u_zero in
  let nrz_until = mux2 qual c.s_offset (mux2 u_zero c.s_period (mux2 (r.until ==:. 0) (zero 8) u)) in
  let since_b = mux2 is_nrz mb_since mb_since in   (* both modes: 0 on a qualified edge, else d *)
  let emit_b = mux2 is_nrz nrz_emit qual in
  let bit_b = mux2 is_nrz s mb_bit ^: c.s_invert in
  let ended = since_b >: c.s_timeout in
  let in_b = r.in_burst in
  let nr =
    { prev = mux2 active s r.prev;
      in_burst = mux2 in_b (~:ended) edge;
      since = mux2 in_b since_b (mux2 edge (zero 10) r.since);
      unq = mux2 in_b (mux2 is_nrz r.unq mb_unq) (mux2 edge gnd r.unq);
      until = mux2 in_b (mux2 is_nrz nrz_until r.until) (mux2 edge c.s_offset r.until) } in
  nr, in_b &: emit_b, bit_b, in_b &: ended

let create ~clock ~clear ~n ~(cfg : cfg_signals) ~samples ~active =
  let spec = Reg_spec.create ~clock ~clear () in
  let w_prev = wire 1 and w_in = wire 1 and w_since = wire 10 and w_unq = wire 1 and w_until = wire 8 in
  let r0 = { prev = reg spec w_prev; in_burst = reg spec w_in; since = reg spec w_since; unq = reg spec w_unq; until = reg spec w_until } in
  let r = ref r0 and first_v = ref gnd and first_b = ref gnd and over = ref gnd and ended = ref gnd in
  for p = 0 to n - 1 do
    let nr, e, b, en = step_sub_rtl cfg !r ~active (bit samples p) in
    over := !over |: (e &: !first_v);
    first_b := mux2 !first_v !first_b b;
    first_v := !first_v |: e;
    ended := !ended |: en;
    r := nr
  done;
  w_prev <== !r.prev; w_in <== !r.in_burst; w_since <== !r.since; w_unq <== !r.unq; w_until <== !r.until;
  (* outputs registered: they describe the clock just sampled *)
  let bit = reg spec !first_b and valid = reg spec !first_v and burst_end = reg spec !ended and overrun = reg spec !over in
  bit, valid, burst_end, overrun, r0.in_burst

let circuit ~n =
  let clock = input "clock" 1 and clear = input "clear" 1 in
  let cfg = cfg_inputs () in
  let samples = input "samples" n and active = input "active" 1 in
  let bit, valid, burst_end, overrun, in_burst = create ~clock ~clear ~n ~cfg ~samples ~active in
  Circuit.create_exn ~name:(Printf.sprintf "edge_sampler%d" n)
    [ output "bit" bit; output "valid" valid; output "burst_end" burst_end; output "overrun" overrun; output "in_burst" in_burst ]

let set_cfg sim (c : cfg) =
  let i nm v w = Cyclesim.in_port sim nm := Bits.of_int ~width:w v in
  i "mode" (mode_code c.mode) 2; i "holdoff" c.holdoff 10; i "timeout" c.timeout 10; i "offset" c.offset 8;
  i "period" c.period 8; i "invert" (if c.invert then 1 else 0) 1
