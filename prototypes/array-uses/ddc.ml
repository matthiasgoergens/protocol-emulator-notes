(* A four-channel shortwave AM receiver: an 8-bit ADC sampled at the chip clock (60 MS/s, the
   whole 0-30 MHz band) feeding one 16-PE upe_v0 chain, simulated clock by clock with the
   lockstep-checked PE model. This is the one candidate in results/evaluation.txt where the host
   cannot keep up and the array can.

   Chain, per channel c (4 PEs; the 8-bit sample walks the whole chain, P <- A everywhere):
     4c    NCO for I: S <- S + K wrapping, 16 bit (915 Hz steps, enough for AM), lane out = S[15]
     4c+1  I accumulator: S <- S + (g ? -A : A) wrapping, g = the lane (the LO's sign): mixing
           with a square-wave LO and the first CIC integrator in one step
     4c+2  NCO for Q: the same K, started a quarter turn ahead (less the two clocks by which
           the sample reaches the Q accumulator later)
     4c+3  Q accumulator
   Every R = 240 clocks the host reads the eight accumulators (through the segment's tap; that
   is 8 words per 4 us) and differences them: a boxcar (sinc) decimator to 250 kS/s. The host
   then filters each channel to 5 kHz, takes the envelope sqrt(I^2 + Q^2), removes DC and writes
   a WAV at 50 kS/s.

   What the scene tests:
   - three stations 50-105 kHz apart around 6 MHz (the 49 m broadcast band), each with its own
     programme, received on channels 0-2;
   - channel 3 tuned to an empty frequency (6.150 MHz) with a strong station at exactly three
     times it (18.450 MHz): a square-wave LO has a third harmonic at -9.5 dB, so that station
     leaks in. The measured leak is the price of mixing without a multiplier.
   - an 8-bit ADC with Gaussian noise; everything at the pins is quantised as the chip would see it. *)

let fclk = 60e6
let r_dec = 240
let pi = Float.pi

let nco = Upe.cfg_bytes ~fn:1 ~xs:0 ~ys:0 ~sw:1 ~pw:0 ~bsel:1
let acc = Upe.cfg_bytes ~fn:1 ~xs:0 ~ys:1 ~ym:2 ~gs:2 ~sw:1 ~pw:0 ~bsel:0 ()

let chan_freq = [| 5.950e6; 6.000e6; 6.055e6; 6.150e6 |]

(* stations: carrier (Hz), carrier amplitude (ADC counts), modulation depth, programme *)
type prog = Melody of float array | Tones of float * float | Chirp | Beeps of float
let stations = [
  (5.950e6, 17., 0.8, Melody [| 523.25; 659.25; 783.99; 1046.5 |]);
  (6.000e6, 17., 0.8, Tones (700., 1100.));
  (6.055e6, 13., 0.8, Chirp);
  (18.450e6, 24., 0.8, Beeps 400.);            (* at 3 x 6.150 MHz: the image test *)
]

let audio p t =
  match p with
  | Melody notes -> sin (2. *. pi *. notes.(int_of_float (t /. 0.25) mod 4) *. t)
  | Tones (a, b) -> if int_of_float (t /. 0.3) mod 2 = 0 then sin (2. *. pi *. a *. t) else sin (2. *. pi *. b *. t)
  | Chirp -> sin (2. *. pi *. (300. +. (1500. *. Float.rem t 1.0)) *. t)
  | Beeps f -> if Float.rem t 0.2 < 0.1 then sin (2. *. pi *. f *. t) else 0.

let gauss = let spare = ref None in fun () ->
  match !spare with
  | Some v -> spare := None; v
  | None ->
    let u1 = Random.float 1. +. 1e-12 and u2 = Random.float 1. in
    let m = sqrt (-2. *. log u1) in spare := Some (m *. sin (2. *. pi *. u2)); m *. cos (2. *. pi *. u2)

let clipped = ref 0

let adc t =
  let v = List.fold_left (fun s (fc, a, m, p) -> s +. (a *. (1. +. (m *. audio p t)) *. cos (2. *. pi *. fc *. t))) 0. stations in
  let v = v +. (4. *. gauss ()) in
  if Float.abs v > 127.5 then incr clipped;
  let q = int_of_float (Float.round v) in
  max (-128) (min 127 q)

(* second-order low-pass (bilinear biquad), for the host's channel filter *)
type biquad = { b0 : float; b1 : float; b2 : float; a1 : float; a2 : float; mutable z1 : float; mutable z2 : float }
let lowpass fs fc =
  let w = tan (pi *. fc /. fs) and q = 0.7071 in
  let n = 1. /. (1. +. (w /. q) +. (w *. w)) in
  { b0 = w *. w *. n; b1 = 2. *. w *. w *. n; b2 = w *. w *. n; a1 = 2. *. ((w *. w) -. 1.) *. n;
    a2 = (1. -. (w /. q) +. (w *. w)) *. n; z1 = 0.; z2 = 0. }
let bq f x = let y = (f.b0 *. x) +. f.z1 in f.z1 <- (f.b1 *. x) -. (f.a1 *. y) +. f.z2; f.z2 <- (f.b2 *. x) -. (f.a2 *. y); y

let main args =
  let seconds = match args with s :: _ -> float_of_string s | [] -> 1.2 in
  let dir = match args with _ :: d :: _ -> d | _ -> "out" in
  ignore (Sys.command ("mkdir --parents " ^ dir));
  Random.init 7;
  let r = Row.create 16 in
  let kof f = int_of_float (Float.round (f *. 65536. /. fclk)) land 0xffff in
  let cfgs = Array.make 16 [] in
  Array.iteri (fun c f ->
      let k = kof f in
      cfgs.(4 * c) <- nco ~k (); cfgs.((4 * c) + 1) <- acc;
      cfgs.((4 * c) + 2) <- nco ~k (); cfgs.((4 * c) + 3) <- acc) chan_freq;
  Row.load_direct r cfgs;
  (* initial phases (the init chain on the chip): I's NCO at 0; Q's a quarter turn ahead, less
     two steps, because each sample reaches the Q accumulator two clocks after the I one *)
  Array.iteri (fun c f ->
      let k = kof f in
      r.pes.(4 * c).s <- 0; r.pes.((4 * c) + 2).s <- (0x4000 - (2 * k)) land 0xffff) chan_freq;
  let total = int_of_float (seconds *. fclk) in
  let prev = Array.make 8 0 in
  let fs1 = fclk /. float r_dec in
  let filt = Array.init 4 (fun _ -> Array.init 4 (fun _ -> lowpass fs1 5000.)) in
  let dc = Array.make 4 0. in
  let out = Array.init 4 (fun _ -> Buffer.create 1_000_000) in
  let raw = open_out (Filename.concat dir "ddc-iq.txt") in
  let nout = ref 0 in
  for t = 0 to total - 1 do
    let x = adc (float t /. fclk) in
    ignore (Row.step r { Row.seg_idle with feed = x land 0xffff });
    if t mod r_dec = r_dec - 1 then begin
      (* the host reads the eight accumulators and differences them (mod 2^16) *)
      let iq = Array.init 8 (fun j ->
          let pe = (4 * (j / 2)) + 1 + (2 * (j mod 2)) in
          let s = r.pes.(pe).s in
          let d = (s - prev.(j)) land 0xffff in
          prev.(j) <- s;
          if d >= 0x8000 then d - 0x10000 else d) in
      if !nout < 20000 then
        Printf.fprintf raw "%s\n" (String.concat " " (Array.to_list (Array.map string_of_int iq)));
      for c = 0 to 3 do
        let i = float iq.(2 * c) and q = float iq.((2 * c) + 1) in
        let i = bq filt.(c).(1) (bq filt.(c).(0) i) and q = bq filt.(c).(3) (bq filt.(c).(2) q) in
        let e = sqrt ((i *. i) +. (q *. q)) in
        dc.(c) <- dc.(c) +. (0.0005 *. (e -. dc.(c)));
        if !nout mod 5 = 0 then Buffer.add_string out.(c) (Printf.sprintf "%.3f\n" (e -. dc.(c)))
      done;
      incr nout
    end
  done;
  close_out raw;
  Array.iteri (fun c b ->
      let oc = open_out (Filename.concat dir (Printf.sprintf "ddc-ch%d.txt" c)) in
      Buffer.output_buffer oc b; close_out oc) out;
  Printf.printf "ddc: %d of %d ADC samples clipped\n" !clipped total;
  Printf.printf "ddc: %d clocks (%.2f s) through 16 PEs, %d decimated I/Q frames at %.0f S/s; channels %s MHz -> %s/ddc-ch*.txt\n"
    total seconds !nout fs1
    (String.concat ", " (Array.to_list (Array.map (fun f -> Printf.sprintf "%.3f" (f /. 1e6)) chan_freq))) dir
