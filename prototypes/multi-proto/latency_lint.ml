(* The latency lint as a regression test (run by [dune test]; stdout must match
   latency.expected, accept a reviewed change with [dune promote]).

   Ethernet-to-TV and CAN-to-TV draw the picture in firmware: a sequencer thread chases the beam
   and the pin stage is an OCaml model (video.ml), so the only video hardware here is the
   sequencer with mailboxes (as ethtv.ml and cantv.ml configure it) and the 10BASE-T receiver
   that feeds it.  The sequencer has no findings.  Each receiver has one, its transition
   detector (rx_q <>: rx_prev, the line now against one clock ago), which is deliberate.

   There is no planted control here, because there is no sync path in this hardware to plant one
   in.  The last circuit instead records a blind spot: two inputs sampled together outside the
   chip (rx and rx_active, from the same line) but synchronised through different numbers of
   registers.  They have no common source inside the circuit, so the lint cannot relate them and
   reports nothing; latency.expected pins that, so a change in behaviour is noticed. *)
open Hardcaml

let blind_spot () =
  let open Signal in
  let clock = input "clock" 1 in
  let spec = Reg_spec.create ~clock () in
  let rx = input "rx" 1 and rx_active = input "rx_active" 1 in
  let rx_q = reg spec (reg spec rx) and act_q = reg spec rx_active (* one register short *) in
  Circuit.create_exn ~name:"blind_spot" [ output "o" (rx_q &: act_q) ]

let () =
  let c = Isa_mb.cfg ~pc_bits:7 ~depth:2 () in
  List.iter
    (fun (title, circ) -> Latency_ci.print ~title (Latency_ci.lint circ))
    [ "sequencer_mb p7 d2 (as ethtv and cantv)", Sequencer_mb.circuit c
    ; "eth_rx h3", Eth_rx.circuit ~h:3
    ; "eth_rx_fixed h3", Eth_rx_fixed.circuit ~h:3
    ; "BLIND SPOT, not caught: two inputs synchronised by 2 and 1 registers", blind_spot () ];
  Latency_ci.exit ()
