(* Compressed sensing on the chip's real acquisition paths, host-side recovery by OMP.

   A  Random-time kicked sampling (single shot, non-repetitive): one kick every second clock at a
      random clock parity and a random bin (from the TRNG/LFSR), so the sample instants are
      spread uniformly; each kick gives a multi-bit value (Chain.Kick, SPICE-derived) whose instant
      the host knows from the calibrated time base. Sparse multitone in 5..700 MHz; the chip samples
      at 30 MS/s on average, against 1.4 GS/s for Nyquist.
   B  The random demodulator (Tropp, Laska, Duarte, Romberg, Baraniuk 2010) with 1-bit samples: the
      four-phase sampler takes 240 MS/s of the pad's decision on the pin plus a dither;
      a random dither (uniform, new every quarter clock) makes the bits linear in expectation;
      each bit is XORed with a +-1 chipping sequence (an LFSR) and summed in a PE accumulator over L
      chips; the sums (240/L MS/s) go to the host. Band 1..115 MHz (below 120 MHz, the chipping
      rate's Nyquist): here CS does not beat Nyquist, it cuts the data rate. The comparator is
      either ideal or the SPICE-fitted pad (Chain.Pad), which decides slowly at small overdrive.

   Output: ../results/cs.txt (tables), ../results/cs_example.csv. Run from prototypes/scope/ocaml:
   ./_build/default/cs.exe [quick] *)

open Chain

let quick = Array.length Sys.argv > 1 && Sys.argv.(1) = "quick"
let out = Buffer.create 4096
let say fmt = Printf.ksprintf (fun s -> print_endline s; Buffer.add_string out (s ^ "\n")) fmt

let two_pi = 2.0 *. Float.pi

let random_tones st k ~fmin ~fmax ~amin ~amax ~min_sep =
  let rec draw acc =
    if List.length acc = k then acc
    else
      let f = uniform st fmin fmax in
      if List.exists (fun t -> Float.abs (t.Linalg.f -. f) < min_sep) acc then draw acc
      else draw ({ Linalg.f; amp = uniform st amin amax; phase = uniform st 0.0 two_pi } :: acc)
  in
  draw [] |> List.sort (fun a b -> compare a.Linalg.f b.Linalg.f) |> Array.of_list

let signal tones t = Array.fold_left (fun s tn -> s +. (tn.Linalg.amp *. cos ((two_pi *. tn.Linalg.f *. t) +. tn.Linalg.phase))) 0.0 tones

(* match estimated to true tones: all found within [ftol] and 25 % amplitude *)
let judge truth est ftol =
  let used = Array.make (Array.length est) false in
  let ferr = ref 0.0 and aerr = ref 0.0 in
  let ok = Array.for_all (fun tr ->
      let best = ref (-1) in
      Array.iteri (fun j e -> if not used.(j) && Float.abs (e.Linalg.f -. tr.Linalg.f) < ftol
                                 && (!best < 0 || Float.abs (e.Linalg.f -. tr.Linalg.f) < Float.abs (est.(!best).Linalg.f -. tr.Linalg.f))
                   then best := j) est;
      if !best < 0 then false
      else begin
        used.(!best) <- true;
        let e = est.(!best) in
        ferr := Float.max !ferr (Float.abs (e.f -. tr.f));
        aerr := Float.max !aerr (Float.abs (e.amp /. tr.amp -. 1.0));
        Float.abs (e.amp /. tr.amp -. 1.0) < 0.25
      end) truth in
  (ok, !ferr, !aerr)

(* ------------------------------------------------------------------ A: kicked random-time sampling *)

let experiment_a st =
  let tb = Timebase.make st in
  let inl = Timebase.calibrate_code_density tb st 2_000_000 in
  let pad = Pad.load () in
  let kick = Kick.load pad.Pad.vt in
  let noise = Noise.default in
  let k_s = 0.2 and d_kout = 2e-9 in
  let u_mid = -0.035 in
  let offset = kick.Kick.base +. u_mid in              (* the signal's mean sits mid-range *)
  (* calibration table: static levels, 64 kicks each, averaged *)
  let cal_d = Array.init 22 (fun i -> -0.14 +. (0.01 *. float_of_int i)) in
  let cal_m = Array.map (fun d ->
      let acc = ref 0.0 and n = ref 0 in
      for _ = 1 to 64 do
        let nc = 10 + Random.State.int st 10 and k = Random.State.int st tb.Timebase.n_taps in
        let tl = Timebase.instant tb st nc k in
        let te = Kick.shot kick noise st (fun _ -> kick.Kick.base +. d) (tl +. d_kout +. (noise.Noise.launch_jitter *. gauss st)) in
        if Float.is_finite te then (acc := !acc +. (Timebase.timestamp tb st te -. Timebase.estimate tb nc k); incr n)
      done;
      !acc /. float_of_int (max 1 !n)) cal_d in
  (* the delay falls as the level rises: sort the table by delay for the host's inversion *)
  let order = Array.init (Array.length cal_d) (fun i -> i) in
  Array.sort (fun a b -> compare cal_m.(a) cal_m.(b)) order;
  let cal_m = Array.map (fun i -> cal_m.(i)) order and cal_d = Array.map (fun i -> cal_d.(i)) order in
  (* aperture response H(f) = sum w e^{-j 2 pi f (pos - centroid)} *)
  let h f =
    let re = ref 0.0 and im = ref 0.0 in
    Array.iteri (fun i p ->
        let a = two_pi *. f *. (p -. kick.Kick.centroid) in
        re := !re +. (kick.Kick.w.(i) *. cos a); im := !im +. (kick.Kick.w.(i) *. sin a)) kick.Kick.pos;
    (!re, !im) in
  say "A. random-time kicked sampling (architecture-v0 time base, INL after code density %.1f ps)" (inl *. 1e12);
  let (hr, hi) = h 700e6 in
  say "   aperture |H| at 300 MHz %.3f, 700 MHz %.3f (known to the host from characterisation)"
    (let r, i = h 300e6 in sqrt ((r *. r) +. (i *. i))) (sqrt ((hr *. hr) +. (hi *. hi)));
  let run_trial ~k ~m ~verbose =
    let w = float_of_int (2 * m) *. tb.Timebase.period in
    let tones = random_tones st k ~fmin:5e6 ~fmax:700e6 ~amin:0.1 ~amax:0.35 ~min_sep:(3.0 /. w) in
    let peak = Array.fold_left (fun s t -> s +. t.Linalg.amp) 0.0 tones in
    let scale = Float.min 1.0 (0.5 /. peak) in           (* keep the pin inside the kick's range *)
    let tones = Array.map (fun t -> { t with Linalg.amp = t.Linalg.amp *. scale }) tones in
    let t_host = Array.make m 0.0 and y = Array.make m 0.0 in
    let valid = ref 0 in
    for i = 0 to m - 1 do
      let nc = (2 * i) + Random.State.int st 2 and kb = Random.State.int st tb.Timebase.n_taps in
      let tl = Timebase.instant tb st nc kb in
      let ta = tl +. d_kout +. (noise.Noise.launch_jitter *. gauss st) in
      let te = Kick.shot kick noise st (fun t -> offset +. (k_s *. signal tones (t -. d_kout))) ta in
      let meas = Timebase.timestamp tb st te -. Timebase.estimate tb nc kb in
      let u = if Float.is_finite meas then Kick.interp cal_m cal_d meas else nan in
      t_host.(i) <- Timebase.estimate tb nc kb +. kick.Kick.centroid;
      if Float.is_finite u then (incr valid; y.(i) <- (kick.Kick.base +. u -. offset) /. k_s) else y.(i) <- 0.0
    done;
    let mean = Array.fold_left ( +. ) 0.0 y /. float_of_int m in
    let y = Array.map (fun v -> v -. mean) y in
    let atom f =
      let r, i = h f in
      (Array.map (fun t -> (r *. cos (two_pi *. f *. t)) -. (i *. sin (two_pi *. f *. t))) t_host,
       Array.map (fun t -> -.((r *. sin (two_pi *. f *. t)) +. (i *. cos (two_pi *. f *. t)))) t_host) in
    let df = 1.0 /. (2.0 *. w) in
    let nf = int_of_float ((700e6 -. 5e6) /. df) in
    let grid = Array.init nf (fun j -> let f = 5e6 +. (float_of_int j *. df) in let c, s = atom f in (f, c, s)) in
    let c0 = !Linalg.corr_macs and o0 = !Linalg.other_flops in
    let t0 = Sys.time () in
    let est, rres = Linalg.omp_tones ~atom ~grid ~df y k in
    let dt = Sys.time () -. t0 in
    let ok, ferr, aerr = judge tones est (1.0 /. w) in
    if verbose then begin
      say "   example: K=%d, M=%d over %.1f us (%d valid kicks), residual %.1f mV rms" k m (w *. 1e6) !valid (rres *. 1e3);
      Array.iter (fun t -> say "     true %9.4f MHz %5.0f mV" (t.Linalg.f /. 1e6) (t.Linalg.amp *. 1e3)) tones;
      Array.iter (fun t -> say "     est  %9.4f MHz %5.0f mV" (t.Linalg.f /. 1e6) (t.Linalg.amp *. 1e3)) est
    end;
    (ok, ferr, aerr, dt, !Linalg.corr_macs - c0, !Linalg.other_flops - o0, w)
  in
  ignore (run_trial ~k:4 ~m:300 ~verbose:true);
  say "   success = every tone found within 1/W and within 25 %% in amplitude; %s trials per cell"
    (if quick then "5" else "20");
  say "   K \\ M     %s" (String.concat "  " (List.map (Printf.sprintf "%16d") [ 100; 200; 400; 800 ]));
  let trials = if quick then 5 else 20 in
  List.iter (fun k ->
      let cells = List.map (fun m ->
          let succ = ref 0 and fe = ref 0.0 and tt = ref 0.0 and cm = ref 0 and om = ref 0 in
          for _ = 1 to trials do
            let ok, ferr, _, dt, c, o, _ = run_trial ~k ~m ~verbose:false in
            if ok then (incr succ; fe := Float.max !fe ferr);
            tt := !tt +. dt; cm := !cm + c; om := !om + o
          done;
          Printf.sprintf "%2d/%2d %4.0fkHz %4.2fs" !succ trials (!fe /. 1e3) (!tt /. float_of_int trials)) [ 100; 200; 400; 800 ] in
      say "   K=%-3d    %s" k (String.concat "  " cells)) [ 1; 2; 4; 8; 16 ];
  say "   (cell: successes, worst frequency error among successes, host time per recovery on this machine)";
  (* work accounting for one K=4, M=400 case *)
  let c0 = !Linalg.corr_macs and o0 = !Linalg.other_flops in
  let _, _, _, dt, _, _, w = run_trial ~k:4 ~m:400 ~verbose:false in
  let c = !Linalg.corr_macs - c0 and o = !Linalg.other_flops - o0 in
  say "   work for K=4, M=400 (%.1f us of signal): %.1f M correlation MACs, %.1f M other flops (least squares and refinement); %.2f s here"
    (w *. 1e6) (float_of_int c /. 1e6) (float_of_int o /. 1e6) dt;
  say "   RP2350 at an assumed 50 M float MACs/s: %.2f s; the correlation share of the work is %.0f %%"
    (float_of_int (c + o) /. 50e6) (100.0 *. float_of_int c /. float_of_int (c + o))

(* ------------------------------------------------------------------ B: random demodulator, 1-bit *)

(* ------------------------------------------------------------------ B: random demodulator, 1-bit *)

(* in-place radix-2 FFT (forward, e^{-j...}) *)
let fft re im =
  let n = Array.length re in
  let j = ref 0 in
  for i = 0 to n - 2 do
    if i < !j then begin
      let t = re.(i) in re.(i) <- re.(!j); re.(!j) <- t;
      let t = im.(i) in im.(i) <- im.(!j); im.(!j) <- t
    end;
    let m = ref (n / 2) in
    while !m >= 1 && !j land !m <> 0 do j := !j lxor !m; m := !m / 2 done;
    j := !j lor !m
  done;
  let len = ref 2 in
  while !len <= n do
    let ang = -.two_pi /. float_of_int !len in
    let wr = cos ang and wi = sin ang in
    let i = ref 0 in
    while !i < n do
      let cr = ref 1.0 and ci = ref 0.0 in
      for k = 0 to (!len / 2) - 1 do
        let a = !i + k and b = !i + k + (!len / 2) in
        let tr = (re.(b) *. !cr) -. (im.(b) *. !ci) and ti = (re.(b) *. !ci) +. (im.(b) *. !cr) in
        re.(b) <- re.(a) -. tr; im.(b) <- im.(a) -. ti;
        re.(a) <- re.(a) +. tr; im.(a) <- im.(a) +. ti;
        let nr = (!cr *. wr) -. (!ci *. wi) in ci := (!cr *. wi) +. (!ci *. wr); cr := nr
      done;
      i := !i + !len
    done;
    len := !len * 2
  done

let experiment_b st =
  let tb = Timebase.make st in
  let _ = Timebase.calibrate_code_density tb st 2_000_000 in
  let pad = Pad.load () in
  let noise = Noise.default in
  let period = tb.Timebase.period in
  let phase_bin p =
    let target = float_of_int p *. period /. 4.0 in
    let best = ref 0 in
    for k = 0 to tb.Timebase.n_taps - 1 do
      if Float.abs (tb.Timebase.line.(k) -. target) < Float.abs (tb.Timebase.line.(!best) -. target) then best := k
    done; !best in
  let pb = Array.init 4 phase_bin in
  let e_host = Array.map (fun k -> tb.Timebase.est.(k)) pb in
  let k_s = 0.1 in
  say "";
  say "B. random demodulator: 1-bit four-phase samples (240 MS/s) + random dither, XOR with an LFSR, PE sums over L";
  say "   host correlation by four interleaved FFTs (one per sampling phase, with the calibrated phase offsets)";
  let run ~k ~l ~w ~dither ~use_pad ~verbose =
    let n_chips = int_of_float (w *. 240e6) in
    let n_chips = n_chips - (n_chips mod (4 * l)) in
    let m = n_chips / l in
    let tones = random_tones st k ~fmin:1e6 ~fmax:115e6 ~amin:0.2 ~amax:0.6 ~min_sep:(3.0 /. w) in
    let peak = Array.fold_left (fun s t -> s +. t.Linalg.amp) 0.0 tones in
    let scale = Float.min 1.0 (0.8 *. dither /. k_s /. peak) in
    let tones = Array.map (fun t -> { t with Linalg.amp = t.Linalg.amp *. scale }) tones in
    let chips = Array.init n_chips (fun _ -> if Random.State.bool st then 1.0 else -1.0) in
    let t_true = Array.init n_chips (fun n -> Timebase.instant tb st ~since:1 (n / 4) pb.(n mod 4)) in
    let t_host n = (float_of_int (n / 4) *. period) +. e_host.(n mod 4) in
    (* dither: a random level, uniform in +-dither, new every quarter clock (ASSUMPTION: a 4-pin
       random DAC from LFSR bits on four-phase outputs, summed into the pin node through resistors,
       settling with 0.3 ns and changing half a quarter away from the sampling instants) *)
    let q = period /. 4.0 in
    let nseg = n_chips + 8 in
    let dl = Array.init nseg (fun _ -> uniform st (-.dither) dither) in
    let dith t =
      let x = (t /. q) +. 0.5 in
      let i = max 1 (min (nseg - 1) (int_of_float (floor x))) in
      let since = (x -. float_of_int i) *. q in
      dl.(i) +. ((dl.(i - 1) -. dl.(i)) *. exp (-.since /. 0.3e-9)) in
    let pin t = pad.Pad.vt +. (k_s *. signal tones t) +. dith t in
    let bits =
      if not use_pad then Array.map (fun t -> if pin t -. Noise.threshold noise st > pad.Pad.vt then 1.0 else -1.0) t_true
      else begin
        let dt = 5e-12 in
        let s = Pad.init pad dt (pin 0.0) in
        let res = Array.make n_chips 0.0 in
        let t = ref 0.0 and i = ref 0 in
        let thr = ref (Noise.threshold noise st) in
        let dl = pad.Pad.d_lv in
        while !i < n_chips do
          let d = Pad.step pad dt s (pin !t -. !thr) in
          t := !t +. dt;
          if Random.State.int st 200 = 0 then thr := Noise.threshold noise st;
          while !i < n_chips && t_true.(!i) -. dl <= !t do res.(!i) <- (if d then 1.0 else -1.0); incr i done
        done;
        res
      end in
    (* the chip's output: sums of chip x bit over L chips *)
    let y = Array.init m (fun j -> let s = ref 0.0 in for n = j * l to ((j + 1) * l) - 1 do s := !s +. (chips.(n) *. bits.(n)) done; !s) in
    let atom f =
      (Array.init m (fun j -> let s = ref 0.0 in for n = j * l to ((j + 1) * l) - 1 do s := !s +. (chips.(n) *. cos (two_pi *. f *. t_host n)) done; !s),
       Array.init m (fun j -> let s = ref 0.0 in for n = j * l to ((j + 1) * l) - 1 do s := !s -. (chips.(n) *. sin (two_pi *. f *. t_host n)) done; !s)) in
    let nc = n_chips / 4 in
    let nfft = let p = ref 1 in while !p < 2 * nc do p := !p * 2 done; !p in
    let df = 1.0 /. (float_of_int nfft *. period) in
    let t0 = Sys.time () in
    let fft_macs = ref 0 in
    (* correlation of a measurement-domain residual with every grid tone, via the chip domain *)
    let correlate r =
      let spec = Array.init 4 (fun p ->
          let re = Array.make nfft 0.0 and im = Array.make nfft 0.0 in
          for c = 0 to nc - 1 do let n = (4 * c) + p in re.(c) <- chips.(n) *. r.(n / l) done;
          fft re im; (re, im)) in
      fft_macs := !fft_macs + (4 * nfft * 5 * (int_of_float (log (float_of_int nfft) /. log 2.0)));
      let nf = int_of_float (115e6 /. df) in
      Array.init nf (fun j ->
          let f = float_of_int j *. df in
          let idx = j mod nfft in
          let sr = ref 0.0 and si = ref 0.0 in
          for p = 0 to 3 do
            let re, im = spec.(p) in
            let a = -.two_pi *. f *. e_host.(p) in
            let cr = cos a and ci = sin a in
            sr := !sr +. ((re.(idx) *. cr) -. (im.(idx) *. ci)); si := !si +. ((re.(idx) *. ci) +. (im.(idx) *. cr))
          done;
          (f, (!sr *. !sr) +. (!si *. !si))) in
    (* OMP with FFT selection, direct atoms for the fits, golden-section refinement *)
    let chosen = ref [] in
    let fit freqs =
      let cols = List.concat_map (fun f -> let c, s = atom f in [ c; s ]) freqs |> Array.of_list in
      let c = Linalg.lstsq cols y in
      let r = Array.copy y in
      Array.iteri (fun j col -> Linalg.axpy (-.c.(j)) col r) cols; (c, r) in
    let resid = ref (Array.copy y) in
    for _ = 1 to k do
      let cands = correlate !resid in
      let bf = ref 0.0 and be = ref (-1.0) in
      Array.iter (fun (f, e) -> if f > 0.5e6 && e > !be && not (List.exists (fun g -> Float.abs (g -. f) < 2.0 *. df) !chosen) then (be := e; bf := f)) cands;
      chosen := !chosen @ [ !bf ];
      resid := snd (fit !chosen)
    done;
    let freqs = Array.of_list !chosen in
    Array.iteri (fun i f0 ->
        let others = List.filteri (fun j _ -> j <> i) (Array.to_list freqs) in
        let _, r = fit others in
        let score f = let ca, sa = atom f in let cs = Linalg.lstsq [| ca; sa |] r in
          let rr = Array.copy r in Linalg.axpy (-.cs.(0)) ca rr; Linalg.axpy (-.cs.(1)) sa rr; -.(Linalg.dot rr rr) in
        let g = (sqrt 5.0 -. 1.0) /. 2.0 in
        let a = ref (f0 -. df) and b = ref (f0 +. df) in
        let c = ref (!b -. (g *. (!b -. !a))) and d = ref (!a +. (g *. (!b -. !a))) in
        let fc = ref (score !c) and fd = ref (score !d) in
        for _ = 1 to 25 do
          if !fc > !fd then (b := !d; d := !c; fd := !fc; c := !b -. (g *. (!b -. !a)); fc := score !c)
          else (a := !c; c := !d; fc := !fd; d := !a +. (g *. (!b -. !a)); fd := score !d)
        done;
        freqs.(i) <- 0.5 *. (!a +. !b)) freqs;
    let c, _ = fit (Array.to_list freqs) in
    let dtime = Sys.time () -. t0 in
    (* amplitude: E[bit] = k_s x / dither for a uniform dither of +-dither *)
    let est = Array.mapi (fun i f -> let a = c.(2 * i) and b = c.((2 * i) + 1) in
                           { Linalg.f; amp = sqrt ((a *. a) +. (b *. b)) *. dither /. k_s; phase = 0.0 }) freqs in
    let ok, ferr, aerr = judge tones est (1.0 /. w) in
    if verbose then begin
      say "   example: K=%d, L=%d, %d sums over %.0f us, dither +-%.0f mV at the pin, %s comparator; host %.2f s (%.0f M FFT flops)"
        k l m (w *. 1e6) (dither *. 1e3) (if use_pad then "SPICE-fitted pad" else "ideal") dtime (float_of_int !fft_macs /. 1e6);
      Array.iter (fun t -> say "     true %9.4f MHz %5.0f mV" (t.Linalg.f /. 1e6) (t.Linalg.amp *. 1e3)) tones;
      Array.iter (fun t -> say "     est  %9.4f MHz %5.0f mV" (t.Linalg.f /. 1e6) (t.Linalg.amp *. 1e3)) est
    end;
    (ok, ferr, aerr, dtime, m)
  in
  let w = 500e-6 in
  say "   noise folding: each sum carries L chips of dither-quantisation noise (variance ~1 per chip) but only the";
  say "   diagonal of the signal, so the tone SNR after correlation falls as 1/sqrt(L) against L = 1";
  ignore (run ~k:4 ~l:32 ~w ~dither:0.1 ~use_pad:false ~verbose:true);
  ignore (run ~k:4 ~l:32 ~w ~dither:0.1 ~use_pad:true ~verbose:true);
  let trials = if quick then 2 else 6 in
  say "   success rate (%d trials per cell, 3 for the pad), W = %.0f us (%d chips)" trials (w *. 1e6) (int_of_float (w *. 240e6));
  List.iter (fun (use_pad, dither, ls) ->
      List.iter (fun l ->
          let tr = if use_pad then min trials 3 else trials in
          let cells = List.map (fun k ->
              let succ = ref 0 in
              for _ = 1 to tr do
                let ok, _, _, _, _ = run ~k ~l ~w ~dither ~use_pad ~verbose:false in
                if ok then incr succ
              done;
              Printf.sprintf "K=%d %d/%d" k !succ tr) [ 1; 2; 4; 8 ] in
          say "   %-5s dither +-%3.0f mV  L=%-4d (%6.3f MS/s of sums, M=%6d): %s"
            (if use_pad then "pad" else "ideal") (dither *. 1e3) l (240.0 /. float_of_int l)
            (int_of_float (w *. 240e6) / l) (String.concat "  " cells)) ls)
    [ (false, 0.1, [ 1; 8; 32; 128 ]); (false, 0.3, [ 8; 32 ]); (true, 0.1, [ 8; 32 ]); (true, 0.3, [ 8; 32 ]) ];
  say "   data rate: raw bits 240 Mbit/s (L=1); sums at L=8: 30 MS/s x 4 bits = 120 Mbit/s; L=32: 7.5 MS/s x 6 bits = 45 Mbit/s;";
  say "   L=128: 1.9 MS/s x 8 bits = 15 Mbit/s = 1.9 MB/s, inside the 7.5 MB/s host link"
let () =
  let st = Random.State.make [| 20260925 |] in
  say "# cs.exe%s (seed 20260925)" (if quick then " quick" else "");
  if Sys.getenv_opt "SKIP_A" = None then experiment_a st;
  experiment_b st;
  let oc = open_out (if quick then "../results/cs-quick.txt" else "../results/cs.txt") in
  output_string oc (Buffer.contents out); close_out oc
