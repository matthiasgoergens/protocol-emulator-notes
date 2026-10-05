(* The latency lint as a regression test ([main.exe latency], run by [dune test]).

   The console is linted with [hold_registers]: the 54-byte line packet shifts through enabled
   registers and is latched once a line, so with default settings each sprite cell reading its
   parameters at its own pipeline stage is one of 66 findings that all mean "the packet is
   constant for the line".  Treating enabled registers as holding values removes that class.

   The 5 findings that remain are the deliberate early launch: the 17-stage sprite pipeline is
   started at hcount = vis_start - nspr - 2 rather than having the syncs delayed by 17 registers,
   so pixel and sync are aligned by a counter constant that the lint cannot see.  They are
   recorded in latency.expected; a change in them, or a new finding, fails the test.

   The planted control removes one register from the pixel-valid (blank) lane at sprite cell 8,
   which must add a finding.  stdout is compared with latency.expected by dune. *)
let main () =
  let config = Latency_ci.hold in
  let real = Latency_ci.lint ~config (Console.circuit ()) in
  Latency_ci.print ~title:"retro_console" ~config real;
  let planted =
    Latency_ci.lint ~config (Console.circuit_planted ~plant_valid_short:true ())
  in
  Latency_ci.print ~title:"PLANTED retro_console, valid lane one register short" ~config planted;
  Latency_ci.expect_caught ~title:"retro_console, valid lane one register short" ~real ~planted;
  Latency_ci.exit ()
