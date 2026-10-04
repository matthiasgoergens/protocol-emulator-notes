(* Raster timing.  Counters run over the whole line and frame, active area first:
   h = 0 .. active-1 visible, then front porch, sync pulse, back porch; likewise v.

   640 x 480 at 60 Hz is CEA-861 format 1 (the one video format every HDMI sink must accept) and
   the VESA DMT 640x480@60 mode: 800 pixels per line with H front porch 16, sync 96, back porch 48,
   and 525 lines with V front porch 10, sync 2, back porch 33; both syncs negative.  (DMT lists
   8-pixel and 8-line borders separately; folded into the porches they give the same numbers.)

   The nominal pixel clock is 25.175 MHz; we use 25.000 MHz from the board's oscillator, which
   gives 31.25 kHz and 59.52 Hz.  Monitors normally lock to that; Gergo Erdi's ULX3S HDMI design
   runs at the same 25 MHz.

   Gergo's RetroClash.VGA640x480 uses V 11/2/31 with a line counter of type Index 524, so his
   frame is 524 lines, one short of the standard.  We use the DMT values. *)
open! Base
open Hardcaml
open Signal

type axis = { active : int; front : int; sync : int; back : int }

type t = { h : axis; v : axis; hsync_active_high : bool; vsync_active_high : bool }

let total a = a.active + a.front + a.sync + a.back

let vga_640x480_60 =
  { h = { active = 640; front = 16; sync = 96; back = 48 }
  ; v = { active = 480; front = 10; sync = 2; back = 33 }
  ; hsync_active_high = false
  ; vsync_active_high = false
  }

(* A small mode for fast simulations of the same logic. *)
let tiny =
  { h = { active = 16; front = 2; sync = 3; back = 4 }
  ; v = { active = 6; front = 1; sync = 2; back = 2 }
  ; hsync_active_high = false
  ; vsync_active_high = false
  }

type signals = { x : Signal.t; y : Signal.t; de : Signal.t; hsync : Signal.t; vsync : Signal.t }

(* All outputs are functions of the registered counters, so they are valid together in the same
   cycle; a pixel generator that is combinational in (x, y) stays aligned with the syncs. *)
let create ~spec t =
  let hw = num_bits_to_represent (total t.h - 1) and vw = num_bits_to_represent (total t.v - 1) in
  let h = wire hw and v = wire vw in
  let h_last = h ==:. total t.h - 1 and v_last = v ==:. total t.v - 1 in
  h <== reg spec (mux2 h_last (zero hw) (h +:. 1));
  v <== reg spec (mux2 h_last (mux2 v_last (zero vw) (v +:. 1)) v);
  let in_sync c a = c >=:. a.active + a.front &: (c <:. a.active + a.front + a.sync) in
  let level active_high s = if active_high then s else ~:s in
  { x = h
  ; y = v
  ; de = h <:. t.h.active &: (v <:. t.v.active)
  ; hsync = level t.hsync_active_high (in_sync h t.h)
  ; vsync = level t.vsync_active_high (in_sync v t.v)
  }
