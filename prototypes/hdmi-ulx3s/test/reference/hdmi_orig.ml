(* REFERENCE COPY, frozen: hw/ or demo/ as of emulator 7cf2f05, before the Delayed rewrite.
   Used only by test/test_latency.ml to show the rewrite is cycle-identical. Do not edit. *)
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

(* A pixel source maps the raster position to a colour, with a fixed latency in pixel clocks
   (registers inside it); the syncs are delayed to match.  Gergo's RetroClash Delayed.hs carries
   the same latency in the type; here it is a number checked by the end-to-end simulation. *)
type source = spec:Reg_spec.t -> x:Signal.t -> y:Signal.t -> (Signal.t * Signal.t * Signal.t) * int

(* The pattern is registered once, so its latency is 1.  [declared_latency] exists only to plant
   a sync/pixel misalignment in a negative control. *)
let test_pattern ?(declared_latency = 1) ~width ~height () : source =
 fun ~spec ~x ~y ->
  let r, g, b = Test_pattern_orig.create ~width ~height ~x ~y in
  (reg spec r, reg spec g, reg spec b), declared_latency

let pixel_circuit ?(name = "hdmi_pixel") ?mutant ?(timing = Video_timing_orig.vga_640x480_60) ~blink_half_period
    ~(source : source) () =
  let clock = input "clock" 1 and clear = input "clear" 1 in
  let spec = Reg_spec.create ~clock ~clear () in
  let t = Video_timing_orig.create ~spec timing in
  let (r, g, b), latency = source ~spec ~x:t.x ~y:t.y in
  let delay s = pipeline spec ~n:latency s in
  let de = delay t.de and hs = delay t.hsync and vs = delay t.vsync in
  let enc d c0 c1 = fst (Hdmi_hw.Tmds.create ?mutant ~spec ~de ~d ~c0 ~c1 ()) in
  let wb = enc b hs vs and wg = enc g gnd gnd and wr = enc r gnd gnd in
  (* toggle changes on the same edge as the encoders' output registers *)
  let toggle = wire 1 in
  toggle <== reg spec ~:toggle;
  Circuit.create_exn ~name
    [ output "word_b" wb; output "word_g" wg; output "word_r" wr; output "toggle" toggle
    ; output "led_1hz" (blink ~spec ~half_period:blink_half_period) ]

let serial_circuit ?(name = "hdmi_serial") ~bits_per_cycle ~blink_half_period () =
  let clock = input "clock" 1 and clear = input "clear" 1 in
  let spec = Reg_spec.create ~clock ~clear () in
  let toggle = input "toggle" 1 in
  let words = List.map [ "word_b"; "word_g"; "word_r" ] ~f:(fun n -> input n 10) in
  let s = Hdmi_hw.Serialiser.create ~spec ~bits_per_cycle ~toggle ~words in
  let lanes = List.mapi s.lanes ~f:(fun i l -> output (Printf.sprintf "lane%d" i) l) in
  Circuit.create_exn ~name
    (lanes @ [ output "armed" s.armed; output "slip" s.slip
             ; output "led_1hz" (blink ~spec ~half_period:blink_half_period) ])
