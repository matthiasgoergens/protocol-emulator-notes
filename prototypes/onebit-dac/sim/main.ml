let pr = Printf.printf

let lockstep trials run_cycles =
  Upe_rtl.bug := "";
  let total = ref 0 and bad = ref 0 in
  List.iteri
    (fun mi mode ->
      let r = Lockstep.campaign ~stop:false ~mode ~seed:(2000 + mi) ~trials ~run_cycles () in
      total := !total + r.cycles;
      (match r.first_fail with
       | None -> pr "%-9s %4d trials %8d cycles  0 mismatches\n" mode r.trials r.cycles
       | Some (t, c, d) ->
         incr bad;
         pr "%-9s MISMATCH in trial %d at cycle %d:\n  %s\n" mode t c (String.concat "\n  " d));
      flush stdout)
    Lockstep.modes;
  pr "total %d cycles compared, %d generators with mismatches\n" !total !bad

let controls only_new trials run_cycles =
  let caught = ref 0 and n = ref 0 in
  List.iter
    (fun (b, what) ->
      if (not only_new) || String.length what > 10 && String.sub what 0 10 = "onebit-dac" then begin
        incr n;
        Upe_rtl.bug := b;
        let hits =
          List.filter_map
            (fun m ->
              let r = Lockstep.campaign ~mode:m ~seed:11 ~trials ~run_cycles () in
              Option.map (fun (_, c, d) -> (c, m, List.hd d)) r.first_fail)
            Lockstep.modes
        in
        (match List.sort compare hits with
         | (c, m, d) :: _ ->
           incr caught;
           pr "%-20s caught: fastest %-8s %6d cycles; %2d of %d generators  (%s)\n    first diff: %s\n" b m c
             (List.length hits) (List.length Lockstep.modes) what d
         | [] -> pr "%-20s MISSED  (%s)\n" b what);
        flush stdout
      end)
    Upe_rtl.bugs;
  Upe_rtl.bug := "";
  pr "%d of %d planted bugs caught\n" !caught !n

let coverage trials run_cycles =
  let tabs = List.map (fun m -> (m, Lockstep.coverage ~mode:m ~seed:5 ~trials ~run_cycles)) Lockstep.modes in
  let events =
    List.sort_uniq compare (List.concat_map (fun (_, h) -> Hashtbl.fold (fun k _ acc -> k :: acc) h []) tabs)
  in
  pr "%-16s" "event";
  List.iter (fun (m, _) -> pr " %8s" m) tabs;
  pr "\n";
  List.iter
    (fun e ->
      pr "%-16s" e;
      List.iter (fun (_, h) -> pr " %8d" (Option.value ~default:0 (Hashtbl.find_opt h e))) tabs;
      pr "\n")
    events

(* a deterministic test input for the system runs: two tones plus pseudo-random noise, so that
   every PE state and the saturation paths are exercised *)
let test_words ~n ~amp ~seed =
  let r = Random.State.make [| seed |] in
  let mk f1 f2 =
    Array.init n (fun i ->
        let t = float i /. 44117.6 in
        let v = amp *. ((0.6 *. sin (2. *. Float.pi *. f1 *. t)) +. (0.3 *. sin (2. *. Float.pi *. f2 *. t)))
                +. (amp *. 0.1 *. (Random.State.float r 2.0 -. 1.0)) in
        int_of_float (Float.round v))
  in
  (mk 1000. 7300., mk 440. 15100.)

module SysM = Dac.System (struct include Model type t = Model.t end)

(* system run on the model: per-step words and pin bits, for both channels *)
let system_run ?(log_inputs = false) ?pause ?(sample_clocks = Dac.sample_clocks) ~order ~clocks ~amp () =
  let d = Dac.design_of order in
  let ops = Dac.run_ops d in
  let l, r = test_words ~n:(clocks / sample_clocks + 4) ~amp ~seed:3 in
  let sys = SysM.create ~log_inputs ?pause ~sample_clocks ~ops_l:ops ~ops_r:ops ~bytes:(Dac.frame_bytes l r) () in
  let steps = [| ref []; ref [] |] in
  for _ = 1 to clocks do
    let st = SysM.cycle sys in
    (* a tick visible now: the word of the next step, and F after the previous step *)
    List.iteri
      (fun ch (sg, tp) ->
        if st.Spec.segs.(sg).fv then steps.(ch) := (st.Spec.segs.(sg).fw, st.Spec.taps.(tp).tf) :: !(steps.(ch)))
      [ (0, 2); (3, 3) ]
  done;
  (sys, d, Array.map (fun s -> Array.of_list (List.rev !s)) steps)

let check_fast order clocks amp =
  let _, d, steps = system_run ~order ~clocks ~amp () in
  Array.iteri
    (fun ch st ->
      let f = Dac.fast_create d in
      let n = Array.length st in
      let bad = ref 0 and ones = ref 0 and first = ref (-1) in
      (* the bit recorded with step i+1's word is F after step i *)
      for i = 0 to n - 2 do
        let b = Dac.fast_step f (fst st.(i)) in
        let a = snd st.(i + 1) in
        if a then incr ones;
        if a <> b then (incr bad; if !first < 0 then first := i)
      done;
      pr "%s channel %s: %d steps compared, %d mismatches (first at %d), ones %.4f, states %s\n" order
        (if ch = 0 then "L" else "R") (n - 1) !bad !first (float !ones /. float (n - 1))
        (String.concat "," (Array.to_list (Array.map string_of_int f.Dac.s))))
    steps

(* the model's system run replayed into a fresh model and the Hardcaml array in lockstep *)
let rtl_lockstep order clocks amp =
  let sys, _, _ = system_run ~log_inputs:true ~order ~clocks ~amp () in
  let inputs = List.rev sys.SysM.inputs_log in
  let m = Model.create () and r = Rtlsim.create () in
  let n = ref 0 and bad = ref None and ticks = ref 0 and fchanges = ref 0 and lastf = ref false in
  (try
     List.iter
       (fun i ->
         Model.cycle m i;
         Rtlsim.cycle r i;
         incr n;
         let a = Model.state m and b = Rtlsim.state r in
         if a.Spec.segs.(0).fv then incr ticks;
         if a.Spec.taps.(2).tf <> !lastf then (incr fchanges; lastf := a.Spec.taps.(2).tf);
         let d = Spec.diff a b in
         if d <> [] then (bad := Some (!n, d); raise Exit))
       inputs
   with Exit -> ());
  match !bad with
  | None ->
    let c k = Option.value ~default:0 (Hashtbl.find_opt m.Model.cov k) in
    pr "%s: %d clocks (setup and %d modulator steps on the left), every state bit compared each clock: 0 mismatches; left pin toggled %d times; model events: saturated %d, lane_loop %d, repeat_tick %d\n" order !n !ticks !fchanges (c "saturated") (c "lane_loop") (c "repeat_tick")
  | Some (c, d) -> pr "%s: MISMATCH at clock %d:\n  %s\n" order c (String.concat "\n  " d)

(* pump timing and underruns: commit clocks modulo the sample period, steps per sample *)
let pump_check sample_clocks clocks =
  (* the host stalls between the left and the right half of a frame: from clock 400,000 it
     sends nothing once the next byte is a frame's third (R lo), until clock 520,000 *)
  let pause c next = c >= 400_000 && c < 520_000 && (c >= 401_000 || next land 3 = 2) in
  pr "sample period %d clocks (%d steps)\n" sample_clocks (sample_clocks / Dac.period);
  let sys, _, steps = system_run ~pause ~sample_clocks ~order:"o3" ~clocks ~amp:8000. () in
  let commits = List.rev sys.SysM.commits in
  let phases = Hashtbl.create 8 in
  List.iter (fun (c, sg, _) -> Hashtbl.replace phases (sg, c mod sample_clocks) (1 + Option.value ~default:0 (Hashtbl.find_opt phases (sg, c mod sample_clocks)))) commits;
  pr "commits: %d; (segment, clock mod %d) -> count:\n" (List.length commits) sample_clocks;
  Hashtbl.iter (fun (sg, ph) n -> pr "  seg %d phase %4d: %d\n" sg ph n) phases;
  (* a torn frame would show as a sample period with a commit on one side only *)
  let per = Hashtbl.create 1024 in
  List.iter (fun (c, sg, _) -> let k = c / sample_clocks in Hashtbl.replace per k (sg :: Option.value ~default:[] (Hashtbl.find_opt per k))) commits;
  let torn = Hashtbl.fold (fun _ l n -> if List.length l <> 2 || List.sort compare l <> [ 0; 3 ] then n + 1 else n) per 0 in
  pr "sample periods with commits: %d; with other than one left and one right commit (torn): %d\n" (Hashtbl.length per) torn;
  let ur = List.rev sys.SysM.underruns in
  pr "underrun reports: %d (host stalled mid-frame from clock 400000 to 519999)\n" (List.length ur);
  List.iteri (fun i (c, k) -> if i < 3 || i >= List.length ur - 2 then pr "  clock %d byte %d\n" c k) ur;
  (* steps per distinct word on the left, the ZOH length *)
  let st = steps.(0) in
  let runs = Hashtbl.create 8 in
  let cur = ref (-1) and len = ref 0 in
  Array.iter (fun (w, _) -> if w = !cur then incr len else begin (if !cur >= 0 then Hashtbl.replace runs !len (1 + Option.value ~default:0 (Hashtbl.find_opt runs !len))); cur := w; len := 1 end) st;
  pr "left: %d steps; run lengths of equal consecutive words (length -> count):\n" (Array.length st);
  Hashtbl.iter (fun l n -> pr "  %d -> %d\n" l n) runs;
  pr "host bytes sent %d of %d; frames consumed %d\n" sys.SysM.host.Dac.next (Array.length sys.SysM.host.Dac.bytes) (List.length commits / 2)

let render order inpath outprefix steps shift0 =
  let d = Dac.design_of order in
  let l, r = Dac.read_stereo inpath in
  let t0 = Unix.gettimeofday () in
  let bl = Dac.render ~shift0 d l ~steps and br = Dac.render ~shift0 d r ~steps in
  Dac.write_bits (outprefix ^ ".L.bits") bl;
  Dac.write_bits (outprefix ^ ".R.bits") br;
  pr "%s: %d samples x %d steps per channel, %.1f s\n" order (Array.length l) steps (Unix.gettimeofday () -. t0)

(* ---- compressed audio ---- *)
module CrcM = Codec.Pe_crc (struct include Model type t = Model.t end)

let adpcm inp outp =
  let ch, pcm, nb, per = Codec.adpcm_decode inp in
  Codec.write_s16 outp pcm;
  pr "adpcm: %d channels, %d blocks of %d samples, %d samples per channel; predictor PE steps %d (%.2f per sample)\n" ch nb per
    (Array.length pcm / ch) !Codec.pe_steps (float !Codec.pe_steps /. float (Array.length pcm))

let sbc_run ?(crc = Codec.crc8_ref) s =
  Codec.n_frames := 0; Codec.n_alloc_ops := 0; Codec.n_mac := 0; Codec.n_div := 0; Codec.n_crc_bits := 0;
  Codec.sbc_decode ~crc s

let sbc inp outp how =
  let s = Codec.read_file inp in
  let crc =
    match how with
    | "pe" -> CrcM.crc
    | "pe-rtl" ->
      let r = Rtlsim.create () in
      CrcM.other := Some (Rtlsim.cycle r, fun () -> Rtlsim.state r);
      CrcM.crc
    | _ -> Codec.crc8_ref
  in
  let ch, pcm, good, bad = sbc_run ~crc s in
  Codec.write_s16 outp pcm;
  let fr = float !Codec.n_frames in
  pr "sbc (%s CRC): %d channels, %d frames decoded, %d rejected, %d samples per channel\n" how ch good bad (Array.length pcm / max 1 ch);
  pr "  per frame: %.0f CRC bits, %.0f allocation operations, %.0f dequantisations (divisions), %.0f MACs\n"
    (float !Codec.n_crc_bits /. fr) (float !Codec.n_alloc_ops /. fr) (float !Codec.n_div /. fr) (float !Codec.n_mac /. fr);
  if how <> "ref" then
    pr "  PE array clocks for the CRCs: %d (%.0f per frame)%s\n" !CrcM.clocks (float !CrcM.clocks /. fr)
      (match how, !CrcM.mismatch with
       | "pe-rtl", None -> "; Hardcaml RTL in lockstep: 0 mismatches"
       | "pe-rtl", Some c -> Printf.sprintf "; RTL MISMATCH at clock %d" c
       | _ -> "")

(* planted controls: each must be caught *)
let sbc_controls inp =
  let s = Codec.read_file inp in
  let _, clean, g0, b0 = sbc_run s in
  pr "clean: %d frames, %d rejected\n" g0 b0;
  (* 1: corrupt the CRC byte of frame 10 (the frame length from the clean parse) *)
  let flen = let _, l = Codec.unpack s 0 ~crc:Codec.crc8_ref in l in
  let b = Bytes.of_string s in
  let at = (10 * flen) + 3 in
  Bytes.set b at (Char.chr (Char.code s.[at] lxor 0x01));
  let _, pcm1, g1, b1 = sbc_run ~crc:CrcM.crc (Bytes.to_string b) in
  pr "control 1, CRC byte of frame 10 flipped, CRC on the PE: %d decoded, %d rejected -> %s\n" g1 b1
    (if b1 = 1 && g1 = g0 - 1 then "CAUGHT" else "MISSED");
  ignore pcm1;
  (* 2: one scale-factor bit flipped in frame 20 (the CRC covers it) *)
  let b = Bytes.of_string s in
  let at = (20 * flen) + 5 in
  Bytes.set b at (Char.chr (Char.code s.[at] lxor 0x10));
  let _, _, g2, b2 = sbc_run ~crc:CrcM.crc (Bytes.to_string b) in
  pr "control 2, a scale-factor bit of frame 20 flipped: %d decoded, %d rejected -> %s\n" g2 b2 (if b2 = 1 then "CAUGHT" else "MISSED");
  (* 3: a wrong bit allocation (loudness offset of subband 0 off by one) *)
  Codec.fault := "alloc_offset";
  let _, pcm3, _, _ = sbc_run s in
  Codec.fault := "";
  let diffs = ref 0 in
  Array.iteri (fun i v -> if i < Array.length clean && v <> clean.(i) then incr diffs) pcm3;
  pr "control 3, loudness offset of subband 0 off by one: %d of %d samples differ from the clean decode%s -> %s\n" !diffs
    (Array.length clean) (if Array.length pcm3 <> Array.length clean then " (length differs)" else "")
    (if !diffs > 0 || Array.length pcm3 <> Array.length clean then "CAUGHT (the reference comparison fails)" else "MISSED");
  (* 4: the PE CRC with a wrong polynomial bit must reject every frame *)
  Codec.fault := "crc_poly";
  let _, _, g4, b4 = sbc_run ~crc:CrcM.crc s in
  Codec.fault := "";
  pr "control 4, the PE CRC's result with one bit wrong: %d decoded, %d rejected -> %s\n" g4 b4 (if g4 = 0 then "CAUGHT" else "MISSED")

let () =
  match Array.to_list Sys.argv with
  | [ _; "adpcm"; i; o ] -> adpcm i o
  | [ _; "sbc"; i; o; how ] -> sbc i o how
  | [ _; "sbc-controls"; i ] -> sbc_controls i
  | [ _; "check-fast"; o; c; a ] -> check_fast o (int_of_string c) (float_of_string a)
  | [ _; "rtl-lockstep"; o; c; a ] -> rtl_lockstep o (int_of_string c) (float_of_string a)
  | [ _; "pump-check"; p; c ] -> pump_check (int_of_string p) (int_of_string c)
  | [ _; "render"; o; i; p; s; sh ] -> render o i p (int_of_string s) (int_of_string sh)
  | [ _; "lockstep"; n; c ] -> lockstep (int_of_string n) (int_of_string c)
  | [ _; "controls"; n; c ] -> controls false (int_of_string n) (int_of_string c)
  | [ _; "controls-new"; n; c ] -> controls true (int_of_string n) (int_of_string c)
  | [ _; "coverage"; n; c ] -> coverage (int_of_string n) (int_of_string c)
  | [ _; "verilog-pe" ] -> Hardcaml.Rtl.print Verilog (Upe_rtl.pe_circuit ())
  | [ _; "verilog-array" ] -> Hardcaml.Rtl.print Verilog (Upe_rtl.array_circuit ~state_ports:false ())
  | _ -> prerr_endline "usage: main.exe lockstep N C | controls N C | controls-new N C | coverage N C | verilog-array"
