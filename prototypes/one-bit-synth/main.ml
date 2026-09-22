open Hardcaml

let fclk = 48_000_000.0
let fs = fclk /. float Synth.div

(* a melody: (frequency, seconds) pairs, precomputed into tuning words and durations in ticks *)
let melody = [ (1000.0, 0.010); (1250.0, 0.010); (1500.0, 0.010); (2000.0, 0.015) ]
let notes = List.map (fun (f, s) -> (Synth.tuning ~fs f, int_of_float (s *. fs))) melody

let circuit = Synth.circuit ~notes ~amp_shift:2

let emit () =
  let oc = open_out "one_bit_synth.v" in
  Rtl.output ~output_mode:(To_channel oc) Verilog circuit; close_out oc

(* Run the modulator for [ticks] steps; return the one-bit stream and the 16-bit samples that fed it. *)
let run ticks =
  let sim = Cyclesim.create circuit in
  let clear = Cyclesim.in_port sim "clear" in
  let pdm = Cyclesim.out_port sim "pdm" and sample = Cyclesim.out_port sim "sample" and tick = Cyclesim.out_port sim "tick" and note = Cyclesim.out_port sim "note" in
  clear := Bits.vdd; Cyclesim.cycle sim; clear := Bits.gnd;
  let bits = ref [] and samples = ref [] and notes_seen = ref [] in
  let got = ref 0 in
  while !got < ticks do
    Cyclesim.cycle sim;
    if Bits.to_int !tick = 1 then begin
      incr got;
      bits := (if Bits.to_int !pdm = 1 then 1.0 else -1.0) :: !bits;
      samples := float (Bits.to_sint !sample) :: !samples;
      let n = Bits.to_int !note in
      (match !notes_seen with h :: _ when h = n -> () | _ -> notes_seen := n :: !notes_seen)
    end
  done;
  Array.of_list (List.rev !bits), Array.of_list (List.rev !samples), List.rev !notes_seen

(* In-band spectrum of the raw bit stream with a Hann window: tone power in the bins around the
   tone, noise power in every other bin below [band] Hz. The window holds an integer number of
   tone cycles so there is no leakage from the tone into the noise bins. *)
let spectrum_db x ~fs ~band =
  let n = Array.length x in
  let w = Array.init n (fun i -> 0.5 -. 0.5 *. cos (2.0 *. Float.pi *. float i /. float n)) in
  let xw = Array.mapi (fun i v -> v *. w.(i)) x in
  let kmax = int_of_float (band *. float n /. fs) in
  Array.init (kmax + 1) (fun k ->
    let re = ref 0.0 and im = ref 0.0 in
    let c = 2.0 *. Float.pi *. float k /. float n in
    Array.iteri (fun i v -> re := !re +. v *. cos (c *. float i); im := !im -. v *. sin (c *. float i)) xw;
    (* normalise so a full-scale sine reads 0 dB *)
    let mag = 2.0 *. sqrt (!re *. !re +. !im *. !im) /. (0.5 *. float n) in
    20.0 *. log10 (mag +. 1e-12))

let () =
  emit ();
  Printf.printf "modulator rate %.0f Hz, tuning words %s\n" fs (String.concat " " (List.map (fun (tw, d) -> Printf.sprintf "%d/%d" tw d) notes));
  let ticks = int_of_float (0.010 *. fs) in                    (* 10 ms: ten cycles of the 1 kHz tone *)
  let bits, samples, notes_seen = run (5 * ticks + 100) in
  let tone = Array.sub bits 0 ticks in
  let band = 20_000.0 in
  let s = spectrum_db tone ~fs ~band in
  let bin f = int_of_float (Float.round (f *. float ticks /. fs)) in
  let k1 = bin 1000.0 in
  let tone_db = Array.fold_left max (-200.0) (Array.sub s (k1 - 1) 3) in
  let noise_lin = ref 0.0 in
  Array.iteri (fun k v -> if k > 0 && (k < k1 - 2 || k > k1 + 2) then noise_lin := !noise_lin +. 10.0 ** (v /. 10.0)) s;
  let snr = tone_db -. 10.0 *. log10 !noise_lin in
  let expected_db = 20.0 *. log10 (2047.0 *. 16.0 /. 4.0 /. 32768.0) in
  Printf.printf "1 kHz tone: %.1f dB (expected %.1f from the 12-bit table at amp_shift 2); 2nd harmonic %.1f dB, 3rd %.1f dB\n"
    tone_db expected_db s.(bin 2000.0) s.(bin 3000.0);
  Printf.printf "in-band (0-20 kHz) signal-to-noise of the raw one-bit stream: %.1f dB\n" snr;
  let peak = Array.fold_left max (-200.0) (Array.sub samples 0 ticks) in
  Printf.printf "sample peak %.0f (expect %.0f)\n" peak (2047.0 *. 16.0 /. 4.0);
  Printf.printf "notes played in order: %s\n" (String.concat " " (List.map string_of_int notes_seen));
  let ok = snr > 45.0 && Float.abs (tone_db -. expected_db) < 1.0 && notes_seen = [ 0; 1; 2; 3; 0 ] in
  print_endline (if ok then "SYNTH PASS" else "SYNTH FAIL");
  exit (if ok then 0 else 1)
