(* Emit the variant's Verilog (without the lockstep debug ports) for synthesis. *)
open Hardcaml
let () =
  let oc = open_out "deadline_sequencer_v.v" in
  Rtl.output ~output_mode:(To_channel oc) Verilog (Sequencer_v.circuit ());
  close_out oc;
  let oc = open_out "deadline_sequencer_vs.v" in
  Rtl.output ~output_mode:(To_channel oc) Verilog (Sequencer_v.circuit ~shared_cfg:true ());
  close_out oc
