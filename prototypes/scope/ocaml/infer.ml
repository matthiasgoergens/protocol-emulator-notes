(* Question-driven compressive inference: answer a small multiple-choice question about a line
   with as few one-bit samples as possible, choosing each sample (instant after a trigger, and
   threshold) to separate the candidates still in play, and stopping when the posterior is sure.
   Davenport, Boufounos, Wakin, Baraniuk (2010) do detection and classification directly on
   compressive measurements; here the measurements are adaptive (sequential Bayesian experimental
   design, greedy in expected information gain) and each costs one repetition of a trigger.

   Engine: hypotheses h = 1..K; for every candidate action a (instant, threshold) a table
   p.(h).(a) = P(bit = 1 | h, a) is precomputed by finite Monte Carlo from a generative model of
   each candidate (with its unknown data, jitter and noise). The estimates are clamped to avoid
   log(0), then treated as exact by the update. Observations are drawn from a FRESH simulation of the
   true candidate, not from the table. Policies: greedy information gain, random actions, and an
   in-order reference. The posterior and its stopping threshold are heuristic; they do not integrate
   uncertainty in the Monte Carlo table and are not calibrated confidence guarantees.

   Scenarios: which of K frames (a 125 Mbit/s NRZ line, strong and weak signal); which of K UART
   baud rates (unknown data); which of K line protocols; is this edge within spec (K = 2).
   Output: ../results/infer.txt. Run from prototypes/scope/ocaml: ./_build/default/infer.exe [quick] *)

open Chain

let quick = Array.length Sys.argv > 1 && Sys.argv.(1) = "quick"
let out = Buffer.create 4096
let say fmt = Printf.ksprintf (fun s -> print_endline s; Buffer.add_string out (s ^ "\n")) fmt

let clamp_mc p = Float.min 0.999 (Float.max 0.001 p)  (* avoid log(0); not a confidence interval *)
let h2 p = if p <= 0.0 || p >= 1.0 then 0.0 else -.((p *. log p) +. ((1.0 -. p) *. log (1.0 -. p)))

type policy = Greedy | Random_action | Fixed of int array   (* a fixed schedule of actions *)

(* one sequential test; returns (decided h, samples used) *)
let run_test st ~(p : float array array) ~(observe : int -> bool) ~eps ~cap policy =
  let k = Array.length p and na = Array.length p.(0) in
  let logpost = Array.make k (-.log (float_of_int k)) in
  let post () =
    let m = Array.fold_left Float.max neg_infinity logpost in
    let e = Array.map (fun l -> exp (l -. m)) logpost in
    let s = Array.fold_left ( +. ) 0.0 e in
    Array.map (fun x -> x /. s) e in
  let n = ref 0 and fin = ref false and dec = ref 0 in
  while not !fin do
    let pi = post () in
    let best = ref 0 in
    Array.iteri (fun i x -> if x > pi.(!best) then best := i) pi;
    if pi.(!best) >= 1.0 -. eps || !n >= cap then (fin := true; dec := !best)
    else begin
      let a =
        match policy with
        | Random_action -> Random.State.int st na
        | Fixed sched -> sched.(!n mod Array.length sched)
        | Greedy ->
          let ba = ref 0 and bv = ref neg_infinity in
          for a = 0 to na - 1 do
            let pm = ref 0.0 and hc = ref 0.0 in
            for h = 0 to k - 1 do pm := !pm +. (pi.(h) *. p.(h).(a)); hc := !hc +. (pi.(h) *. h2 p.(h).(a)) done;
            let ig = h2 !pm -. !hc in
            if ig > !bv then (bv := ig; ba := a)
          done;
          !ba
      in
      let b = observe a in
      for h = 0 to k - 1 do
        logpost.(h) <- logpost.(h) +. log (if b then p.(h).(a) else 1.0 -. p.(h).(a))
      done;
      incr n
    end
  done;
  (!dec, !n)

let evaluate st ~name ~p ~simulate ~eps ~cap ~trials ~policies =
  let k = Array.length p in
  List.iter (fun (pname, pol) ->
      let err = ref 0 and tot = ref 0 and mx = ref 0 in
      for t = 1 to trials do
        let truth = t mod k in
        let d, n = run_test st ~p ~observe:(fun a -> simulate truth a) ~eps ~cap pol in
        if d <> truth then incr err;
        tot := !tot + n; mx := max !mx n
      done;
      say "   %-34s K=%d %-8s mean %6.1f samples (max %4d), errors %d/%d" name k pname
        (float_of_int !tot /. float_of_int trials) !mx !err trials) policies

(* Monte-Carlo table: p.(h).(a) from [draw h a] (a fresh random realisation, true = 1) *)
let table st k na ~mc draw =
  Array.init k (fun h -> Array.init na (fun a ->
      let c = ref 0 in
      for _ = 1 to mc do if draw st h a then incr c done;
      clamp_mc (float_of_int !c /. float_of_int mc)))

let noise = Noise.default
let sig_v = Noise.threshold_sigma noise

(* ------------------------------------------------------------------ S1: which of K frames *)

let frames st =
  say "S1. Which of K frames? 125 Mbit/s NRZ, 64-bit frames sharing a 16-bit sync; the matcher triggers on the";
  say "    sync, the TDC timestamps its last edge (20 ps rms), one sample per repetition at a chosen bit centre.";
  say "    Candidates differ from a base frame in 1..6 random bits (like register addresses or status flags).";
  let ui = 8e-9 and rise = 1e-9 in
  let base = Array.init 64 (fun i -> if i < 16 then (i mod 2 = 0) else Random.State.bool st) in
  let make k = Array.init k (fun h ->
      if h = 0 then Array.copy base
      else begin
        let f = Array.copy base in
        let nflip = 1 + Random.State.int st 6 in
        for _ = 1 to nflip do let i = 16 + Random.State.int st 48 in f.(i) <- not f.(i) done;
        f
      end) in
  (* the line near sample instant t (in bits after the frame start) for frame fr, with jitter:
     sum of erf edges; amplitude amp at the pin relative to the threshold *)
  let level fr amp t_bits =
    let i = int_of_float (floor t_bits) in
    let v = ref (if fr.(max 0 (min 63 (i - 2))) then amp else -.amp) in
    for j = i - 1 to i + 2 do
      let prev = fr.(max 0 (min 63 (j - 1))) and cur = fr.(max 0 (min 63 j)) in
      if prev <> cur then begin
        let dt = (t_bits -. float_of_int j) *. ui in
        let s = rise /. 2.563 in
        let e = phi (dt /. s) in
        v := !v +. ((if cur then 2.0 else -2.0) *. amp *. e)
      end
    done;
    !v in
  let draw fr amp st a =
    (* a = bit index; instant = centre, with trigger and sampling jitter *)
    let tj = (sqrt ((20e-12 ** 2.0) +. (30e-12 ** 2.0) +. (10e-12 ** 2.0)) *. gauss st) /. ui in
    level fr amp (float_of_int a +. 0.5 +. tj) +. (sig_v *. gauss st) > 0.0 in
  let trials = if quick then 60 else 400 in
  List.iter (fun (amp, label) ->
      List.iter (fun k ->
          let fr = make k in
          let p = table st k 64 ~mc:(if quick then 300 else 2000) (fun st h a -> draw fr.(h) amp st a) in
          let simulate h a = draw fr.(h) amp st a in
          let decode = Fixed (Array.init 64 (fun i -> i)) in
          evaluate st ~name:(Printf.sprintf "frames, %s" label) ~p ~simulate ~eps:1e-3 ~cap:640 ~trials
            ~policies:[ ("greedy", Greedy); ("random", Random_action); ("in-order", decode) ]) [ 2; 4; 8 ])
    [ (0.3, "strong (300 mV)"); (0.003, "weak (3 mV)") ];
  say "    in-order = read the bits in order (repeating the frame as often as needed), stopping when sure; a full";
  say "    decode reads all 64 bits (strong signal) or about 64 x 5 samples (weak: 10 %% raw bit errors, majority of 5)."

(* ------------------------------------------------------------------ S2: which baud rate *)

let bauds st =
  say "";
  say "S2. Which of K UART baud rates? 8N1 with unknown data; trigger on a falling edge that is a start bit";
  say "    (the line idled first); one sample per trigger at a chosen delay; data bits are nuisance (marginalised).";
  let rates = [| 9600.; 19200.; 38400.; 57600.; 115200.; 230400.; 460800.; 921600. |] in
  (* delays: 64 log-spaced from 0.3 us to 1.2 ms *)
  let acts = Array.init 64 (fun i -> 0.3e-6 *. (4000.0 ** (float_of_int i /. 63.0))) in
  let draw st h a =
    let bit = 1.0 /. rates.(h) in
    let t = acts.(a) +. (3e-9 *. gauss st) in           (* trigger/TDC jitter: irrelevant here *)
    let b = t /. bit in
    if b < 1.0 then false                                  (* start bit *)
    else if b < 9.0 then Random.State.bool st              (* data: unknown *)
    else if b < 10.0 then true                             (* stop bit *)
    else if Random.State.int st 4 = 0 then Random.State.bool st else true  (* idle or the next frame *)
  in
  let trials = if quick then 60 else 400 in
  List.iter (fun k ->
      (* the K fastest-to-slowest spread: K rates spaced across the list *)
      let idx = Array.init k (fun i -> i * (7 / max 1 (k - 1))) in
      let idx = if k = 8 then Array.init 8 (fun i -> i) else idx in
      let p = table st k 64 ~mc:(if quick then 300 else 2000) (fun st h a -> draw st idx.(h) a) in
      let simulate h a = draw st idx.(h) a in
      evaluate st ~name:"baud rate" ~p ~simulate ~eps:1e-3 ~cap:2000 ~trials
        ~policies:[ ("greedy", Greedy); ("random", Random_action) ]) [ 2; 4; 8 ];
  say "    decode instead: capture at 4 samples per bit of the fastest candidate for one frame of the slowest";
  say "    (10 bits at 9600 = 1.04 ms at 3.7 MS/s) = 3,840 samples, then decide offline."

(* ------------------------------------------------------------------ S3: which protocol *)

let protocols st =
  say "";
  say "S3. Which of K protocols is on this line? One sample per falling edge at a chosen delay; each candidate";
  say "    is a generative model with random data; the table is P(high at delay | a falling edge at 0).";
  (* each generator returns a list of (time, level) transitions over ~2 ms, starting at a random phase *)
  let gen st name =
    let tr = ref [] and t = ref 0.0 and lv = ref true in
    let set v dt = t := !t +. dt; if v <> !lv then (tr := (!t, v) :: !tr; lv := v) in
    let horizon = 2.5e-3 in
    (match name with
     | `Uart r ->
       while !t < horizon do
         set true (uniform st 0.0 (20.0 /. r));
         set false (1.0 /. r);
         for _ = 1 to 8 do set (Random.State.bool st) (1.0 /. r) done;
         set true (1.0 /. r)
       done
     | `Spi f ->                                          (* SCK mode 0 bursts of 8, idle low *)
       lv := false;
       while !t < horizon do
         set false (uniform st 2e-6 20e-6);
         for _ = 1 to 8 do set true (0.5 /. f); set false (0.5 /. f) done
       done
     | `I2c f ->                                          (* SCL, 9-clock bytes, idle high *)
       while !t < horizon do
         set true (uniform st 5e-6 50e-6);
         for _ = 1 to 9 do set false (0.5 /. f); set true (0.5 /. f) done
       done
     | `Ws2812 ->                                         (* idle low; 24-bit pixels at 800 kHz *)
       lv := false;
       while !t < horizon do
         set false (uniform st 50e-6 300e-6);
         for _ = 1 to 24 * 8 do
           if Random.State.bool st then (set true 0.8e-6; set false 0.45e-6) else (set true 0.4e-6; set false 0.85e-6)
         done
       done
     | `Can r ->                                          (* NRZ with bit stuffing, idle recessive (high) *)
       while !t < horizon do
         set true (uniform st (11.0 /. r) (40.0 /. r));
         let run = ref 0 and last = ref true in
         for _ = 1 to 100 do
           let b = if !run >= 5 then not !last else Random.State.bool st in
           if b = !last then incr run else run := 1;
           last := b; set b (1.0 /. r)
         done
       done
     | `Pwm (f, duty) ->
       while !t < horizon do set true (duty /. f); set false ((1.0 -. duty) /. f) done);
    Array.of_list (List.rev !tr) in
  let cands = [| ("UART 115200", `Uart 115200.); ("I2C SCL 100 kHz", `I2c 100e3); ("SPI SCK 1 MHz", `Spi 1e6);
                 ("CAN 500 kbit/s", `Can 500e3); ("UART 9600", `Uart 9600.); ("I2C SCL 400 kHz", `I2c 400e3);
                 ("WS2812", `Ws2812); ("PWM 20 kHz 30 %", `Pwm (20e3, 0.3)) |] in
  let acts = Array.init 64 (fun i -> 0.05e-6 *. (4000.0 ** (float_of_int i /. 63.0))) in
  let draw st h a =
    let tr = gen st (snd cands.(h)) in
    (* a random falling edge in the first half, then the level at the delay *)
    let falls = List.filter (fun (t, v) -> (not v) && t < 1.0e-3) (Array.to_list tr) |> Array.of_list in
    if Array.length falls = 0 then true
    else begin
      let t0 = fst falls.(Random.State.int st (Array.length falls)) in
      let t = t0 +. acts.(a) +. (5e-9 *. gauss st) in
      let lv = ref false in
      Array.iter (fun (tt, v) -> if tt <= t then lv := v) tr;
      !lv
    end in
  let trials = if quick then 40 else 200 in
  List.iter (fun k ->
      let p = table st k 64 ~mc:(if quick then 150 else 600) draw in
      let simulate h a = draw st h a in
      evaluate st ~name:(Printf.sprintf "protocol (first %d of the list)" k) ~p ~simulate ~eps:1e-3 ~cap:2000 ~trials
        ~policies:[ ("greedy", Greedy); ("random", Random_action) ]) [ 2; 4; 8 ];
  say "    candidates in order: %s" (String.concat ", " (Array.to_list (Array.map fst cands)));
  say "    decode instead: capture ~1 ms at 4 MS/s (4,000 samples) and classify offline."

(* ------------------------------------------------------------------ S4: is this edge within spec *)

let edge_spec st =
  say "";
  say "S4. Is this I2C rise within the fast-mode limit (30-70 %% in 300 ns)? K = 2 with an indifference zone:";
  say "    rise 250 ns (pass) against 350 ns (fail); actions: (instant, threshold) pairs; noise on the threshold";
  say "    from the pad (%.1f mV) and on the instant (TDC, 20 ps); one sample per released edge." (sig_v *. 1e3);
  let vdd = 3.3 in
  let tau r = r /. log (0.7 /. 0.3) in
  let inst = Array.init 16 (fun i -> 50e-9 *. float_of_int (i + 1)) in
  let thr = Array.init 8 (fun j -> vdd *. (0.2 +. (0.08 *. float_of_int j))) in
  let na = 16 * 8 in
  let rises = [| 250e-9; 350e-9 |] in
  let draw st h a =
    let t = inst.(a / 8) +. (20e-12 *. gauss st) and th = thr.(a mod 8) in
    let v = vdd *. (1.0 -. exp (-.t /. tau rises.(h))) in
    (0.15 *. v) +. (sig_v *. gauss st) > 0.15 *. th in                        (* k_s = 0.15 as in demo_i2c *)
  let p = table st 2 na ~mc:(if quick then 400 else 4000) draw in
  let trials = if quick then 100 else 1000 in
  evaluate st ~name:"edge within spec" ~p ~simulate:(fun h a -> draw st h a) ~eps:1e-3 ~cap:5000 ~trials
    ~policies:[ ("greedy", Greedy); ("random", Random_action) ];
  (* robustness: a true rise of 300 ns, right at the limit, is 50/50 by construction; 280 and 320 ns *)
  List.iter (fun r ->
      let dec = Array.make 2 0 and tot = ref 0 in
      for _ = 1 to trials / 4 do
        let d, n = run_test st ~p ~observe:(fun a ->
            let t = inst.(a / 8) +. (20e-12 *. gauss st) and th = thr.(a mod 8) in
            let v = vdd *. (1.0 -. exp (-.t /. tau r)) in (0.15 *. v) +. (sig_v *. gauss st) > 0.15 *. th)
            ~eps:1e-3 ~cap:5000 Greedy in
        dec.(d) <- dec.(d) + 1; tot := !tot + n
      done;
      say "   true rise %.0f ns: decided pass %d, fail %d, mean %.1f samples" (r *. 1e9) dec.(0) dec.(1)
        (float_of_int !tot /. float_of_int (trials / 4))) [ 280e-9; 300e-9; 320e-9 ];
  say "    reconstruct instead: demo_i2c.py used 1.8 M one-bit samples for the whole waveform."

let () =
  let st = Random.State.make [| 7 |] in
  say "# infer.exe%s (seed 7); heuristic stop at posterior >= 1 - 1e-3; errors counted against the true candidate" (if quick then " quick" else "");
  frames st; bauds st; protocols st; edge_spec st;
  say "";
  say "CRC consistency has no such shortcut: a CRC check needs every bit it covers (any unread bit can flip the";
  say "answer), so it is a decode question, and the chip's CRC unit on the bit path answers it at line rate.";
  say "";
  say "CAUTION: action probabilities are finite-Monte-Carlo point estimates clamped to [0.001, 0.999]. The";
  say "posterior treats them as exact, so the 0.999 stop is not a calibrated 0.1 %% error guarantee. The reported";
  say "trial errors measure these simulations only; zero errors in finite trials is not evidence of zero error rate.";
  let oc = open_out (if quick then "../results/infer-quick.txt" else "../results/infer.txt") in
  output_string oc (Buffer.contents out); close_out oc
