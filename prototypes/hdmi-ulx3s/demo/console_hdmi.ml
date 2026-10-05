(* The retro console (../../retro-console/console.ml, the chip's video generator, unchanged) shown
   over HDMI.  The console races its own PAL beam: 256 x 240 pixels of 10 clocks each, 3,405 clocks
   per line, 312 lines per field.  Here it runs on the 25 MHz pixel clock, so a field takes 42.5 ms
   (23.5 fields/s), and its pixels go into a frame buffer that the 640 x 480 raster reads at 2 x 2
   scale, centred: 512 x 480 with 64-pixel black borders left and right.  The scaling and centring
   are what Gergo Erdi's RetroClash Video.hs calls scale and center.

   The CPU's part (game.ml, building one 54-byte packet per line) is precomputed into a ROM of
   [fields] consecutive fields, which loops.  The console gets each packet exactly as main.ml's
   testbench feeds it: decided at hcount 1000 for the next line, one byte per clock from 1001.

   The pixel colour (hue 0..15, 0 = grey; luma 0..10) becomes RGB through an approximate palette
   (palette below), not through the composite path of the software TV.

   Memories are Verilog modules instantiated here (rtl/packet_rom.v, rtl/frame_buffer.v), so that
   yosys infers block RAM without guessing. *)
open! Base
open Hardcaml
open Signal

let lines = Console.nvis (* 240 *)
let plen = Console.plen (* 54 *)

(* Palette: luma 0..10 to Y = luma / 10; hue h > 0 at angle 15 + 30 (h' - 1) degrees from the U
   axis (hues 13..15 alias to 1..3, as in console.ml), fixed saturation; BT.601 YUV to RGB. *)
let palette_rgb col =
  let hue = col lsr 4 and luma = min 10 (col land 15) in
  let y = Float.of_int luma /. 10.0 in
  let u, v =
    if hue = 0 then 0.0, 0.0
    else
      let h = if hue > 12 then hue - 13 else hue - 1 in
      let a = Float.of_int (15 + (30 * h)) *. Float.pi /. 180.0 in
      let s = 0.22 in
      s *. Float.cos a, s *. Float.sin a
  in
  let c x = Int.max 0 (Int.min 255 (Float.iround_nearest_exn (x *. 255.0))) in
  c (y +. (1.140 *. v)), c (y -. (0.395 *. u) -. (0.581 *. v)), c (y +. (2.032 *. u))

let rom_depth ~fields = fields * lines * plen

let source ~fields ~packet_file : Hdmi_hw.Hdmi.source =
 fun ~spec ~x ~y ->
  (* --- the console and its packet feed --- *)
  let din = wire 8 and strobe = wire 1 in
  let clock = Reg_spec.clock spec and clear = Reg_spec.clear spec in
  let _, _, _, _, _, pcol, pvalid, hcount, vcount = Console.create ~clock ~clear ~din ~strobe in
  let line_end = hcount ==:. Console.cpl - 1 in
  let field_end = line_end &: (vcount ==:. Console.lpf - 1) in
  let fw = Int.max 1 (num_bits_to_represent (fields - 1)) in
  let field = reg_fb spec ~enable:field_end ~width:fw ~f:(fun f -> mux2 (f ==:. fields - 1) (zero fw) (f +:. 1)) in
  (* next line, as main.ml's run: (v + 1) mod lpf; a packet only if it is visible *)
  let next = mux2 (vcount ==:. Console.lpf - 1) (zero 9) (vcount +:. 1) in
  let next_vis = next >=:. Console.first_vis &: (next <:. Console.first_vis + lines) in
  let sending = next_vis &: (hcount >=:. 1001) &: (hcount <:. 1001 + plen) in
  (* The ROM has one cycle of read latency, so byte j is addressed at hcount 1000 + j and reaches
     [din] at 1001 + j.  Address = (field * lines + next - first_vis) * plen + j. *)
  let aw = num_bits_to_represent (rom_depth ~fields - 1) in
  let mulc s c = uresize (s *: of_int ~width:(num_bits_to_represent c) c) aw in
  let line_idx = uresize (next -:. Console.first_vis) aw in
  let j = select (hcount -:. 1000) 5 0 in
  let addr = mulc (mulc (uresize field aw) lines +: line_idx) plen +: uresize j aw in
  assert (aw <= 17) (* packet_rom.v's address width: at most 10 fields *);
  let rom =
    Instantiation.create ()
      ~parameters:[ Parameter.create ~name:"DEPTH" ~value:(Int (rom_depth ~fields))
                  ; Parameter.create ~name:"FILE" ~value:(String packet_file) ]
      ~name:"packet_rom" ~inputs:[ "clock", clock; "addr", uresize addr 17 ] ~outputs:[ "data", 8 ]
  in
  din <== Map.find_exn rom "data";
  strobe <== sending;
  (* --- writer: sample each console pixel in the middle of its 10 clocks (as main.ml's check) --- *)
  let prev_valid = reg spec pvalid in
  let first = pvalid &: ~:prev_valid in
  let sub = wire 4 and col = wire 8 in
  let sub_now = mux2 first (zero 4) sub and col_now = mux2 first (zero 8) col in
  let sub_last = sub_now ==:. Console.pixc - 1 in
  sub <== reg spec (mux2 sub_last (zero 4) (sub_now +:. 1));
  col <== reg spec (mux2 sub_last (col_now +:. 1) col_now);
  let we = pvalid &: (sub_now ==:. 5) in
  let wline = select (vcount -:. Console.first_vis) 7 0 in
  let waddr = concat_msb [ wline; col_now ] in
  (* --- reader: 2 x 2 scale, centred.  Latency-checked (Hardcaml_latency.Delayed): x and y come
     in at the raster's latency, the frame buffer read is one register, and the colour leaves
     three registers later; hdmi.ml delays the syncs to match.  The console and the writer above
     are plain signals: they run on the console's own beam, and the frame buffer is where the
     two time bases meet, so no latency relates them. --- *)
  let module D = Hardcaml_latency.Delayed in
  let x0 = 64 in
  let inside = D.(x >=:. x0 &: (x <:. x0 + 512) &: (y <:. 480)) in
  let xr = D.(x -:. x0) in
  let raddr = D.(reg spec (concat_msb [ select y 8 1; select xr 8 1 ])) in
  let inside1 = D.reg spec inside in
  let pix =
    D.lift ~name:"frame_buffer" ~latency:1
      (function
        | [ raddr ] ->
          let fb =
            Instantiation.create () ~name:"frame_buffer"
              ~inputs:[ "clock", clock; "we", we; "waddr", waddr; "wdata", pcol; "raddr", raddr ]
              ~outputs:[ "rdata", 8 ]
          in
          Map.find_exn fb "rdata"
        | _ -> assert false)
      [ raddr ]
  in
  let inside2 = D.reg spec inside1 in
  let channel f =
    let table = List.init 256 ~f:(fun c -> D.of_int ~width:8 (f (palette_rgb c))) in
    D.(reg spec (mux2 inside2 (mux pix table) (zero 8)))
  in
  channel (fun (r, _, _) -> r), channel (fun (_, g, _) -> g), channel (fun (_, _, b) -> b)
