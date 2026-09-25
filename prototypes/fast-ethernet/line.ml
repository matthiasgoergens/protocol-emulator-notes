(* Continuous-time line and a behavioural oversampling front end.

   The line is a sequence of levels, one per UI, starting at time 0 with UI [ui] (ns). Each level
   change is an edge whose time is moved by:
   - random jitter, Gaussian with standard deviation [rj] ns;
   - duty-cycle distortion [dcd] ns peak-to-peak: rising edges (to a higher level) +dcd/2, falling
     edges -dcd/2 (a threshold offset against a finite slew, or an unbalanced output stage);
   - [ddr] ns on every edge at an odd UI boundary: a transmitter that puts alternate UIs on the
     falling clock edge (both edges of a 62.5 MHz clock), with the clock's duty-cycle error
     (ddr = (duty - 50 %) x 16 ns).

   The receiver samples [n] times per clock of period [tclk] ns (16 ns x (1 + ppm)), sample i at
   i x tclk / n plus a fixed per-tap error [tap_err.(i)] (multi-phase mismatch), plus Gaussian
   sampling jitter [sj]. A sample within [aperture] ns of an edge is a coin toss (metastability
   or threshold noise). ASSUMPTIONS of the front end, stated because it is someone else's block:
   n = 2 is both edges of the core clock; n = 4 is the four-phase stage (4 phases per clock);
   n = 6 and n = 8 would need six or eight phases, or a delay-line / TDC sampler. *)

let gauss rng =
  let u1 = Random.State.float rng 1.0 +. 1e-12 and u2 = Random.State.float rng 1.0 in
  sqrt (-2.0 *. log u1) *. cos (2.0 *. Float.pi *. u2)

type line = { t : float array; lv : int array; first : int }  (* edge times, level after each edge *)

let make ~rng ~ui ?(rj = 0.0) ?(dcd = 0.0) ?(ddr = 0.0) (levels : int array) =
  let ts = ref [] in
  for k = Array.length levels - 1 downto 1 do
    if levels.(k) <> levels.(k - 1) then begin
      let up = levels.(k) > levels.(k - 1) in
      let t = float k *. ui +. rj *. gauss rng +. (if up then dcd /. 2.0 else -. dcd /. 2.0)
              +. (if k land 1 = 1 then ddr else 0.0) in
      ts := (t, levels.(k)) :: !ts
    end
  done;
  let a = Array.of_list !ts in
  Array.stable_sort (fun (x, _) (y, _) -> compare x y) a;
  { t = Array.map fst a; lv = Array.map snd a; first = levels.(0) }

type sampler = {
  line : line; n : int; tclk : float; tap_err : float array; sj : float; aperture : float;
  rng : Random.State.t; mutable idx : int; mutable clk : int; t0 : float;
}

let sampler ~rng ~line ~n ~ppm ?(tap_err = [||]) ?(sj = 0.0) ?(aperture = 0.02) ?(t0 = 0.37) () =
  let tap_err = if tap_err = [||] then Array.make n 0.0 else tap_err in
  { line; n; tclk = 16.0 *. (1.0 +. ppm *. 1e-6); tap_err; sj; aperture; rng; idx = 0; clk = 0; t0 }

let level_at s t =
  let l = s.line in
  (* advance the pointer past edges before t (sample times are increasing up to jitter) *)
  while s.idx < Array.length l.t && l.t.(s.idx) <= t -. 5.0 do s.idx <- s.idx + 1 done;
  let i = ref s.idx in
  while !i < Array.length l.t && l.t.(!i) <= t do incr i done;
  let before = if !i = 0 then l.first else l.lv.(!i - 1) in
  let near = (!i < Array.length l.t && l.t.(!i) -. t < s.aperture) || (!i > 0 && t -. l.t.(!i - 1) < s.aperture) in
  if near && Random.State.bool s.rng then
    (if !i < Array.length l.t && l.t.(!i) -. t < s.aperture then l.lv.(!i) else if !i >= 2 then l.lv.(!i - 2) else l.first)
  else before

let clock s =
  let base = s.t0 +. float s.clk *. s.tclk in
  s.clk <- s.clk + 1;
  Array.init s.n (fun i -> level_at s (base +. float i *. s.tclk /. float s.n +. s.tap_err.(i) +. s.sj *. gauss s.rng))

let end_time s = s.t0 +. float s.clk *. s.tclk
