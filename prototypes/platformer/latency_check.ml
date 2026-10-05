(* The latency lint as a regression test ([main.exe latency], run by [dune test]).

   The chip is linted with [hold_registers]: with default settings, 628 of its 630 findings come
   from the byte-wide configuration chain through the 18 PE-Xs (cfg_in shifting through enabled
   registers), which is constant while the chip runs.  The 3 findings that remain are recorded in
   latency.expected, with their classification in ../../notes/latency-adoption.md; a change in
   them, or a new finding, fails the test.

   The planted control passes the sync and blanking levels through one more register than the
   burst gate from the same sequencer pins, which must add a finding. *)
let main () =
  let config = Latency_ci.hold in
  let real = Latency_ci.lint ~config (Video.circuit ()) in
  Latency_ci.print ~title:"platformer_video" ~config real;
  Latency_ci.print ~title:"platformer_video, lean PE-X" ~config
    (Latency_ci.lint ~config (Video.circuit ~lean:true ()));
  let planted = Latency_ci.lint ~config (Video.circuit ~plant_sync_late:true ()) in
  Latency_ci.print ~title:"PLANTED platformer_video, sync levels one register late" ~config planted;
  Latency_ci.expect_caught ~title:"platformer_video, sync levels one register late" ~real ~planted;
  Latency_ci.exit ()
