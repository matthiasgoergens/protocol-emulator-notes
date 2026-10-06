(* The v2 core's Verilog for the power-up determinism proof: the synthesis view (no debug ports),
   optionally with register groups built without the clear (planted faults), or with one of
   Sequencer2.cert_mutants (for ../../verifier's certificate check on the RTL).
   Usage: emit_core.exe FILE [GROUP...]     GROUP: one of Sequencer2.unreset_groups
          emit_core.exe FILE mutant:N       N: the index in Sequencer2.cert_mutants, from 0 *)
open Hardcaml

let () =
  match Array.to_list Sys.argv with
  | [ _; file; m ] when String.length m > 7 && String.sub m 0 7 = "mutant:" ->
    let bug = fst (List.nth Sequencer2.cert_mutants (int_of_string (String.sub m 7 (String.length m - 7)))) in
    let oc = open_out file in
    Rtl.output ~output_mode:(To_channel oc) Verilog (Sequencer2.circuit ~bug ~debug:false ());
    close_out oc
  | _ :: file :: unreset ->
    let oc = open_out file in
    Rtl.output ~output_mode:(To_channel oc) Verilog (Sequencer2.circuit ~unreset ~debug:false ());
    close_out oc
  | _ ->
    prerr_endline ("usage: emit_core.exe FILE [GROUP...]; groups: " ^ String.concat " " Sequencer2.unreset_groups);
    exit 2
