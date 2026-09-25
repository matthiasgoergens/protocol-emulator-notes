(* JTAG on the STOCK sequencer (isa.ml, sequencer.ml and harness.ml are symlinks to
   ../../deadline-sequencer), and the SWD engine's size against the stock 64-word store. *)
let () =
  let ok = Jtag_suite.main () in
  (match Swd_host.programmes Swd_host.fastest with
   | _, len -> Printf.printf "SWD engine on the stock ISA: fits, %d words\n" len
   | exception Failure m -> Printf.printf "SWD engine on the stock ISA: %s\n" m);
  print_endline (if ok then "ALL PASS" else "FAILURES");
  exit (if ok then 0 else 1)
