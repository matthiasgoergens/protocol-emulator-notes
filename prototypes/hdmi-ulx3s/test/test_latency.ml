(* Latency checks of the HDMI pixel path, run by [dune test]:

   1. The pixel path is written with Hardcaml_latency.Delayed (hw/hdmi.ml, hw/video_timing.ml,
      hw/test_pattern.ml, demo/console_hdmi.ml), so a sync/blank/pixel misalignment does not
      build.  Both sources build; with one register planted out of the syncs (the negative
      control), neither does.
   2. The rewrite is cycle-identical to the design before it (frozen in test/reference/): every
      output, every cycle, over whole frames of the small mode and one of 640 x 480, and the same
      for the end-to-end "latency" mutant, which must stay misaligned in the same way.  (The demo
      source instantiates Verilog memories, which Cyclesim cannot run; it is compared at the
      Verilog level by test/compare_demo_rtl.sh.)
   3. Latency_lint over the built circuits, printed for the committed expected file
      (test/latency.expected), and over the original plain design with the syncs one register
      short, which it must flag.

   stdout is compared with test/latency.expected; anything that varies with unrelated edits (node
   counts, the text of the Delayed error) goes to stderr, with LATENCY_VERBOSE=1 only.  Exit
   status 1 on any failure. *)
open! Base
open Hardcaml
open Hdmi_hw
module D = Hardcaml_latency.Delayed

let failures = Latency_ci.failures
let fail = Latency_ci.fail
let tiny = Video_timing.tiny
let vga = Video_timing.vga_640x480_60

let pattern ?misdeclare (m : Video_timing.t) =
  Hdmi.test_pattern ?misdeclare ~width:m.h.active ~height:m.v.active ()
;;

let demo () = Hdmi_demo.Console_hdmi.source ~fields:1 ~packet_file:"packets.hex"

(* 1. construction-time check *)
let builds ~title f =
  match f () with
  | (_ : Circuit.t) ->
    Stdio.printf "%s: built\n" title;
    true
  | exception D.Latency_mismatch msg ->
    Stdio.printf "%s: REJECTED by the latency check\n" title;
    Latency_ci.diag "%s:\n%s\n" title msg;
    false
;;

let () =
  let ok title f = if not (builds ~title f) then fail "%s did not build" title in
  let rejected title f = if builds ~title f then fail "%s built, but must not" title in
  ok "pattern, 640x480" (fun () ->
    Hdmi.pixel_circuit ~blink_half_period:5 ~source:(pattern vga) ());
  ok "demo, 640x480" (fun () ->
    Hdmi.pixel_circuit ~name:"demo" ~blink_half_period:5 ~source:(demo ()) ());
  rejected "PLANTED pattern, syncs one register short" (fun () ->
    Hdmi.pixel_circuit ~plant_sync_short:true ~blink_half_period:5 ~source:(pattern vga) ());
  rejected "PLANTED demo, syncs one register short" (fun () ->
    Hdmi.pixel_circuit
      ~name:"demo"
      ~plant_sync_short:true
      ~blink_half_period:5
      ~source:(demo ())
      ())
;;

(* 2. cycle identity with the frozen original *)
let outputs = [ "word_b"; "word_g"; "word_r"; "toggle"; "led_1hz" ]

let compare_lockstep ~title ~cycles a b =
  let sa = Cyclesim.create a and sb = Cyclesim.create b in
  let reset sim =
    Cyclesim.in_port sim "clear" := Bits.vdd;
    Cyclesim.cycle sim;
    Cyclesim.in_port sim "clear" := Bits.gnd
  in
  reset sa;
  reset sb;
  let differ = ref 0 and first = ref None in
  for t = 0 to cycles - 1 do
    Cyclesim.cycle sa;
    Cyclesim.cycle sb;
    let same =
      List.for_all outputs ~f:(fun n ->
        Bits.equal !(Cyclesim.out_port sa n) !(Cyclesim.out_port sb n))
    in
    if not same
    then (
      Int.incr differ;
      if Option.is_none !first then first := Some t)
  done;
  Stdio.printf "%s: %d of %d cycles differ (all of %s)\n" title !differ cycles
    (String.concat ~sep:", " outputs);
  !differ, !first
;;

(* the rewrite must be identical to the original *)
let lockstep ~title ~cycles a b =
  match compare_lockstep ~title ~cycles a b with
  | 0, _ -> ()
  | _, first ->
    fail "%s: rewrite differs from the original, first at cycle %s" title
      (Option.value_map first ~default:"?" ~f:Int.to_string)
;;

(* a control for [lockstep]: the pair is known to differ, so a comparison that reports no
   difference here is blind, and the check fails *)
let lockstep_must_differ ~title ~cycles a b =
  match compare_lockstep ~title ~cycles a b with
  | 0, _ -> fail "%s: no cycle differs, so the lockstep comparison cannot see this fault" title
  | _ -> ()
;;

let frame (m : Video_timing.t) = Video_timing.total m.h * Video_timing.total m.v

(* the same mode, as the frozen original's type *)
let to_orig (m : Video_timing.t) : Video_timing_orig.t =
  let axis (a : Video_timing.axis) : Video_timing_orig.axis =
    { active = a.active; front = a.front; sync = a.sync; back = a.back }
  in
  { h = axis m.h
  ; v = axis m.v
  ; hsync_active_high = m.hsync_active_high
  ; vsync_active_high = m.vsync_active_high
  }
;;

let () =
  let orig ?(declared_latency = 1) (m : Video_timing.t) =
    Hdmi_orig.pixel_circuit ~timing:(to_orig m) ~blink_half_period:7
      ~source:
        (Hdmi_orig.test_pattern ~declared_latency ~width:m.h.active ~height:m.v.active ())
      ()
  in
  let ours ?misdeclare (m : Video_timing.t) =
    Hdmi.pixel_circuit ~timing:m ~blink_half_period:7 ~source:(pattern ?misdeclare m) ()
  in
  lockstep ~title:"pattern, small mode, 5 frames" ~cycles:(5 * frame tiny) (orig tiny) (ours tiny);
  lockstep ~title:"pattern, 640x480, 1 frame + 1000" ~cycles:(frame vga + 1000) (orig vga)
    (ours vga);
  (* the end-to-end negative control must still be misaligned, and in the same way *)
  lockstep ~title:"e2e mutant 'latency', small mode, 5 frames" ~cycles:(5 * frame tiny)
    (orig ~declared_latency:0 tiny) (ours ~misdeclare:true tiny);
  (* ... and the comparison itself must be able to see it: the rewritten mutant against the
     ORIGINAL GOOD design (what would be compared if the rewrite had introduced the fault), over
     the same small mode and the same outputs.  This is the detection control of the small mode;
     before 2026-10-05 only word_b of the mutant against the rewrite was counted, and the
     lockstep comparison itself was never shown to fail on this fault. *)
  lockstep_must_differ ~title:"e2e mutant 'latency' (rewrite) against the ORIGINAL good design, small mode, 5 frames"
    ~cycles:(5 * frame tiny) (orig tiny) (ours ~misdeclare:true tiny);
  (* the same with the roles swapped: a rewrite that was correct against an original that had
     the fault would be as wrong *)
  lockstep_must_differ ~title:"e2e mutant 'latency' (original) against the REWRITTEN good design, small mode, 5 frames"
    ~cycles:(5 * frame tiny) (orig ~declared_latency:0 tiny) (ours tiny)
;;

(* 3. the lint *)
let () =
  let lint ~title ?config c =
    let l = Latency_ci.lint ?config c in
    Latency_ci.print ~title ?config l;
    l
  in
  ignore
    (lint ~title:"hdmi_pixel (pattern, Delayed)"
       (Hdmi.pixel_circuit ~blink_half_period:5 ~source:(pattern tiny) ~timing:tiny ())
     : Latency_ci.linted);
  ignore
    (lint ~title:"hdmi_pixel_demo (Delayed)" ~config:Latency_ci.hold
       (Hdmi.pixel_circuit ~name:"demo" ~blink_half_period:5 ~source:(demo ()) ())
     : Latency_ci.linted);
  ignore
    (lint ~title:"hdmi_serial (bit clock)"
       (Hdmi.serial_circuit ~bits_per_cycle:2 ~blink_half_period:5 ())
     : Latency_ci.linted);
  (* The construction-time check refuses to build the planted design, so the lint's own control
     is the original plain design, which builds whatever its syncs are delayed by. *)
  let plain declared_latency =
    Hdmi_orig.pixel_circuit ~timing:(to_orig tiny) ~blink_half_period:5
      ~source:
        (Hdmi_orig.test_pattern ~declared_latency ~width:tiny.h.active
           ~height:tiny.v.active ())
      ()
  in
  let real = lint ~title:"original plain hdmi_pixel" (plain 1) in
  let planted =
    lint ~title:"PLANTED original plain hdmi_pixel, syncs one register short" (plain 0)
  in
  Latency_ci.expect_caught ~title:"plain hdmi_pixel, syncs one register short" ~real ~planted
;;

let () =
  if !failures > 0
  then (
    Stdio.eprintf "%d failure(s)\n" !failures;
    Stdlib.exit 1)
;;
