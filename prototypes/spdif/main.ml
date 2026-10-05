(* S/PDIF on the generic blocks: test and demo driver. One subcommand per result file; README
   lists them. Every run prints its own parameters so the result files are self-describing. *)

open Printf

let pr fmt = ksprintf (fun s -> print_endline s; flush stdout) fmt
let fails = ref 0
let check name ok = if not ok then begin incr fails; pr "FAIL: %s" name end

let cs_pair rate = (Iec60958.channel_status (Iec60958.cd_params rate) ~channel:0, Iec60958.channel_status (Iec60958.cd_params rate) ~channel:1)

let pre_of_oracle = function Oracle.Z -> Iec60958.B | X -> M | Y -> W

(* ---- comparing a decoded stream with what was sent ---- *)

type cmp = { offset : int; compared : int; mismatched : int; first_bad : int; resyncs : int; skipped : int }

(* [got] is a list of (preamble, slots); find where it starts in [sent], then compare item by
   item. After a mismatch, look for the next four items a little further on or back in [sent]
   (a receiver that dropped or invented subframes and then resynchronised); [skipped] counts the
   sent subframes jumped over that way. *)
let compare_stream (sent : Iec60958.subframe array) (got : (Iec60958.preamble * int) array) =
  let n = Array.length sent and m = Array.length got in
  let eq j k = j >= 0 && j < n && k < m && (let (p, s) = got.(k) in sent.(j).pre = p && sent.(j).slots land lnot 15 = s land lnot 15) in
  let run4 j k = let r = ref true in for d = 0 to min 3 (m - 1 - k) do if not (eq (j + d) (k + d)) then r := false done; !r in
  let off = ref (-1) in
  (try for j = 0 to n - 1 do if !off < 0 && run4 j 0 then (off := j; raise Exit) done with Exit -> ());
  if m = 0 || !off < 0 then { offset = -1; compared = 0; mismatched = m; first_bad = 0; resyncs = 0; skipped = 0 }
  else begin
    let bad = ref 0 and first = ref (-1) and c = ref 0 and j = ref !off and rs = ref 0 and sk = ref 0 in
    for k = 0 to m - 1 do
      if !j < n then begin
        incr c;
        if eq !j k then incr j
        else begin
          incr bad; if !first < 0 then first := k;
          (* the next items: same place, or up to 4 sent subframes further, or 2 back *)
          let cand = List.find_opt (fun d -> run4 (!j + d) (k + 1)) [ 1; 2; 3; 4; 5; 0; -1 ] in
          match cand with
          | Some d -> if d <> 1 then (incr rs; sk := !sk + (d - 1)); j := !j + d
          | None -> incr j
        end
      end
    done;
    { offset = !off; compared = !c; mismatched = !bad; first_bad = !first; resyncs = !rs; skipped = !sk }
  end

let rx_got (d : Rx.decoded) =
  Array.of_list (List.map (fun (s : Rx.rx_subframe) -> ((match s.kind with KB -> Iec60958.B | KM -> M | KW -> W), s.slots)) d.subframes)

let oracle_got (o : Oracle.result) = Array.of_list (List.map (fun (s : Oracle.sub) -> (pre_of_oracle s.pre, Oracle.slots s)) o.subs)

(* ---- a foreign source: the reference encoder at an exact rate, with offset and jitter ---- *)

type src_cfg = { rate : Iec60958.rate; ppm : float; t0 : float; jit : Line.jitter; frames : int; frame0 : int; seed : int }

let random_stream ~seed ~rate ~frames ~frame0 =
  let st = Random.State.make [| seed |] in
  let smp = Array.init frames (fun _ -> (Random.State.int st 0x1000000, Random.State.int st 0x1000000)) in
  let vu = Array.init (frames * 4) (fun _ -> if Random.State.int st 20 = 0 then 1 else 0) in
  let cs = cs_pair rate in
  Array.of_list (Iec60958.stream ~frame0 ~cs ~samples:(fun i -> smp.(i)) ~v:(fun i c -> vu.((4 * i) + c)) ~u:(fun i c -> vu.((4 * i) + 2 + c)) frames)

let line_of_subframes (c : src_cfg) ?(mangle = fun (l : int array) -> l) sfs =
  let ui = Iec60958.ui_ns c.rate /. (1. +. (c.ppm *. 1e-6)) in
  let lv = mangle (Iec60958.ui_levels (Array.to_list sfs)) in
  Line.add_jitter ~seed:c.seed c.jit (Line.of_levels ~t0:c.t0 ~ui lv)

let clocks_for ~fclk (l : Line.t) = int_of_float ((l.edges.(Array.length l.edges - 1) +. 3000.) *. fclk *. 1e-9)

type verdict = { rx_cmp : cmp; rx_err : int; rx_startup : int; rx_trailing : int; rx_detail : string; rx_par : int; rx_cs_ok : int; rx_cs_bad : int; or_cmp : cmp; or_err : int; or_par : int; or_cs_ok : int; or_cs_bad : int; rr : Rx.run_result }

let judge ?(impl = Rx.Rtl) ?scfg ~fclk ~phase ~rate (sfs : Iec60958.subframe array) (line : Line.t) =
  let samples = Line.sample ~fclk ~phase ~clocks:(clocks_for ~fclk line) line in
  let rr = Rx.run ~impl ?scfg ~samples () in
  let end_clock = int_of_float ((line.edges.(Array.length line.edges - 1) -. phase) *. fclk *. 1e-9) in
  let d = Rx.decode ~end_clock rr in
  let csl, csr = cs_pair rate in
  let rx_cs_ok = List.length (List.filter (fun (_, l, r) -> l = csl && r = csr) d.cs_blocks) in
  let o = Oracle.decode line.edges in
  let or_cs_ok = List.length (List.filter (fun (l, r) -> l = csl && r = csr) o.blocks) in
  { rx_cmp = compare_stream sfs (rx_got d); rx_err = d.count_errors + d.prefix_errors + d.short_records + rr.overflows + rr.sampler_overruns; rx_startup = d.startup_errors; rx_trailing = d.trailing_errors;
    rx_detail = sprintf "count %d prefix %d short %d overflow %d overrun %d; after the last edge %d" d.count_errors d.prefix_errors d.short_records rr.overflows rr.sampler_overruns d.trailing_errors;
    rx_par = List.length (List.filter (fun (s : Rx.rx_subframe) -> s.parity_bad) d.subframes);
    rx_cs_ok; rx_cs_bad = List.length d.cs_blocks - rx_cs_ok;
    or_cmp = compare_stream sfs (oracle_got o); or_err = o.violations + o.bad_preambles + o.frame_errors;
    or_par = List.length (List.filter (fun (s : Oracle.sub) -> not s.parity_ok) o.subs);
    or_cs_ok; or_cs_bad = List.length o.blocks - or_cs_ok; rr }

(* [expect]: the subframes sent minus the most the receiver may miss at the edges of a capture:
   the first (it locks on mid-subframe) and the last (its tail is flushed only by a next preamble). *)
let clean v ~expect =
  v.rx_startup <= 1 && v.rx_trailing <= 1 &&
  v.rx_cmp.mismatched = 0 && v.rx_cmp.compared >= expect && v.rx_err = 0 && v.rx_par = 0 && v.rx_cs_ok >= 1 && v.rx_cs_bad = 0
  && v.or_cmp.mismatched = 0 && v.or_cmp.compared >= expect && v.or_err = 0 && v.or_par = 0 && v.or_cs_ok >= 1 && v.or_cs_bad = 0

let show v =
  sprintf "chip: %d/%d equal (offset %d, %d resync, %d sent skipped), errors %d [%s] (+%d while locking), parity %d, cs blocks %d ok %d bad | oracle: %d/%d equal (%d resync, %d skipped), errors %d, parity %d, cs %d ok %d bad"
    (v.rx_cmp.compared - v.rx_cmp.mismatched) v.rx_cmp.compared v.rx_cmp.offset v.rx_cmp.resyncs v.rx_cmp.skipped v.rx_err v.rx_detail v.rx_startup v.rx_par v.rx_cs_ok v.rx_cs_bad
    (v.or_cmp.compared - v.or_cmp.mismatched) v.or_cmp.compared v.or_cmp.resyncs v.or_cmp.skipped v.or_err v.or_par v.or_cs_ok v.or_cs_bad

(* ---- subcommands ---- *)

let pacer_lockstep n =
  let st = Random.State.make [| 7 |] in
  let total = ref 0 and bad = ref 0 in
  for _ = 1 to n do
    let inc = 0x400_0000 + Random.State.int st 0x3bff_ffff in
    let sim = Hardcaml.Cyclesim.create (Pacer.circuit ()) in
    let m = Pacer.create () in
    let en_at = Random.State.int st 50 and density = Random.State.int st 100 in
    for c = 0 to 3000 do
      let push = if Random.State.int st 100 < density then Some (Random.State.int st 256) else None in
      let enable = c = en_at in
      let ip nm v w = Hardcaml.Cyclesim.in_port sim nm := Hardcaml.Bits.of_int ~width:w v in
      ip "inc" inc 32; ip "enable" (if enable then 1 else 0) 1; ip "push" (if push <> None then 1 else 0) 1; ip "push_data" (Option.value push ~default:0) 8;
      let rdy = Hardcaml.Bits.to_int !(Hardcaml.Cyclesim.out_port sim "ready") in
      let model_ready = Pacer.ready m in
      Hardcaml.Cyclesim.cycle sim;
      let o = Pacer.step m ~inc ~enable ~push in
      let g nm = Hardcaml.Bits.to_int !(Hardcaml.Cyclesim.out_port sim nm) in
      incr total;
      let b = match o.boundary with Some q -> q | None -> 4 in
      if (c > 0 && (rdy = 1) <> model_ready)
      || g "nibble" <> o.nibble || g "boundary" <> b || (g "underrun" = 1) <> o.underrun then incr bad
    done
  done;
  pr "pacer: RTL against model, %d random configurations (inc 2^26..2^30, random push density and start), %d clocks, %d mismatching clocks" n !total !bad;
  check "pacer lockstep" (!bad = 0)

(* the chip's transmitter, judged UI by UI against the reference encoder and by the oracle *)
let tx_run ?bank_fault ?(use_rtl = false) ~rate ~fclk ~frames ~seed () =
  let csl, csr = cs_pair rate in
  let st = Random.State.make [| seed |] in
  let smp = Array.init (frames + 50) (fun _ -> (Random.State.int st 65536, Random.State.int st 65536)) in
  let inc = Pacer.inc_of ~ui_hz:(128. *. Iec60958.rate_hz rate) ~clk_hz:fclk in
  let clocks = int_of_float (float frames /. Iec60958.rate_hz rate *. fclk) + 400 in
  let r = Tx_fw.run ?bank_fault ~use_rtl ~csl ~csr ~inc ~src:(Tx_fw.samples_source (fun i -> smp.(i))) ~clocks () in
  let nfr = (Array.length r.bounds / 128) - 1 in
  let sfs = Array.of_list (Iec60958.stream ~cs:(csl, csr)
                              ~samples:(fun i -> let l, r = smp.(i) in (Iec60958.audio24_of_16 l, Iec60958.audio24_of_16 r)) nfr) in
  let tr = Iec60958.transitions (Iec60958.ui_levels (Array.to_list sfs)) in
  let diff = ref 0 in
  Array.iteri (fun k t -> let (_, _, b) = r.bounds.(k) in if b <> t then incr diff) tr;
  (r, sfs, Array.length tr, !diff, inc)

let tx_suite () =
  List.iter (fun (rate, fclk) ->
      let r, sfs, n, diff, inc = tx_run ~use_rtl:true ~rate ~fclk ~frames:450 ~seed:11 () in
      let line = Line.of_bounds ~fclk r.bounds in
      let o = Oracle.decode line.edges in
      let oc = compare_stream sfs (oracle_got o) in
      let csl, csr = cs_pair rate in
      let csok = List.length (List.filter (fun (l, r) -> l = csl && r = csr) o.blocks) in
      pr "tx %s at %.3f MHz: inc 0x%08x; %d UIs against the reference encoder, %d differ; underruns %d; pacer RTL = model on all %d clocks; T0 %d words, T1 %d"
        (Iec60958.rate_name rate) (fclk /. 1e6) inc n diff r.underruns r.clocks r.words_t0 r.words_t1;
      pr "   oracle on the pin's edges: %d/%d subframes equal, %d violations, %d bad preambles, %d frame errors, %d parity errors, cs blocks %d equal of %d; UI %.3f ns"
        (oc.compared - oc.mismatched) oc.compared o.violations o.bad_preambles o.frame_errors
        (List.length (List.filter (fun (s : Oracle.sub) -> not s.parity_ok) o.subs)) csok (List.length o.blocks) o.ui_ns;
      List.iter (fun t -> pr "   oracle violation at %.0f ns (last edge at %.0f ns)" t line.edges.(Array.length line.edges - 1)) o.viol_at;
      check "tx" (diff = 0 && r.underruns = 0 && oc.mismatched = 0 && oc.compared >= 2 * 440 && o.violations = 0 && csok >= 1);
      (* the pin capture for sigrok, on the transmitter's quarter grid *)
      let tag = sprintf "%s-%.0f" (match rate with R48 -> "48k" | R32 -> "32k" | R44 -> "44k1") (fclk /. 1e3) in
      ignore (Sys.command "mkdir --parents results/sigrok");
      Line.to_binary ~ts:(1e9 /. fclk /. 4.) ~path:(sprintf "results/sigrok/tx-%s.bin" tag) line;
      let oc2 = open_out (sprintf "results/sigrok/tx-%s.expected" tag) in
      fprintf oc2 "# samplerate %.0f\n" (4. *. fclk);
      Array.iter (fun (s : Iec60958.subframe) ->
          fprintf oc2 "%s %06x %d %d %d %d\n" (Iec60958.preamble_name s.pre) (Iec60958.audio24 s) (Iec60958.slot s 28) (Iec60958.slot s 29) (Iec60958.slot s 30) (Iec60958.slot s 31)) sfs;
      close_out oc2)
    [ (Iec60958.R44, 60e6); (R48, 60e6); (R44, 60.8523e6); (R48, 60.8523e6) ];
  (* a control for the sigrok comparison: one wrong hi_expand entry in the transmitter's bank,
     judged against the stream that should have been sent *)
  let r, sfs, _, diff, _ = tx_run ~bank_fault:(fun b -> b.(256 + 0x33) <- b.(256 + 0x33) lxor 0x40) ~rate:R44 ~fclk:60e6 ~frames:450 ~seed:11 () in
  Line.to_binary ~ts:(1e9 /. 60e6 /. 4.) ~path:"results/sigrok/control-44k1-60000.bin" (Line.of_bounds ~fclk:60e6 r.bounds);
  let oc2 = open_out "results/sigrok/control-44k1-60000.expected" in
  fprintf oc2 "# samplerate %.0f\n" (4. *. 60e6);
  Array.iter (fun (s : Iec60958.subframe) ->
      fprintf oc2 "%s %06x %d %d %d %d\n" (Iec60958.preamble_name s.pre) (Iec60958.audio24 s) (Iec60958.slot s 28) (Iec60958.slot s 29) (Iec60958.slot s 30) (Iec60958.slot s 31)) sfs;
  close_out oc2;
  pr "sigrok control capture written: hi_expand entry 0x33 corrupted, %d UIs differ from the reference" diff

let random_jitter st rate =
  let ui = Iec60958.ui_ns rate in
  let hf = Random.State.bool st in
  let f = if hf then 8000. *. (50. ** Random.State.float st 1.) else 200. *. (40. ** Random.State.float st 1.) in
  let tmpl = if f >= 8000. then 0.25 else 0.25 *. 8000. /. f in   (* AES3 figure 11, UI p-p *)
  { Line.rms_ns = Random.State.float st 2.0; sin_pp_ns = tmpl *. ui *. Random.State.float st 1.0; sin_hz = f;
    sin_phase = Random.State.float st 6.28 }

let rx_random n seed =
  let st = Random.State.make [| seed |] in
  let pass = ref 0 in
  for k = 1 to n do
    let rate = if Random.State.bool st then Iec60958.R44 else R48 in
    let fclk = if Random.State.int st 3 = 0 then 60.8523e6 else 60e6 in
    let ppm = Random.State.float st 2000. -. 1000. in
    let jit = random_jitter st rate in
    let c = { rate; ppm; t0 = Random.State.float st 1000.; jit; frames = 420; frame0 = Random.State.int st 192; seed = Random.State.bits st } in
    let sfs = random_stream ~seed:c.seed ~rate ~frames:c.frames ~frame0:c.frame0 in
    let v = judge ~fclk ~phase:(Random.State.float st 16.) ~rate sfs (line_of_subframes c sfs) in
    let ok = clean v ~expect:(2 * c.frames - 2) in
    if ok then incr pass;
    pr "rx %2d %s rx %.3f MHz, source %+7.1f ppm, jitter %.2f ns rms + %.3f UI p-p at %.0f Hz: %s  %s" k (Iec60958.rate_name rate) (fclk /. 1e6) ppm
      jit.rms_ns (jit.sin_pp_ns /. Iec60958.ui_ns rate) jit.sin_hz (if ok then "PASS" else "FAIL") (show v);
    check "rx random" ok
  done;
  pr "rx random: %d of %d runs clean (24-bit random audio, random V and U, 420 frames each, starting at a random frame of the block)" !pass n

(* planted faults: each must make the round trip fail *)
let controls () =
  let rate = Iec60958.R44 and fclk = 60e6 in
  let base = { rate; ppm = 500.; t0 = 300.; jit = { Line.rms_ns = 1.0; sin_pp_ns = 10.; sin_hz = 20000.; sin_phase = 0. }; frames = 420; frame0 = 150; seed = 99 } in
  let sfs = random_stream ~seed:base.seed ~rate ~frames:base.frames ~frame0:base.frame0 in
  let run ?(words = ("CAUGHT", "missed")) ?(oracle_na = false) ?scfg name ?mangle sfs_sent ~caught =
    let v = judge ?scfg ~fclk ~phase:3. ~rate sfs (line_of_subframes base ?mangle sfs_sent) in
    let c = caught v in
    pr "%-50s chip %s, oracle %s   [%s]" name (if fst c then fst words else snd words) (if oracle_na then "not involved" else if snd c then fst words else snd words) (show v);
    (v, c) in
  let v0, _ = run ~words:("clean", "NOT CLEAN") "clean stream (must pass)" sfs ~caught:(fun v -> (clean v ~expect:838, clean v ~expect:838)) in
  check "control baseline clean" (clean v0 ~expect:838);
  let mod_sf i f = Array.mapi (fun j s -> if j = i then f s else s) sfs in
  (* index of a subframe of a given kind, from 200 on *)
  let find ?(from = 200) p = let r = ref 0 in (try Array.iteri (fun j (s : Iec60958.subframe) -> if j >= from && s.pre = p then (r := j; raise Exit)) sfs with Exit -> ()); !r in
  let iM = find M and iB = find B and iB0 = find ~from:0 B in
  let need name (_, (a, b)) = check name (a && b) in
  need "wrong preamble" (run "wrong preamble (an M sent as W)" (mod_sf iM (fun s -> { s with pre = W })) ~caught:(fun v ->
      (v.rx_cmp.mismatched > 0 || v.rx_err > 0, v.or_cmp.mismatched > 0 || v.or_err > 0)));
  need "wrong preamble B" (run "wrong preamble (the block's B sent as M)" (mod_sf iB (fun s -> { s with pre = M })) ~caught:(fun v ->
      (v.rx_cmp.mismatched > 0 || v.rx_cs_ok < 2, v.or_cmp.mismatched > 0 || v.or_cs_ok < 2)));
  need "parity" (run "parity bit flipped" (mod_sf 301 (fun s -> { s with slots = s.slots lxor (1 lsl 31) })) ~caught:(fun v ->
      (v.rx_par > 0, v.or_par > 0)));
  (* a channel-status bit error with the parity kept right: only the channel status shows it *)
  let csf = (iB0 + 2 * 37) in   (* in the one complete block of the capture *)
  need "channel status" (run "channel-status bit flipped (frame 37, parity kept)" (mod_sf csf (fun s -> { s with slots = s.slots lxor (1 lsl 30) lxor (1 lsl 31) })) ~caught:(fun v ->
      (v.rx_cs_bad > 0 && v.rx_par = 0, v.or_cs_bad > 0 && v.or_par = 0)));
  (* a biphase violation: no transition at the boundary between slots 5 and 6 (two zero aux bits) of subframe 250 *)
  let ui_at sf slot = (64 * sf) + 8 + (2 * (slot - 4)) in
  let viol l = let b = ui_at 250 6 in Array.mapi (fun i x -> if i >= b then 1 - x else x) l in
  need "biphase violation" (run "biphase violation (missing cell-boundary edge)" ~mangle:viol sfs ~caught:(fun v ->
      (v.rx_err > 0 || v.rx_cmp.mismatched > 0, v.or_err > 0 || v.or_cmp.mismatched > 0)));
  let drop l = let b = ui_at 260 15 + 1 in Array.init (Array.length l - 1) (fun i -> if i < b then l.(i) else l.(i + 1)) in
  need "dropped half-bit" (run "dropped half-bit (one UI removed)" ~mangle:drop sfs ~caught:(fun v ->
      (v.rx_err > 0 || v.rx_cmp.mismatched > 0, v.or_err > 0 || v.or_cmp.mismatched > 0)));
  (* planted faults in the chip itself *)
  need "rx holdoff" (run ~oracle_na:true ~scfg:(Rx.sampler_cfg ~holdoff:35 ()) "chip fault: sampler holdoff 35 (below 1 UI)" sfs ~caught:(fun v ->
      (not (clean v ~expect:838), true)));
  need "rx timeout" (run ~oracle_na:true ~scfg:(Rx.sampler_cfg ~timeout:130 ()) "chip fault: sampler timeout 130 (above 3 UI)" sfs ~caught:(fun v ->
      (not (clean v ~expect:838), true)));
  (* transmitter: one wrong entry in the parity table *)
  let r, sfs_t, _, diff, _ = tx_run ~bank_fault:(fun b -> b.(512 + 0x5a) <- 1 - b.(512 + 0x5a)) ~rate ~fclk ~frames:450 ~seed:12 () in
  let o = Oracle.decode (Line.of_bounds ~fclk r.bounds).edges in
  let opar = List.length (List.filter (fun (s : Oracle.sub) -> not s.parity_ok) o.subs) in
  let affected = Array.fold_left (fun a (s : Iec60958.subframe) -> a + (if (Iec60958.audio24 s lsr 8) land 0xff = 0x5a || (Iec60958.audio24 s lsr 16) land 0xff = 0x5a then 1 else 0)) 0 sfs_t in
  pr "%-50s reference compare: %d UIs differ; oracle parity errors %d (subframes with a 0x5a sample byte: %d)" "chip fault: TX parity table entry 0x5a wrong" diff opar affected;
  check "tx parity table control" (diff > 0 && opar > 0 && opar = affected);
  let r2, _, _, diff2, _ = tx_run ~bank_fault:(fun b -> b.(256 + 0x33) <- b.(256 + 0x33) lxor 0x40) ~rate ~fclk ~frames:450 ~seed:12 () in
  let o2 = Oracle.decode (Line.of_bounds ~fclk r2.bounds).edges in
  let oc2 = compare_stream sfs_t (oracle_got o2) in
  pr "%-50s reference compare: %d UIs differ; oracle: %d of %d subframes differ, %d parity errors" "chip fault: TX hi_expand entry 0x33 wrong" diff2 oc2.mismatched oc2.compared
    (List.length (List.filter (fun (s : Oracle.sub) -> not s.parity_ok) o2.subs));
  check "tx expand control" (diff2 > 0 && oc2.mismatched > 0)

let roundtrip () =
  List.iter (fun (rate, ppm, rx_fclk) ->
      let fclk_tx = 60e6 *. (1. +. (ppm *. 1e-6)) in
      let r, sfs, _, diff, _ = tx_run ~rate ~fclk:fclk_tx ~frames:420 ~seed:(int_of_float ppm + 5) () in
      let line = Line.add_jitter ~seed:3 { Line.rms_ns = 1.5; sin_pp_ns = 0.2 *. Iec60958.ui_ns rate; sin_hz = 31000.; sin_phase = 1. }
          (Line.map_time (fun t -> t +. 123.) (Line.of_bounds ~fclk:fclk_tx r.bounds)) in
      let v = judge ~fclk:rx_fclk ~phase:0.7 ~rate sfs line in
      let ok = clean v ~expect:(2 * 420 - 2) && diff = 0 in
      pr "round trip %s: chip TX at 60 MHz %+.0f ppm -> 1.5 ns rms + 0.2 UI p-p at 31 kHz -> chip RX at %.3f MHz: %s  %s" (Iec60958.rate_name rate) ppm (rx_fclk /. 1e6) (if ok then "PASS" else "FAIL") (show v);
      check "roundtrip" ok)
    [ (Iec60958.R44, -1000., 60e6); (R44, 0., 60e6); (R44, 1000., 60e6); (R48, -1000., 60e6); (R48, 1000., 60e6);
      (R44, 300., 60.8523e6); (R48, -300., 60.8523e6) ]

let jitter () =
  pr "transmit jitter: TIE of every UI boundary of the pin NCO, against a least-squares line; 'peak HP' after AES3's 700 Hz intrinsic-jitter filter";
  pr "limits: AES3-1992 6.2.5.1 intrinsic jitter < 0.025 UI peak (filtered); IEC 60958-3 consumer intrinsic jitter 0.05 UI (Cirrus/Wolfson white paper's summary, unverified against the standard)";
  pr "%-9s %-10s %-8s %-10s %10s %10s %12s %10s %10s" "rate" "clock" "grid" "skew" "p-p ns" "p-p UI" "peak HP ns" "peak UI" "rms ns";
  List.iter (fun (rate, fclk) ->
      let ui = Iec60958.ui_ns rate in
      let inc = Pacer.inc_of ~ui_hz:(128. *. Iec60958.rate_hz rate) ~clk_hz:fclk in
      let n = int_of_float (0.05 *. 128. *. Iec60958.rate_hz rate) in   (* 50 ms *)
      let ideal = Tie.ideal_bounds ~inc n in
      List.iter (fun (g, gname, skew, sname) ->
          let s = Tie.measure ~ui_ns:ui (Tie.place ~g ~skew_ns:skew ~fclk ideal) in
          pr "%-9s %-10s %-8s %-10s %10.3f %10.4f %12.3f %10.4f %10.3f" (Iec60958.rate_name rate) (sprintf "%.3f" (fclk /. 1e6)) gname sname s.pp_ns (s.pp_ns /. ui) s.hp_peak_ns (s.hp_peak_ns /. ui) s.rms_ns)
        [ (4, "quarter", [||], "none"); (4, "quarter", [| 0.; 0.5; -0.5; 0.25 |], "+-0.5 ns"); (4, "quarter", [| 0.; 1.0; -1.0; 0.5 |], "+-1 ns");
          (2, "half", [||], "none"); (1, "clock", [||], "none") ])
    [ (Iec60958.R44, 60e6); (R48, 60e6); (R44, 60.8523e6); (R48, 60.8523e6) ];
  (* at the transmitted edges only, from the pacer model running the transmit firmware *)
  pr "at the transmitted edges only (the pacer model driven by the TX firmware, random 16-bit audio, 20 ms; filter stepped per edge):";
  List.iter (fun (rate, fclk) ->
      let ui = Iec60958.ui_ns rate in
      let r, _, _, _, inc = tx_run ~rate ~fclk ~frames:(int_of_float (0.02 *. Iec60958.rate_hz rate)) ~seed:21 () in
      let tq = 1e9 /. fclk /. 4. and tc = 1e9 /. fclk in
      let period = 4294967296. /. float inc in
      let pairs = Array.of_list (List.filteri (fun _ x -> x <> None) (Array.to_list (Array.mapi (fun k (c, q, t) ->
          if t = 1 then Some ((float r.enable_clock +. (float (k + 1) *. period)) *. tc, float ((4 * c) + q) *. tq) else None) r.bounds))
          |> List.map Option.get) in
      let s = Tie.measure_edges pairs in
      pr "%-9s %-10s %-8s %-10s %10.3f %10.4f %12.3f %10.4f %10.3f   (%d edges)" (Iec60958.rate_name rate) (sprintf "%.3f" (fclk /. 1e6)) "quarter" "edges" s.pp_ns (s.pp_ns /. ui) s.hp_peak_ns (s.hp_peak_ns /. ui) s.rms_ns (Array.length pairs);
      check "intrinsic jitter at edges below 0.025 UI" (s.hp_peak_ns /. ui < 0.025))
    [ (Iec60958.R44, 60e6); (R48, 60e6); (R44, 60.8523e6); (R48, 60.8523e6) ];
  (* the analytic quarter grid against the pacer model's actual boundaries *)
  let r, _, _, _, inc = tx_run ~rate:R44 ~fclk:60e6 ~frames:220 ~seed:4 () in
  let ideal = Tie.ideal_bounds ~inc (Array.length r.bounds) in
  let placed = Tie.place ~g:4 ~fclk:60e6 ideal in
  let tq = 1e9 /. 60e6 /. 4. in
  let off = (float ((4 * r.enable_clock) + 0) *. tq) in
  let maxd = ref 0. in
  Array.iteri (fun k (c, q, _) -> maxd := Float.max !maxd (Float.abs ((float ((4 * c) + q) *. tq) -. off -. placed.(k)))) r.bounds;
  pr "check: the pacer model's %d boundaries lie on the analytic quarter-grid placement to within %.3f ns (the model truncates inc/4)" (Array.length r.bounds) !maxd

(* receiver jitter tolerance: sinusoidal jitter, raised until the chip or the oracle fails *)
let tolerance () =
  pr "receiver jitter tolerance (sinusoidal jitter, plus 0.5 ns rms random; AES3 figure 11 asks 0.25 UI p-p above 8 kHz): largest passing p-p in steps of 0.05 UI";
  List.iter (fun (rate, ppm, fclk) ->
      List.iter (fun f ->
          let last_ok = ref 0. and first_bad = ref nan in
          let a = ref 0.05 in
          while Float.is_nan !first_bad && !a < 1.01 do
            let ui = Iec60958.ui_ns rate in
            let c = { rate; ppm; t0 = 100.; jit = { Line.rms_ns = 0.5; sin_pp_ns = !a *. ui; sin_hz = f; sin_phase = 0.3 }; frames = 220; frame0 = 100; seed = 5 } in
            let sfs = random_stream ~seed:5 ~rate ~frames:c.frames ~frame0:c.frame0 in
            let v = judge ~fclk ~phase:2. ~rate sfs (line_of_subframes c sfs) in
            let ok = v.rx_cmp.mismatched = 0 && v.rx_cmp.compared >= 438 && v.rx_startup <= 1 && v.rx_trailing <= 1 && v.rx_err = 0 && v.rx_par = 0 in
            if ok then last_ok := !a else first_bad := !a;
            a := !a +. 0.05
          done;
          pr "  %s, source %+.0f ppm, rx %.3f MHz, jitter at %7.0f Hz: passes %.2f UI p-p (%.1f ns), first failure %s" (Iec60958.rate_name rate) ppm (fclk /. 1e6) f !last_ok
            (!last_ok *. Iec60958.ui_ns rate) (if Float.is_nan !first_bad then "none up to 1 UI" else sprintf "%.2f UI" !first_bad))
        [ 10e3; 100e3; 400e3; 1e6 ])
    [ (Iec60958.R44, 0., 60e6); (R48, 1000., 60e6); (R48, -1000., 60.8523e6) ]

(* ---- demo: the synthesiser on the PE array -> chip TX -> line -> chip RX and the oracle ---- *)

let write_wav_stereo path rate (l : int array) (r : int array) =
  let oc = open_out_bin path in
  let n = Array.length l in
  let le32 x = for i = 0 to 3 do output_byte oc ((x lsr (8 * i)) land 0xff) done in
  let le16 x = for i = 0 to 1 do output_byte oc ((x lsr (8 * i)) land 0xff) done in
  output_string oc "RIFF"; le32 (36 + (4 * n)); output_string oc "WAVEfmt ";
  le32 16; le16 1; le16 2; le32 rate; le32 (rate * 4); le16 4; le16 16;
  output_string oc "data"; le32 (4 * n);
  for i = 0 to n - 1 do le16 (l.(i) land 0xffff); le16 (r.(i) land 0xffff) done;
  close_out oc

(* the chiptune of ../array-uses/synth.ml, its PEs stepping once per audio frame; PEs 14 and 15
   (offset and sigma-delta there) pass the signed sum to the segment tap *)
let synth_source ~fs =
  let row = Row.create 16 in
  let pass = Upe.cfg_bytes ~fn:1 ~xs:1 ~ys:0 ~sw:0 ~pw:1 ~k:0 () in
  let tuning f = Int64.to_int (Int64.of_float (Float.round (f *. 4294967296. /. fs))) in
  let config (v : (float * int) array) nz =
    let c = Array.make 16 [] in
    for i = 0 to 3 do
      let f, a = v.(i) in let k = tuning f in
      c.(3 * i) <- Synth.nco_lo (k land 0xffff); c.((3 * i) + 1) <- Synth.nco_hi ((k lsr 16) land 0xffff); c.((3 * i) + 2) <- Synth.square a
    done;
    c.(12) <- Synth.lfsr; c.(13) <- Synth.square nz; c.(14) <- pass; c.(15) <- pass; c in
  let n = ref 0 and cur = ref [||] in
  let tap = ref [] in
  let next () =
    let t = float !n /. fs in
    if !n mod 176 = 0 then begin
      let v, nz = Synth.state_at t in
      let c = config v nz in
      if c <> !cur then begin
        let first = !cur = [||] in
        Row.load_direct row c; if first then row.pes.(12).s <- 0xace1; cur := c
      end
    end;
    ignore (Row.step row Row.seg_idle);
    incr n;
    let s = row.pes.(15).p land 0xffff in
    tap := s :: !tap;
    (s, s) in
  ({ Tx_fw.next_frame = next }, tap)

let demo seconds =
  let rate = Iec60958.R44 and fclk = 60e6 in
  let fs = Iec60958.rate_hz rate in
  let csl, csr = cs_pair rate in
  let src, tap = synth_source ~fs in
  let inc = Pacer.inc_of ~ui_hz:(128. *. fs) ~clk_hz:fclk in
  let clocks = int_of_float (seconds *. fclk) in
  let t0 = Unix.gettimeofday () in
  let r = Tx_fw.run ~csl ~csr ~inc ~src ~clocks () in
  pr "demo: synthesiser (16 upe_v0 PEs, one step per frame) -> TX firmware -> NCO pacer: %d clocks (%.2f s), %d frames sourced, underruns %d (%.0f s)"
    clocks seconds r.frames_sourced r.underruns (Unix.gettimeofday () -. t0);
  let synth = Array.of_list (List.rev !tap) in
  let to_s16 x = if x >= 0x8000 then x - 0x10000 else x in
  (* the line: the transmitter's crystal +150 ppm against the receiver's, 1 ns rms jitter *)
  let line = Line.add_jitter ~seed:9 { Line.no_jitter with rms_ns = 1.0 }
      (Line.map_time (fun t -> (t /. (1. +. 150e-6)) +. 77.) (Line.of_bounds ~fclk r.bounds)) in
  let o = Oracle.decode line.edges in
  let osub = Array.of_list o.subs in
  let k0 = (let r = ref 0 in (try Array.iteri (fun i (s : Oracle.sub) -> if s.pre <> Oracle.Y then (r := i; raise Exit)) osub with Exit -> ()); !r) in
  let nfr = (Array.length osub - k0) / 2 in
  let ol = Array.init nfr (fun i -> Iec60958.sign24 (Oracle.audio24 osub.(k0 + (2 * i))) asr 8) in
  let orr = Array.init nfr (fun i -> Iec60958.sign24 (Oracle.audio24 osub.(k0 + (2 * i) + 1)) asr 8) in
  ignore (Sys.command "mkdir --parents results/demo");
  write_wav_stereo "results/demo/oracle.wav" 44100 ol orr;
  let synth16 = Array.map to_s16 synth in
  write_wav_stereo "results/demo/synth-direct.wav" 44100 synth16 synth16;
  let same = ref 0 in
  Array.iteri (fun i x -> if i < Array.length synth16 && synth16.(i) = x && orr.(i) = x then incr same) ol;
  pr "demo: oracle decoded %d frames, %d violations, %d parity errors, %d cs blocks; %d of %d frames equal the synthesiser's tap word (left and right)"
    nfr o.violations (List.length (List.filter (fun (s : Oracle.sub) -> not s.parity_ok) o.subs)) (List.length o.blocks) !same nfr;
  check "demo oracle" (!same = nfr && nfr > 0 && o.violations = 0);
  let t1 = Unix.gettimeofday () in
  let samples = Line.sample ~fclk:60e6 ~phase:1.1 ~clocks:(clocks_for ~fclk:60e6 line) line in
  let rr = Rx.run ~impl:Rtl ~samples () in
  let end_clock = int_of_float ((line.edges.(Array.length line.edges - 1) -. 1.1) *. 60e6 *. 1e-9) in
  let d = Rx.decode ~end_clock rr in
  let got = Array.of_list d.subframes in
  let nf = Array.length got / 2 in
  let j0 = (let r = ref 0 in (try Array.iteri (fun i (s : Rx.rx_subframe) -> if s.kind <> KW then (r := i; raise Exit)) got with Exit -> ()); !r) in
  let nf = min nf ((Array.length got - j0) / 2) in
  let gl = Array.init nf (fun i -> Iec60958.sign24 ((got.(j0 + (2 * i)).slots lsr 4) land 0xffffff) asr 8) in
  let gr = Array.init nf (fun i -> Iec60958.sign24 ((got.(j0 + (2 * i) + 1).slots lsr 4) land 0xffffff) asr 8) in
  write_wav_stereo "results/demo/chip-rx.wav" 44100 gl gr;
  (* align the chip's frames to the oracle's by searching a short window *)
  let best = ref (-1) in
  for off = 0 to 20 do if !best < 0 && nf > 50 && Array.sub gl 10 30 = Array.sub ol (10 + off) 30 then best := off done;
  let eq = ref 0 in
  if !best >= 0 then Array.iteri (fun i x -> if i + !best < nfr && ol.(i + !best) = x && orr.(i + !best) = gr.(i) then incr eq) gl;
  pr "demo: chip RX (%.0f s): %d frames, errors %d (+%d after the last edge), parity %d, %d cs blocks; %d of %d frames equal the oracle's (offset %d)"
    (Unix.gettimeofday () -. t1) nf (d.count_errors + d.prefix_errors + d.short_records) d.trailing_errors (List.length (List.filter (fun (s : Rx.rx_subframe) -> s.parity_bad) d.subframes))
    (List.length d.cs_blocks) !eq nf !best;
  check "demo chip rx" (!eq = nf && nf > 0 && d.count_errors + d.prefix_errors + d.short_records = 0);
  let rep = Analyser.report ~fclk:60e6 d in
  let oc = open_out "results/demo/analyser.txt" in
  List.iter (fun l -> fprintf oc "|%s|\n" l) rep.lines; close_out oc;
  List.iter (fun l -> pr "  |%s|" l) rep.lines;
  check "analyser fs" (Float.abs (rep.measured_fs -. (44100. *. (1. +. 150e-6))) < 5.)

(* sigrok's annotations: "Preamble X", 28 bit lines, "Aux", "Sample", "Audio 0x..", "V" or "E",
   "S: u", "C: c", "P: p" per subframe. It checks no parity, so P is compared as a value. *)
let sigrok_compare ann expected =
  let read f = let ic = open_in f in let rec go a = match input_line ic with l -> go (l :: a) | exception End_of_file -> close_in ic; List.rev a in go [] in
  let strip l = match String.index_opt l ':' with Some i -> String.trim (String.sub l (i + 1) (String.length l - i - 1)) | None -> l in
  let subs = ref [] and cur = ref None and unknown = ref 0 in
  List.iter (fun l ->
      let a = strip l in
      let w = String.split_on_char ' ' a in
      match w with
      | [ "Preamble"; p ] -> cur := Some (p, 0, 0, 0, 0)
      | [ "Unknown"; "Preamble" ] -> incr unknown; cur := None
      | [ "Audio"; x ] -> (match !cur with Some (p, _, v, u, c) -> cur := Some (p, int_of_string x, v, u, c) | None -> ())
      | [ "E" ] -> (match !cur with Some (p, au, _, u, c) -> cur := Some (p, au, 1, u, c) | None -> ())
      | [ "S:"; x ] -> (match !cur with Some (p, au, v, _, c) -> cur := Some (p, au, v, int_of_string x, c) | None -> ())
      | [ "C:"; x ] -> (match !cur with Some (p, au, v, u, _) -> cur := Some (p, au, v, u, int_of_string x) | None -> ())
      | [ "P:"; x ] -> (match !cur with Some (p, au, v, u, c) -> subs := (sprintf "%s %06x %d %d %d %s" p au v u c x) :: !subs; cur := None | None -> ())
      | _ -> ()) (read ann);
  let got = Array.of_list (List.rev !subs) in
  let exp = Array.of_list (List.filter (fun l -> l <> "" && l.[0] <> '#') (read expected)) in
  let n = Array.length exp and m = Array.length got in
  let off = ref (-1) in
  (try for j = 0 to n - 4 do if m >= 4 && !off < 0 && got.(0) = exp.(j) && got.(1) = exp.(j + 1) && got.(2) = exp.(j + 2) && got.(3) = exp.(j + 3) then (off := j; raise Exit) done with Exit -> ());
  let eq = ref 0 and cmp = ref 0 in
  if !off >= 0 then Array.iteri (fun k g -> if !off + k < n then (incr cmp; if exp.(!off + k) = g then incr eq)) got;
  pr "sigrok %s: %d subframes annotated (%d unknown preambles); aligned at sent subframe %d; %d of %d equal to the sent (preamble, 24-bit audio, V, U, C, P)"
    (Filename.basename ann) m !unknown !off !eq !cmp;
  check "sigrok" (!off >= 0 && !off <= 2 && !eq = !cmp && !cmp >= n - 6)

let () =
  (match Array.to_list Sys.argv |> List.tl with
  | [ "sigrok-compare"; a; e ] -> sigrok_compare a e
  | [ "pacer" ] -> pacer_lockstep 200
  | [ "tx" ] -> tx_suite ()
  | [ "rx"; n; seed ] -> rx_random (int_of_string n) (int_of_string seed)
  | [ "controls" ] -> controls ()
  | [ "roundtrip" ] -> roundtrip ()
  | [ "jitter" ] -> jitter ()
  | [ "tolerance" ] -> tolerance ()
  | [ "demo"; s ] -> demo (float_of_string s)
  | _ -> prerr_endline "usage: main.exe pacer | tx | rx N SEED | controls | roundtrip | jitter | tolerance | demo SECONDS"; exit 2);
  if !fails > 0 then (pr "%d CHECK(S) FAILED" !fails; exit 1) else pr "ALL CHECKS PASS"
