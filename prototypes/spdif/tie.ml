(* Transmit jitter of edges placed on a clock grid: time interval error (TIE) per UI boundary,
   peak-to-peak, and the peak after the intrinsic-jitter measurement filter of AES3-1992 6.2.5.1
   (EBU Tech 3250 6.2.5.1): "a minimum-phase high-pass filter with 3 dB attenuation at 700 Hz, a
   first order roll-off to 70 Hz and with a pass-band gain of unity". Modelled as a first-order
   high-pass at 700 Hz (a one-pole filter is minimum phase; the "to 70 Hz" is its roll-off range),
   discretised at the UI rate. *)

(* the ideal boundary times (in clocks) of an NCO with increment [inc], started at 0 *)
let ideal_bounds ~inc n = Array.init n (fun k -> float (k + 1) *. 4294967296. /. float inc)

(* placed on a grid of [g] points per clock: the start of the grid interval after the crossing,
   plus a static error per grid phase (ns), as a four-phase clock with skewed phases would have *)
let place ~g ?(skew_ns = [||]) ~fclk ideal =
  Array.map (fun t ->
      let x = Float.ceil (t *. float g) in
      let ph = int_of_float (Float.rem x (float g)) in
      let s = if Array.length skew_ns = 0 then 0. else skew_ns.(ph) in
      (x /. float g *. 1e9 /. fclk) +. s) ideal

type stats = { pp_ns : float; hp_peak_ns : float; rms_ns : float }

(* [times]: actual edge times (ns) of consecutive UI boundaries *)
let measure ~ui_ns (times : float array) =
  let n = Array.length times in
  (* least-squares line through (k, t_k): removes the static phase and the frequency *)
  let sx = ref 0. and sy = ref 0. and sxx = ref 0. and sxy = ref 0. in
  Array.iteri (fun k t -> let x = float k in sx := !sx +. x; sy := !sy +. t; sxx := !sxx +. (x *. x); sxy := !sxy +. (x *. t)) times;
  let fn = float n in
  let b = ((fn *. !sxy) -. (!sx *. !sy)) /. ((fn *. !sxx) -. (!sx *. !sx)) in
  let a = (!sy -. (b *. !sx)) /. fn in
  let tie = Array.mapi (fun k t -> t -. (a +. (b *. float k))) times in
  let mx = Array.fold_left Float.max neg_infinity tie and mn = Array.fold_left Float.min infinity tie in
  let rc = 1. /. (2. *. Float.pi *. 700.) and dt = ui_ns *. 1e-9 in
  let alpha = rc /. (rc +. dt) in
  let y = ref 0. and peak = ref 0. and settle = int_of_float (10. *. rc /. dt) in
  let ss = ref 0. and cnt = ref 0 in
  for k = 1 to n - 1 do
    y := alpha *. (!y +. tie.(k) -. tie.(k - 1));
    if k > settle then begin peak := Float.max !peak (Float.abs !y); ss := !ss +. (!y *. !y); incr cnt end
  done;
  { pp_ns = mx -. mn; hp_peak_ns = !peak; rms_ns = sqrt (!ss /. float (max 1 !cnt)) }

(* the same at the transmitted edges only: [pairs] = (ideal, actual) times in ns of the boundaries
   that carry a transition. Intrinsic jitter is defined at the transition zero crossings, which
   are an irregular subset of the UI boundaries, so the filter is stepped with each edge's own dt. *)
let measure_edges (pairs : (float * float) array) =
  let n = Array.length pairs in
  let sx = ref 0. and sy = ref 0. and sxx = ref 0. and sxy = ref 0. in
  Array.iter (fun (x, t) -> let y = t -. x in sx := !sx +. x; sy := !sy +. y; sxx := !sxx +. (x *. x); sxy := !sxy +. (x *. y)) pairs;
  let fn = float n in
  let b = ((fn *. !sxy) -. (!sx *. !sy)) /. ((fn *. !sxx) -. (!sx *. !sx)) in
  let a = (!sy -. (b *. !sx)) /. fn in
  let tie = Array.map (fun (x, t) -> t -. x -. (a +. (b *. x))) pairs in
  let mx = Array.fold_left Float.max neg_infinity tie and mn = Array.fold_left Float.min infinity tie in
  let rc = 1. /. (2. *. Float.pi *. 700.) in
  let y = ref 0. and peak = ref 0. and ss = ref 0. and cnt = ref 0 in
  let t_start = fst pairs.(0) in
  for k = 1 to n - 1 do
    let dt = (fst pairs.(k) -. fst pairs.(k - 1)) *. 1e-9 in
    let alpha = rc /. (rc +. dt) in
    y := alpha *. (!y +. tie.(k) -. tie.(k - 1));
    if (fst pairs.(k) -. t_start) *. 1e-9 > 10. *. rc then begin peak := Float.max !peak (Float.abs !y); ss := !ss +. (!y *. !y); incr cnt end
  done;
  { pp_ns = mx -. mn; hp_peak_ns = !peak; rms_ns = sqrt (!ss /. float (max 1 !cnt)) }
