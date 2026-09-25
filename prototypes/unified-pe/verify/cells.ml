(* The configuration library: one configuration per cell the architecture requires, each with
   a directed test judged by an independent reference (refs.ml). Every test runs the model and
   the Hardcaml array in lockstep (all state compared every clock) and judges the model's
   outputs against the reference; a lockstep mismatch also fails the test. *)
open Spec

let pr = Printf.printf

(* ---- stimulus helpers ---- *)
let ctrl seg ~src ?(bc = false) ?(chain = false) ~run () =
  { idle with mbx_wr = true; mbx_seg = seg; mbx_sel = 2;
              mbx_byte = src lor (if bc then 8 else 0) lor (if run then 16 else 0) lor (if chain then 32 else 0) }

let cfg_seq seg (ops : op array) =
  let n = Array.length ops in
  assert (n = seg_end.(seg) - seg_start.(seg) + 1);
  List.concat
    (List.init n (fun q ->
         let b = bytes_of_op ops.(n - 1 - q) in
         List.init 8 (fun m -> { idle with cfg_wr = true; cfg_seg = seg; cfg_byte = b.(7 - m) })))

let init_seq seg (vals : int array) =
  let n = Array.length vals in
  assert (n = seg_end.(seg) - seg_start.(seg) + 1);
  List.concat
    (List.init n (fun q ->
         let v = vals.(n - 1 - q) in
         [ { idle with init_wr = true; init_seg = seg; init_byte = v lsr 8 };
           { idle with init_wr = true; init_seg = seg; init_byte = v land 0xff } ]))

let feed_seq seg v =
  [ { idle with mbx_wr = true; mbx_seg = seg; mbx_sel = 0; mbx_byte = v land 0xff };
    { idle with mbx_wr = true; mbx_seg = seg; mbx_sel = 1; mbx_byte = (v lsr 8) land 0xff } ]

let with_fixed seg d v (i : inputs) =
  let fd = Array.copy i.fixed_d and fv = Array.copy i.fixed_v in
  fd.(seg) <- d;
  fv.(seg) <- v;
  { i with fixed_d = fd; fixed_v = fv }

let idles n = List.init n (fun _ -> idle)

(* run both simulators; return the model's state after every clock and the mismatch count *)
let run stim =
  let m = Model.create () and r = Rtlsim.create () in
  let mism = ref 0 and first = ref None in
  let states =
    List.mapi
      (fun c i ->
        Model.cycle m i;
        Rtlsim.cycle r i;
        let a = Model.state m and b = Rtlsim.state r in
        if a <> b then begin
          incr mism;
          if !first = None then first := Some (c, diff a b)
        end;
        a)
      stim
  in
  (match !first with
   | Some (c, d) -> pr "    lockstep mismatch at clock %d: %s\n" c (String.concat "; " d)
   | None -> ());
  (Array.of_list states, !mism)

type verdict = { cell : string; ok : bool; note : string }

let results : verdict list ref = ref []

let report cell ~checks ~bad ~mism note =
  let ok = bad = 0 && mism = 0 && checks > 0 in
  pr "%-34s %s  %d checks, %d wrong, %d lockstep mismatches%s\n" cell (if ok then "PASS" else "FAIL") checks bad mism
    (if note = "" then "" else "  -- " ^ note);
  flush stdout;
  results := { cell; ok; note } :: !results

let rng = Random.State.make [| 2026 |]
let ri n = Random.State.int rng n

(* ---------------------------------------------------------------- sprites *)
(* Segments 2 and 3 joined (PEs 4..15): PE 4 counts pixels ({x, background} + 0x0100 on every
   valid input), PEs 5..15 are 11 sprites. Later PEs win. S and K reloaded per line. *)
let counter_op bg_unused =
  ignore bg_unused;
  { nop with xsel = 0; ysel = 0; k = 0x0100; alu = 1; swb = 1; pwb = 1; stream = true }

let sprite_op ~x ~colour = { nop with gsel = 6; pwb = 3; swb = 0; stream = true; k = (x lsl 8) lor colour }

let sprites_test () =
  let lines = 6 in
  let stim = ref [] and expect = ref [] and marks = ref [] in
  let add l = stim := !stim @ l in
  for line = 0 to lines - 1 do
    let bg = ri 256 in
    let spr =
      Array.init 11 (fun j ->
          let x = if line = 0 then 16 * j else ri 241 in
          (x, ri 256, (if line = 5 then 0xffff else ri 0x10000)))
    in
    (* line 5: all sprites solid and overlapping, to test priority *)
    let spr = if line = 5 then Array.init 11 (fun j -> (20 + (3 * j), 1 + j, 0xffff)) else spr in
    add [ ctrl 2 ~src:3 ~run:false (); ctrl 3 ~src:0 ~run:false () ];
    add (cfg_seq 2 (Array.init 4 (fun q -> if q = 0 then counter_op bg else let x, c, _ = spr.(q - 1) in sprite_op ~x ~colour:c)));
    add (cfg_seq 3 (Array.init 8 (fun q -> let x, c, _ = spr.(q + 3) in let o = sprite_op ~x ~colour:c in if q = 7 then { o with tap_p = true } else o)));
    add (init_seq 2 (Array.init 4 (fun q -> if q = 0 then (0xff lsl 8) lor bg else let _, _, b = spr.(q - 1) in b)));
    add (init_seq 3 (Array.init 8 (fun q -> let _, _, b = spr.(q + 3) in b)));
    add [ ctrl 2 ~src:3 ~run:true (); ctrl 3 ~src:0 ~run:true () ];
    marks := List.length !stim :: !marks;
    (* 256 pixels, with random one-clock gaps (stream stepping) *)
    let n = ref 0 in
    while !n < 256 do
      if ri 4 = 0 then add [ idle ] else (add [ with_fixed 2 0 true idle ]; incr n)
    done;
    add (idles 16);
    let ref_line =
      Array.init 256 (fun x ->
          let c = ref bg in
          Array.iter (fun (sx, col, bm) -> let d = x - sx in if d >= 0 && d < 16 && (bm lsr (15 - d)) land 1 = 1 then c := col) spr;
          (x, !c))
    in
    expect := !expect @ [ ref_line ]
  done;
  let states, mism = run !stim in
  let marks = Array.of_list (List.rev !marks) in
  let checks = ref 0 and bad = ref 0 in
  List.iteri
    (fun line ref_line ->
      let lo = marks.(line) and hi = if line + 1 < lines then marks.(line + 1) else Array.length states in
      let got = ref [] in
      for c = lo to hi - 1 do
        let t = states.(c).taps.(3) in
        if t.tv then got := (t.td lsr 8, t.td land 0xff) :: !got
      done;
      let got = Array.of_list (List.rev !got) in
      if Array.length got <> 256 then (incr bad; pr "    line %d: %d pixels out\n" line (Array.length got))
      else Array.iteri (fun x e -> incr checks; if got.(x) <> e then incr bad) ref_line)
    !expect;
  report "sprite (11 per line, 6 lines)" ~checks:!checks ~bad:!bad ~mism
    "per-line reload of S (init chain) and K (configuration chain); x in 0..240 (the window wraps mod 256)"

(* ---------------------------------------------------------------- tiles *)
(* A one-colour tile layer with mid-line reload. The renderer is PE 2, alone in segment 1 with a
   pass-through PE 3, so the init chain reaches only it. It shows S[15] (g = S[15] ^ lane, lane
   = broadcast 0) and shifts left once per pixel; every 16 pixels the thread writes the next
   tile row's two bytes into the init chain in the gaps between pixels (one pixel every 3
   clocks). Counter in PE 0 (segment 0, fixed port), PE 1 passes. *)
let tiles_test () =
  let bg = 0x11 and tile_col = 0xee in
  let ntiles = 16 in
  let tiles = Array.init ntiles (fun _ -> ri 0x10000) in
  let pass = { nop with pwb = 0; stream = true } in
  let renderer =
    { nop with xsel = 2; sinsel = 1; lane_bc = true; swb = 2; gsel = 3; pwb = 3; stream = true; k = tile_col }
  in
  let stim = ref [] in
  let add l = stim := !stim @ l in
  add [ ctrl 0 ~src:3 ~run:false (); ctrl 1 ~src:0 ~bc:false ~run:false () ];
  add (cfg_seq 0 [| counter_op 0; pass |]);
  add (cfg_seq 1 [| renderer; { pass with tap_p = true } |]);
  add (init_seq 0 [| (0xff lsl 8) lor bg; 0 |]);
  add (init_seq 1 [| 0; 0 |]);
  add [ ctrl 0 ~src:3 ~run:true (); ctrl 1 ~src:0 ~run:true () ];
  let start = List.length !stim in
  (* pixel p enters PE 0 at clock 3p (relative), reaches PE 2 at 3p + 2; tile t's bytes are
     written at 48t - 3 and 48t - 2, the two gap clocks before pixel 16t steps at 48t + 2...
     we shift by 3 so the first tile's writes land at relative clocks 0 and 1. *)
  let total = (3 * 16 * ntiles) + 3 + 20 in
  let seq =
    Array.init total (fun c ->
        let i = if c >= 3 && (c - 3) mod 3 = 0 && (c - 3) / 3 < 16 * ntiles then with_fixed 0 0 true idle else idle in
        (* pixel p is at PE 2 at clock 3 + 3p + 2; gaps before pixel 16t are clocks 48t + 3 and 48t + 4 *)
        let rel = c - 3 in
        if rel >= 0 && rel mod 48 = 0 && rel / 48 < ntiles then
          { i with init_wr = true; init_seg = 1; init_byte = tiles.(rel / 48) lsr 8 }
        else if rel >= 1 && (rel - 1) mod 48 = 0 && (rel - 1) / 48 < ntiles then
          { i with init_wr = true; init_seg = 1; init_byte = tiles.((rel - 1) / 48) land 0xff }
        else i)
  in
  (* the writes at rel 48t, 48t+1 must not coincide with PE 2's steps (rel 3p + 2) *)
  add (Array.to_list seq);
  let states, mism = run !stim in
  let got = ref [] in
  for c = start to Array.length states - 1 do
    let t = states.(c).taps.(1) in
    if t.tv then got := (t.td lsr 8, t.td land 0xff) :: !got
  done;
  let got = Array.of_list (List.rev !got) in
  let checks = ref 0 and bad = ref 0 in
  if Array.length got <> 16 * ntiles then (incr bad; pr "    %d pixels out\n" (Array.length got))
  else
    Array.iteri
      (fun p (x, col) ->
        incr checks;
        let b = (tiles.(p / 16) lsr (15 - (p mod 16))) land 1 in
        let e = if b = 1 then tile_col else bg in
        if x <> p land 0xff || col <> e then incr bad)
      got;
  report "tile layer, mid-line reload (16 tiles)" ~checks:!checks ~bad:!bad ~mism
    "needs the renderer alone in a 2-PE segment and gaps between pixels for the init writes"

(* ---------------------------------------------------------------- FIR on 1-bit samples *)
(* Transposed form in segment 3 (8 taps): P <- A + (g ? -K : K), g = broadcast sample bit
   (bit 1 means -1). Coefficients loaded in reverse. The sample bit goes out through the
   mailbox's control byte, one per clock. *)
let fir_test () =
  let h = Array.init 8 (fun _ -> ri 2001 - 1000) in
  let bits = Array.init 400 (fun _ -> ri 2) in
  let tap i = { nop with xsel = 1; ysel = 0; ymod = 2; gsel = 2; lane_bc = true; alu = 0; pwb = 1; k = h.(7 - i) land 0xffff; tap_p = i = 7 } in
  let stim = ref [] in
  let add l = stim := !stim @ l in
  add [ ctrl 3 ~src:4 ~run:false () ];
  add (cfg_seq 3 (Array.init 8 tap));
  (* bit m is visible during clock start + m *)
  let start = List.length !stim + 1 in
  add (Array.to_list (Array.map (fun b -> ctrl 3 ~src:4 ~bc:(b = 1) ~run:true ()) bits));
  add [ ctrl 3 ~src:4 ~run:false () ];
  let states, mism = run !stim in
  let s = Array.map (fun b -> 1 - (2 * b)) bits in
  let checks = ref 0 and bad = ref 0 in
  for m = 0 to Array.length bits - 1 do
    incr checks;
    (* samples before the first count as zero (the partial sums start from P = 0) *)
    let e = Refs.clamp16 (Refs.convolve h s m) in
    let got = Refs.to_signed states.(start + m).taps.(3).td in
    if got <> e then incr bad
  done;
  report "FIR, 8 taps, 1-bit samples" ~checks:!checks ~bad:!bad ~mism "coefficients within +-1000, no saturation reached"

(* ---------------------------------------------------------------- CIC *)
(* Order 2, decimation 4, in segment 3: integrator, integrator, phase counter (K = 0xC000, lane
   out = carry: the carry is 0 once in 4 steps), decimator (deletes when the left carry is 1),
   comb, comb, then two pass PEs. Samples arrive on the fixed port with random gaps. *)
let cic_test () =
  let integ = { nop with xsel = 0; ysel = 1; alu = 1; swb = 1; pwb = 1; stream = true } in
  let counter = { nop with xsel = 0; ysel = 0; k = 0xc000; alu = 1; swb = 1; pwb = 0; lout = 2; stream = true } in
  let decim = { nop with gsel = 2; del = true; pwb = 0; stream = true } in
  let comb = { nop with xsel = 1; ysel = 2; ymod = 3; alu = 1; swb = 2; pwb = 1; stream = true } in
  let pass = { nop with pwb = 0; stream = true } in
  let ops = [| integ; integ; counter; decim; comb; comb; pass; { pass with tap_p = true } |] in
  let n = 400 in
  let x = Array.init n (fun _ -> ri 20001 - 10000) in
  let stim = ref [] in
  let add l = stim := !stim @ l in
  add [ ctrl 3 ~src:3 ~run:false () ];
  add (cfg_seq 3 ops);
  add [ ctrl 3 ~src:3 ~run:true () ];
  let start = List.length !stim in
  Array.iter (fun v -> if ri 3 = 0 then add [ idle ]; add [ with_fixed 3 (v land 0xffff) true idle ]) x;
  add (idles 20);
  let states, mism = run !stim in
  let got = ref [] in
  for c = start to Array.length states - 1 do
    let t = states.(c).taps.(3) in
    if t.tv then got := Refs.to_signed t.td :: !got
  done;
  let got = Array.of_list (List.rev !got) in
  let h = Refs.poly_mul (Refs.boxcar 4) (Refs.boxcar 4) in
  let expect = Array.init (n / 4) (fun j -> Refs.to_signed (Refs.convolve h x (4 * j))) in
  let checks = ref 0 and bad = ref 0 in
  if Array.length got <> Array.length expect then (incr bad; pr "    %d outputs, expected %d\n" (Array.length got) (Array.length expect))
  else Array.iteri (fun j e -> incr checks; if got.(j) <> e then incr bad) expect;
  report "CIC, order 2, R = 4 (8 PEs)" ~checks:!checks ~bad:!bad ~mism
    "inputs up to +-10,000 so the integrators wrap; output = boxcar4^2 at n = 4j, mod 2^16"

(* ---------------------------------------------------------------- NCOs and mixer *)
(* PE 0 (segment 0): 16-bit NCO. PEs 2-3 (segment 1): 32-bit NCO, low word then high word with
   the carry on the lane; samples from the fixed port pass through them to PE 4 (segment 2,
   joined), the mixer: P <- 0 + (g ? -A : A), g = the high word's MSB on the lane. *)
let nco_mixer_test () =
  let k16 = 0x1234 + ri 0x1000 and k32 = 0x01234567 + ri 0x100000 in
  let klo = k32 land 0xffff and khi = k32 lsr 16 in
  let nco16 = { nop with xsel = 0; ysel = 0; k = k16; alu = 1; swb = 1; lout = 1 } in
  let lo = { nop with xsel = 0; ysel = 0; k = klo; alu = 1; swb = 1; pwb = 0; lout = 2 } in
  let hi = { nop with xsel = 0; ysel = 0; k = khi; alu = 1; swb = 1; pwb = 0; lout = 1; cin_lane = true } in
  let mixer = { nop with xsel = 0; ysel = 1; ymod = 2; gsel = 2; alu = 0; swb = 0; pwb = 1 } in
  let pass = { nop with pwb = 0 } in
  let stim = ref [] in
  let add l = stim := !stim @ l in
  add [ ctrl 0 ~src:4 ~run:false (); ctrl 1 ~src:3 ~run:false (); ctrl 2 ~src:0 ~run:false () ];
  add (cfg_seq 0 [| nco16; pass |]);
  add (cfg_seq 1 [| lo; hi |]);
  add (cfg_seq 2 [| mixer; pass; pass; { pass with tap_p = true } |]);
  (* the high word starts at -K_hi, cancelling its one-step lead (see README) *)
  add (init_seq 1 [| 0; (0x10000 - khi) land 0xffff |]);
  add [ ctrl 0 ~src:4 ~run:true (); ctrl 1 ~src:3 ~run:true (); ctrl 2 ~src:0 ~run:true () ];
  (* the ctrl writes land on consecutive clocks; step 1 of segments 0 and 1 is the clock after
     each write *)
  let start = List.length !stim in
  let n = 3000 in
  let xs = Array.init n (fun _ -> ri 4001 - 2000) in
  add (Array.to_list (Array.map (fun v -> with_fixed 1 (v land 0xffff) true idle) xs));
  let states, mism = run !stim in
  let checks = ref 0 and bad = ref 0 in
  (* segment 0 started one clock before segment 1 (its ctrl write was one clock earlier) *)
  let t0_16 = start - 2 and t0_32 = start - 1 in
  for t = 1 to n - 10 do
    incr checks;
    let s16 = states.(t0_16 + t - 1).pes.(0).s in
    if s16 <> (t * k16) land 0xffff then incr bad;
    incr checks;
    let lo_t = states.(t0_32 + t - 1).pes.(2).s and hi_t1 = states.(t0_32 + t).pes.(3).s in
    if (hi_t1 lsl 16) lor lo_t <> (t * k32) land 0xffffffff then incr bad
  done;
  (* mixer: sample fed at clock c (relative to start) is multiplied by the sign of phase
     (c + 1 + 1) * K: it passes PE 2 at c, PE 3 at c + 1, and meets the lane at PE 4 at c + 2 *)
  let checks_m = ref 0 and bad_m = ref 0 in
  for c = 0 to n - 10 do
    incr checks_m;
    (* the lane at clock start + c + 2 is the high word's MSB after its step at clock
       start + c + 1, which is step c + 3 of segment 1; high(t) = upper16((t - 1) K) *)
    let phase = ((c + 2) * k32) land 0xffffffff in
    let e = if phase lsr 31 = 1 then - xs.(c) else xs.(c) in
    let got = Refs.to_signed states.(start + c + 2).pes.(4).p in
    if got <> e then incr bad_m
  done;
  report "NCO 16-bit and 32-bit (PE pair)" ~checks:!checks ~bad:!bad ~mism
    (Printf.sprintf "K16 = %#x, K32 = %#x; high word lags one step, cancelled by S = -K_hi at start" k16 k32);
  report "mixer / carrier wipe-off" ~checks:!checks_m ~bad:!bad_m ~mism "sample c (fixed port, clock c) leaves PE 4 at c + 2, multiplied by sign(phase (c + 2) K)"

(* ---------------------------------------------------------------- GPS correlator *)
(* 12 correlators in segments 2+3 joined: S <- S + (g ? -A : A), g = the broadcast code chip,
   P <- A, so PE 4 + j integrates code offset j. Samples: the C/A code delayed by tau chips,
   +-3 plus noise, on segment 2's fixed port; the chip through the mailbox control byte. *)
let gps_test () =
  let catalogue_ok = List.for_all (fun (prn, oct) -> Refs.first10_octal (Refs.ca_code prn) = oct) [ (1, 1440); (2, 1620); (3, 1710); (4, 1744) ] in
  let prn = 3 in
  let code = Refs.ca_code prn in
  let tau = 5 in
  let corr i = { nop with xsel = 0; ysel = 1; ymod = 2; gsel = 2; lane_bc = true; alu = 0; swb = 1; pwb = 0; tap_p = i = 7 } in
  let stim = ref [] in
  let add l = stim := !stim @ l in
  add [ ctrl 2 ~src:3 ~run:false (); ctrl 3 ~src:0 ~run:false () ];
  add (cfg_seq 2 (Array.init 4 corr));
  add (cfg_seq 3 (Array.init 8 (fun i -> corr (i + 4))));
  add (init_seq 2 (Array.make 4 0));
  add (init_seq 3 (Array.make 8 0));
  (* segment 3 takes segment 2's broadcast (control bit 5, proposed) *)
  add [ ctrl 3 ~src:0 ~chain:true ~run:true () ];
  let n = 1023 in
  (* x_m: the sample on the fixed port at clock m; received signal = code delayed by tau *)
  let x = Array.init n (fun m -> let c = code.((m + tau) mod 1023) in (3 * (1 - (2 * c))) + (ri 7 - 3)) in
  (* segment 2's ctrl carries the chip: chip m visible at clock start + m *)
  let _start = List.length !stim + 1 in
  add
    (Array.to_list
       (Array.init n (fun m ->
            let i = ctrl 2 ~src:3 ~bc:(code.(m) = 1) ~run:true () in
            (* x_{m-1} presented at clock start + m - 1 *)
            if m >= 1 then with_fixed 2 (x.(m - 1) land 0xffff) true i else i)));
  add [ with_fixed 2 (x.(n - 1) land 0xffff) true (ctrl 2 ~src:3 ~run:false ()) ];
  let states, mism = run !stim in
  (* after clock start + n - 1, the last with a chip; segment 3 keeps running after it *)
  let final = states.(_start + n - 1) in
  let checks = ref 0 and bad = ref 0 in
  let got = Array.init 12 (fun j -> Refs.to_signed final.pes.(4 + j).s) in
  (* x_k is on the fixed port at clock start + k; PE 4 + j sees it at start + k + j, with
     chip k + j *)
  let expect =
    Array.init 12 (fun j ->
        let s = ref 0 in
        for m = 0 to n - 1 do
          let chip_clock = m + j in
          if chip_clock < n then s := !s + (x.(m) * (1 - (2 * code.(chip_clock))))
        done;
        Refs.clamp16 !s)
  in
  Array.iteri (fun j e -> incr checks; if got.(j) <> e then incr bad) expect;
  let peak = ref 0 in
  Array.iteri (fun j v -> if v > got.(!peak) then peak := j) got;
  if not catalogue_ok then incr bad;
  incr checks;
  if !peak <> tau || got.(tau) < 2500 then incr bad;
  report "GPS C/A correlator (12 offsets, 2 segments)" ~checks:!checks ~bad:!bad ~mism
    (Printf.sprintf "PRN %d delayed by %d chips, first-10-chip catalogue check (PRN 1-4) %s; peak at PE offset %d (sums %s)" prn tau
       (if catalogue_ok then "ok" else "FAILED") !peak
       (String.concat " " (Array.to_list (Array.map string_of_int got))))

(* ---------------------------------------------------------------- sync words *)
(* (a) exact 16-bit match in segment 0: PE 0 deserialises the broadcast bit (S <- S << 1 | lane),
   PE 1 XORs with the sync word and sets F on zero. (b) soft +-1 correlation of an 8-bit word in
   segment 3, transposed: PE i holds template bit i in S[15]; g = S[15] ^ bit; P <- A + (g ? -1 : 1). *)
let sync_test () =
  let sync16 = 0x1acf and sync8 = 0x7e in
  let n = 600 in
  let bits = Array.init n (fun _ -> ri 2) in
  let put w width at = for i = 0 to width - 1 do bits.(at + i) <- (w lsr (width - 1 - i)) land 1 done in
  List.iter (fun at -> put sync16 16 at) [ 50; 200; 420 ];
  List.iter (fun at -> put sync8 8 at) [ 100; 300 ];
  bits.(305) <- 1 - bits.(305) (* one flipped bit *);
  let deser = { nop with xsel = 2; sinsel = 1; lane_bc = true; ysel = 0; k = 0; alu = 6; swb = 1; pwb = 1 } in
  let cmp = { nop with xsel = 1; ysel = 0; k = sync16; alu = 4; fwb = 2; pwb = 1; tap_p = true } in
  let soft = { nop with xsel = 1; ysel = 3; ymod = 2; gsel = 3; lane_bc = true; alu = 0; pwb = 1 } in
  let stim = ref [] in
  let add l = stim := !stim @ l in
  add [ ctrl 0 ~src:4 ~run:false (); ctrl 3 ~src:4 ~run:false () ];
  add (cfg_seq 0 [| deser; cmp |]);
  add (cfg_seq 3 (Array.init 8 (fun i -> if i = 7 then { soft with tap_p = true } else soft)));
  add (init_seq 3 (Array.init 8 (fun i -> ((sync8 lsr (7 - i)) land 1) lsl 15)));
  let start = List.length !stim + 1 in
  (* both segments get the same bit per clock, alternating... one mailbox write per clock, so
     the two correlators run in two passes over the same bits *)
  add (Array.to_list (Array.map (fun b -> ctrl 0 ~src:4 ~bc:(b = 1) ~run:true ()) bits));
  add [ ctrl 0 ~src:4 ~run:false () ];
  let start2 = List.length !stim + 1 in
  add (Array.to_list (Array.map (fun b -> ctrl 3 ~src:4 ~bc:(b = 1) ~run:true ()) bits));
  add [ ctrl 3 ~src:4 ~run:false () ];
  let states, mism = run !stim in
  let checks = ref 0 and bad = ref 0 in
  (* (a): bit m visible at start + m; PE 0's S after that clock ends with bit m; PE 1's F after
     start + m + 1 is the match of the 16 bits ending at m *)
  let found = ref [] in
  for m = 15 to n - 2 do
    incr checks;
    let w = ref 0 in
    for i = m - 15 to m do w := (!w lsl 1) lor bits.(i) done;
    let e = !w = sync16 in
    let got = states.(start + m + 1).taps.(0).tf in
    if got then found := (m - 15) :: !found;
    if got <> e then incr bad
  done;
  (* (b): score after clock start2 + m = sum_i (t_i = b_{m-7+i} ? 1 : -1) *)
  let hits = ref [] in
  for m = 7 to n - 1 do
    incr checks;
    let sc = ref 0 in
    for i = 0 to 7 do sc := !sc + if (sync8 lsr (7 - i)) land 1 = bits.(m - 7 + i) then 1 else -1 done;
    let got = Refs.to_signed states.(start2 + m).taps.(3).td in
    if got >= 6 then hits := (m - 7, got) :: !hits;
    if got <> !sc then incr bad
  done;
  report "sync word: exact 16-bit match (2 PEs)" ~checks:!checks ~bad:!bad ~mism
    (Printf.sprintf "found at %s; soft 8-bit score >= 6 at %s"
       (String.concat "," (List.rev_map string_of_int !found))
       (String.concat "," (List.rev_map (fun (a, s) -> Printf.sprintf "%d(%d)" a s) !hits)))

(* ---------------------------------------------------------------- min-plus *)
(* Relaxation along a path v0 -> v1 -> v2 -> v3 in segment 3: per edge two PEs, P <- A + w
   (saturating) and S <- min(S, A), P <- the new minimum. Candidate distances of v0 stream in
   on the fixed port; 0x7fff is infinity. *)
let minplus_test () =
  let w = [| ri 3000; ri 3000; 20000 + ri 5000; ri 3000 |] in
  let add_op k = { nop with xsel = 1; ysel = 0; k; alu = 0; pwb = 1; stream = true } in
  let min_op = { nop with xsel = 0; ysel = 1; alu = 3; swb = 1; pwb = 1; stream = true } in
  let ops = Array.init 8 (fun i -> if i mod 2 = 0 then add_op w.(i / 2) else min_op) in
  let ops = Array.mapi (fun i o -> if i = 7 then { o with tap_p = true } else o) ops in
  let stim = ref [] in
  let add l = stim := !stim @ l in
  add [ ctrl 3 ~src:3 ~run:false () ];
  add (cfg_seq 3 ops);
  add (init_seq 3 (Array.make 8 0x7fff));
  add [ ctrl 3 ~src:3 ~run:true () ];
  let cands = Array.init 30 (fun _ -> 2000 + ri 20000) in
  Array.iter (fun v -> add [ with_fixed 3 v true idle ]; if ri 2 = 0 then add [ idle ]) cands;
  add (idles 12);
  let states, mism = run !stim in
  let final = states.(Array.length states - 1) in
  (* reference: d_j = min over candidates of (c + w_0 + ... + w_j), capped at infinity, with the
     cap applied after each edge as the saturating adder does *)
  let checks = ref 0 and bad = ref 0 in
  let d = ref (Array.fold_left min max_int cands) in
  for j = 0 to 3 do
    d := min 0x7fff (!d + w.(j));
    incr checks;
    if final.pes.(8 + (2 * j) + 1).s <> !d then incr bad
  done;
  report "min-plus relaxation (2 PEs per edge)" ~checks:!checks ~bad:!bad ~mism
    (Printf.sprintf "weights %d %d %d %d; one PE would need a fused add-then-min" w.(0) w.(1) w.(2) w.(3))

(* ---------------------------------------------------------------- sorting *)
(* Systolic insertion sort in segment 3: S <- max(S, A), P <- the loser; S starts at -32768.
   20 values stream in (8 stay, sorted, 12 plus the 8 sentinels leave through the tap). *)
let sort_test () =
  let op = { nop with xsel = 0; ysel = 1; alu = 2; swb = 1; pwb = 2; stream = true } in
  let stim = ref [] in
  let add l = stim := !stim @ l in
  add [ ctrl 3 ~src:3 ~run:false () ];
  add (cfg_seq 3 (Array.init 8 (fun i -> if i = 7 then { op with tap_p = true } else op)));
  add (init_seq 3 (Array.make 8 0x8000));
  add [ ctrl 3 ~src:3 ~run:true () ];
  let start = List.length !stim in
  let vals = Array.init 20 (fun _ -> ri 0x10000) in
  Array.iter (fun v -> add [ with_fixed 3 v true idle ]; if ri 3 = 0 then add [ idle ]) vals;
  add (idles 12);
  let states, mism = run !stim in
  let final = states.(Array.length states - 1) in
  let sorted = List.sort (fun a b -> compare b a) (Array.to_list (Array.map Refs.to_signed vals)) in
  let top = List.filteri (fun i _ -> i < 8) sorted in
  let checks = ref 0 and bad = ref 0 in
  List.iteri (fun j e -> incr checks; if Refs.to_signed final.pes.(8 + j).s <> e then incr bad) top;
  let out = ref [] in
  for c = start to Array.length states - 1 do
    let t = states.(c).taps.(3) in
    if t.tv then out := Refs.to_signed t.td :: !out
  done;
  let rest = List.filteri (fun i _ -> i >= 8) sorted @ List.init 8 (fun _ -> -0x8000) in
  incr checks;
  if List.sort compare !out <> List.sort compare rest then incr bad;
  report "sorting (insertion, 8 PEs, 20 values)" ~checks:!checks ~bad:!bad ~mism "S holds the top 8 in order; the rest leave through the tap"

(* ---------------------------------------------------------------- CRCs *)
let bits_of_msg (c : Refs.crc) msg =
  List.concat_map
    (fun ch ->
      let b = Char.code ch in
      List.init 8 (fun i -> if c.refin then (b lsr i) land 1 else (b lsr (7 - i)) land 1))
    (List.of_seq (String.to_seq msg))

let finish (c : Refs.crc) reg = (if c.refout then Refs.reflect reg c.width else reg) lxor c.xorout

(* CRC-16 in one PE (PE 0), bits through the feed register (two mailbox writes per bit, so
   stream stepping sees a valid bit every other clock); F <- (S' = 0). *)
let crc16_run (c : Refs.crc) msg =
  let op = { nop with xsel = 2; sinsel = 0; ysel = 0; ymod = 1; gsel = 4; alu = 4; swb = 1; fwb = 2; stream = true;
                      k = c.poly land 0xfffe; tap_p = false } in
  let stim = ref [] in
  let add l = stim := !stim @ l in
  add [ ctrl 0 ~src:2 ~run:false () ];
  add (cfg_seq 0 [| op; nop |]);
  add (init_seq 0 [| c.init; 0 |]);
  add [ ctrl 0 ~src:2 ~run:true () ];
  List.iter (fun b -> add (feed_seq 0 b)) (bits_of_msg c msg);
  add (idles 3);
  let states, mism = run !stim in
  let final = states.(Array.length states - 1) in
  (finish c final.pes.(0).s, final.pes.(0).f, mism)

(* CRC-32 on a PE pair (PEs 2, 3). Low: g = cb_in ^ A[0] (pairlo), X = S << 1 with sin = g,
   Y = K_lo gated. High: g = g_in, X = S << 1 with sin = s15_in, Y = K_hi gated.
   [mode]: `Continuous (bits every clock, both PEs step every clock the segment runs: the
   design in the architecture note); `Follow (bits with gaps, low steps on valid, high
   follows its left neighbour: the proposed follow bit); `Stream_both (bits with gaps, both
   in stream mode: expected to fail, it shows why follow is needed). *)
let crc32_run ?(gaps = true) mode (c : Refs.crc) msg =
  let kl = c.poly land 0xfffe and kh = c.poly lsr 16 in
  let lo = { nop with xsel = 2; sinsel = 0; ysel = 0; ymod = 1; gsel = 4; pairlo = true; alu = 4; swb = 1; k = kl; pwb = 0 } in
  let hi = { nop with xsel = 2; sinsel = 2; ysel = 0; ymod = 1; gsel = 7; alu = 4; swb = 1; k = kh; pwb = 0 } in
  let lo, hi =
    match mode with
    | `Continuous -> (lo, hi)
    | `Follow -> ({ lo with stream = true }, { hi with follow = true })
    | `Stream_both -> ({ lo with stream = true }, { hi with stream = true })
  in
  let stim = ref [] in
  let add l = stim := !stim @ l in
  add [ ctrl 1 ~src:3 ~run:false () ];
  add (cfg_seq 1 [| lo; hi |]);
  add (init_seq 1 [| c.init land 0xffff; c.init lsr 16 |]);
  let bits = bits_of_msg c msg in
  (match mode with
   | `Continuous ->
     (* run for exactly one clock per bit: run set on the clock before the first bit *)
     add [ ctrl 1 ~src:3 ~run:true () ];
     List.iteri
       (fun i b ->
         let r = with_fixed 1 b true idle in
         add [ (if i = List.length bits - 1 then { (ctrl 1 ~src:3 ~run:false ()) with fixed_d = r.fixed_d; fixed_v = r.fixed_v } else r) ])
       bits
   | _ ->
     add [ ctrl 1 ~src:3 ~run:true () ];
     List.iter (fun b -> if gaps && ri 2 = 0 then add [ idle ]; add [ with_fixed 1 b true idle ]) bits;
     add (idles 3));
  let states, mism = run !stim in
  let final = states.(Array.length states - 1) in
  let reg = (final.pes.(3).s lsl 16) lor final.pes.(2).s in
  (finish c reg, mism)

let crc_tests () =
  let msgs = "123456789" :: List.init 20 (fun _ -> String.init (1 + ri 40) (fun _ -> Char.chr (ri 256))) in
  List.iter
    (fun (c : Refs.crc) ->
      let checks = ref 0 and bad = ref 0 and mism = ref 0 in
      incr checks;
      if Refs.crc c "123456789" <> c.check then incr bad (* the reference against the catalogue *);
      if c.width = 16 then begin
        List.iter
          (fun m ->
            let got, _, mm = crc16_run c m in
            mism := !mism + mm;
            incr checks;
            if got <> Refs.crc c m then incr bad)
          msgs;
        (* residue: for the non-reflected, zero-xorout CRCs, message || crc leaves S = 0, F = 1 *)
        if (not c.refin) && c.xorout = 0 then begin
          let m = "123456789" in
          let cr = Refs.crc c m in
          let m2 = m ^ String.init 2 (fun i -> Char.chr ((cr lsr (8 * (1 - i))) land 0xff)) in
          let _, f1, mm1 = crc16_run c m and s2, f2, mm2 = crc16_run c m2 in
          mism := !mism + mm1 + mm2;
          checks := !checks + 2;
          if f1 || not f2 || s2 <> 0 then incr bad
        end;
        report (c.name ^ " (1 PE)") ~checks:!checks ~bad:!bad ~mism:!mism
          (Printf.sprintf "catalogue check %#x; 20 random messages; bits via the mailbox feed" c.check)
      end
      else begin
        List.iter
          (fun m ->
            List.iter
              (fun mode ->
                let got, mm = crc32_run mode c m in
                mism := !mism + mm;
                incr checks;
                if got <> Refs.crc c m then incr bad)
              [ `Continuous; `Follow ])
          msgs;
        report (c.name ^ " (PE pair)") ~checks:!checks ~bad:!bad ~mism:!mism
          "bits every clock (as designed) and with gaps (follow bit); 21 messages each"
      end)
    Refs.catalogue;
  (* control: the pair in plain stream mode with gaps must fail *)
  let c = List.find (fun (c : Refs.crc) -> c.name = "CRC-32/ISO-HDLC") Refs.catalogue in
  let wrong = List.length (List.filter (fun m -> fst (crc32_run `Stream_both c m) <> Refs.crc c m) msgs) in
  pr "%-34s %s  %d of %d messages wrong (expected: most, since the high PE steps a clock late)\n"
    "CRC-32 pair, stream mode, no follow" (if wrong > 0 then "EXPECTED FAIL" else "UNEXPECTED PASS") wrong (List.length msgs);
  let wrong_ng = List.length (List.filter (fun m -> fst (crc32_run ~gaps:false `Stream_both c m) <> Refs.crc c m) msgs) in
  pr "%-34s %d of %d messages wrong\n" "  same, bits every clock" wrong_ng (List.length msgs)

let run_all ?(keep_bug = false) () =
  if not keep_bug then (Upe_rtl.bug := ""; Model.bug := "");
  sprites_test ();
  tiles_test ();
  fir_test ();
  cic_test ();
  nco_mixer_test ();
  gps_test ();
  sync_test ();
  minplus_test ();
  sort_test ();
  crc_tests ();
  let v = List.rev !results in
  pr "%d of %d cells pass\n" (List.length (List.filter (fun r -> r.ok) v)) (List.length v)
