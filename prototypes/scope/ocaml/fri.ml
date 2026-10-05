(* Edge-time super-resolution with finite-rate-of-innovation sampling, against the TDC.

   A digital line is a stream of steps: two unknowns per edge (time, amplitude). Sampling it
   through a known kernel that spreads each edge over several samples lets a few samples locate
   the edge far more finely than the sample period (Vetterli, Marziliano, Blu 2002; with an RC
   kernel, i.e. exponential reproduction, Dragotti, Vetterli, Blu 2007). The kernel here is a
   deliberate RC low-pass (tau) in front of the kicked input; the samples are kicked samples
   (multi-bit, per-shot noise from the SPICE-derived chain, results/sck.txt: 5.5 mV rms at the pin)
   taken every second clock (33.3 ns). For a first-order kernel the innovation sequence
   z_n = y_n - alpha y_(n-1), alpha = exp(-Ts/tau), is constant except around an edge, and the two
   differences w_n = z_n - z_(n-1) at and after the edge give the amplitude and the edge's offset:
   a = (w_n + w_(n+1)) / (1 - alpha), exp(-delta/tau) = 1 - w_n / a.
   Edges must be at least two samples apart (the rate of innovation: 2 unknowns per 2 samples).

   Output: ../results/fri.txt. Run from prototypes/scope/ocaml: ./_build/default/fri.exe *)

open Chain

let out = Buffer.create 4096
let say fmt = Printf.ksprintf (fun s -> print_endline s; Buffer.add_string out (s ^ "\n")) fmt

let () =
  let st = Random.State.make [| 11 |] in
  let ts = 2.0 /. 60e6 in
  say "# fri.exe (seed 11): edges at random times, >= 3 samples apart; RC kernel; samples every %.1f ns" (ts *. 1e9);
  say "   amp = edge height at the pin (inside the kick's 210 mV range); sigma = per-sample noise; t_jit = sample-instant";
  say "   error known to the host only through the calibrated time base (15 ps rms)";
  say "   tau      amp     sigma   edges  rms edge-time error   (TDC on the same edge: about 20 ps rms, 1 timestamp per edge)";
  List.iter (fun (tau, amp, sigma) ->
      let alpha = exp (-.ts /. tau) in
      let errs = ref [] in
      for _ = 1 to 2000 do
        (* one edge in a random position inside interval (t_(n-1), t_n] with n = 5, plus a quiet baseline *)
        let delta = Random.State.float st ts in
        let te = (5.0 *. ts) -. delta in
        let a = amp *. (if Random.State.bool st then 1.0 else -1.0) in
        let y = Array.init 9 (fun n ->
            let t = (float_of_int n *. ts) +. (15e-12 *. gauss st) in
            let v = if t > te then a *. (1.0 -. exp (-.(t -. te) /. tau)) else 0.0 in
            v +. (sigma *. gauss st)) in
        let z = Array.init 9 (fun n -> if n = 0 then 0.0 else y.(n) -. (alpha *. y.(n - 1))) in
        (* average the baseline innovation before the edge and the plateau after it to cut noise *)
        let pre = (z.(1) +. z.(2) +. z.(3) +. z.(4)) /. 4.0 in
        let post = (z.(6) +. z.(7) +. z.(8)) /. 3.0 in
        let w5 = z.(5) -. pre in
        let a_est = (post -. pre) /. (1.0 -. alpha) in
        let r = 1.0 -. (w5 /. a_est) in
        if r > 0.0 then begin
          let d_est = -.tau *. log r in
          errs := (d_est -. delta) :: !errs
        end
      done;
      let n = List.length !errs in
      let rms = sqrt (List.fold_left (fun s e -> s +. (e *. e)) 0.0 !errs /. float_of_int (max 1 n)) in
      say "   %5.1f ns %4.0f mV %5.1f mV %5d  %8.0f ps" (tau *. 1e9) (amp *. 1e3) (sigma *. 1e3) n (rms *. 1e12))
    [ (10e-9, 0.2, 5.5e-3); (20e-9, 0.2, 5.5e-3); (40e-9, 0.2, 5.5e-3); (20e-9, 0.2, 1.4e-3); (20e-9, 0.2, 0.2e-3) ];
  say "   sigma 1.4 mV = 16 kicks averaged (repetitive signal); 0.2 mV = the pad's own thermal noise only";
  say "";
  say "Reading: from two or three multi-bit samples 33 ns apart the edge is located to about a nanosecond,";
  say "far below the sample period but far above the TDC's 20 ps. For digital edges the TDC is the right";
  say "tool: a comparator plus a timestamp IS a one-edge FRI sampler with an ideal kernel. FRI earns its";
  say "keep where no comparator can see the event: pulses smaller than the pad's decision overdrive, edges";
  say "behind an unknown offset, or amplitude and time wanted jointly from a slow, averaged channel.";
  let oc = open_out "../results/fri.txt" in
  output_string oc (Buffer.contents out); close_out oc
