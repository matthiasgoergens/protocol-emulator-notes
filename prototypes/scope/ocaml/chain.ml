(* The scope's signal chain in OCaml: a port of the core of ../padmodel.py, ../scopemodel.py and
   ../acq.py (KickLinear), reading the SPICE-derived tables in data/ (written by
   ../export_tables.py). Assumptions are the same as in the Python files and marked there. *)

let data_dir =
  match Sys.getenv_opt "SCOPE_DATA" with
  | Some d -> d
  | None -> "data"   (* run from prototypes/scope/ocaml *)

(* ---------------------------------------------------------------- random numbers *)

let gauss st =
  let u1 = Random.State.float st 1.0 and u2 = Random.State.float st 1.0 in
  sqrt (-2.0 *. log (Float.max u1 1e-300)) *. cos (2.0 *. Float.pi *. u2)

let uniform st a b = a +. Random.State.float st (b -. a)

(* standard normal CDF *)
let phi x =
  (* Abramowitz-Stegun 7.1.26 on erf, |error| < 1.5e-7 *)
  let z = Float.abs x /. sqrt 2.0 in
  let t = 1.0 /. (1.0 +. 0.3275911 *. z) in
  let y =
    1.0
    -. (((((1.061405429 *. t -. 1.453152027) *. t) +. 1.421413741) *. t -. 0.284496736) *. t
        +. 0.254829592)
       *. t *. exp (-.z *. z)
  in
  if x >= 0.0 then 0.5 *. (1.0 +. y) else 0.5 *. (1.0 -. y)

(* ---------------------------------------------------------------- csv *)

let read_lines path =
  let ic = open_in path in
  let rec go acc = match input_line ic with l -> go (l :: acc) | exception End_of_file -> close_in ic; List.rev acc in
  go []

let split_csv l = String.split_on_char ',' l |> List.map String.trim

(* ---------------------------------------------------------------- the pad (padmodel.Pad) *)

module Pad = struct
  let vdd = 1.2

  type t = {
    vin_g : float array; va_g : float array; i : float array array;  (* i.(va).(vin) *)
    c_a : float; c_m : float; tau_in : float; v_lv : float; d_lv : float; vt : float }

  let load () =
    let lines = read_lines (Filename.concat data_dir "pad_iv_tt.csv") in
    let head = List.hd lines |> split_csv |> List.tl |> List.map float_of_string |> Array.of_list in
    let rows = List.tl lines |> List.map (fun l -> split_csv l |> List.map float_of_string) in
    let va_g = List.map List.hd rows |> Array.of_list in
    let i = List.map (fun r -> Array.of_list (List.tl r)) rows |> Array.of_list in
    let params = read_lines (Filename.concat data_dir "pad_params.csv")
                 |> List.map (fun l -> match split_csv l with [ k; v ] -> (k, float_of_string v) | _ -> failwith l) in
    let p k = List.assoc k params in
    { vin_g = head; va_g; i; c_a = p "C_a"; c_m = p "C_m"; tau_in = p "tau_in"; v_lv = p "v_lv";
      d_lv = p "d_lv"; vt = p "vt" }

  let current p vin va =
    let nx = Array.length p.vin_g and ny = Array.length p.va_g in
    let clip x n = Float.min (Float.max x 0.0) (float_of_int n -. 1.001) in
    let x = clip ((vin -. p.vin_g.(0)) /. (p.vin_g.(1) -. p.vin_g.(0))) nx in
    let y = clip ((va -. p.va_g.(0)) /. (p.va_g.(1) -. p.va_g.(0))) ny in
    let xi = int_of_float x and yi = int_of_float y in
    let fx = x -. float_of_int xi and fy = y -. float_of_int yi in
    let r = p.i in
    ((1.0 -. fy) *. (((1.0 -. fx) *. r.(yi).(xi)) +. (fx *. r.(yi).(xi + 1))))
    +. (fy *. (((1.0 -. fx) *. r.(yi + 1).(xi)) +. (fx *. r.(yi + 1).(xi + 1))))

  (* streaming state: step it with the pad voltage at each time step *)
  type state = { mutable vin : float; mutable va : float }

  let init p dt v0 =
    let s = { vin = v0; va = (if v0 > p.vt then 0.0 else vdd) } in
    for _ = 1 to 400 do
      s.va <- Float.min vdd (Float.max 0.0 (s.va +. (dt *. current p s.vin s.va /. p.c_a)))
    done;
    s

  (* one step; returns the thick-inverter output's digital value (true = p2c high), before the
     thin inverter's fixed delay d_lv, which callers add *)
  let step p dt s v =
    let a_in = dt /. (p.tau_in +. dt) in
    let vin' = s.vin +. (a_in *. (v -. s.vin)) in
    let dv = vin' -. s.vin in
    s.vin <- vin';
    s.va <- Float.min vdd (Float.max 0.0 (s.va +. (((dt *. current p s.vin s.va) +. (p.c_m *. dv)) /. p.c_a)));
    s.va < p.v_lv

  (* whole waveform: p2c as bool array, delayed by d_lv *)
  let run p dt (v : float array) =
    let n = Array.length v in
    let s = init p dt v.(0) in
    let core = Array.init n (fun k -> step p dt s v.(k)) in
    let sh = int_of_float (Float.round (p.d_lv /. dt)) in
    Array.init n (fun k -> if k < sh then core.(0) else core.(k - sh))
end

(* ---------------------------------------------------------------- noise (acq.Noise) *)

module Noise = struct
  type t = { vdd_noise : float; thermal : float; dvt_dvdd : float; launch_jitter : float; iovdd_noise : float }
  let default = { vdd_noise = 5e-3; thermal = 0.7e-3; dvt_dvdd = 0.43; launch_jitter = 10e-12; iovdd_noise = 5e-3 }
  let threshold_sigma n = sqrt (((n.dvt_dvdd *. n.vdd_noise) ** 2.0) +. (n.thermal ** 2.0))
  let threshold n st = threshold_sigma n *. gauss st
end

(* ---------------------------------------------------------------- time base (scopemodel.TimeBase, mode "arch") *)

module Timebase = struct
  type t = {
    period : float; line : float array;   (* bin edges within a clock, n_taps + 1 entries, last = period *)
    line_delay : float array;              (* the delay-line part of each bin (supply-sensitive) *)
    mutable est : float array;             (* calibrated edges *)
    n_taps : int; skew : float array; period_jitter : float; vdd_noise : float; delay_sens : float;
    vernier : float; v_inl : float array }

  let make ?(f_clk = 60e6) ?(mismatch = 0.03) ?(bow = 20e-12) ?(phase_skew = 50e-12)
      ?(period_jitter = 10e-12) ?(vdd_noise = 5e-3) ?(vernier = 15e-12) ?(vernier_inl = 2e-12) st =
    let period = 1.0 /. f_clk in
    let tap = 134.3e-12 in
    let q = period /. 4.0 in
    let n = int_of_float (ceil (q /. tap)) + 2 in
    let seg = Array.make (n + 1) 0.0 in
    for i = 1 to n do seg.(i) <- seg.(i - 1) +. (tap *. (1.0 +. (mismatch *. gauss st))) done;
    let seg = Array.map (fun x -> x +. (bow *. sin (Float.pi *. Float.min 1.0 (Float.max 0.0 (x /. q))))) seg in
    let seg = Array.of_list (List.filter (fun x -> x < q) (Array.to_list seg)) in
    let skew = [| 0.0; phase_skew *. gauss st; phase_skew *. gauss st; phase_skew *. gauss st |] in
    let pairs =
      List.concat_map (fun p -> Array.to_list (Array.map (fun s -> ((float_of_int p *. q) +. skew.(p) +. s, s)) seg)) [ 0; 1; 2; 3 ]
      |> List.sort compare |> Array.of_list in
    let n_taps = Array.length pairs in
    let line = Array.append (Array.map fst pairs) [| period |] in
    let line_delay = Array.map snd pairs in
    let v_inl = Array.init 64 (fun _ -> vernier_inl *. gauss st) in
    { period; line; line_delay; est = Array.copy line; n_taps; skew; period_jitter; vdd_noise; delay_sens = 1.08;
      vernier; v_inl }

  let bin_of tb f =
    (* largest k with line.(k) <= f, clipped to 0 .. n_taps-1 *)
    let lo = ref 0 and hi = ref tb.n_taps in
    while !hi - !lo > 1 do
      let m = (!lo + !hi) / 2 in
      if tb.line.(m) <= f then lo := m else hi := m
    done;
    !lo

  let calibrate_code_density tb st n_hits =
    let counts = Array.make tb.n_taps 0 in
    for _ = 1 to n_hits do
      let k = bin_of tb (Random.State.float st tb.period) in
      counts.(k) <- counts.(k) + 1
    done;
    let est = Array.make (tb.n_taps + 1) 0.0 in
    for k = 0 to tb.n_taps - 1 do
      est.(k + 1) <- est.(k) +. (float_of_int counts.(k) /. float_of_int n_hits *. tb.period)
    done;
    tb.est <- est;
    let worst = ref 0.0 in
    for k = 0 to tb.n_taps - 1 do worst := Float.max !worst (Float.abs (est.(k) -. tb.line.(k))) done;
    !worst

  (* true instant of bin k on clock n relative to clock 0's edge, with supply noise on the line
     part and clock jitter accumulated over [since] clocks *)
  let instant tb st ?(since = 0) n k =
    (float_of_int n *. tb.period) +. tb.line.(k)
    +. (tb.period_jitter *. sqrt (float_of_int since) *. gauss st)
    +. (tb.delay_sens *. tb.vdd_noise *. gauss st *. tb.line_delay.(k))

  let estimate tb n k = (float_of_int n *. tb.period) +. tb.est.(k)

  (* nearest reachable (clock, bin) to a wanted time, using the calibration *)
  let nearest tb t =
    let n = int_of_float (floor (t /. tb.period)) in
    let f = t -. (float_of_int n *. tb.period) in
    let best = ref 0 in
    for k = 0 to tb.n_taps - 1 do
      if Float.abs (tb.est.(k) -. f) < Float.abs (tb.est.(!best) -. f) then best := k
    done;
    (n, !best)

  (* TDC timestamp with the Vernier interpolator *)
  let timestamp tb st t =
    let n = floor (t /. tb.period) in
    let f = t -. (n *. tb.period) in
    let k0 = bin_of tb f in
    let f = f -. (tb.delay_sens *. tb.vdd_noise *. gauss st *. tb.line_delay.(k0)) in
    let f = Float.min (Float.max f 0.0) (tb.period -. 1e-15) in
    let k = bin_of tb f in
    if tb.vernier > 0.0 then
      let j = max 0 (min 63 (int_of_float (floor ((f -. tb.line.(k)) /. tb.vernier)))) in
      (n *. tb.period) +. tb.est.(k) +. ((float_of_int j +. 0.5) *. tb.vernier) +. tb.v_inl.(j)
    else (n *. tb.period) +. (0.5 *. (tb.est.(k) +. tb.est.(k + 1)))
end

(* ---------------------------------------------------------------- kicked sampling (acq.KickLinear) *)

module Kick = struct
  type t = { deltas : float array; delay : float array; pos : float array; w : float array; base : float;
             centroid : float }

  let load vt =
    let rows = read_lines (Filename.concat data_dir "kick_r500.csv") |> List.map split_csv in
    let pick tag = List.filter_map (function [ t; a; b ] when t = tag -> Some (float_of_string a, float_of_string b) | _ -> None) rows in
    let d = pick "D" and w = pick "W" in
    let pos = Array.of_list (List.map fst w) and wv = Array.of_list (List.map snd w) in
    let centroid = ref 0.0 in
    Array.iteri (fun i p -> centroid := !centroid +. (p *. wv.(i))) pos;
    { deltas = Array.of_list (List.map fst d); delay = Array.of_list (List.map snd d); pos; w = wv;
      base = vt -. 0.25; centroid = !centroid }

  let interp xs ys x =
    let n = Array.length xs in
    if x < xs.(0) || x > xs.(n - 1) then nan
    else begin
      let i = ref 0 in
      while !i < n - 2 && xs.(!i + 1) < x do incr i done;
      let a = xs.(!i) and b = xs.(!i + 1) in
      ys.(!i) +. ((x -. a) /. (b -. a) *. (ys.(!i + 1) -. ys.(!i)))
    end

  (* the pad's output edge time for a kick arriving at t_kick on a pin whose voltage is pin t
     (including the DAC's offset); nan if out of the kick's range *)
  let shot k noise st pin t_kick =
    let u = ref 0.0 in
    Array.iteri (fun i p -> u := !u +. (k.w.(i) *. pin (t_kick +. p))) k.pos;
    let u = !u -. k.base -. Noise.threshold noise st -. (noise.Noise.iovdd_noise /. 3.3 *. 0.5 *. gauss st) in
    t_kick +. interp k.deltas k.delay u
end
