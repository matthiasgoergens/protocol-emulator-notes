(* The stuff tracker: bit stuffing on transmit and destuffing with a violation check on receive,
   with a programmable run length. Protocol-agnostic; the protocols are configurations:

   - USB (full and low speed): a 0 after every six consecutive 1s      run 6, ones, value 1
   - CAN: the complement after five equal bits of either value         run 5, either
   - HDLC, SDLC, AX.25 (bit-oriented framing): a 0 after five 1s       run 5, ones, value 1

   The run is counted over every bit on the line, stuff bits included: a stuff bit is an ordinary
   bit for the next run. In "ones" mode it is the complement of [value], so it ends the run (USB:
   the stuffed 0 starts a count of 0); in "either" mode it is the complement of the last bit, so it
   starts a new run of one (CAN: a stuff bit and four more of its value make another run of five).

   Transmit: when a bit is due and the last [run] bits form a run, the stuff bit goes out and no
   data bit is taken; otherwise the next data bit goes out, or, with no data bit available, nothing
   (an underrun, which the serialiser takes as the end of the frame).
   Receive: the bit after a run is a stuff bit and is dropped; if it continues the run instead of
   breaking it, that is a stuff violation (USB: seven 1s, an error or an abort; CAN: a stuff error).
   After a violation the count restarts as after any stuff bit, so the stream is still destuffed
   deterministically.

   The count saturates at 15; run 0 switches stuffing off (no bit is ever a stuff bit), and a run
   longer than 15 cannot be configured. In either mode a stuff bit starts a run of one, so a run
   of 1 there would emit nothing but stuff bits: either mode needs a run of 2 or more. [restart] (the start of a frame) clears the count and the
   last bit.

   The model below and the RTL further down are written separately from the same rules;
   check.ml runs them in lockstep, and against independent stuffers (refs/). *)

type cfg = { run : int; either : bool; value : int }

(* the configurations of the protocols above *)
let usb = { run = 6; either = false; value = 1 }
let can = { run = 5; either = true; value = 0 }
let hdlc = { run = 5; either = false; value = 1 }
let off = { run = 0; either = false; value = 0 }

(* ---- model ---- *)

type st = { mutable cnt : int; mutable last : int }

let init () = { cnt = 0; last = 0 }
let restart st = st.cnt <- 0; st.last <- 0

(* does bit b continue the current run? *)
let continues c st b = if c.either then b = st.last else b = c.value

(* the next bit on the line is a stuff bit *)
let full c st = c.run > 0 && st.cnt >= c.run

(* the count after bit b; at a stuff position b starts a new run whatever it is *)
let count_after c st b ~stuff_pos =
  if stuff_pos || not (continues c st b) then (if c.either then 1 else Bool.to_int (b = c.value))
  else min 15 (st.cnt + 1)

let commit c st b ~stuff_pos = st.cnt <- count_after c st b ~stuff_pos; st.last <- b

(* The stuff bit, when one is due. *)
let stuff_bit c st = if c.either then 1 - st.last else 1 - c.value

type tx = Stuffed of int | Data of int | Underrun

(* Transmit: what goes out when a bit is due, given the next data bit if there is one. Does not
   change the state; [tx_commit] does. *)
let tx_peek c st ~data = if full c st then Stuffed (stuff_bit c st) else match data with Some b -> Data b | None -> Underrun

let tx_commit c st = function
  | Stuffed b -> commit c st b ~stuff_pos:true
  | Data b -> commit c st b ~stuff_pos:false
  | Underrun -> ()

(* Receive one bit: (kept, violation). With [drop] false (outside a frame, for the receive
   framer) the run is counted but no bit is dropped or flagged. *)
let rx_step ?(drop = true) c st b =
  let f = drop && full c st in
  let err = f && continues c st b in
  commit c st b ~stuff_pos:f;
  (not f, err)

(* whole streams, for the tests: stuff a bit list, destuff a bit list *)
let stuff_list c bits =
  let st = init () and out = ref [] in
  let rec go = function
    | [] -> ()
    | b :: rest as l ->
      (match tx_peek c st ~data:(Some b) with
       | Stuffed s as x -> tx_commit c st x; out := s :: !out; go l
       | Data _ as x -> tx_commit c st x; out := b :: !out; go rest
       | Underrun -> assert false)
  in
  go bits;
  (* a stuff bit due after the last data bit is sent too (USB, CAN) *)
  if full c st then out := stuff_bit c st :: !out;
  List.rev !out

let destuff_list c bits =
  let st = init () and out = ref [] and errs = ref 0 in
  List.iter (fun b -> let keep, e = rx_step c st b in if keep then out := b :: !out; if e then incr errs) bits;
  (List.rev !out, !errs)

(* ---- RTL ---- *)
open Hardcaml
open Signal

type cfg_signals = { s_run : Signal.t; (* 4 bits *) s_either : Signal.t; s_value : Signal.t }

let cfg_const c = { s_run = of_int ~width:4 c.run; s_either = of_bool c.either; s_value = of_int ~width:1 c.value }

(* Planted faults for check.ml's controls; "" is the design. *)
let bug = ref ""
let is b = !bug = b

let bugs =
  [ "stuff_off_by_one", "a stuff bit after run + 1 bits";
    "stuff_same_value", "the stuff bit repeats the run instead of breaking it";
    "stuff_not_counted", "a stuff bit does not count towards the next run (either mode)";
    "destuff_no_error", "a bit continuing the run after a full run is not a violation";
    "destuff_keeps", "the stuff bit is passed on instead of dropped";
    "restart_ignored", "restart does not clear the count" ]

(* The count and last-bit registers, updated with bit [b] when [update]. [stuff_pos] says that b
   occupies a stuff position. Returns (full, continues b, cnt, last). *)
let core ~spec ~restart ~(cfg : cfg_signals) ~update ~b ~stuff_pos =
  let cnt = wire 4 and last = wire 1 in
  let run_eff = if is "stuff_off_by_one" then cfg.s_run +:. 1 else cfg.s_run in
  let full = (cfg.s_run <>:. 0) &: (cnt >=: run_eff) in
  let cont c = mux2 cfg.s_either (c ==: last) (c ==: cfg.s_value) in
  let restart_cnt = mux2 cfg.s_either (of_int ~width:4 1) (uresize (b ==: cfg.s_value) 4) in
  let restart_cnt =
    if is "stuff_not_counted" then mux2 (stuff_pos &: cfg.s_either) (zero 4) restart_cnt else restart_cnt in
  let next = mux2 (stuff_pos |: ~:(cont b)) restart_cnt (mux2 (cnt ==:. 15) cnt (cnt +:. 1)) in
  let clr = if is "restart_ignored" then gnd else restart in
  cnt <== reg spec (mux2 clr (zero 4) (mux2 update next cnt));
  last <== reg spec (mux2 clr gnd (mux2 update b last));
  (full, cont, cnt, last)

(* Transmit. When [due] (a bit goes out this clock): if a stuff bit is due it goes out and the
   data bit is not taken; else the data bit [data_bit] goes out if [data_valid] and is taken; else
   [underrun]. Outputs are combinational of this clock's state and inputs.
   Contract: [restart] and [due] are never high in the same clock. A bit sent in a restart clock
   goes out but is not counted, so the next run could exceed [run] (Aristotle's counterexample,
   aristotle-runs/RESULTS.md); txpath drives them from two values of one phase register. *)
type tx_out = { out_bit : Signal.t; take : Signal.t; stuffed : Signal.t; underrun : Signal.t }

let tx ~clock ~clear ~restart ~cfg ~due ~data_bit ~data_valid =
  let spec = Reg_spec.create ~clock ~clear () in
  let full_w = wire 1 and last_w = wire 1 in
  let stuffed = due &: full_w in
  let sbit = mux2 cfg.s_either (~:last_w) (~:(cfg.s_value)) in
  let sbit = if is "stuff_same_value" then ~:sbit else sbit in
  let out_bit = mux2 full_w sbit data_bit in
  let take = due &: ~:full_w &: data_valid in
  let underrun = due &: ~:full_w &: ~:data_valid in
  let full, _, _, last = core ~spec ~restart ~cfg ~update:(stuffed |: take) ~b:out_bit ~stuff_pos:stuffed in
  full_w <== full; last_w <== last;
  { out_bit; take; stuffed; underrun }

(* Receive. With [valid], bit [b] arrives; [keep] says it is a data bit, [err] that it is a stuff
   violation. Combinational of this clock's state and inputs. Without [drop] the run is counted
   and nothing is dropped or flagged. *)
type rx_out = { keep : Signal.t; err : Signal.t }

let rx ?(drop = vdd) ~clock ~clear ~restart ~cfg ~valid ~b () =
  let spec = Reg_spec.create ~clock ~clear () in
  let full_w = wire 1 in
  let full, cont, _, _ = core ~spec ~restart ~cfg ~update:valid ~b ~stuff_pos:(valid &: full_w &: drop) in
  let full = full &: drop in
  full_w <== full;
  let keep = valid &: (if is "destuff_keeps" then vdd else ~:full) in
  let err = valid &: full &: (if is "destuff_no_error" then gnd else cont b) in
  { keep; err }
