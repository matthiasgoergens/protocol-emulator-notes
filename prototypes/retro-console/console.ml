(* Systolic retro console video chip, PAL, racing the beam.

   Clock: 12 x the PAL colour subcarrier = 53.203425 MHz, which the RP2040 on the demo board can
   produce to within 64 ppm (53.2 MHz); NTSC would need an external oscillator. A line is 3405
   clocks (64.00 us), a field 312 lines, progressive ("288p").
   Per line the CPU streams a 54-byte packet into a byte-wide shift chain (one byte per strobe):
     0 colA, 1 colB, 2-3 u0, 4-5 ustep, 6-7 v0, 8-9 vstep (little endian), then 16 x (x, bitmap, colour).
   The packet is copied into the active registers at the start of the line.
   Background: u = u0 + px * ustep, v = v0 + px * vstep (8.8 fixed point, 16 bits wrapping);
   colour = bit 12 of u XOR bit 12 of v ? colB : colA. With v fixed this is stripes (a perspective
   ground); with both moving it is a rotated, zoomed checkerboard (a rotozoomer).
   Sprites: 16 cells in a pipeline; cell i covers pixels x .. x+15, bitmap bit 7 is leftmost, each
   bit two pixels wide; later cells win. Colour byte: hue (4 bits, 0 = grey) and luma (0..10).
   Pixels: 256 per line, 10 clocks each.
   Colour: hue h (1..12) is a square wave at phase 15 + 30 (h - 1) degrees relative to the U axis;
   PAL flips the sign of V on alternate lines, which mirrors the phase (p -> 11 - p), and the burst
   swings between 135 and 225 degrees the same way. Hues 13..15 alias to 1..3.
   Outputs: luma DAC code (0 = sync tip, 4 = blank/black, 14 = white), chroma pin driven with a
   square wave for burst and coloured pixels, a second chroma pin driven for coloured pixels only
   (doubles saturation relative to burst). *)
open Hardcaml
open Signal

let cpl = 3405
let lpf = 312
let sync_len = 250
let half = 1702
let burst_start = 298
let burst_len = 120
let pixc = 10
let npix = 256
let vis_start = 662
let first_vis = 40
let nvis = 240
let vsync_lines = 3
let nspr = 16
let plen = 10 + 3 * nspr
let burst_phase = 4                     (* 15 + 30 * 4 = 135 degrees *)

let create ~clock ~clear ~din ~strobe =
  let spec = Reg_spec.create ~clock ~clear () in
  let hcount = reg_fb spec ~width:12 ~f:(fun h -> mux2 (h ==:. (cpl - 1)) (zero 12) (h +:. 1)) in
  let line_end = hcount ==:. (cpl - 1) in
  let vcount = reg_fb spec ~enable:line_end ~width:9 ~f:(fun v -> mux2 (v ==:. (lpf - 1)) (zero 9) (v +:. 1)) in
  let sc = reg_fb spec ~width:4 ~f:(fun s -> mux2 (s ==:. 11) (zero 4) (s +:. 1)) in
  (* systolic packet chain *)
  let shadow = Array.make plen (zero 8) in
  let prev = ref din in
  for j = 0 to plen - 1 do
    let r = reg spec ~enable:strobe !prev in
    shadow.(j) <- r; prev := r
  done;
  let line_start = hcount ==:. 0 in
  let act = Array.map (fun s -> reg spec ~enable:line_start s) shadow in
  let pkt k = act.(plen - 1 - k) in
  let vis_line = (vcount >=:. first_vis) &: (vcount <:. (first_vis + nvis)) in
  let launch = vis_line &: (hcount ==:. (vis_start - nspr - 2)) in
  let open Always in
  let u = Variable.reg spec ~width:16 and v = Variable.reg spec ~width:16 and px = Variable.reg spec ~width:9 in
  let sub = Variable.reg spec ~width:4 and on = Variable.reg spec ~width:1 in
  let u0 = concat_msb [ pkt 3; pkt 2 ] and step = concat_msb [ pkt 5; pkt 4 ] in
  let v0 = concat_msb [ pkt 7; pkt 6 ] and vstep = concat_msb [ pkt 9; pkt 8 ] in
  compile
    [ if_ launch [ u <-- u0; v <-- v0; px <--. 0; sub <--. 0; on <-- vdd ]
        [ when_ on.value
            [ if_ (sub.value ==:. (pixc - 1))
                [ sub <--. 0; px <-- px.value +:. 1; u <-- u.value +: step; v <-- v.value +: vstep
                ; when_ (px.value ==:. (npix - 1)) [ on <-- gnd ] ]
                [ sub <-- sub.value +:. 1 ] ] ] ];
  let bg = mux2 (bit u.value 12 ^: bit v.value 12) (pkt 1) (pkt 0) in
  let stage = ref (reg spec (select px.value 7 0), reg spec bg, reg spec on.value) in
  for i = 0 to nspr - 1 do
    let x, col, v = !stage in
    let sx = pkt (10 + 3 * i) and bmp = pkt (11 + 3 * i) and scol = pkt (12 + 3 * i) in
    let d = uresize x 9 -: uresize sx 9 in
    let cover = v &: (d <:. 16) in
    let b = mux (select d 3 1) (List.init 8 (fun k -> bit bmp (7 - k))) in
    stage := (reg spec x, reg spec (mux2 (cover &: b) scol col), reg spec v)
  done;
  let _, pcol, pvalid = !stage in
  let hue = select pcol 7 4 and luma = select pcol 3 0 in
  let luma_c = mux2 (luma >:. 10) (of_int ~width:4 10) luma in
  let vsync = vcount <:. vsync_lines in
  let sync_low =
    mux2 vsync
      ((hcount <:. (half - sync_len)) |: ((hcount >=:. half) &: (hcount <:. (cpl - sync_len))))
      (hcount <:. sync_len) in
  let code = mux2 sync_low (zero 4) (mux2 pvalid (luma_c +:. 4) (of_int ~width:4 4)) in
  let burst = ~:vsync &: (hcount >=:. burst_start) &: (hcount <:. (burst_start + burst_len)) in
  let odd = lsb vcount in
  let mirror p = mux2 odd (of_int ~width:4 11 -: p) p in
  let sq p =
    let s = uresize sc 5 +: uresize p 5 in
    let m = mux2 (s >=:. 12) (s -:. 12) s in
    m <:. 6 in
  let hue_p = mux2 (hue >:. 12) (hue -:. 13) (hue -:. 1) in
  let colour_px = pvalid &: (hue <>:. 0) in
  let chroma_on = burst |: colour_px in
  let chroma_val = mux2 burst (sq (mirror (of_int ~width:4 burst_phase))) (sq (mirror hue_p)) in
  let r = reg spec in
  r code, r chroma_val, r chroma_on, r colour_px, line_start, pcol, pvalid, hcount, vcount

let circuit () =
  let clock = input "clock" 1 and clear = input "clear" 1 in
  let din = input "din" 8 and strobe = input "strobe" 1 in
  let code, cv, con, c2on, ls, pcol, pvalid, h, v = create ~clock ~clear ~din ~strobe in
  Circuit.create_exn ~name:"retro_console"
    [ output "luma" code; output "chroma" cv; output "chroma_oe" con; output "chroma2_oe" c2on
    ; output "line_start" ls; output "pix_col" pcol; output "pix_valid" pvalid
    ; output "hcount" h; output "vcount" v ]
