(* A ring of 16 cells, each holding a 24-bit signed saturating value. Once per pixel every cell
   updates at the same time from the old values:
     r_i <- sat (op_i x y)   op in {add, sub, max, min}
     x = r_i (xs = 0) or r_(i+xs) (xs = 1..4)
     y = r_(i+1+ys) (ys = 0..3) or the constant k_i (ys = 4)
   indices mod 16. The CPU loads all 16 values before each line (48 bytes during blanking); the
   configuration (ops, sources, constants, output mapping) is per frame.
   Output: four tap cells give four sign bits, which pick one of 16 LUT entries. A non-zero entry is
   the palette index; zero means "use the ramp": clamp ((base - r_ramp) asr shift, 0, max).
   This is the "plain systolic array" cell from notes/prior-art-triage.md: + gives forward
   differencing (polynomials along the line), max/min give max-plus/min-plus combination. *)

let n = 16 and width = 24
let cpl = 3405 and lpf = 312 and vis_start = 662 and pixc = 10 and first_vis = 40 and nvis = 240 and npix = 256
let vmax = (1 lsl (width - 1)) - 1 and vmin = -(1 lsl (width - 1))
let sat v = if v > vmax then vmax else if v < vmin then vmin else v

type cfg = {
  op : int array; xs : int array; ys : int array; k : int array;
  pal : int array;          (* 16 palette bytes, hue lsl 4 lor luma, as in the retro console *)
  taps : int array;         (* 4 cell indices *)
  lut : int array;          (* 16 entries, 0 = ramp *)
  ramp_tap : int; ramp_shift : int; ramp_base : int; ramp_max : int;
}

(* count of saturating results, so a scene that silently leaves the exact range is caught *)
let saturations = Atomic.make 0

let step c s =
  Array.init n (fun i ->
    let x = if c.xs.(i) = 0 then s.(i) else s.((i + c.xs.(i)) mod n) in
    let y = if c.ys.(i) = 4 then c.k.(i) else s.((i + 1 + c.ys.(i)) mod n) in
    let v = match c.op.(i) with 0 -> x + y | 1 -> x - y | 2 -> max x y | _ -> min x y in
    if v <> sat v then Atomic.incr saturations;
    sat v)

let index c s =
  let bits = ref 0 in
  Array.iteri (fun j t -> if s.(t) < 0 then bits := !bits lor (1 lsl j)) c.taps;
  let e = c.lut.(!bits) in
  if e <> 0 then e
  else begin
    let r = (c.ramp_base - s.(c.ramp_tap)) asr c.ramp_shift in
    if r < 0 then 0 else if r > c.ramp_max then c.ramp_max else r
  end

(* one visible line: pixel x shows the state after x steps from [init] *)
let line c init =
  let s = ref (Array.copy init) in
  Array.init npix (fun _ -> let v = index c !s in s := step c !s; v)

let render c ~inits = Array.init nvis (fun y -> line c (inits y))

(* ---- the host side: a scene compiled to a configuration and per-line initial values ---- *)

let frac = 16  (* fixed-point fraction bits of the wiggle *)

type scene = {
  cx : int; cy : int; rx : int; ry : int;           (* ellipse *)
  glow : (int * int) array;                          (* three glow centres *)
  wy : int; wamp : float; wroots : float * float * float;  (* wiggle: y = wy + amp * cubic *)
}

let scene_at t =
  let f = float t in
  { cx = 128 + int_of_float (60. *. sin (f *. 0.05)); cy = 80 + int_of_float (25. *. cos (f *. 0.07));
    rx = 34 + int_of_float (12. *. sin (f *. 0.11)); ry = 22;
    glow = Array.init 3 (fun j ->
      let a = f *. 0.04 +. float j *. 2.094 in
      (128 + int_of_float (80. *. cos a), 120 + int_of_float (70. *. sin (a *. 1.3))));
    wy = 185; wamp = 28. *. cos (f *. 0.09);
    wroots = (0.15 +. 0.05 *. sin (f *. 0.05), 0.5, 0.85) }

(* the wiggle's integer cubic in Newton form, exact on-chip: P(x) = p0 + d1 x + d2 C(x,2) + d3 C(x,3) *)
let wiggle_newton sc =
  let r1, r2, r3 = sc.wroots in
  let p t = let u = t /. 255. in (u -. r1) *. (u -. r2) *. (u -. r3) /. 0.06 *. sc.wamp in
  let fx x = p (float x) *. float (1 lsl frac) in
  let v0 = fx 0 and v1 = fx 1 and v2 = fx 2 and v3 = fx 3 in
  (* forward differences at x = 0, each rounded; the chip then evaluates the Newton form exactly *)
  let d1 = Float.round (v1 -. v0) and d2 = Float.round (v2 -. 2. *. v1 +. v0)
  and d3 = Float.round (v3 -. 3. *. v2 +. 3. *. v1 -. v0) in
  (int_of_float (Float.round v0), int_of_float d1, int_of_float d2, int_of_float d3)

(* exact integer value of the forward-difference sequence with Δ^0..3 at x = 0 *)
let fd_eval (p0, d1, d2, d3) x =
  let c2 = x * (x - 1) / 2 and c3 = x * (x - 1) * (x - 2) / 6 in
  p0 + d1 * x + d2 * c2 + d3 * c3

let wband = 3 lsl frac
let glow_offset = [| 2; 2; 1 |]  (* pipeline depth of each glow source through the min cells *)

let quad (qx, qy) x y = (x - qx) * (x - qx) + (y - qy) * (y - qy)
let ellipse_q sc x y =
  let dy = float (y - sc.cy) *. float sc.rx /. float sc.ry in
  (x - sc.cx) * (x - sc.cx) + int_of_float (Float.round (dy *. dy)) - sc.rx * sc.rx

let cfg_of_scene _sc =
  let op = Array.make n 0 and xs = Array.make n 0 and ys = Array.make n 4 and k = Array.make n 0 in
  let set i o x y kk = op.(i) <- o; xs.(i) <- x; ys.(i) <- y; k.(i) <- kk in
  (* 0,1: ellipse Q and its difference *)
  set 0 0 0 0 0; set 1 0 0 4 2;
  (* 2,3: wiggle band F + w and F - w, both adding cell 4; 4, 5: second and third differences *)
  set 2 0 0 1 0; set 3 0 0 0 0; set 4 0 0 0 0; set 5 0 0 4 0;
  (* 6: G2 = min (G, Q3); 7: G = min (Q1, Q2); 8, 9, 10: Q3, Q1, Q2; 11, 12, 13: D1, D3, D2 *)
  set 6 3 1 1 0; set 7 3 2 2 0; set 8 0 0 3 0; set 9 0 0 1 0; set 10 0 0 2 0;
  set 11 0 0 4 2; set 12 0 0 4 2; set 13 0 0 4 2;
  let pal = [| 0x00; 0xB1; 0xB2; 0xB3; 0xB4; 0xB5; 0xA5; 0xA6; 0xA7; 0xA8; 0x08; 0x09; 0x0A; 0x00; 0x68; 0x46 |] in
  let lut = Array.init 16 (fun b -> if b land 1 <> 0 then 15 else if b land 2 = 0 && b land 4 <> 0 then 14 else 0) in
  { op; xs; ys; k; pal; taps = [| 0; 2; 3; 14 |]; lut;
    ramp_tap = 6; ramp_shift = 7; ramp_base = 1600; ramp_max = 12 }

let cfg_at t =
  let sc = scene_at t in
  let c = cfg_of_scene sc in
  let _, _, _, d3 = wiggle_newton sc in
  c.k.(5) <- d3; c

(* initial values for visible line y *)
let inits_at t y =
  let sc = scene_at t in
  let s = Array.make n 0 in
  s.(0) <- ellipse_q sc 0 y; s.(1) <- 1 - 2 * sc.cx;
  let (p0, d1, d2, d3) = wiggle_newton sc in
  let f0 = p0 - (y - sc.wy) * (1 lsl frac) in
  (* keep far-away lines out of saturation: move F0 towards zero as long as it cannot reach the band *)
  let f0 =
    let lo = ref max_int and hi = ref min_int in
    for x = 0 to npix - 1 do let v = fd_eval (p0, d1, d2, d3) x - p0 in lo := min !lo v; hi := max !hi v done;
    if f0 - wband + !lo >= 0 then min f0 (wband + 1 - !lo + (1 lsl frac))
    else if f0 + wband + !hi < 0 then max f0 (-wband - 1 - !hi - (1 lsl frac))
    else f0 in
  s.(2) <- f0 + wband; s.(3) <- f0 - wband; s.(4) <- d1; s.(5) <- d2;
  let q j o = quad sc.glow.(j) o y in
  let d j o = 2 * (o - fst sc.glow.(j)) + 1 in
  let o = glow_offset in
  s.(9) <- q 0 o.(0); s.(11) <- d 0 o.(0);
  s.(10) <- q 1 o.(1); s.(13) <- d 1 o.(1);
  s.(8) <- q 2 o.(2); s.(12) <- d 2 o.(2);
  s.(7) <- min (q 0 1) (q 1 1);
  s.(6) <- min (min (q 0 0) (q 1 0)) (q 2 0);
  s

(* direct evaluation of the same picture, no forward differencing, no pipeline *)
let reference t =
  let sc = scene_at t in
  let c = cfg_at t in
  let wn = wiggle_newton sc in
  Array.init nvis (fun y -> Array.init npix (fun x ->
    if ellipse_q sc x y < 0 then 15
    else
      let f = fd_eval wn x - (y - sc.wy) * (1 lsl frac) in
      if f + wband >= 0 && f - wband < 0 then 14
      else
        let g = Array.fold_left (fun m p -> min m (quad p x y)) max_int sc.glow in
        let r = (c.ramp_base - g) asr c.ramp_shift in
        if r < 0 then 0 else if r > c.ramp_max then c.ramp_max else r))
