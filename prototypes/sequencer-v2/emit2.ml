(* Verilog of the v2 core for synthesis: no debug ports (as the base core's synthesis), memories
   outside. Usage: emit2.exe FILE *)
open Hardcaml

let () =
  let file = try Sys.argv.(1) with _ -> "deadline_sequencer_v2.v" in
  let oc = open_out file in
  Rtl.output ~output_mode:(To_channel oc) Verilog (Sequencer2.circuit ~debug:false ());
  close_out oc
