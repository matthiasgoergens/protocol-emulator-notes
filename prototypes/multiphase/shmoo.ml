(* The chip as a timing debugger: a shmoo of an external SPI target with programmable output edges
   and a TDC on the input, plus runt-pulse injection. Behavioural throughout; the chip side is the
   programmable-phase extension of the stage (a delay-line DTC per output lane, a delay-line TDC per
   input lane), with the tap delay and its mismatch as parameters.

   Chip model:
   - Output: an edge is placed at a clock edge plus a tap of a delay line. Taps are nominally [tap]
     apart; each stage's actual delay is tap * (1 + N(0, mismatch)), so the line has INL (a random
     walk). Calibration counts taps per clock period with the TDC (as the hardware would) and scales
     requested offsets by the measured mean tap; INL is not calibrated out.
   - Input: a TDC on the same kind of line reports the time of an input edge after a reference clock
     edge as a tap count; the firmware converts with the calibrated mean tap.
   - Glitches: two edges on one pin in one clock, from two lanes, give a pulse of a programmed width.

   Target model: an SPI mode 0 slave.
   - It samples MOSI on SCK's rising edge. Setup t_su and hold t_h (per event, with jitter): if MOSI
     changes inside (rise - t_su, rise + t_h) the bit it latches is random.
   - It drives MISO after SCK's falling edge with delay t_co, which is data dependent: 0.35 ns
     slower when driving a 1 (a bimodal response for the TDC to find).
   - It ignores SCK pulses shorter than its minimum pulse width (per pulse, with jitter); a longer
     runt counts as a clock and slips the shift register by one bit.
   - A "supply" knob scales all its delays by (1.2 / vdd) ^ 1.3, to make the shmoo two-dimensional.
   These numbers are invented but of the right order for a 3.3 V CMOS peripheral; the point is that
   the measured window must match whatever the model has, including when the model is changed
   (the control below moves the hold time by 0.5 ns and checks the measured boundary moves too).

   Output: results/shmoo.txt *)

let tap = (match Sys.getenv_opt "TAP_PS" with Some s -> float_of_string s | None -> 75.0) *. 1e-12
let mismatch = 0.03            (* per-stage delay sigma, relative *)
let period = 1.0 /. 60e6
let rng = Random.State.make [| 2026; 9; 25 |]
let gauss () =
  let u1 = Random.State.float rng 1.0 and u2 = Random.State.float rng 1.0 in
  sqrt (-2.0 *. log (max u1 1e-300)) *. cos (2.0 *. Float.pi *. u2)

(* the delay line: cumulative actual delays of taps 0..ntaps *)
let ntaps = int_of_float (ceil (period /. (tap *. 0.8))) + 8
let line =
  let a = Array.make (ntaps + 1) 0.0 in
  for i = 1 to ntaps do a.(i) <- a.(i - 1) +. (tap *. (1.0 +. (mismatch *. gauss ()))) done; a
(* calibration: the TDC counts how many taps one clock period spans; mean tap = period / count *)
let cal_count = let c = ref 0 in while !c < ntaps && line.(!c + 1) <= period do incr c done; !c
let tap_cal = period /. float cal_count
let dtc_actual offset = (* requested offset (s) -> actual (s) *)
  let i = int_of_float (Float.round (offset /. tap_cal)) in
  let i = max 0 (min ntaps i) in line.(i)
let tdc_measure dt = (* actual delay after the reference edge -> measured (s) *)
  let i = ref 0 in while !i < ntaps && line.(!i + 1) <= dt do incr i done; float !i *. tap_cal

type target = { t_su : float; t_h : float; t_co0 : float; t_co1 : float; w_min : float; sigma : float }
let nominal = { t_su = 1.5e-9; t_h = 1.0e-9; t_co0 = 7.0e-9; t_co1 = 7.35e-9; w_min = 1.2e-9; sigma = 60e-12 }
let scale vdd = (1.2 /. vdd) ** 1.3

(* One SPI byte, MSB first, SCK rising edges at 0, T, 2T, ... The chip changes MOSI for bit b at
   [offset] from edge b (negative: before the edge; the DTC realises it as a tap after the previous
   clock edge). The target latches, at each edge, the new value if the change was at least t_su
   before it, the old value if the change came at least t_h after it, and a random bit in between.
   For offset < 0 the correct result is the byte; for offset > 0 every edge sees the previous bit,
   so the correct result is the byte shifted by one with the idle level (0) in front: both are
   clean, deterministic transfers. Only the window (-t_su, +t_h) fails. Returns (latched, expected). *)
let spi_byte tgt ~vdd ~offset byte =
  let k = scale vdd in
  let change = dtc_actual (offset +. period) -. period in
  let got = ref 0 in
  for b = 7 downto 0 do
    let nw = (byte lsr b) land 1 and old = if b = 7 then 0 else (byte lsr (b + 1)) land 1 in
    let su = (tgt.t_su *. k) +. (tgt.sigma *. gauss ()) and h = (tgt.t_h *. k) +. (tgt.sigma *. gauss ()) in
    let latched = if change <= -.su then nw else if change >= h then old else if nw = old then nw else Random.State.int rng 2 in
    got := (!got lsl 1) lor latched
  done;
  !got, (if offset < 0.0 then byte else byte lsr 1)

let shmoo tgt ~title =
  let offsets = List.init 81 (fun i -> (float (i - 40)) *. 0.1e-9) in
  let vdds = [ 1.40; 1.35; 1.30; 1.25; 1.20; 1.15; 1.10; 1.05; 1.00 ] in
  let buf = Buffer.create 4096 in
  Buffer.add_string buf (Printf.sprintf "%s\nMOSI edge offset from SCK rise, -4.0 .. +4.0 ns in 0.1 ns steps (| marks 0); 32 bytes per point; # all correct, . any wrong\n" title);
  let bounds = ref [] in
  List.iter (fun vdd ->
      Buffer.add_string buf (Printf.sprintf "vdd %.2f  " vdd);
      let row = List.map (fun off ->
          let ok = ref true in
          for _ = 1 to 32 do
            let got, want = spi_byte tgt ~vdd ~offset:off (Random.State.int rng 256) in
            if got <> want then ok := false
          done;
          !ok) offsets in
      List.iteri (fun i ok -> Buffer.add_char buf (if i = 40 then (if ok then '|' else ':') else if ok then '#' else '.')) row;
      (* the failing window: first and last failing offset *)
      let fails = List.filteri (fun i _ -> not (List.nth row i)) offsets in
      (match fails with
       | [] -> Buffer.add_string buf "  (no failures)"
       | _ ->
         let lo = List.fold_left min infinity fails and hi = List.fold_left max neg_infinity fails in
         bounds := (vdd, lo, hi) :: !bounds;
         Buffer.add_string buf (Printf.sprintf "  fails from %+.1f to %+.1f ns; model window -%.2f..+%.2f ns"
                                  (lo *. 1e9) (hi *. 1e9) (tgt.t_su *. scale vdd *. 1e9) (tgt.t_h *. scale vdd *. 1e9)));
      Buffer.add_char buf '\n') vdds;
  Buffer.contents buf, List.rev !bounds

let () =
  let pr s = print_string s in
  pr (Printf.sprintf "delay line: nominal tap %.0f ps, per-stage mismatch %.0f %%; %d taps; calibration counted %d taps per %.2f ns clock -> %.1f ps per tap\n"
        (tap *. 1e12) (mismatch *. 100.0) ntaps cal_count (period *. 1e9) (tap_cal *. 1e12));
  let worst_inl = ref 0.0 in
  for i = 0 to cal_count do worst_inl := Float.max !worst_inl (Float.abs (line.(i) -. (float i *. tap_cal))) done;
  pr (Printf.sprintf "worst INL after calibration over one clock: %.0f ps\n\n" (!worst_inl *. 1e12));
  let s1, b1 = shmoo nominal ~title:"Shmoo 1: nominal target (t_su 1.5 ns, t_h 1.0 ns at 1.2 V)" in
  pr s1;
  let s2, b2 = shmoo { nominal with t_h = 1.5e-9 } ~title:"\nControl: target with hold time 1.5 ns (+0.5 ns): the right-hand boundary must move by about +0.5 ns" in
  pr s2;
  let h1 = List.assoc 1.20 (List.map (fun (v, _, hi) -> v, hi) b1) and h2 = List.assoc 1.20 (List.map (fun (v, _, hi) -> v, hi) b2) in
  pr (Printf.sprintf "hold boundary at 1.20 V: %.1f ns -> %.1f ns, moved %+.1f ns -> %s\n\n" (h1 *. 1e9) (h2 *. 1e9) ((h2 -. h1) *. 1e9)
        (if Float.abs (h2 -. h1 -. 0.5e-9) <= 0.15e-9 then "control PASS" else "control FAIL"));
  (* response time: MISO edge after SCK fall, measured by the TDC *)
  let n = 2000 in
  let meas = Array.init n (fun _ ->
      let bit = Random.State.int rng 2 in
      let tco = (if bit = 1 then nominal.t_co1 else nominal.t_co0) +. (0.08e-9 *. gauss ()) in
      bit, tco, tdc_measure tco) in
  pr (Printf.sprintf "Response time: %d MISO edges timed by the TDC from SCK's falling edge (model: 7.00 ns for a 0, 7.35 ns for a 1, jitter 80 ps rms)\n" n);
  (* one bin per tap, so the TDC's quantisation does not alias into empty bins *)
  let w = tap_cal in
  let lo = 6.6e-9 in
  let nb = int_of_float (1.0e-9 /. w) + 1 in
  let hist = Array.make nb 0 and hist_true = Array.make nb 0 in
  Array.iter (fun (_, t, m) ->
      let bin x = int_of_float ((x -. lo) /. w) in
      let b = bin m in if b >= 0 && b < nb then hist.(b) <- hist.(b) + 1;
      let b = bin t in if b >= 0 && b < nb then hist_true.(b) <- hist_true.(b) + 1) meas;
  Array.iteri (fun i c ->
      pr (Printf.sprintf "  %.3f ns  measured %4d %-45s true %4d\n" ((lo +. (float i *. w)) *. 1e9) c (String.make (c / 8) '#') hist_true.(i))) hist;
  let mean sel = let l = List.filter (fun (b, _, _) -> b = sel) (Array.to_list meas) in
    List.fold_left (fun a (_, _, m) -> a +. m) 0.0 l /. float (List.length l) in
  let m0 = mean 0 and m1 = mean 1 in
  pr (Printf.sprintf "  measured mean for 0s %.3f ns, for 1s %.3f ns: data-dependent delay %.0f ps (model 350 ps)\n\n" (m0 *. 1e9) (m1 *. 1e9) ((m1 -. m0) *. 1e12));
  (* glitch injection: a runt pulse on SCK during its low phase *)
  pr "Runt pulse on SCK (two lanes: rise at t, fall at t + w), 200 bytes per width; the target slips a bit when it accepts the runt\n";
  List.iter (fun wreq ->
      let slips = ref 0 in
      for _ = 1 to 200 do
        let w = dtc_actual (wreq +. 2e-9) -. dtc_actual 2e-9 in
        let wmin = nominal.w_min +. (0.1e-9 *. gauss ()) in
        if w >= wmin then incr slips
      done;
      pr (Printf.sprintf "  requested %.1f ns: %3d of 200 bytes corrupted %s\n" (wreq *. 1e9) !slips (String.make (!slips / 5) '#')))
    (List.init 16 (fun i -> 0.6e-9 +. (float i *. 0.1e-9)))
