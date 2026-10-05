(* eth10-node checks. Usage: main.exe [tx|...] ; with no argument, everything. *)

let clock_hz = 60e6
let tick_ns = 1e9 /. clock_hz /. 4.0   (* quarter clock *)
let ms n = int_of_float (n *. 1e-3 *. clock_hz)

let pr fmt = Printf.printf (fmt ^^ "\n%!")
let verdict ok = if ok then "PASS" else "FAIL"

let example_frame payload =
  Eth_model.udp_frame ~dst_mac:[ 0xFF; 0xFF; 0xFF; 0xFF; 0xFF; 0xFF ] ~src_mac:[ 0x02; 0x00; 0x00; 0x12; 0x34; 0x56 ]
    ~src_ip:[ 10; 0; 0; 2 ] ~dst_ip:[ 10; 0; 0; 255 ] ~src_port:4096 ~dst_port:4096
    ~payload:(List.map Char.code (List.init (String.length payload) (String.get payload)))

let summary name (r : Clause14.report) =
  let nlps = List.length r.nlp_widths and frames = List.length (Clause14.frames_of r) in
  let mn l = List.fold_left Float.min infinity l and mx l = List.fold_left Float.max neg_infinity l in
  pr "  %s: %d link pulses (width %.1f..%.1f ns), gaps after activity %.3f..%.3f ms; %d frames, TP_IDL %.1f..%.1f ns, max crossing deviation %.2f ns; %d violations"
    name nlps (mn r.nlp_widths) (mx r.nlp_widths) (mn r.nlp_gaps_ms) (mx r.nlp_gaps_ms) frames (mn r.tp_idls) (mx r.tp_idls) r.max_edge_dev
    (List.length r.violations);
  List.iteri (fun i v -> if i < 5 then pr "    violation: %s" v) r.violations

(* ---------------- transmit ---------------- *)

let tx () =
  pr "== transmit firmware (tx_fw.ml): program sizes %s of %d words"
    (String.concat ", " (List.init 4 (fun t -> string_of_int (Tx_fw.program_size t)))) Isa.prog_len;
  let frames = [ example_frame "hello from firmware"; example_frame (String.make 120 'x'); example_frame "a" ] in
  let frame_odd = example_frame (String.make 61 'o') in   (* 61 + 42 = 103 bytes: odd length *)
  let frames = frames @ [ frame_odd ] in
  let streams = List.map (fun f -> Tx_fw.streams (Tx_fw.wire_of_frame f)) frames in
  (* 1. idle only: 70 ms, link pulses *)
  let r = Tx_fw.simulate ~cycles:(ms 70.0) [] in
  let c = Clause14.check ~tick_ns r.runs in
  summary "idle 70 ms" c;
  let ok1 = c.violations = [] && List.length c.nlp_widths >= 4 in
  (* 2. frames at chosen times, two of them back to back at the minimum gap *)
  let starts = [ ms 3.0; ms 20.0; ms 20.13; ms 50.0 ] in   (* 20.13: queued right behind the second *)
  let r2 = Tx_fw.simulate ~cycles:(ms 80.0) (List.combine starts streams) in
  let c2 = Clause14.check ~tick_ns r2.runs in
  summary "four frames in 80 ms" c2;
  let got = Clause14.frames_of c2 in
  let want = List.map (fun f -> f @ Eth_model.fcs_bytes f) frames in
  let ok2 = c2.violations = [] && got = want in
  pr "  decoded frames equal the frames sent (with FCS): %b" (got = want);
  (* 3. back to back: the feeder queues frames immediately; the gap is the firmware's own *)
  let r3 = Tx_fw.simulate ~cycles:(ms 2.0) (List.map (fun s -> (0, s)) streams) in
  let c3 = Clause14.check ~tick_ns r3.runs in
  let gaps = let rec g = function
      | Clause14.Frame a :: (Clause14.Frame b :: _ as rest) -> ((b.t_ns -. a.end_ns) /. 1e3) :: g rest
      | _ :: rest -> g rest | [] -> [] in g c3.events in
  pr "  frames queued back to back (the feeder raises start as soon as it can): gaps %s us; violations %d"
    (String.concat ", " (List.map (Printf.sprintf "%.2f") gaps)) (List.length c3.violations);
  let ok3 = c3.violations = [] && Clause14.frames_of c3 = List.map (fun f -> f @ Eth_model.fcs_bytes f) frames in
  (* 4. RTL alongside the interpreter: 20 ms with two frames *)
  let r4 = Tx_fw.simulate ~rtl:true ~cycles:(ms 20.0) [ (ms 1.0, List.nth streams 0); (ms 2.0, List.nth streams 3) ] in
  let c4 = Clause14.check ~tick_ns r4.runs in
  pr "  RTL (sequencer.ml) against interpreter over 20 ms, 2 frames: %d diverging clocks; checker violations %d" r4.divergent
    (List.length c4.violations);
  let ok4 = r4.divergent = 0 && c4.violations = [] in
  (* 5. constrained random: 40 frames of 60..400 bytes, random contents, random arrival times
     (a third of them arriving while the previous is still going out) *)
  Random.init 14;
  let t = ref (ms 0.5) in
  let rnd = List.init 40 (fun _ ->
      let len = 60 + Random.int 341 in
      let f = List.init len (fun _ -> Random.int 256) in
      t := !t + (if Random.int 3 = 0 then 0 else Random.int (ms 6.0));
      (!t, f)) in
  let r5 = Tx_fw.simulate ~cycles:(!t + ms 30.0) (List.map (fun (a, f) -> (a, Tx_fw.streams (Tx_fw.wire_of_frame f))) rnd) in
  let c5 = Clause14.check ~tick_ns r5.runs in
  summary "40 random frames" c5;
  let ok5 = c5.violations = [] && Clause14.frames_of c5 = List.map (fun (_, f) -> f @ Eth_model.fcs_bytes f) rnd in
  pr "  random frames decoded equal to those sent: %b" (Clause14.frames_of c5 = List.map (fun (_, f) -> f @ Eth_model.fcs_bytes f) rnd);
  pr "transmit: %s" (verdict (ok1 && ok2 && ok3 && ok4 && ok5));
  (* controls: each must be flagged by the checker (or the frame comparison) *)
  pr "controls (each must fail):";
  let control name ?(p = Tx_fw.default) ?(tp_idl = 6) ?late ?(mutate = fun s -> s) ?(cycles = ms 45.0) ?(back_to_back = false) () =
    let mem = Array.init 4 (fun t -> Tx_fw.program ~p ?late_thread:late t) in
    let st = List.map (fun f -> mutate (Tx_fw.streams ~tp_idl (Tx_fw.wire_of_frame f))) [ List.nth frames 0; List.nth frames 2 ] in
    let r = Tx_fw.simulate ~mem ~cycles (List.combine (if back_to_back then [ ms 3.0; ms 3.0 ] else [ ms 3.0; ms 30.0 ]) st) in
    let c = Clause14.check ~tick_ns r.runs in
    let got = Clause14.frames_of c in
    let caught = c.violations <> [] || got <> List.map (fun f -> f @ Eth_model.fcs_bytes f) [ List.nth frames 0; List.nth frames 2 ] in
    pr "  %-58s %s (%s)" name (if caught then "caught" else "MISSED")
      (match c.violations with v :: _ -> v | [] -> "frames differ") ; caught in
  let flip s = Array.mapi (fun t a -> if t = 2 then Array.mapi (fun i b -> if i = 30 then b lxor 4 else b) a else a) s in
  let swap_legs s = Array.map (Array.map (fun b ->
      let r = ref 0 in for i = 0 to 3 do
        let p0 = (b lsr (2 * i)) land 1 and p1 = (b lsr ((2 * i) + 1)) land 1 in
        r := !r lor (p1 lsl (2 * i)) lor (p0 lsl ((2 * i) + 1)) done; !r)) s in
  let cs = [
    control "TP_IDL of 4 half-bits instead of 6" ~tp_idl:4 ();
    control "link-pulse period 30 ms (nlp_outer 113)" ~p:{ Tx_fw.default with nlp_outer = 113 } ~cycles:(ms 100.0) ();
    control "link-pulse period 6 ms (nlp_outer 22)" ~p:{ Tx_fw.default with nlp_outer = 22 } ();
    control "link pulse lowered 3 slots late (14 clocks, 233 ns)" ~p:{ Tx_fw.default with nlp_width_slots = 3 } ();
    control "one TD+ bit flipped in thread 2's stream" ~mutate:flip ();
    control "thread 1 one slot late" ~late:1 ();
    control "inter-packet wait 110 slots instead of 113" ~p:{ Tx_fw.default with ipg_slots = 110 } ~back_to_back:true ();
    control "TD+ and TD- swapped in the streams" ~mutate:swap_legs ();
  ] in
  pr "controls: %d of %d caught" (List.length (List.filter Fun.id cs)) (List.length cs)

let () =
  let what = if Array.length Sys.argv > 1 then Sys.argv.(1) else "all" in
  if what = "tx" || what = "all" then tx ();
  if what = "crc" || what = "all" then ignore (Rx_tests.crc ());
  if what = "sampler" || what = "all" then ignore (Rx_tests.sampler ());
  if what = "rx" || what = "all" then ignore (Rx_tests.rx ());
  if what = "node" then begin
    pr "== node demo (node.ml): requests %s -> replies %s" Sys.argv.(2) Sys.argv.(3);
    let ok, _, _ = Node_demo.run ~requests:Sys.argv.(2) ~replies_out:Sys.argv.(3) () in
    pr "node (simulation side): %s" (verdict ok)
  end;
  if what = "emit" then begin
    let emit name c =
      let oc = open_out (Filename.concat "synth" (name ^ ".v")) in
      Hardcaml.Rtl.output ~output_mode:(To_channel oc) Verilog c; close_out oc; pr "wrote synth/%s.v" name in
    emit "edge_sampler1" (Edge_sampler.circuit ~n:1);
    emit "edge_sampler4" (Edge_sampler.circuit ~n:4);
    emit "crc_unit" (Crc_unit.circuit ());
    emit "systolic_matcher_en" (Matcher_en.circuit ());
    emit "eth_rx_path4" (Rx_path.circuit ~n:4 ~scfg:(Rx_path.eth_sampler_cfg ~clock_hz:60e6 ~n:4) ())
  end;
  if what = "node-busy" then begin
    pr "== node with requests %s us apart (faster than replies go out; in half duplex these would collide with the replies, the model ignores that)" Sys.argv.(4);
    let ok, _, _ = Node_demo.run ~subset:true ~gap_us:(float_of_string Sys.argv.(4)) ~tail_ms:1.0 ~requests:Sys.argv.(2) ~replies_out:Sys.argv.(3) () in
    pr "node-busy: %s" (verdict ok)
  end;
  if what = "node-controls" then begin
    let res = Node_demo.controls ~requests:Sys.argv.(2) ~dir:Sys.argv.(3) in
    List.iter (fun (name, ok, out) -> pr "control %-52s simulation-side checks %s; replies in %s" name (if ok then "pass" else "FAIL") out) res
  end
