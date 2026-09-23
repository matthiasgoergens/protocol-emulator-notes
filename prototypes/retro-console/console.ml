(* Systolic retro console video chip, NTSC, racing the beam.

   Clock: 16 x the NTSC colour subcarrier = 57.272727 MHz; a line is 3640 clocks (227.5 subcarrier
   cycles), a field 262 lines, progressive ("240p").
   Per line the CPU streams a 54-byte packet into a byte-wide shift chain (one byte per strobe):
     0 colA, 1 colB, 2-3 u0 (little endian), 4-5 step, then 16 x (x, bitmap, colour).
   The packet is copied into the active registers at the start of the line.
   Background: u = u0 + px * step (8.8 fixed point, 16 bits wrapping); colour = bit 12 of u ? colB : colA.
   Sprites: 16 cells in a pipeline; cell i covers pixels x .. x+15, bitmap bit 7 is leftmost, each
   bit two pixels wide; later cells win. Colour byte: hue (4 bits, 0 = grey) and luma (0..10).
   Pixels: 256 per line, 11 clocks each.
   Outputs: luma DAC code (0 = sync tip, 4 = blank/black, 14 = white), chroma pin driven with a
   square wave for burst and coloured pixels, a second chroma pin driven for coloured pixels only
   (doubles saturation relative to burst). *)
open Hardcaml
open Signal

let cpl = 3640
let lpf = 262
let sync_len = 269
let half = 1820
let burst_start = 304
let burst_len = 144
let pixc = 11
let npix = 256
let vis_start = 722
let first_vis = 30
let nvis = 224
let vsync_lines = 3
let nspr = 16
let plen = 6 + 3 * nspr
let burst_shift = 8

let create ~clock ~clear ~din ~strobe =
  let spec = Reg_spec.create ~clock ~clear () in
  let hcount = reg_fb spec ~width:12 ~f:(fun h -> mux2 (h ==:. (cpl - 1)) (zero 12) (h +:. 1)) in
  let line_end = hcount ==:. (cpl - 1) in
  let vcount = reg_fb spec ~enable:line_end ~width:9 ~f:(fun v -> mux2 (v ==:. (lpf - 1)) (zero 9) (v +:. 1)) in
  let sc = reg_fb spec ~width:4 ~f:(fun s -> s +:. 1) in
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
  let u = Variable.reg spec ~width:16 and px = Variable.reg spec ~width:9 in
  let sub = Variable.reg spec ~width:4 and on = Variable.reg spec ~width:1 in
  let u0 = concat_msb [ pkt 3; pkt 2 ] and step = concat_msb [ pkt 5; pkt 4 ] in
  compile
    [ if_ launch [ u <-- u0; px <--. 0; sub <--. 0; on <-- vdd ]
        [ when_ on.value
            [ if_ (sub.value ==:. (pixc - 1))
                [ sub <--. 0; px <-- px.value +:. 1; u <-- u.value +: step
                ; when_ (px.value ==:. (npix - 1)) [ on <-- gnd ] ]
                [ sub <-- sub.value +:. 1 ] ] ] ];
  let bg = mux2 (bit u.value 12) (pkt 1) (pkt 0) in
  let stage = ref (reg spec (select px.value 7 0), reg spec bg, reg spec on.value) in
  for i = 0 to nspr - 1 do
    let x, col, v = !stage in
    let sx = pkt (6 + 3 * i) and bmp = pkt (7 + 3 * i) and scol = pkt (8 + 3 * i) in
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
  let sq shift = ~:(msb (sc +: shift)) in
  let colour_px = pvalid &: (hue <>:. 0) in
  let chroma_on = burst |: colour_px in
  let chroma_val = mux2 burst (sq (of_int ~width:4 burst_shift)) (sq (hue +:. burst_shift)) in
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
