(* Checks of the generic receive blocks and of the 10BASE-T receive path built from them. *)
open Hardcaml

let pr fmt = Printf.printf (fmt ^^ "\n%!")
let verdict ok = if ok then "PASS" else "FAIL"

(* ---------------- CRC unit ---------------- *)

let crc () =
  pr "== CRC unit (crc_unit.ml)";
  let digits = List.map Char.code [ '1'; '2'; '3'; '4'; '5'; '6'; '7'; '8'; '9' ] in
  let ok_model = List.for_all (fun (e : Crc_unit.catalogue) ->
      let c = Crc_unit.cfg_of e in
      let v = Crc_unit.crc_of_bytes c digits in
      let bits = List.concat_map (Crc_unit.bits_of_byte c) digits @ Crc_unit.crc_bits c v in
      let res = Crc_unit.run c bits in
      let ok = v = e.check_value && res = e.residue_value in
      pr "  model %-28s check %0*X (catalogue %0*X), residue %0*X (catalogue %0*X) %s" e.name ((e.w + 3) / 4) v ((e.w + 3) / 4) e.check_value
        ((e.w + 3) / 4) res ((e.w + 3) / 4) e.residue_value (if ok then "ok" else "WRONG");
      ok) Crc_unit.catalogue in
  (* RTL against the model: catalogue entries and random configurations, random bits, random restarts *)
  let sim = Cyclesim.create (Crc_unit.circuit ()) in
  let i n = Cyclesim.in_port sim n and o n = Cyclesim.out_port sim n in
  Random.init 7;
  let cfgs = List.map Crc_unit.cfg_of Crc_unit.catalogue
             @ List.init 200 (fun _ ->
                 let w = 1 + Random.int 32 in
                 let m = Crc_unit.mask_of w in
                 { Crc_unit.width = w; poly = Random.bits () land m lor 1; init = Random.bits () land m; reflected = Random.bool ();
                   xorout = Random.bits () land m; residue = Random.bits () land m }) in
  let bad = ref 0 and cycles = ref 0 in
  List.iter (fun (c : Crc_unit.cfg) ->
      Crc_unit.set_cfg sim c;
      let model = ref 0 in
      for k = 0 to 399 do
        let start = k = 0 || Random.int 60 = 0 and valid = Random.int 4 <> 0 and b = Random.int 2 in
        i "start" := Bits.of_bool start; i "valid" := Bits.of_bool valid; i "bit" := Bits.of_int ~width:1 b;
        Cyclesim.cycle sim; incr cycles;
        model := if start then c.init else if valid then Crc_unit.step c !model b else !model;
        let raw = Bits.to_int !(o "raw") in
        if raw <> !model || Bits.to_int !(o "value") <> (!model lxor c.xorout)
           || (Bits.to_int !(o "check") = 1) <> (!model = c.residue) then incr bad
      done) cfgs;
  pr "  RTL against model: %d configurations (8 catalogue + 200 random widths 1..32), %d cycles, %d mismatches" (List.length cfgs) !cycles !bad;
  let ok = ok_model && !bad = 0 in
  pr "crc: %s" (verdict ok); ok

(* ---------------- edge sampler: lockstep ---------------- *)

let random_cfg n =
  let mode = match Random.int 3 with 0 -> Edge_sampler.Manchester | 1 -> Biphase_mark | _ -> Nrz in
  { Edge_sampler.mode; holdoff = n + Random.int (6 * n); timeout = n + Random.int (20 * n); offset = n + Random.int (4 * n);
    period = n + Random.int (6 * n); invert = Random.bool () }

let sampler_lockstep ?(mutant = false) () =
  let total_bad = ref 0 and runs = ref 0 and bits = ref 0 and ends = ref 0 in
  List.iter (fun n ->
      let sim = Cyclesim.create (Edge_sampler.circuit ~n) in
      let i nm = Cyclesim.in_port sim nm and o nm = Cyclesim.out_port sim nm in
      for _ = 1 to 100 do
        incr runs;
        let cfg = random_cfg n in
        Edge_sampler.set_cfg sim cfg;
        i "clear" := Bits.vdd; Cyclesim.cycle sim; i "clear" := Bits.gnd;
        let st = Edge_sampler.init () in
        let level = ref 0 and left = ref 0 in
        let mcfg = if mutant then { cfg with holdoff = cfg.holdoff + 1 } else cfg in
        for _ = 1 to 2000 do
          let samples = List.init n (fun _ ->
              if !left = 0 then begin level := 1 - !level; left := 1 + Random.int (8 * n) end;
              decr left; !level) in
          let active = Random.int 50 <> 0 in
          let word = List.fold_left (fun (acc, k) s -> (acc lor (s lsl k), k + 1)) (0, 0) samples |> fst in
          i "samples" := Bits.of_int ~width:n word; i "active" := Bits.of_bool active;
          Cyclesim.cycle sim;
          let m = Edge_sampler.step_clock mcfg st ~active samples in
          if m.valid then incr bits;
          if m.burst_end then incr ends;
          let rv = Bits.to_int !(o "valid") = 1 in
          if rv <> m.valid || (rv && Bits.to_int !(o "bit") <> m.bit) || (Bits.to_int !(o "burst_end") = 1) <> m.burst_end
             || (Bits.to_int !(o "overrun") = 1) <> m.overrun then incr total_bad
        done
      done) [ 1; 2; 4 ];
  (!total_bad, !runs, !bits, !ends)

(* ---------------- matcher with enable: lockstep ---------------- *)

let matcher_lockstep () =
  let sim = Cyclesim.create (Matcher_en.circuit ()) in
  let i = Cyclesim.in_port sim and o = Cyclesim.out_port sim in
  let bad = ref 0 in
  for _ = 1 to 100 do
    let cfg = { Model.t = Array.init Model.n (fun _ -> Random.int 2); m = Array.init Model.n (fun _ -> Random.int 2); thr = Random.int 18 } in
    List.iter (fun b -> i "cfg_in" := Bits.of_int ~width:1 b; i "cfg_shift" := Bits.vdd; Cyclesim.cycle sim) (Model.cfg_bits cfg);
    i "cfg_shift" := Bits.gnd;
    i "clear" := Bits.vdd; Cyclesim.cycle sim; i "clear" := Bits.gnd;
    let xs = Array.make 2000 0 and m = ref 0 in
    for _ = 1 to 1500 do
      let en = Random.int 3 = 0 and x = Random.int 2 in
      i "enable" := Bits.of_bool en; i "x" := Bits.of_int ~width:1 x;
      Cyclesim.cycle sim;
      if en then begin xs.(!m) <- x; incr m end;
      (* after the step presenting x(m-1) the outputs are the model's at time m *)
      let xf k = xs.(k) in
      if Bits.to_int !(o "y") <> Model.y_at cfg xf !m || (Bits.to_int !(o "hit") = 1) <> Model.hit_at cfg xf !m then incr bad
    done
  done;
  !bad

(* ---------------- biphase mark and NRZ (UART) through the sampler ---------------- *)

(* run a continuous-time line through the sampler RTL; returns the emitted bits per burst *)
let run_sampler ~n ~clock_hz ~cfg ~(line : float -> int) ~cycles =
  let sim = Cyclesim.create (Edge_sampler.circuit ~n) in
  let i nm = Cyclesim.in_port sim nm and o nm = Cyclesim.out_port sim nm in
  Edge_sampler.set_cfg sim cfg;
  i "clear" := Bits.vdd; Cyclesim.cycle sim; i "clear" := Bits.gnd;
  i "active" := Bits.vdd;
  let bursts = ref [] and cur = ref [] and over = ref false in
  for c = 0 to cycles - 1 do
    let w = ref 0 in
    for p = 0 to n - 1 do if line ((float c +. (float p /. float n)) *. 1e9 /. clock_hz) = 1 then w := !w lor (1 lsl p) done;
    i "samples" := Bits.of_int ~width:n !w;
    Cyclesim.cycle sim;
    if Bits.to_int !(o "valid") = 1 then cur := Bits.to_int !(o "bit") :: !cur;
    if Bits.to_int !(o "overrun") = 1 then over := true;
    if Bits.to_int !(o "burst_end") = 1 then (bursts := List.rev !cur :: !bursts; cur := [])
  done;
  if !cur <> [] then bursts := List.rev !cur :: !bursts;
  (List.rev !bursts, !over)

(* biphase mark: a transition at every cell boundary, and one mid-cell for a 1 *)
let bmc_line ~bit_ns ~jitter bits t0 =
  let edges = ref [] and t = ref t0 in
  List.iter (fun b ->
      edges := (!t +. ((Random.float 2.0 -. 1.0) *. jitter)) :: !edges;
      if b = 1 then edges := (!t +. (bit_ns /. 2.0) +. ((Random.float 2.0 -. 1.0) *. jitter)) :: !edges;
      t := !t +. bit_ns) bits;
  edges := !t :: !edges;   (* closing boundary *)
  let e = Array.of_list (List.rev !edges) in
  fun time -> let k = ref 0 in Array.iter (fun x -> if x <= time then incr k) e; !k land 1

let uart_line ~bit_ns bytes t0 gap_ns =
  (* 8N1, idle high; returns the line and the end time *)
  let segs = ref [] and t = ref t0 in
  List.iter (fun b ->
      let bits = [ 0 ] @ List.init 8 (fun i -> (b lsr i) land 1) @ [ 1 ] in
      List.iter (fun v -> segs := (!t, v) :: !segs; t := !t +. bit_ns) bits;
      t := !t +. gap_ns) bytes;
  let s = Array.of_list (List.rev !segs) in
  let tend = !t in
  ((fun time ->
      if time < t0 || time >= tend then 1
      else begin
        let lo = ref 0 and hi = ref (Array.length s) in
        while !hi - !lo > 1 do let mid = (!lo + !hi) / 2 in if fst s.(mid) <= time then lo := mid else hi := mid done;
        if time >= fst s.(!lo) +. bit_ns then 1 else snd s.(!lo)
      end), tend)

(* UART framing on the recovered NRZ bit stream: start bit 0, 8 data bits LSB first, stop bit 1 *)
let uart_decode bits =
  let rec go acc = function
    | 0 :: rest when List.length rest >= 9 ->
      let d = List.filteri (fun i _ -> i < 8) rest in
      let stop = List.nth rest 8 in
      let byte = List.fold_left (fun a (i, b) -> a lor (b lsl i)) 0 (List.mapi (fun i b -> (i, b)) d) in
      if stop = 1 then go (byte :: acc) (List.filteri (fun i _ -> i > 8) rest) else List.rev acc
    | _ :: rest -> go acc rest
    | [] -> List.rev acc in
  go [] bits

let other_modes () =
  let clock_hz = 60e6 and n = 4 in
  let sub = 1e9 /. clock_hz /. float n in
  (* BMC at 300 kbit/s (USB Power Delivery's rate), with a rate offset and jitter *)
  pr "  biphase mark, 300 kbit/s, n = 4 at 60 MHz, 64 random bits per burst, 10 bursts per cell:";
  let bmc_ok = ref true in
  List.iter (fun (off_pct, jit) ->
      let good = ref 0 in
      for _ = 1 to 10 do
        let bits = List.init 64 (fun _ -> Random.int 2) in
        let bit_ns = 1e9 /. 300e3 *. (1.0 +. (off_pct /. 100.0)) in
        let line = bmc_line ~bit_ns ~jitter:jit bits 1000.0 in
        let cfg = { Edge_sampler.mode = Biphase_mark; holdoff = int_of_float (0.75 *. 1e9 /. 300e3 /. sub); timeout = 1000; offset = 0; period = 0; invert = false } in
        let bursts, over = run_sampler ~n ~clock_hz ~cfg ~line ~cycles:(int_of_float ((1000.0 +. (66.0 *. bit_ns)) *. 1e-9 *. clock_hz) + 600) in
        if bursts = [ bits ] && not over then incr good
      done;
      if off_pct = 0.0 || Float.abs off_pct <= 10.0 then (if !good < 10 then bmc_ok := false);
      pr "    rate %+5.1f %%, jitter +-%3.0f ns: %d of 10 bursts decoded exactly" off_pct jit !good)
    [ (0.0, 0.0); (10.0, 50.0); (-10.0, 50.0); (0.0, 300.0) ];
  (* UART at 1 Mbaud through NRZ mode *)
  pr "  NRZ with resynchronisation, UART 8N1 at 1 Mbaud, n = 1 at 60 MHz, 16 random bytes per cell:";
  let uart_ok = ref true in
  List.iter (fun off_pct ->
      let bytes = List.init 16 (fun _ -> Random.int 256) in
      let bit_ns = 1000.0 *. (1.0 +. (off_pct /. 100.0)) in
      let line, tend = uart_line ~bit_ns bytes 2000.0 0.0 in
      let cfg = { Edge_sampler.mode = Nrz; holdoff = 2; timeout = 1000; offset = 30; period = 60; invert = false } in
      let bursts, _ = run_sampler ~n:1 ~clock_hz ~cfg ~line ~cycles:(int_of_float ((tend +. 30000.0) *. 1e-9 *. clock_hz)) in
      let got = uart_decode (List.concat bursts) in
      let ok = got = bytes in
      if Float.abs off_pct <= 4.0 && not ok then uart_ok := false;
      pr "    baud offset %+5.1f %%: %s" off_pct (if ok then "16 of 16 bytes" else Printf.sprintf "%d bytes, wrong" (List.length got)))
    [ -6.0; -4.0; 0.0; 4.0; 6.0 ];
  !bmc_ok && !uart_ok

let sampler () =
  pr "== edge sampler (edge_sampler.ml)";
  Random.init 11;
  let bad, runs, bits, ends = sampler_lockstep () in
  pr "  RTL against model: %d random configurations over n = 1, 2, 4 (all three modes), 2000 clocks each; %d bits, %d burst ends; %d mismatching clocks"
    runs bits ends bad;
  Random.init 11;
  let mbad, _, _, _ = sampler_lockstep ~mutant:true () in
  pr "  control: model with holdoff + 1 against the same RTL: %d mismatching clocks (must be > 0)" mbad;
  Random.init 12;
  let mm = matcher_lockstep () in
  pr "  matcher with enable (matcher_en.ml) against ../systolic-matcher/model.ml in enabled steps: 100 configurations x 1500 clocks, %d mismatches" mm;
  let ok_modes = other_modes () in
  let ok = bad = 0 && mbad > 0 && mm = 0 && ok_modes in
  pr "sampler: %s" (verdict ok); ok

(* ---------------- 10BASE-T receive path ---------------- *)

type rx_result = { frames : (int list * bool * int) list; overrun : bool }

let run_rx ?d ~n ~clock_hz ?(template = Rx_path.sfd_template ()) ?(drop = fun _ -> false) ?(drop_keeps_level = false) bursts =
  let scfg = Rx_path.eth_sampler_cfg ~clock_hz ~n in
  let sim = Cyclesim.create (Rx_path.circuit ?d ~n ~scfg ()) in
  let i nm = Cyclesim.in_port sim nm and o nm = Cyclesim.out_port sim nm in
  List.iter (fun b -> i "cfg_in" := Bits.of_int ~width:1 b; i "cfg_shift" := Bits.vdd; Cyclesim.cycle sim) (Model.cfg_bits template);
  i "cfg_shift" := Bits.gnd;
  i "clear" := Bits.vdd; Cyclesim.cycle sim; i "clear" := Bits.gnd;
  let last = List.fold_left (fun a b -> Float.max a (Line.end_ns b)) 0.0 bursts in
  let cycles = int_of_float ((last +. 3000.0) *. 1e-9 *. clock_hz) in
  let samples = Line.sample ~clock_hz ~n ~cycles bursts in
  let frames = ref [] and cur = ref [] and over = ref false in
  Array.iteri (fun c (w, act) ->
      let dropped = drop c in
      let act' = act && not dropped in
      i "samples" := Bits.of_int ~width:n (if act' || (drop_keeps_level && act) then w else 0); i "active" := Bits.of_bool act';
      Cyclesim.cycle sim;
      if Bits.to_int !(o "byte_valid") = 1 then cur := Bits.to_int !(o "rx_byte") :: !cur;
      if Bits.to_int !(o "overrun") = 1 then over := true;
      if Bits.to_int !(o "frame_end") = 1 then begin
        frames := (List.rev !cur, Bits.to_int !(o "frame_ok") = 1, Bits.to_int !(o "length")) :: !frames; cur := [] end) samples;
  { frames = List.rev !frames; overrun = !over }

let random_frame ?(min = 46) ?(max = 245) () =
  let len = min + Random.int (max - min + 1) in
  let f = List.init len (fun _ -> Random.int 256) in
  f @ Eth_model.fcs_bytes f

(* k frames on one line, [gap_ns] apart (end of TP_IDL to next start) *)
let train ?(gap_ns = 10000.0) ?(ppm = 0.0) ?(jitter_ns = 0.0) ?(preamble_bits = 56) frames =
  let t = ref 1000.0 in
  List.map (fun f ->
      let b = Line.make_burst ~preamble_bits ~ppm ~jitter_ns ~start_ns:!t f in
      t := Line.end_ns b +. gap_ns; b) frames

let intact res sent = List.length (List.filter (fun (b, ok, _) -> ok && List.mem b sent) res.frames)
let false_accepts res sent = List.length (List.filter (fun (b, ok, _) -> ok && not (List.mem b sent)) res.frames)

let rx () =
  pr "== 10BASE-T receive path (rx_path.ml: edge sampler -> matcher -> packer + CRC unit)";
  Random.init 2027;
  (* the matcher's latency, found by trying delays; only one may work *)
  let frames = List.init 6 (fun _ -> random_frame ()) in
  let works = List.filter (fun d -> let r = run_rx ~d ~n:1 ~clock_hz:60e6 (train frames) in intact r frames = 6) [ 15; 16; 17; 18; 19 ] in
  pr "  delay-line length that recovers frames: %s (the design uses %d)" (String.concat "," (List.map string_of_int works)) Rx_path.delay;
  let all_ok = ref (works = [ Rx_path.delay ]) in
  let cell ~n ~clock_hz ?(ppm = [ -100.0; 100.0 ]) ?(jitter_ns = 0.0) ?(k = 10) () =
    let good = ref 0 and total = ref 0 and fa = ref 0 in
    List.iter (fun p ->
        let frames = List.init k (fun _ -> random_frame ()) in
        let r = run_rx ~n ~clock_hz (train ~ppm:p ~jitter_ns frames) in
        good := !good + intact r frames; total := !total + k; fa := !fa + false_accepts r frames) ppm;
    (!good, !total, !fa) in
  (* ppm and clock choices *)
  pr "  clock offsets: transmitter at +-ppm against the receiver clock (10 frames of 46-245 bytes each sign):";
  List.iter (fun (clock_hz, n) ->
      let row = List.map (fun p -> let g, t, _ = cell ~n ~clock_hz ~ppm:[ -.p; p ] () in (p, g, t)) [ 100.0; 1000.0; 10000.0; 60000.0; 100000.0; 150000.0 ] in
      pr "    receiver %.2f MHz, n = %d: %s" (clock_hz /. 1e6) n
        (String.concat "  " (List.map (fun (p, g, t) -> Printf.sprintf "+-%g ppm %d/%d" p g t) row));
      List.iter (fun (p, g, t) -> if p <= 10000.0 && g <> t then all_ok := false) row)
    [ (60e6, 1); (60.857143e6, 1); (60e6, 4); (60.857143e6, 4); (53.2e6, 4) ];
  (* jitter *)
  pr "  edge jitter, uniform +-j ns on every edge, +-100 ppm (20 frames per cell):";
  List.iter (fun (clock_hz, n) ->
      let row = List.map (fun j -> let g, t, fa = cell ~n ~clock_hz ~jitter_ns:j () in (j, g, t, fa)) [ 0.0; 4.0; 6.0; 8.0; 10.0; 12.0; 14.0 ] in
      pr "    %.2f MHz n = %d: %s" (clock_hz /. 1e6) n
        (String.concat " " (List.map (fun (j, g, t, _) -> Printf.sprintf "%g:%d/%d" j g t) row));
      if List.exists (fun (_, _, _, fa) -> fa > 0) row then (pr "      FALSE ACCEPT"; all_ok := false))
    [ (60e6, 1); (60.857143e6, 1); (60e6, 4); (60.857143e6, 4) ];
  (* preamble loss *)
  pr "  preamble truncated to p bits before the SFD (60 MHz, n = 1, 4 frames each):";
  let pre_row = List.map (fun p ->
      let frames = List.init 4 (fun _ -> random_frame ()) in
      let r = run_rx ~n:1 ~clock_hz:60e6 (train ~preamble_bits:p frames) in (p, intact r frames)) [ 56; 32; 16; 12; 10; 9; 8; 6; 4; 0 ] in
  pr "    %s" (String.concat "  " (List.map (fun (p, g) -> Printf.sprintf "%d:%d/4" p g) pre_row));
  if List.exists (fun (p, g) -> p >= 10 && g <> 4) pre_row then all_ok := false;
  (* runts: short frames come through with a good CRC and their length; the node drops them *)
  let runts = List.init 8 (fun k -> let f = List.init (10 + (6 * k)) (fun _ -> Random.int 256) in f @ Eth_model.fcs_bytes f) in
  let r = run_rx ~n:1 ~clock_hz:60e6 (train runts) in
  let lens = List.map (fun (_, _, l) -> l) r.frames in
  pr "  runts of 14..56 bytes with FCS: received %d, lengths %s, all CRC-good: %b (dropped by the node on length < 64)"
    (List.length r.frames) (String.concat "," (List.map string_of_int lens)) (List.for_all (fun (_, ok, _) -> ok) r.frames);
  if lens <> List.map List.length runts then all_ok := false;
  (* CRC failures: one flipped bit, and random bursts of corruption *)
  let fa = ref 0 and rejected = ref 0 and n_bad = 200 in
  let bad_frames = List.init n_bad (fun k ->
      let f = random_frame () in
      let a = Array.of_list f in
      let len = Array.length a in
      if k mod 2 = 0 then (let bitpos = Random.int (8 * len) in a.(bitpos / 8) <- a.(bitpos / 8) lxor (1 lsl (bitpos mod 8)))
      else (let s = Random.int (len - 4) in for j = s to s + 3 do a.(j) <- Random.int 256 done;
            if Array.to_list a = f then a.(s) <- a.(s) lxor 1);
      Array.to_list a) in
  List.iteri (fun k chunk ->
      ignore k;
      let r = run_rx ~n:1 ~clock_hz:60e6 (train chunk) in
      List.iter (fun (_, ok, _) -> if ok then incr fa else incr rejected) r.frames)
    (let rec split l = if l = [] then [] else List.filteri (fun i _ -> i < 20) l :: split (List.filteri (fun i _ -> i >= 20) l) in split bad_frames);
  pr "  corrupted frames (100 with one flipped bit, 100 with 4 random bytes): %d rejected, %d accepted" !rejected !fa;
  if !fa <> 0 || !rejected <> n_bad then all_ok := false;
  (* back to back *)
  pr "  frames back to back (10 frames, gap from end of TP_IDL to next preamble):";
  List.iter (fun gap ->
      let frames = List.init 10 (fun _ -> random_frame ()) in
      let r = run_rx ~n:1 ~clock_hz:60e6 (train ~gap_ns:gap ~ppm:100.0 frames) in
      let g = intact r frames in
      if gap >= 9300.0 && g <> 10 then all_ok := false;
      pr "    gap %6.0f ns: %d/10" gap g) [ 9300.0; 2000.0; 1000.0; 600.0; 400.0; 200.0 ];
  (* squelch dropout inside a frame (the hwfuzz finding for eth_rx) *)
  let drops = List.map (fun k ->
      let frames = List.init 10 (fun _ -> random_frame ()) in
      let r0 = run_rx ~n:1 ~clock_hz:60e6 ~drop:(fun c -> c mod 3000 >= 1500 && c mod 3000 < 1500 + k) (train frames) in
      let r1 = run_rx ~n:1 ~clock_hz:60e6 ~drop_keeps_level:true ~drop:(fun c -> c mod 3000 >= 1500 && c mod 3000 < 1500 + k) (train frames) in
      (k, intact r0 frames, intact r1 frames)) [ 1; 2; 3; 4; 6 ] in
  pr "  activity dropped for k clocks every 3000 clocks; comparator reads 0 / keeps the line's sign while squelched: %s"
    (String.concat "  " (List.map (fun (k, g0, g1) -> Printf.sprintf "k=%d:%d/10,%d/10" k g0 g1) drops));
  (* one clock of dropout must be harmless, and the comparator's reading while squelched must not
     matter; longer dropouts shift the anchor and lose the next mid-bit edge (see README) *)
  if List.exists (fun (k, g0, g1) -> (k <= 1 && (g0 < 10 || g1 < 10)) || g0 <> g1) drops then all_ok := false;
  (* controls: planted faults, each must lose the frames *)
  pr "  controls (each must fail to deliver the 6 frames):";
  let frames = List.init 6 (fun _ -> random_frame ()) in
  let ctl name r = let g = intact r frames in pr "    %-52s %d/6 -> %s" name g (if g < 6 then "caught" else "MISSED"); g < 6 in
  let t = Rx_path.sfd_template () in
  let bad_t = { t with Model.t = Array.mapi (fun j v -> if j = 0 then 1 - v else v) t.Model.t } in
  let c1 = ctl "delay line 17 instead of 18" (run_rx ~d:17 ~n:1 ~clock_hz:60e6 (train frames)) in
  let c2 = ctl "SFD template's newest bit flipped" (run_rx ~template:bad_t ~n:1 ~clock_hz:60e6 (train frames)) in
  let c3 = ctl "sampler holdoff 3 instead of 5 (boundaries qualify)"
      (let r = ref None in
       Rx_path.sampler_override := Some (fun c -> { c with Edge_sampler.holdoff = 3 });
       r := Some (run_rx ~n:1 ~clock_hz:60e6 (train frames)); Rx_path.sampler_override := None; Option.get !r) in
  let c4 = ctl "CRC polynomial with one bit flipped"
      (Rx_path.crc_override := Some { Rx_path.crc32 with poly = Rx_path.crc32.poly lxor 0x100 };
       let r = run_rx ~n:1 ~clock_hz:60e6 (train frames) in Rx_path.crc_override := None; r) in
  if not (c1 && c2 && c3 && c4) then all_ok := false;
  pr "rx: %s" (verdict !all_ok); !all_ok
