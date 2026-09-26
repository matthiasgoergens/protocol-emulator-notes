(* A five-voice chiptune synthesiser on one 16-PE segment of upe_v0, simulated clock by clock
   at 60 MHz with the lockstep-checked PE model (upe.ml), and rendered to a WAV file.

   Configuration (PE index: role):
     3v, 3v+1  voice v's 32-bit NCO, v = 0..3: low half S <- S + K_lo wrapping, lane out = the
               carry register; high half S <- S + K_hi + carry-in from the lane, lane out = S[15].
               Both pass the sum word on (P <- A).
     3v+2      voice v's square wave: P <- A + (g ? -K : K), g = the lane (the NCO's MSB),
               K = the amplitude. The sum word walks down the chain collecting every voice.
     12        noise: a Galois LFSR, S <- (S << 1 | g) XOR (g ? K : 0), g = S[15], K = 0x002d
               (x^16 + x^5 + x^3 + x^2 + 1 without the x^0 term, which the serial bit supplies);
               lane out = S[15]; P <- A.
     13        noise voice: as a square voice, with g = the LFSR bit.
     14        offset: P <- A + 0x8000 wrapping (signed sum to unsigned density).
     15        first-order sigma-delta: S <- S + A wrapping; lane out = the carry register: the pin.
   The host changes notes and envelopes by reloading the segment's configuration chain. Two
   ways are modelled, and the difference between them is a finding:
     chain   the realistic one: 128 bytes at one byte per 8 clocks (the host link's estimated
             7.5 MB/s), with the segment's enable low for 1,017 clocks (17 us) on each of the
             999 reloads after the initial configuration;
     direct  an idealised double-buffered configuration: the new bytes appear at once.
   The pin stream is filtered by two RC poles at 20 kHz (the board's filter) and sampled at
   48 kHz into a 16-bit WAV. *)

let fclk = 60e6
let n_pe = 16

let nco_lo k = Upe.cfg_bytes ~fn:1 ~xs:0 ~ys:0 ~sw:1 ~pw:0 ~bsel:2 ~k ()
let nco_hi k = Upe.cfg_bytes ~fn:1 ~xs:0 ~ys:0 ~sw:1 ~pw:0 ~bsel:1 ~cinb:1 ~k ()
let square amp = Upe.cfg_bytes ~fn:0 ~xs:1 ~ys:0 ~ym:2 ~gs:2 ~sw:0 ~pw:1 ~bsel:0 ~k:amp ()
let lfsr = Upe.cfg_bytes ~fn:4 ~xs:2 ~sins:3 ~ys:0 ~ym:1 ~gs:3 ~bcast:1 ~sw:1 ~pw:0 ~bsel:1 ~k:0x002d ()
let offset = Upe.cfg_bytes ~fn:1 ~xs:1 ~ys:0 ~sw:0 ~pw:1 ~k:0x8000 ()
let sigma_delta = Upe.cfg_bytes ~fn:1 ~xs:0 ~ys:1 ~sw:1 ~pw:0 ~bsel:2 ()

let tuning f = Int64.to_int (Int64.of_float (Float.round (f *. 4294967296. /. fclk)))

(* voice state per tick: frequency (Hz) and amplitude *)
let config (v : (float * int) array) (noise_amp : int) =
  let c = Array.make n_pe [] in
  for i = 0 to 3 do
    let f, a = v.(i) in
    let k = tuning f in
    c.(3 * i) <- nco_lo (k land 0xffff);
    c.((3 * i) + 1) <- nco_hi ((k lsr 16) land 0xffff);
    c.((3 * i) + 2) <- square a
  done;
  c.(12) <- lfsr; c.(13) <- square noise_amp; c.(14) <- offset; c.(15) <- sigma_delta;
  c

(* ---- the tune: 120 bpm, 16th-note ticks of 125 ms, envelopes stepped every 4 ms ---- *)
let midi n = 440. *. (2. ** (float_of_int (n - 69) /. 12.))
let bass = [| 36; 36; 43; 43; 45; 45; 41; 41 |]                 (* C C G G A A F F, per half bar *)
let chords = [| [| 60; 64 |]; [| 59; 62 |]; [| 57; 60 |]; [| 57; 60 |] |]  (* per bar, two voices *)
let melody = [| 72; 0; 76; 79; 77; 76; 74; 0; 72; 74; 76; 0; 74; 72; 71; 0;
                69; 0; 72; 76; 74; 72; 71; 0; 72; 0; 69; 0; 67; 0; 0; 0 |]

let env_tick = 0.004
let sixteenth = 0.125

(* amplitude of a note struck at t0 with peak a, decaying by a factor per env tick *)
let env a t0 t decay = if t < t0 then 0 else int_of_float (float a *. (decay ** ((t -. t0) /. env_tick)))

let state_at t =
  let step = int_of_float (t /. sixteenth) in
  let t_step = float step *. sixteenth in
  let bar = (step / 16) mod 4 and half = (step / 8) mod 8 in
  let v = Array.make 4 (440., 0) in
  let hb = float (step / 8 * 8) *. sixteenth in
  v.(0) <- (midi bass.(half), env 5000 hb t 0.985);
  let cb = float (step / 4 * 4) *. sixteenth in           (* chords struck every beat *)
  let ch = chords.(bar) in
  v.(1) <- (midi ch.(0), env 2600 cb t 0.97);
  v.(2) <- (midi ch.(1), env 2600 cb t 0.97);
  let m = melody.(step mod 32) in
  v.(3) <- (if m = 0 then (midi 72, 0) else (midi m, env 4200 t_step t 0.99));
  let noise = if step mod 2 = 1 then env 3000 t_step t 0.80 else if step mod 4 = 0 then env 1500 t_step t 0.9 else 0 in
  (v, noise)

let write_wav path rate (samples : float array) =
  let oc = open_out_bin path in
  let n = Array.length samples in
  let le32 x = for i = 0 to 3 do output_byte oc ((x lsr (8 * i)) land 0xff) done in
  let le16 x = for i = 0 to 1 do output_byte oc ((x lsr (8 * i)) land 0xff) done in
  output_string oc "RIFF"; le32 (36 + (2 * n)); output_string oc "WAVEfmt ";
  le32 16; le16 1; le16 1; le32 rate; le32 (rate * 2); le16 2; le16 16;
  output_string oc "data"; le32 (2 * n);
  Array.iter (fun s -> le16 (int_of_float (Float.round (Float.max (-32767.) (Float.min 32767. s))) land 0xffff)) samples;
  close_out oc

let run ?(hold = `Show) ~mode ~seconds ~out () =
  let r = Row.create n_pe in
  let total = int_of_float (seconds *. fclk) in
  let per_env = int_of_float (env_tick *. fclk) in
  let decim = 1250 in
  let alpha = 1. -. exp (-2. *. Float.pi *. 20e3 /. fclk) in
  let y1 = ref 0. and y2 = ref 0. in
  let wav = Array.make (total / decim) 0. in
  let ones = ref 0 in
  let cur = ref [||] in
  let reloads = ref 0 and paused = ref 0 in
  let pending = ref [] in       (* bytes still to shift, one per 8 clocks *)
  let log = Buffer.create 65536 in
  let check_after = ref false and bad_loads = ref 0 in
  let last_pin = ref 0 in
  for t = 0 to total - 1 do
    if t mod per_env = 0 then begin
      let v, nz = state_at (float t /. fclk) in
      let c = config v nz in
      Buffer.add_string log (Printf.sprintf "%d" t);
      Array.iter (fun (f, a) -> Buffer.add_string log (Printf.sprintf " %.4f %d" f a)) v;
      Buffer.add_string log (Printf.sprintf " %d\n" nz);
      if c <> !cur then begin
        incr reloads;
        if !cur = [||] || mode = `Direct then begin
          let first = !cur = [||] in
          Row.load_direct r c;
          if first then r.pes.(12).s <- 0xace1   (* LFSR seed, via the init chain on the chip *)
        end else pending := Row.chain_bytes c;
        cur := c
      end
    end;
    let si =
      match !pending with
      | [ b ] when t mod 8 = 0 -> pending := []; check_after := true; { Row.seg_idle with en = 0; cfg_in = b; cfg_strobe = 1 }
      | b :: rest when t mod 8 = 0 -> pending := rest; { Row.seg_idle with en = 0; cfg_in = b; cfg_strobe = 1 }
      | _ :: _ -> { Row.seg_idle with en = 0 }
      | [] -> Row.seg_idle
    in
    if si.en = 0 then incr paused;
    let o = Row.step r si in
    if !check_after then begin
      check_after := false;
      Array.iteri (fun i b ->
          if List.mapi (fun j _ -> r.pes.(i).Upe.c.(7 - j)) b <> b then incr bad_loads) !cur
    end;
    (* while the segment is paused for a reload the pin shows the half-shifted configuration's
       lane (Show), keeps its last value (Hold, a pin stage that latches the tap), or toggles
       (Toggle: density 1/2, the modulator's zero) *)
    let pin =
      if si.en = 1 then o.b_out
      else match hold with `Show -> o.b_out | `Hold -> !last_pin | `Toggle -> 1 - !last_pin in
    last_pin := pin;
    ones := !ones + pin;
    let x = if pin = 1 then 1. else -1. in
    y1 := !y1 +. (alpha *. (x -. !y1));
    y2 := !y2 +. (alpha *. (!y1 -. !y2));
    if t mod decim = decim - 1 && t / decim < Array.length wav then wav.(t / decim) <- 30000. *. !y2
  done;
  if Sys.getenv_opt "SYNTH_DEBUG" <> None then
    Printf.printf "debug: voice 3 NCO = %04x%04x, K = %s, paused %d, steps %d\n" r.pes.(10).s r.pes.(9).s
      (String.concat " " (List.map string_of_int (List.filteri (fun j _ -> j >= 6) (!cur).(9) @ List.filteri (fun j _ -> j >= 6) (!cur).(10))))
      !paused (total - !paused);
  write_wav out 48000 wav;
  let oc = open_out (Filename.remove_extension out ^ "-schedule.txt") in
  Buffer.output_buffer oc log; close_out oc;
  if !bad_loads > 0 then (Printf.eprintf "FAIL: %d configurations wrong after a chain reload\n" !bad_loads; exit 1);
  Printf.printf "%s: %d PE configurations differed from the intended one after a chain reload\n"
    (match mode with `Chain -> "chain" | `Direct -> "direct") !bad_loads;
  Printf.printf "%s: %d clocks (%.2f s), %d configuration changes, %d clocks paused for reloads (%.3f %%), pin density %.4f -> %s\n"
    (match mode with `Chain -> "chain" | `Direct -> "direct") total seconds !reloads !paused
    (100. *. float !paused /. float total) (float !ones /. float total) out

let main args =
  let seconds = match args with s :: _ -> float_of_string s | [] -> 4.0 in
  let dir = match args with _ :: d :: _ -> d | _ -> "out" in
  ignore (Sys.command ("mkdir --parents " ^ dir));
  let only = Sys.getenv_opt "SYNTH_ONLY" in
  let want m = match only with None -> true | Some o -> o = m in
  if want "direct" then run ~mode:`Direct ~seconds ~out:(Filename.concat dir "synth-direct.wav") ();
  if want "chain" then run ~mode:`Chain ~seconds ~out:(Filename.concat dir "synth-chain.wav") ();
  if want "hold" then run ~hold:`Hold ~mode:`Chain ~seconds ~out:(Filename.concat dir "synth-chain-hold.wav") ();
  if want "toggle" then run ~hold:`Toggle ~mode:`Chain ~seconds ~out:(Filename.concat dir "synth-chain-toggle.wav") ()
