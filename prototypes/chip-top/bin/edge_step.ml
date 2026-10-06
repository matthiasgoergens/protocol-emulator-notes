(* One sub-sample step of the edge sampler (../blocks/eth10/edge_sampler.ml, step_sub_rtl) as a
   combinational circuit, and the same step in its plain form (as it was before the comparisons
   were moved onto since, 2026-10-06), for formal/edge_step_equiv: [edge_step.exe new|plain FILE]. *)
open Hardcaml
open Signal
module E = Eth10.Edge_sampler

let since_max = E.since_max

(* the plain form, verbatim from before the change *)
let plain (c : E.cfg_signals) (r : E.rst) ~active s =
  let edge = active &: (s <>: r.prev) in
  let d = mux2 (r.since ==:. since_max) r.since (r.since +:. 1) in
  let is_nrz = c.s_mode ==:. 2 and is_manch = c.s_mode ==:. 0 in
  let qual = edge &: (d >=: c.s_holdoff) in
  let mb_bit = mux2 is_manch s r.unq in
  let mb_since = mux2 qual (zero 10) d in
  let mb_unq = mux2 qual gnd (r.unq |: edge) in
  let u = r.until -:. 1 in
  let u_zero = (r.until ==:. 1) in
  let nrz_emit = ~:qual &: u_zero in
  let nrz_until = mux2 qual c.s_offset (mux2 u_zero c.s_period (mux2 (r.until ==:. 0) (zero 8) u)) in
  let since_b = mux2 is_nrz mb_since mb_since in
  let emit_b = mux2 is_nrz nrz_emit qual in
  let bit_b = mux2 is_nrz s mb_bit ^: c.s_invert in
  let ended = since_b >: c.s_timeout in
  let in_b = r.in_burst in
  let nr : E.rst =
    { prev = mux2 active s r.prev;
      in_burst = mux2 in_b (~:ended) edge;
      since = mux2 in_b since_b (mux2 edge (zero 10) r.since);
      unq = mux2 in_b (mux2 is_nrz r.unq mb_unq) (mux2 edge gnd r.unq);
      until = mux2 in_b (mux2 is_nrz nrz_until r.until) (mux2 edge c.s_offset r.until) } in
  nr, in_b &: emit_b, bit_b, in_b &: ended

let () =
  let which = Sys.argv.(1) and file = Sys.argv.(2) in
  let c = E.cfg_inputs () in
  let r : E.rst = { prev = input "prev" 1; in_burst = input "in_burst" 1; since = input "since" 10;
                    unq = input "unq" 1; until = input "until" 8 } in
  let active = input "active" 1 and s = input "s" 1 in
  let nr, e, b, en = (if which = "plain" then plain else E.step_sub_rtl) c r ~active s in
  let circ = Circuit.create_exn ~name:"edge_step"
      [ output "n_prev" nr.prev; output "n_in_burst" nr.in_burst; output "n_since" nr.since;
        output "n_unq" nr.unq; output "n_until" nr.until; output "emit" e; output "bit" b; output "ended" en ] in
  let oc = open_out file in
  Rtl.output ~output_mode:(To_channel oc) Verilog circ;
  close_out oc
