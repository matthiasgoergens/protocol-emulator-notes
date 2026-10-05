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

(* All outputs carry their latency (Hardcaml_latency.Delayed).  The two counters are one
   register, so that they are at the same latency: in the plain design they were two registers
   updated on the same edge, but [Delayed.reg_fb] gives each feedback register the latency of
   what it reads plus one, and v reads h's wrap, so two separate [reg_fb]s would put v one stage
   after h and the [de] below would not build.  One concatenated register has the same flip-flops
   and the same behaviour.  The counters are the time origin: everything here is at latency 1
   (reg_fb's output), and every pixel source and delayed sync is measured from them. *)
module D = Hardcaml_latency.Delayed

type signals = { x : D.t; y : D.t; de : D.t; hsync : D.t; vsync : D.t }

let create ~spec t =
  let hw = Signal.num_bits_to_represent (total t.h - 1)
  and vw = Signal.num_bits_to_represent (total t.v - 1) in
  let open D in
  let split s = select s (hw - 1) 0, select s (hw + vw - 1) hw in
  let state =
    reg_fb spec ~latency:0 ~width:(hw + vw) ~f:(fun s ->
        let h, v = split s in
        let h_last = h ==:. total t.h - 1 and v_last = v ==:. total t.v - 1 in
        concat_msb
          [ mux2 h_last (mux2 v_last (zero vw) (v +:. 1)) v; mux2 h_last (zero hw) (h +:. 1) ])
  in
  let h, v = split state in
  let in_sync c a = c >=:. a.active + a.front &: (c <:. a.active + a.front + a.sync) in
  let level active_high s = if active_high then s else ~:s in
  { x = h
  ; y = v
  ; de = h <:. t.h.active &: (v <:. t.v.active)
  ; hsync = level t.hsync_active_high (in_sync h t.h)
  ; vsync = level t.vsync_active_high (in_sync v t.v)
  }
