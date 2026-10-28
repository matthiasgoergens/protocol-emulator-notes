(* Writes each block as a Verilog top of its own, for an external prover: the design, or one
   planted fault from [Stuff.bugs] / [Linecode.bugs].
   Usage: emit.exe DIR [BUG]. *)
open Hardcaml
open Signal

let stuff_cfg () =
  { Stuff.s_run = input "cfg_run" 4; s_either = input "cfg_either" 1; s_value = input "cfg_value" 1 }

let line_cfg () =
  { Linecode.s_mode = input "cfg_mode" 2; s_invert = input "cfg_invert" 1;
    s_toggle_on = input "cfg_toggle_on" 1 }

let clock () = input "clock" 1
let clear () = input "clear" 1

let stuff_tx () =
  let o =
    Stuff.tx ~clock:(clock ()) ~clear:(clear ()) ~restart:(input "restart" 1) ~cfg:(stuff_cfg ())
      ~due:(input "due" 1) ~data_bit:(input "data_bit" 1) ~data_valid:(input "data_valid" 1) in
  [ output "out_bit" o.out_bit; output "take" o.take; output "stuffed" o.stuffed;
    output "underrun" o.underrun ]

let stuff_rx () =
  let o =
    Stuff.rx ~clock:(clock ()) ~clear:(clear ()) ~restart:(input "restart" 1) ~cfg:(stuff_cfg ())
      ~valid:(input "valid" 1) ~b:(input "b" 1) () in
  [ output "keep" o.keep; output "err" o.err ]

let line_enc () =
  let o =
    Linecode.encoder ~clock:(clock ()) ~clear:(clear ()) ~restart:(input "restart" 1)
      ~cfg:(line_cfg ()) ~tick:(input "tick" 1) ~bit:(input "bit" 1) in
  [ output "need_bit" o.need_bit; output "line" o.line; output "sym" o.sym ]

let line_dec () =
  let o =
    Linecode.decoder ~clock:(clock ()) ~clear:(clear ()) ~cfg:(line_cfg ()) ~valid:(input "valid" 1)
      ~sym:(input "sym" 1) in
  [ output "out_valid" o.out_valid; output "out_bit" o.out_bit; output "err" o.err ]

let blocks = [ "stuff_tx", stuff_tx; "stuff_rx", stuff_rx; "line_enc", line_enc; "line_dec", line_dec ]

let () =
  let dir = Sys.argv.(1) in
  let bug = if Array.length Sys.argv > 2 then Sys.argv.(2) else "" in
  if bug <> "" && not (List.mem_assoc bug Stuff.bugs || List.mem_assoc bug Linecode.bugs) then
    failwith ("unknown bug " ^ bug);
  Stuff.bug := bug;
  Linecode.bug := bug;
  List.iter
    (fun (name, f) ->
      let circuit = Circuit.create_exn ~name (f ()) in
      Rtl.output ~output_mode:(Rtl.Output_mode.To_file (Filename.concat dir (name ^ ".v"))) Verilog
        circuit)
    blocks
