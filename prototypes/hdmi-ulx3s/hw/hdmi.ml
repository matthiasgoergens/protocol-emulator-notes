(* The two clock domains of the HDMI output, as circuits to emit as Verilog modules.

   hdmi_pixel  (pixel clock): raster timing -> pixel source -> three TMDS encoders -> three 10-bit
               words and the [toggle] that marks each new set of words; and a 1 Hz LED.
   hdmi_serial (bit clock): Serialiser, and a 1 Hz LED of its own.

   Blue carries HSYNC on c0 and VSYNC on c1; green and red carry 00 (DVI 1.0 section 3.2.1).

   The two LEDs are Gergo Erdi's standing first check: blink at 1 Hz from the clock that the video
   depends on before believing anything on the screen (his VGA showed nothing because the PLL made
   40 MHz instead of 25.175 MHz while the simulation looked right).  Both should blink at exactly
   1 Hz, in step, for as long as you watch. *)
open! Base
open Hardcaml
open Signal

(* LED toggling every [half_period] cycles: 1 Hz when half_period = f / 2.  The terminal count is
   compared one cycle early and registered, so at 250 MHz the 27-bit comparison is not in series
   with the counter's reset (it was the critical path, 172 MHz, before). *)
let blink ~spec ~half_period =
  assert (half_period >= 2);
  let w = num_bits_to_represent (half_period - 1) in
  let c = wire w and led = wire 1 in
  let wrap = reg spec (c ==:. half_period - 2) (* high while c = half_period - 1 *) in
  c <== reg spec (mux2 wrap (zero w) (c +:. 1));
  led <== reg spec (led ^: wrap);
  led

(* A pixel source maps the raster position to a colour, with registers inside it.  Its latency is
   carried by the signals (Hardcaml_latency.Delayed, the counterpart of Gergo's RetroClash
   Delayed.hs): x and y arrive at the raster counters' latency, the colour leaves at whatever the
   source's registers make it, and [pixel_circuit] delays the syncs to match with [align].  A
   source that registers its colour one time fewer or more than it says needs no change here;
   one that combines signals of different latencies does not build. *)
module D = Hardcaml_latency.Delayed

type source = spec:Reg_spec.t -> x:D.t -> y:D.t -> D.t * D.t * D.t

module Pattern = Test_pattern.Make (D)

(* The pattern is registered once.  [misdeclare] exists only for a negative control of the
   end-to-end simulation: the registered colour is declared to be at the raster's latency, as if
   it were combinational, so [align] leaves the syncs one pixel early.  It is the one way to
   misalign this design, and it needs [D.of_signal], the escape hatch that asserts a latency
   without checking it. *)
let test_pattern ?(misdeclare = false) ~width ~height () : source =
 fun ~spec ~x ~y ->
  let r, g, b = Pattern.create ~width ~height ~x ~y in
  let r, g, b = D.reg spec r, D.reg spec g, D.reg spec b in
  if misdeclare
  then
    let lie c = D.of_signal ~latency:(D.latency_exn x) (D.to_signal c) in
    lie r, lie g, lie b
  else r, g, b

(* [plant_sync_short] removes one register from the delayed syncs and blank, for the negative
   control of the latency check (test/test_latency.ml): building the circuit must fail. *)
let pixel_circuit ?(name = "hdmi_pixel") ?mutant ?(timing = Video_timing.vga_640x480_60)
    ?(plant_sync_short = false) ~blink_half_period ~(source : source) () =
  let clock = Signal.input "clock" 1 and clear = Signal.input "clear" 1 in
  let spec = Reg_spec.create ~clock ~clear () in
  let t = Video_timing.create ~spec timing in
  let r, g, b = source ~spec ~x:t.x ~y:t.y in
  let de, hs, vs, r, g, b =
    match D.align spec [ t.de; t.hsync; t.vsync; r; g; b ] with
    | [ de; hs; vs; r; g; b ] -> de, hs, vs, r, g, b
    | _ -> assert false
  in
  let de, hs, vs =
    if plant_sync_short
    then (
      (* the planted bug: the syncs and blank delayed by hand, one register short *)
      let n = D.latency_exn r - D.latency_exn t.de - 1 in
      D.pipeline spec ~n t.de, D.pipeline spec ~n t.hsync, D.pipeline spec ~n t.vsync)
    else de, hs, vs
  in
  (* The TMDS encoder is an existing, unchecked circuit with one register; [D.lift] checks that
     de, the pixel and the control bits agree on latency before it. *)
  let enc d c0 c1 =
    D.lift ~name:"tmds" ~latency:1
      (function
        | [ de; d; c0; c1 ] -> fst (Tmds.create ?mutant ~spec ~de ~d ~c0 ~c1 ())
        | _ -> assert false)
      [ de; d; c0; c1 ]
    |> D.to_signal
  in
  let wb = enc b hs vs and wg = enc g D.gnd D.gnd and wr = enc r D.gnd D.gnd in
  (* toggle changes on the same edge as the encoders' output registers *)
  let toggle = Signal.wire 1 in
  Signal.(toggle <== reg spec ~:toggle);
  Circuit.create_exn ~name
    Signal.
      [ output "word_b" wb; output "word_g" wg; output "word_r" wr; output "toggle" toggle
      ; output "led_1hz" (blink ~spec ~half_period:blink_half_period) ]

let serial_circuit ?(name = "hdmi_serial") ~bits_per_cycle ~blink_half_period () =
  let clock = input "clock" 1 and clear = input "clear" 1 in
  let spec = Reg_spec.create ~clock ~clear () in
  let toggle = input "toggle" 1 in
  let words = List.map [ "word_b"; "word_g"; "word_r" ] ~f:(fun n -> input n 10) in
  let s = Serialiser.create ~spec ~bits_per_cycle ~toggle ~words in
  let lanes = List.mapi s.lanes ~f:(fun i l -> output (Printf.sprintf "lane%d" i) l) in
  Circuit.create_exn ~name
    (lanes @ [ output "armed" s.armed; output "slip" s.slip
             ; output "led_1hz" (blink ~spec ~half_period:blink_half_period) ])
