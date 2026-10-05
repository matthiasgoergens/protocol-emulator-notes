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

let lockstep ~title ~cycles a b =
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
  if !differ > 0
  then
    fail "%s: rewrite differs from the original, first at cycle %d" title
      (Option.value_exn !first)
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
  (* ... and it must differ from the good design, or the comparison above shows nothing *)
  let sa = Cyclesim.create (ours tiny) and sb = Cyclesim.create (ours ~misdeclare:true tiny) in
  let differ = ref 0 in
  for _ = 1 to 5 * frame tiny do
    Cyclesim.cycle sa;
    Cyclesim.cycle sb;
    if not (Bits.equal !(Cyclesim.out_port sa "word_b") !(Cyclesim.out_port sb "word_b"))
    then Int.incr differ
  done;
  Stdio.printf "e2e mutant 'latency' against the good design: word_b differs on %d cycles\n" !differ;
  if !differ = 0 then fail "the misdeclared pattern is indistinguishable from the good one"
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
