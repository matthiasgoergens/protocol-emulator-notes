(* The crazy network as hardware. The wiring (left neighbour, sparse partners) is fixed at
   elaboration from Model.partner: those are the wires that would be taped out. Everything else
   is loaded through two byte chains:
     config chain (cfg_strobe), 147 bytes: p, tap, reset, 16 palette colours, then per cell op, k
     seed chain (seed_strobe), 4 bytes, sent by the CPU during the previous line and XORed into
     cells 0..3 at the start of the line (after clearing the state if reset is set).
   Timing and colour output are the PAL console's: 3405 clocks per line, 312 lines, pixels of 10
   clocks, 12 x fsc, hue by square-wave phase mirrored on alternate lines. *)
open Hardcaml
open Signal

let n = Model.n
let cpl = Model.cpl and lpf = Model.lpf and vis_start = Model.vis_start
let first_vis = Model.first_vis and nvis = Model.nvis and npix = Model.npix and pixc = Model.pixc
let sync_len = 250 and half = 1702 and burst_start = 298 and burst_len = 120 and vsync_lines = 3
let cfg_len = 3 + 16 + 2 * n

let chain spec ~enable ~din len =
  let regs = Array.make len (zero 8) in
  let prev = ref din in
  for j = 0 to len - 1 do let r = reg spec ~enable !prev in regs.(j) <- r; prev := r done;
  (* after shifting bytes b0..b(len-1) in order, regs.(len-1-k) holds b_k *)
  fun k -> regs.(len - 1 - k)

let create ~clock ~clear ~cfg_in ~cfg_strobe ~seed_in ~seed_strobe =
  let spec = Reg_spec.create ~clock ~clear () in
  let cfg = chain (Reg_spec.create ~clock ()) ~enable:cfg_strobe ~din:cfg_in cfg_len in
  let seed = chain spec ~enable:seed_strobe ~din:seed_in 4 in
  let p = cfg 0 and tap = cfg 1 and reset = lsb (cfg 2) in
  let pal = List.init 16 (fun i -> cfg (3 + i)) in
  let op i = select (cfg (19 + 2 * i)) 1 0 and k i = cfg (20 + 2 * i) in
  let hcount = reg_fb spec ~width:12 ~f:(fun h -> mux2 (h ==:. (cpl - 1)) (zero 12) (h +:. 1)) in
  let line_end = hcount ==:. (cpl - 1) in
  let vcount = reg_fb spec ~enable:line_end ~width:9 ~f:(fun v -> mux2 (v ==:. (lpf - 1)) (zero 9) (v +:. 1)) in
  let pc = reg_fb spec ~width:4 ~f:(fun c -> mux2 line_end (zero 4) (mux2 (c +:. 1 ==: select p 3 0) (zero 4) (c +:. 1))) in
  let line_start = hcount ==:. 0 in
  let do_step = (pc ==:. 0) &: ~:line_start in
  let s = Array.init n (fun _ -> wire 8) in
  let next = Array.init n (fun i ->
    let a = s.(Model.left.(i)) and b = s.(Model.partner.(i)) in
    let v = mux (op i) [ a +: b; a ^: b; a -: b; mux2 (a >: b) a b ] in
    v +: k i) in
  let regs = Array.init n (fun i ->
    let base = mux2 reset (zero 8) s.(i) in
    let injected = if i < 4 then base ^: seed i else base in
    reg spec (mux2 line_start injected (mux2 do_step next.(i) s.(i)))) in
  Array.iteri (fun i r -> s.(i) <== r) regs;
  let tap_val = mux (select tap 5 0) (Array.to_list s) in
  let colour = reg spec (mux (select tap_val 7 4) pal) in
  (* PAL composite output, as in the retro console *)
  let vis_line = (vcount >=:. first_vis) &: (vcount <:. (first_vis + nvis)) in
  let pvalid = reg spec (vis_line &: (hcount >=:. vis_start) &: (hcount <:. (vis_start + npix * pixc))) in
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
  r code, r chroma_val, r (burst |: colour_px), r colour_px, colour, hcount, vcount

let circuit () =
  let clock = input "clock" 1 and clear = input "clear" 1 in
  let cfg_in = input "cfg_in" 8 and cfg_strobe = input "cfg_strobe" 1 in
  let seed_in = input "seed_in" 8 and seed_strobe = input "seed_strobe" 1 in
  let code, cv, con, c2on, colour, h, v = create ~clock ~clear ~cfg_in ~cfg_strobe ~seed_in ~seed_strobe in
  Circuit.create_exn ~name:"crazy_network"
    [ output "luma" code; output "chroma" cv; output "chroma_oe" con; output "chroma2_oe" c2on
    ; output "colour" colour; output "hcount" h; output "vcount" v ]
