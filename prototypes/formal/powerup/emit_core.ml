(* The v2 core's Verilog for the power-up determinism proof: the synthesis view (no debug ports),
   optionally with register groups built without the clear (planted faults).
   Usage: emit_core.exe FILE [GROUP...]     GROUP: one of Sequencer2.unreset_groups *)
open Hardcaml

let () =
  match Array.to_list Sys.argv with
  | _ :: file :: unreset ->
    let oc = open_out file in
    Rtl.output ~output_mode:(To_channel oc) Verilog (Sequencer2.circuit ~unreset ~debug:false ());
    close_out oc
  | _ ->
    prerr_endline ("usage: emit_core.exe FILE [GROUP...]; groups: " ^ String.concat " " Sequencer2.unreset_groups);
    exit 2
