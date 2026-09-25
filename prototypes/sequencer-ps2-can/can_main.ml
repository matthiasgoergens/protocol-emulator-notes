(* CAN checks: our nodes against reference nodes on a bus with propagation delays and oscillator
   offsets; arbitration between our nodes; controls that must fail; constrained random runs. *)
open Can_bench

let us = Sim.us
let pp_frames fs = String.concat ", " (List.map Can_model.pp_frame fs)
let fails = ref 0
let total_cycles = ref 0 and total_mismatch = ref 0 and total_frames = ref 0

(* A participant: one of our nodes, or a reference node. *)
type part = Ours of node | Ref of Can_model.t

let name_of = function Ours n -> n.name | Ref r -> r.Can_model.name

(* what a participant received correctly, not counting its own frames *)
let received_by = function
  | Ours n -> List.filter_map (fun r -> match r.frame, r.end_code, r.ack_level with
      | Some f, Some 0, _ -> Some f | _ -> None) (frames_of n)
  | Ref r -> List.rev (List.filter_map (fun (_, f, ok, own) -> if ok && not own then Some f else None) r.received)

let own_sent = function
  | Ours n -> acked n
  | Ref r -> List.rev_map snd r.sent

(* Every frame a participant sent must have been received exactly once by every other one,
   nothing else may have been received, and no errors may have been reported. *)
let check_delivery ~submitted =
  let problems = ref [] in
  let add s = problems := s :: !problems in
  List.iter (fun (p, subs) ->
    let sent = own_sent p in
    if List.sort compare sent <> List.sort compare subs then
      add (Printf.sprintf "%s sent [%s], submitted [%s]" (name_of p) (pp_frames sent) (pp_frames subs))) submitted;
  List.iter (fun (p, own) ->
    let expect = List.concat_map (fun (q, subs) -> if q == p then [] else subs) submitted in
    let got = List.filter (fun f -> not (List.mem f own)) (received_by p) in
    if List.sort compare got <> List.sort compare expect then
      add (Printf.sprintf "%s received [%s], expected [%s]" (name_of p) (pp_frames got) (pp_frames expect));
    (match p with
     | Ours n ->
       let errs = List.filter (fun r -> match r.end_code with Some 0 | None -> false | Some _ -> true) (frames_of n) in
       if errs <> [] then add (Printf.sprintf "%s reported %d error frames (codes %s)" n.name (List.length errs)
                                (String.concat "," (List.map (fun r -> match r.end_code with Some c -> string_of_int c | None -> "-") errs)))
     | Ref r -> if r.errors <> [] then add (Printf.sprintf "%s saw errors: %s" r.name
                                              (String.concat "," (List.map (fun (_, e) -> Can_model.pp_err e) r.errors))))) submitted;
  List.rev !problems

let result name problems seqs =
  let mism = List.fold_left (fun a s -> a + s.m.Sim.Machine.mismatches) 0 seqs in
  let cyc = List.fold_left (fun a s -> a + s.m.Sim.Machine.cycle) 0 seqs in
  total_cycles := !total_cycles + cyc; total_mismatch := !total_mismatch + mism;
  let problems = problems @ List.filter_map (fun s -> Option.map (fun x -> "lockstep: " ^ x) s.m.Sim.Machine.first) seqs in
  let ok = problems = [] in
  if not ok then incr fails;
  Printf.printf "  %-66s %s (%d cycles, %d mismatches)%s\n" name (if ok then "PASS" else "FAIL") cyc mism
    (if ok then "" else "\n      " ^ String.concat "\n      " problems);
  ok

(* order in which frames went on the bus, as the reference node saw them *)
let bus_order r = List.rev_map (fun (_, f, _, _) -> f) r.Can_model.received

let fr id dlc = { Can_model.id; rtr = false; dlc; data = List.init (min dlc 8) (fun i -> (id * 7 + i * 29) land 0xFF) }

let () =
  let t = timing_500k in
  let _, rxl, _ = Can_fw.rx pins_a t and _, txl, _ = Can_fw.tx pins_a t in
  Printf.printf "CAN firmware, 500 kbit/s at 60 MHz (N=%d SP=%d SJW=%d slots): RX thread %d words, TX thread %d words\n"
    t.n t.sp t.sjw rxl txl;
  print_endline "Scenarios:";
  (* S1: two nodes on one sequencer and a reference node; A and B start together, B has the
     lower identifier and must win; A retransmits; then the reference node sends a remote frame *)
  begin
    let bus = Can_model.Bus.create [| Sim.ns 60.; Sim.ns 90.; Sim.ns 40. |] in
    let a = make_node ~name:"A" ~pins:pins_a ~bus_idx:0 and b = make_node ~name:"B" ~pins:pins_b ~bus_idx:1 in
    let s = make_seq ~bus ~hz:clock_hz ~name:"seq" ~a ~b () in
    let r = Can_model.create ~bus ~idx:2 () in
    let fa = fr 0x123 3 and fb = fr 0x0F0 8 and fr_ = { Can_model.id = 0x7FF; rtr = true; dlc = 2; data = [] } in
    submit a ~at:(us 40.) [ fa ]; submit b ~at:(us 40.) [ fb ];
    r.queue <- [];
    let ra = ref_agent ~ppm:3000. r in
    let inject = Sim.agent ~name:"inj" ~hz:1e5 (fun now -> if now >= us 300. && now < us 310. then r.queue <- [ fr_ ]) in
    ignore (Sim.run ~until:(us 900.) [ s.agent; ra; inject ]);
    let order = bus_order r in
    total_frames := !total_frames + List.length order;
    let p = check_delivery ~submitted:[ Ours a, [ fa ]; Ours b, [ fb ]; Ref r, [ fr_ ] ] in
    let p = p @ (if List.map (fun (f : Can_model.frame) -> f.id) order = [ 0x0F0; 0x123; 0x7FF ] then []
                 else [ "bus order " ^ pp_frames order ]) in
    let lost = List.length (List.filter (fun (_, _, v) -> v = 3) a.tx_status) in
    let p = p @ (if lost = 1 then [] else [ Printf.sprintf "A lost arbitration %d times" lost ]) in
    ignore (result "one sequencer, nodes A (0x123) and B (0x0F0) start together, ref +0.3%" p [ s ]);
    Printf.printf "      bus order: %s; A lost arbitration %d time(s) and retransmitted\n" (pp_frames order) lost
  end;
  (* S2: two sequencer instances at +0.5 % and -0.5 %, reference at +0.2 %; three-way arbitration
     on identifiers that differ only in the last bits *)
  begin
    let bus = Can_model.Bus.create [| Sim.ns 30.; Sim.ns 120.; Sim.ns 70. |] in
    let a = make_node ~name:"A" ~pins:pins_a ~bus_idx:0 and b = make_node ~name:"B" ~pins:pins_a ~bus_idx:1 in
    let s1 = make_seq ~bus ~hz:(clock_hz *. 1.005) ~name:"seq1" ~a () in
    let s2 = make_seq ~bus ~hz:(clock_hz *. 0.995) ~name:"seq2" ~a:b () in
    let r = Can_model.create ~bus ~idx:2 () in
    let fa = fr 0x3A5 8 and fb = fr 0x3A6 5 and fr_ = fr 0x3A4 1 in
    submit a ~at:(us 30.) [ fa ]; submit b ~at:(us 30.) [ fb ];
    let inject = Sim.agent ~name:"inj" ~hz:1e5 (fun now -> if now >= us 10. && now < us 20. then r.queue <- [ fr_ ]) in
    ignore (Sim.run ~until:(us 1000.) [ s1.agent; s2.agent; ref_agent ~ppm:2000. r; inject ]);
    let order = bus_order r in
    total_frames := !total_frames + List.length order;
    let p = check_delivery ~submitted:[ Ours a, [ fa ]; Ours b, [ fb ]; Ref r, [ fr_ ] ] in
    let ids = List.map (fun (f : Can_model.frame) -> f.id) order in
    let p = p @ (if ids = [ 0x3A4; 0x3A5; 0x3A6 ] then [] else [ "bus order " ^ pp_frames order ]) in
    ignore (result "two sequencers at +0.5% / -0.5%, ref +0.2%, 3-way arbitration" p [ s1; s2 ]);
    Printf.printf "      bus order: %s (ids 3A4 < 3A5 < 3A6)\n" (String.concat " " (List.map (Printf.sprintf "%03X") ids))
  end;
  (* ---- controls *)
  print_endline "Controls (each must be caught):";
  let caught name ok = Printf.printf "  %-78s %s\n" name (if ok then "caught" else "MISSED"); if not ok then incr fails in
  let control ?(faults_b = Can_fw.no_faults) ?(faults_a = Can_fw.no_faults) ?(ppm_seq = 0.) ?(ppm_ref = 0.) ?stream_a ~fa ?fref () =
    let bus = Can_model.Bus.create [| Sim.ns 50.; Sim.ns 80.; Sim.ns 40. |] in
    let a = make_node ~name:"A" ~pins:pins_a ~bus_idx:0 and b = make_node ~name:"B" ~pins:pins_b ~bus_idx:1 in
    let s = seq_agent ~bus ~hz:(clock_hz *. (1. +. ppm_seq /. 1e6)) ~name:"seq"
        [ (0, 1, a, None); (2, 3, b, None) ]
        [ 0, (let p, _, _ = Can_fw.rx ~faults:faults_a pins_a t in p); 1, (let p, _, _ = Can_fw.tx ~faults:faults_a pins_a t in p);
          2, (let p, _, _ = Can_fw.rx ~faults:faults_b pins_b t in p); 3, (let p, _, _ = Can_fw.tx ~faults:faults_b pins_b t in p) ] in
    let r = Can_model.create ~bus ~idx:2 () in
    (match fa with Some f -> submit a ~at:(us 30.) ?stream:stream_a [ f ] | None -> ());
    (match fref with Some f -> r.queue <- [ f ] | None -> ());
    ignore (Sim.run ~until:(us 700.) [ s.agent; ref_agent ~ppm:ppm_ref r ]);
    a.queue <- [];
    total_cycles := !total_cycles + s.m.cycle; total_mismatch := !total_mismatch + s.m.mismatches;
    a, b, r, s in
  let codes nd = List.filter_map (fun r -> r.end_code) (frames_of nd) in
  let f8 = { Can_model.id = 0x000; rtr = false; dlc = 8; data = [ 0; 0; 0xFF; 0xFF; 0; 0; 0xFF; 0xFF ] } in
  (* 1. a missing stuff bit: A drops the first stuff bit of its stream *)
  let a, b, r, _ = control ~fa:(Some f8) ~stream_a:(fun f -> Can_fw.tx_bytes ~drop_stuff:0 { Can_fw.id = f.Can_model.id; rtr = f.rtr; dlc = f.dlc; data = f.data }) () in
  caught (Printf.sprintf "A's stream missing its first stuff bit: B end codes [%s], ref errors [%s], A tx [%s]"
            (String.concat "," (List.map string_of_int (codes b))) (String.concat "," (List.map (fun (_, e) -> Can_model.pp_err e) r.errors))
            (String.concat "," (List.map (fun (_, _, v) -> string_of_int v) a.tx_status)))
    (List.mem 1 (codes b) && List.exists (fun (_, e) -> e = Can_model.Stuff) r.errors && good_frames b = []);
  (* 2. a wrong CRC: the last CRC bit flipped *)
  let f3 = fr 0x456 3 in
  let a, b, r, _ = control ~fa:(Some f3) ~stream_a:(fun f -> Can_fw.tx_bytes ~flip_crc:true { Can_fw.id = f.Can_model.id; rtr = f.rtr; dlc = f.dlc; data = f.data }) () in
  caught (Printf.sprintf "A's CRC with its last bit flipped: B end codes [%s], ref errors [%s], A tx [%s]"
            (String.concat "," (List.map string_of_int (codes b))) (String.concat "," (List.map (fun (_, e) -> Can_model.pp_err e) r.errors))
            (String.concat "," (List.map (fun (_, _, v) -> string_of_int v) a.tx_status)))
    (List.mem 2 (codes b) && List.exists (fun (_, e) -> e = Can_model.Crc) r.errors && good_frames b = []);
  (* 3. skipped resynchronisation: B without resync, reference transmitting at +0.5 %, our clock -0.5 % *)
  let long = { Can_model.id = 0x001; rtr = false; dlc = 8; data = [ 0xFF; 0xFF; 0xFF; 0x7F; 0xFF; 0xFF; 0xFF; 0xFE ] } in
  let _, b, r, _ = control ~faults_b:{ Can_fw.no_faults with no_resync = true } ~ppm_seq:(-5000.) ~ppm_ref:5000. ~fa:None ~fref:long () in
  let _, b_ok, _, _ = control ~ppm_seq:(-5000.) ~ppm_ref:5000. ~fa:None ~fref:long () in
  caught (Printf.sprintf "B without resync, clocks 1%% apart: B good frames %d (codes [%s]); with resync %d; ref errors [%s]"
            (List.length (good_frames b)) (String.concat "," (List.map string_of_int (codes b)))
            (List.length (good_frames b_ok)) (String.concat "," (List.map (fun (_, e) -> Can_model.pp_err e) r.errors)))
    (good_frames b = [] && good_frames b_ok = [ long ]);
  (* 4. the wrong CRC polynomial in B's firmware *)
  let _, b, _, _ = control ~faults_b:{ Can_fw.no_faults with bad_poly = true } ~fa:(Some f3) () in
  caught (Printf.sprintf "B with CRC polynomial 0x4599 xor 1: B end codes [%s]" (String.concat "," (List.map string_of_int (codes b))))
    (List.mem 2 (codes b) && good_frames b = []);
  (* 5. no arbitration check: A and B both transmit at once and neither backs off *)
  begin
    let bus = Can_model.Bus.create [| Sim.ns 50.; Sim.ns 80.; Sim.ns 40. |] in
    let a = make_node ~name:"A" ~pins:pins_a ~bus_idx:0 and b = make_node ~name:"B" ~pins:pins_b ~bus_idx:1 in
    let s = make_seq ~faults:{ Can_fw.no_faults with no_arbitration_check = true } ~bus ~hz:clock_hz ~name:"seq" ~a ~b () in
    let r = Can_model.create ~bus ~idx:2 () in
    submit a ~at:(us 30.) [ fr 0x123 2 ]; submit b ~at:(us 30.) [ fr 0x0F0 2 ];
    ignore (Sim.run ~until:(us 300.) [ s.agent; ref_agent r ]);
    total_cycles := !total_cycles + s.m.cycle; total_mismatch := !total_mismatch + s.m.mismatches;
    caught (Printf.sprintf "no arbitration check, A and B start together: ref errors [%s], ref good frames %d"
              (String.concat "," (List.map (fun (_, e) -> Can_model.pp_err e) r.errors)) (List.length (received_by (Ref r))))
      (r.errors <> [] && List.length (List.filter (fun (_, _, ok, _) -> ok) r.received) = 0)
  end;
  (* ---- constrained random *)
  let n = try int_of_string Sys.argv.(1) with _ -> 20 in
  Printf.printf "Constrained random (%d runs): two sequencer instances (1 or 2 nodes each) and a reference node,\n\
                \  clocks within +-0.5 %%, delays 10-150 ns, random frames, often submitted simultaneously:\n" n;
  let contests = ref 0 and passed = ref 0 in
  for seed = 1 to n do
    Random.init (7000 + seed);
    let ppm () = Random.float 10000. -. 5000. in
    let nb2 = Random.bool () in
    let delays = Array.init 4 (fun _ -> Sim.ns (10. +. Random.float 140.)) in
    let bus = Can_model.Bus.create delays in
    let a = make_node ~name:"A" ~pins:pins_a ~bus_idx:0 and c = make_node ~name:"C" ~pins:pins_a ~bus_idx:2 in
    let b = make_node ~name:"B" ~pins:pins_b ~bus_idx:1 in
    let p1 = ppm () and p2 = ppm () and pr = ppm () in
    let s1 = if nb2 then make_seq ~bus ~hz:(clock_hz *. (1. +. p1 /. 1e6)) ~name:"seq1" ~a ~b ()
      else make_seq ~bus ~hz:(clock_hz *. (1. +. p1 /. 1e6)) ~name:"seq1" ~a () in
    let s2 = make_seq ~bus ~hz:(clock_hz *. (1. +. p2 /. 1e6)) ~name:"seq2" ~a:c () in
    let r = Can_model.create ~bus ~idx:3 () in
    let used = Hashtbl.create 16 in
    let rand_frame () =
      let rec id () = let i = Random.int 0x800 in if Hashtbl.mem used i then id () else (Hashtbl.add used i (); i) in
      let rtr = Random.int 8 = 0 in
      let dlc = Random.int 9 in
      { Can_model.id = id (); rtr; dlc; data = (if rtr then [] else List.init dlc (fun _ -> Random.int 256)) } in
    let simultaneous = Random.bool () in
    let t0 = us (30. +. Random.float 50.) in
    let plan nd = let k = 1 + Random.int 2 in
      let fs = List.init k (fun _ -> rand_frame ()) in
      let at = if simultaneous then t0 else us (30. +. Random.float 600.) in
      submit nd ~at fs; fs in
    let fa = plan a and fc = plan c in
    let fb = if nb2 then plan b else [] in
    let fref = [ rand_frame () ] in
    let ref_at = if simultaneous then t0 else us (30. +. Random.float 600.) in
    let inject = Sim.agent ~name:"inj" ~hz:1e6 (fun now -> if now >= ref_at && now < ref_at + us 1.5 && r.queue = [] && r.sent = [] then r.queue <- fref) in
    let nframes = List.length fa + List.length fb + List.length fc + 1 in
    let parts = [ Ours a, fa; Ours c, fc; Ref r, fref ] @ (if nb2 then [ Ours b, fb ] else []) in
    let stop () = List.length r.received >= nframes && a.queue = [] && c.queue = [] && b.queue = [] in
    let agents = [ s1.agent; s2.agent; ref_agent ~ppm:pr r; inject ] in
    let t_stop = Sim.run ~stop ~until:(us (1000. +. 400. *. float nframes)) agents in
    (* let the last frame's EOF and END reports finish everywhere *)
    ignore (Sim.run ~until:(t_stop + us 100.) agents);
    let lost = List.length (List.filter (fun (_, _, v) -> v = 3) (a.tx_status @ b.tx_status @ c.tx_status)) + r.lost in
    contests := !contests + lost;
    total_frames := !total_frames + List.length r.received;
    let p = check_delivery ~submitted:parts in
    let ok = result (Printf.sprintf "seed %2d: %d frames, %s, clocks %+.0f/%+.0f/%+.0f ppm, %d lost arbitrations" seed nframes
                       (if simultaneous then "simultaneous" else "spread") p1 p2 pr lost) p ([ s1; s2 ]) in
    if ok then incr passed
  done;
  Printf.printf "random: %d of %d runs pass; %d arbitration losses resolved\n" !passed n !contests;
  Printf.printf "totals: %d frames on the bus, %d cycles compared in lockstep, %d mismatches\n" !total_frames !total_cycles !total_mismatch;
  print_endline (if !fails = 0 then "CAN: ALL PASS" else Printf.sprintf "CAN: %d FAILURES" !fails);
  exit (if !fails = 0 then 0 else 1)
