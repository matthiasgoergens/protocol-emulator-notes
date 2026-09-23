(* The semiring ring as hardware (semantics in model.ml). Two byte chains:
     config chain (cfg_strobe), 106 bytes, per frame during vertical blanking:
       per cell: op | xs lsl 2 | ys lsl 5, then k (3 bytes, big-endian)     64 bytes
       palette 16, taps 4, LUT 16, ramp tap, ramp shift, ramp base (3), ramp max
     init chain (init_strobe), 48 bytes per line during horizontal blanking: the 16 cell values,
       cell 0 first, big-endian. The bytes shift straight through the cell registers, so there is
       no second copy of the state.
   Timing and colour output are the PAL console's. *)
open Hardcaml
open Signal

let n = Model.n and w = Model.width
let cpl = Model.cpl and lpf = Model.lpf and vis_start = Model.vis_start
let first_vis = Model.first_vis and nvis = Model.nvis and npix = Model.npix and pixc = Model.pixc
let sync_len = 250 and half = 1702 and burst_start = 298 and burst_len = 120 and vsync_lines = 3
let cfg_len = 106

let chain spec ~enable ~din len =
  let regs = Array.make len (zero 8) in
  let prev = ref din in
  for j = 0 to len - 1 do let r = reg spec ~enable !prev in regs.(j) <- r; prev := r done;
  fun k -> regs.(len - 1 - k)

let sat v =
  (* v is w + 1 bits; clamp to w bits signed *)
  let over = msb v ^: bit v (w - 1) in
  mux2 over (mux2 (msb v) (of_int ~width:w Model.vmin) (of_int ~width:w Model.vmax)) (select v (w - 1) 0)

let create ?(fault = false) ~clock ~clear ~cfg_in ~cfg_strobe ~init_in ~init_strobe () =
  let spec = Reg_spec.create ~clock ~clear () in
  let cfg = chain (Reg_spec.create ~clock ()) ~enable:cfg_strobe ~din:cfg_in cfg_len in
  let opsel i = cfg (4 * i) in
  let k i = concat_msb [ cfg (4 * i + 1); cfg (4 * i + 2); cfg (4 * i + 3) ] in
  let pal = List.init 16 (fun j -> cfg (64 + j)) in
  let taps = List.init 4 (fun j -> select (cfg (80 + j)) 3 0) in
  let lut = List.init 16 (fun j -> select (cfg (84 + j)) 3 0) in
  let ramp_tap = select (cfg 100) 3 0 and ramp_shift = select (cfg 101) 4 0 in
  let ramp_base = concat_msb [ cfg 102; cfg 103; cfg 104 ] and ramp_max = select (cfg 105) 3 0 in
  let hcount = reg_fb spec ~width:12 ~f:(fun h -> mux2 (h ==:. (cpl - 1)) (zero 12) (h +:. 1)) in
  let line_end = hcount ==:. (cpl - 1) in
  let vcount = reg_fb spec ~enable:line_end ~width:9 ~f:(fun v -> mux2 (v ==:. (lpf - 1)) (zero 9) (v +:. 1)) in
  let vis_line = (vcount >=:. first_vis) &: (vcount <:. (first_vis + nvis)) in
  let in_window = (hcount >=:. vis_start) &: (hcount <:. (vis_start + npix * pixc)) in
  let pc = reg_fb spec ~width:4 ~f:(fun c ->
    mux2 (hcount ==:. (vis_start - 1)) (zero 4) (mux2 (c ==:. (pixc - 1)) (zero 4) (c +:. 1))) in
  let do_step = vis_line &: in_window &: (pc ==:. (pixc - 1)) in
  let s = Array.init n (fun _ -> wire w) in
  let at i = s.(i mod n) in
  let next = Array.init n (fun i ->
    let o = opsel i in
    let x = mux (select o 4 2) (List.init 5 (fun j -> at (i + j))) in
    let y = mux (select o 7 5) (List.init 4 (fun j -> at (i + 1 + j)) @ [ k i ]) in
    (* one adder per cell: x + y for add, x - y otherwise; the sign of x - y (exact in w + 1 bits)
       decides max and min *)
    let op = select o 1 0 in
    let is_add = op ==:. 0 in
    let y25 = sresize y (w + 1) in
    let t = sresize x (w + 1) +: mux2 is_add y25 (~:y25) +: uresize (~:is_add) (w + 1) in
    let lt = msb t in
    let mx = mux2 lt y x and mn = mux2 lt x y in
    let mn = if fault && i = 7 then mx else mn in
    mux op [ sat t; sat t; mx; mn ]) in
  (* the init bank: all 16 values as one 384-bit shift register, a byte at a time *)
  let bank = concat_msb (Array.to_list s) in
  let shifted = concat_msb [ select bank (n * w - 9) 0; init_in ] in
  let regs = Array.init n (fun i ->
    let from_chain = select shifted ((n - i) * w - 1) ((n - 1 - i) * w) in
    reg spec (mux2 init_strobe from_chain (mux2 do_step next.(i) s.(i)))) in
  Array.iteri (fun i r -> s.(i) <== r) regs;
  let sl = Array.to_list s in
  let bits = List.map (fun t -> msb (mux t sl)) taps in
  let e = mux (concat_lsb bits) lut in
  let diff = sresize ramp_base (w + 1) -: sresize (mux ramp_tap sl) (w + 1) in
  let sh = log_shift sra diff ramp_shift in
  let ramp = mux2 (msb sh) (zero 4) (mux2 (sh >+ uresize ramp_max (w + 1)) ramp_max (select sh 3 0)) in
  let idx = mux2 (e ==:. 0) ramp e in
  let colour = reg spec (mux idx pal) in
  let pvalid = reg spec (vis_line &: in_window) in
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

let circuit ?fault () =
  let clock = input "clock" 1 and clear = input "clear" 1 in
  let cfg_in = input "cfg_in" 8 and cfg_strobe = input "cfg_strobe" 1 in
  let init_in = input "init_in" 8 and init_strobe = input "init_strobe" 1 in
  let code, cv, con, c2on, colour, h, v = create ?fault ~clock ~clear ~cfg_in ~cfg_strobe ~init_in ~init_strobe () in
  Circuit.create_exn ~name:"semiring_ring"
    [ output "luma" code; output "chroma" cv; output "chroma_oe" con; output "chroma2_oe" c2on
    ; output "colour" colour; output "hcount" h; output "vcount" v ]
