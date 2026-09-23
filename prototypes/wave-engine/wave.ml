(* Wave engine: the picture is a sum of up to ten plane waves, racing the beam, PAL.

   Per line the CPU sends a 66-byte packet: 16 palette colours, then for each of ten waves its
   start phase for this line (2 bytes, = phi + ky * line, computed by the CPU), its phase step
   per pixel (2 bytes, = kx) and an amplitude byte (bit 7 on, bit 6 negate, bits 1..0 right
   shift). Phases are 16 bits for a full cycle.

   The waves sit on a ring of ten records that rotates once per clock, so over a pixel's ten
   clocks every record passes the head once. The head looks up the sine of its phase (top 8
   bits, a 256-entry table of 60 sin), applies its amplitude, adds it to the pixel sum, and
   advances its own phase by its step: one table and one phase adder serve every wave. After
   ten clocks the sum picks the palette entry clamp(((sum + 8) >> 4) + 8, 0, 15): rounded, so
   weak waves show both their crests and their troughs.

   Timing, sync and colour output are the PAL retro console's. *)
open Hardcaml
open Signal

let cpl = 3405 and lpf = 312 and vis_start = 662 and pixc = 10 and first_vis = 40 and nvis = 240 and npix = 256
let sync_len = 250 and half = 1702 and burst_start = 298 and burst_len = 120 and vsync_lines = 3
let nw = 10
let plen = 16 + 5 * nw
let sine = Array.init 256 (fun i -> int_of_float (Float.round (60.0 *. sin (2.0 *. Float.pi *. float i /. 256.0))))

let create ~clock ~clear ~din ~strobe =
  let spec = Reg_spec.create ~clock ~clear () in
  let hcount = reg_fb spec ~width:12 ~f:(fun h -> mux2 (h ==:. (cpl - 1)) (zero 12) (h +:. 1)) in
  let line_end = hcount ==:. (cpl - 1) in
  let vcount = reg_fb spec ~enable:line_end ~width:9 ~f:(fun v -> mux2 (v ==:. (lpf - 1)) (zero 9) (v +:. 1)) in
  let shadow = Array.make plen (zero 8) in
  let prev = ref din in
  for j = 0 to plen - 1 do let r = reg spec ~enable:strobe !prev in shadow.(j) <- r; prev := r done;
  let line_start = hcount ==:. 0 in
  let act = Array.map (fun s -> reg spec ~enable:line_start s) shadow in
  let pkt k = act.(plen - 1 - k) in
  let pal = List.init 16 pkt in
  let wbyte w k = pkt (16 + 5 * w + k) in
  let vis_line = (vcount >=:. first_vis) &: (vcount <:. (first_vis + nvis)) in
  let launch = vis_line &: (hcount ==:. (vis_start - pixc - 1)) in
  (* the ring: slot 0 is the head; every clock slot j takes slot j+1 and slot nw-1 takes the
     processed head, so a record returns to the head every ten clocks *)
  let ph = Array.init nw (fun _ -> wire 16) and st = Array.init nw (fun _ -> wire 16) and am = Array.init nw (fun _ -> wire 8) in
  let head_sin = mux (select ph.(0) 15 8) (List.map (fun v -> of_int ~width:8 (v land 0xFF)) (Array.to_list sine)) in
  let a0 = am.(0) in
  let shifted = mux (select a0 1 0) [ sresize head_sin 12; sra (sresize head_sin 12) 1; sra (sresize head_sin 12) 2; sra (sresize head_sin 12) 3 ] in
  let contrib = mux2 (bit a0 7) (mux2 (bit a0 6) (negate shifted) shifted) (zero 12) in
  let running = wire 1 in
  let set_or_rot j ~load ~rot = mux2 launch load (mux2 running rot (match j with _ -> rot)) in
  let regs_ph = Array.init nw (fun j ->
    let load = concat_msb [ wbyte j 1; wbyte j 0 ] in
    let rot = if j = nw - 1 then ph.(0) +: st.(0) else ph.(j + 1) in
    reg spec (set_or_rot j ~load ~rot)) in
  let regs_st = Array.init nw (fun j ->
    let load = concat_msb [ wbyte j 3; wbyte j 2 ] in
    let rot = if j = nw - 1 then st.(0) else st.(j + 1) in
    reg spec (set_or_rot j ~load ~rot)) in
  let regs_am = Array.init nw (fun j ->
    let load = wbyte j 4 in
    let rot = if j = nw - 1 then am.(0) else am.(j + 1) in
    reg spec (set_or_rot j ~load ~rot)) in
  Array.iteri (fun j r -> ph.(j) <== r; st.(j) <== regs_st.(j); am.(j) <== regs_am.(j)) regs_ph;
  let open Always in
  let sub = Variable.reg spec ~width:4 and px = Variable.reg spec ~width:9 and on = Variable.reg spec ~width:1 in
  let acc = Variable.reg spec ~width:12 in
  let pix = Variable.reg spec ~width:8 and pix_new = Variable.wire ~default:gnd in
  let total = acc.value +: contrib in
  let idx = let v = sra (total +:. 8) 4 +:. 8 in mux2 (v <+. 0) (zero 12) (mux2 (v >+. 15) (of_int ~width:12 15) v) in
  compile
    [ if_ launch [ on <-- vdd; sub <--. 0; px <--. 0; acc <--. 0 ]
        [ when_ on.value
            [ if_ (sub.value ==:. (pixc - 1))
                [ sub <--. 0; acc <--. 0; pix <-- mux (select idx 3 0) pal; pix_new <-- vdd
                ; px <-- px.value +:. 1; when_ (px.value ==:. (npix - 1)) [ on <-- gnd ] ]
                [ sub <-- sub.value +:. 1; acc <-- total ] ] ] ];
  running <== on.value;
  let pvalid = reg spec (vis_line &: (hcount >=:. vis_start) &: (hcount <:. (vis_start + npix * pixc))) in
  let colour = pix.value in
  (* PAL output *)
  let sc = reg_fb spec ~width:4 ~f:(fun c -> mux2 (c ==:. 11) (zero 4) (c +:. 1)) in
  let hue = select colour 7 4 and luma = select colour 3 0 in
  let luma_c = mux2 (luma >:. 10) (of_int ~width:4 10) luma in
  let vsync = vcount <:. vsync_lines in
  let sync_low = mux2 vsync ((hcount <:. (half - sync_len)) |: ((hcount >=:. half) &: (hcount <:. (cpl - sync_len)))) (hcount <:. sync_len) in
  let code = mux2 sync_low (zero 4) (mux2 pvalid (luma_c +:. 4) (of_int ~width:4 4)) in
  let burst = ~:vsync &: (hcount >=:. burst_start) &: (hcount <:. (burst_start + burst_len)) in
  let odd = lsb vcount in
  let mirror q = mux2 odd (of_int ~width:4 11 -: q) q in
  let sq q = let t = uresize sc 5 +: uresize q 5 in let m = mux2 (t >=:. 12) (t -:. 12) t in m <:. 6 in
  let hue_p = mux2 (hue >:. 12) (hue -:. 13) (hue -:. 1) in
  let colour_px = pvalid &: (hue <>:. 0) in
  let chroma_val = mux2 burst (sq (mirror (of_int ~width:4 4))) (sq (mirror hue_p)) in
  let r = reg spec in
  r code, r chroma_val, r (burst |: colour_px), r colour_px, pix.value, r pix_new.value, hcount, vcount

let circuit () =
  let clock = input "clock" 1 and clear = input "clear" 1 and din = input "din" 8 and strobe = input "strobe" 1 in
  let code, cv, con, c2on, pix, pnew, h, v = create ~clock ~clear ~din ~strobe in
  Circuit.create_exn ~name:"wave_engine"
    [ output "luma" code; output "chroma" cv; output "chroma_oe" con; output "chroma2_oe" c2on
    ; output "pix" pix; output "pix_new" pnew; output "hcount" h; output "vcount" v ]

(* reference model: the palette colours of one line *)
let reference p =
  Array.init npix (fun px ->
    let sum = ref 0 in
    for w = 0 to nw - 1 do
      let b k = p.(16 + 5 * w + k) in
      let ph0 = b 0 lor (b 1 lsl 8) and step = b 2 lor (b 3 lsl 8) and a = b 4 in
      let phase = (ph0 + px * step) land 0xFFFF in
      let s = sine.(phase lsr 8) in
      let sh = s asr (a land 3) in
      if a land 0x80 <> 0 then sum := !sum + (if a land 0x40 <> 0 then - sh else sh)
    done;
    let v = ((!sum + 8) asr 4) + 8 in
    p.(max 0 (min 15 v)))
