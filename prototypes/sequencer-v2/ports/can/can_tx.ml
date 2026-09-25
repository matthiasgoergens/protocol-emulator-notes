(* CAN transmit on ISA v2: the TX thread of ../../../sequencer-ps2-can (re-assembled, can_fw.ml)
   against the reference CAN nodes of can_model.ml on the wired-AND bus of can_bench.ml, with
   interpreter and v2 RTL in lockstep (Sim.Machine). Our nodes transmit only: the RX thread is not
   ported (can_fw.ml says why), its slot holds txe recessive, and the reference nodes are the
   receivers that check every frame and acknowledge it.

   The checks mirror can_main.ml's where they do not need our receiver: delivery of every frame
   exactly once to every reference node, arbitration order and retransmission, "no ACK" status,
   clocks and delays; the controls that break the transmitter (a stuff bit missing, a CRC bit
   flipped, no arbitration check) must be caught by the reference nodes; constrained random runs. *)
open Can_bench

let us = Sim.us
let pp_frames fs = String.concat ", " (List.map Can_model.pp_frame fs)
let fails = ref 0
let total_cycles = ref 0 and total_mismatch = ref 0 and total_frames = ref 0

let fr id dlc = { Can_model.id; rtr = false; dlc; data = List.init (min dlc 8) (fun i -> (id * 7 + i * 29) land 0xFF) }

(* a sequencer with TX-only nodes: (rx slot, tx slot, node) *)
let tx_seq ?(faults = Can_fw.no_faults) ~bus ~hz ~name nodes =
  let t = !timing in
  let mems = List.concat_map (fun (rt, tt, nd) ->
      [ rt, Can_fw.rx_idle nd.pins; tt, (let p, _, _ = Can_fw.tx ~faults nd.pins t in p) ]) nodes in
  seq_agent ~bus ~hz ~name (List.map (fun (rt, tt, nd) -> (rt, tt, nd, None)) nodes) mems

let ref_received r = List.rev (List.filter_map (fun (_, f, ok, own) -> if ok && not own then Some f else None) r.Can_model.received)
let bus_order r = List.rev_map (fun (_, f, _, _) -> f) r.Can_model.received

(* every frame submitted by anyone reaches every reference node except its sender exactly once;
   our nodes' frames are all acknowledged; no reference node saw an error *)
let check ~ours ~refs =
  let p = ref [] in
  let add s = p := s :: !p in
  List.iter (fun (nd, subs) ->
      let a = acked nd in
      if List.sort compare a <> List.sort compare subs then
        add (Printf.sprintf "%s acknowledged [%s], submitted [%s]" nd.name (pp_frames a) (pp_frames subs))) ours;
  List.iter (fun (r, _) ->
      let expect = List.concat_map snd ours @ List.concat_map (fun (q, s) -> if q == r then [] else s) refs in
      let got = ref_received r in
      if List.sort compare got <> List.sort compare expect then
        add (Printf.sprintf "%s received [%s], expected [%s]" r.Can_model.name (pp_frames got) (pp_frames expect));
      if r.errors <> [] then
        add (Printf.sprintf "%s saw errors: %s" r.name (String.concat "," (List.map (fun (_, e) -> Can_model.pp_err e) r.errors))))
    refs;
  List.rev !p

let result name problems seqs =
  let mism = List.fold_left (fun a s -> a + s.m.Sim.Machine.mismatches) 0 seqs in
  let cyc = List.fold_left (fun a s -> a + s.m.Sim.Machine.cycle) 0 seqs in
  total_cycles := !total_cycles + cyc; total_mismatch := !total_mismatch + mism;
  let problems = problems @ List.filter_map (fun s -> Option.map (fun x -> "lockstep: " ^ x) s.m.Sim.Machine.first) seqs in
  let ok = problems = [] in
  if not ok then incr fails;
  Printf.printf "  %-70s %s (%d cycles, %d mismatches)%s\n%!" name (if ok then "PASS" else "FAIL") cyc mism
    (if ok then "" else "\n      " ^ String.concat "\n      " problems);
  ok

let statuses nd = List.rev_map (fun (_, _, v) -> v) nd.tx_status

let () =
  let t = !timing in
  let _, txl, _ = Can_fw.tx pins_a t in
  Printf.printf "CAN TX on v2, %.0f kbit/s at 60 MHz (N=%d SP=%d SJW=%d slots): TX thread %d words\n%!"
    (bit_rate () /. 1e3) t.n t.sp t.sjw txl;
  print_endline "Scenarios:";
  (* T1: one node sends three frames (one remote) to two reference nodes on other clocks *)
  begin
    let bus = Can_model.Bus.create [| Sim.ns 60.; Sim.ns 90.; Sim.ns 40. |] in
    let a = make_node ~name:"A" ~pins:pins_a ~bus_idx:0 in
    let s = tx_seq ~bus ~hz:clock_hz ~name:"seq" [ (0, 1, a) ] in
    let r1 = Can_model.create ~bus ~idx:1 ~name:"ref1" () and r2 = Can_model.create ~bus ~idx:2 ~name:"ref2" () in
    let fs = [ fr 0x123 3; { Can_model.id = 0x7FF; rtr = true; dlc = 2; data = [] }; fr 0x000 8 ] in
    submit a ~at:(us 40.) fs;
    ignore (Sim.run ~until:(us 1200.) [ s.agent; ref_agent ~ppm:3000. r1; ref_agent ~ppm:(-2000.) r2 ]);
    total_frames := !total_frames + List.length (bus_order r1);
    ignore (result "A sends 3 frames (one remote) to two reference nodes at +0.3% / -0.2%"
              (check ~ours:[ a, fs ] ~refs:[ r1, []; r2, [] ]) [ s ])
  end;
  (* T2: A (0x123) against a reference node (0x0F0) starting together: A loses, retransmits *)
  begin
    let bus = Can_model.Bus.create [| Sim.ns 60.; Sim.ns 90.; Sim.ns 40. |] in
    let a = make_node ~name:"A" ~pins:pins_a ~bus_idx:0 in
    let s = tx_seq ~bus ~hz:clock_hz ~name:"seq" [ (0, 1, a) ] in
    let r1 = Can_model.create ~bus ~idx:1 ~name:"ref1" () and r2 = Can_model.create ~bus ~idx:2 ~name:"ref2" () in
    let fa = fr 0x123 3 and fb = fr 0x0F0 8 in
    submit a ~at:(us 40.) [ fa ];
    let inject = Sim.agent ~name:"inj" ~hz:1e5 (fun now -> if now >= us 40. && now < us 50. && r1.sent = [] then r1.queue <- [ fb ]) in
    ignore (Sim.run ~until:(us 900.) [ s.agent; ref_agent ~ppm:3000. r1; ref_agent r2; inject ]);
    let order = List.map (fun (f : Can_model.frame) -> f.id) (bus_order r2) in
    total_frames := !total_frames + List.length order;
    let lost = List.length (List.filter (( = ) 3) (statuses a)) in
    let p = check ~ours:[ a, [ fa ] ] ~refs:[ r1, [ fb ]; r2, [] ]
            @ (if order = [ 0x0F0; 0x123 ] then [] else [ "bus order " ^ String.concat " " (List.map (Printf.sprintf "%03X") order) ])
            @ (if lost >= 1 then [] else [ "A never lost arbitration" ]) in
    ignore (result (Printf.sprintf "A (0x123) and ref1 (0x0F0) start together: A lost %d time(s), retransmitted" lost) p [ s ])
  end;
  (* T3: two of our nodes on one sequencer start together; B has the lower identifier *)
  begin
    let bus = Can_model.Bus.create [| Sim.ns 60.; Sim.ns 90.; Sim.ns 40. |] in
    let a = make_node ~name:"A" ~pins:pins_a ~bus_idx:0 and b = make_node ~name:"B" ~pins:pins_b ~bus_idx:1 in
    let s = tx_seq ~bus ~hz:clock_hz ~name:"seq" [ (0, 1, a); (2, 3, b) ] in
    let r = Can_model.create ~bus ~idx:2 () in
    let fa = fr 0x123 3 and fb = fr 0x0F0 8 in
    submit a ~at:(us 40.) [ fa ]; submit b ~at:(us 40.) [ fb ];
    ignore (Sim.run ~until:(us 900.) [ s.agent; ref_agent ~ppm:3000. r ]);
    let order = List.map (fun (f : Can_model.frame) -> f.id) (bus_order r) in
    total_frames := !total_frames + List.length order;
    let p = check ~ours:[ a, [ fa ]; b, [ fb ] ] ~refs:[ r, [] ]
            @ (if order = [ 0x0F0; 0x123 ] then [] else [ "bus order" ]) in
    ignore (result "one sequencer, nodes A (0x123) and B (0x0F0) start together, ref +0.3%" p [ s ])
  end;
  (* T4: two sequencers at +0.5 % / -0.5 % and two reference nodes; 3-way arbitration *)
  begin
    let bus = Can_model.Bus.create [| Sim.ns 30.; Sim.ns 120.; Sim.ns 70.; Sim.ns 50. |] in
    let a = make_node ~name:"A" ~pins:pins_a ~bus_idx:0 and b = make_node ~name:"B" ~pins:pins_a ~bus_idx:1 in
    let s1 = tx_seq ~bus ~hz:(clock_hz *. 1.005) ~name:"seq1" [ (0, 1, a) ] in
    let s2 = tx_seq ~bus ~hz:(clock_hz *. 0.995) ~name:"seq2" [ (0, 1, b) ] in
    let r1 = Can_model.create ~bus ~idx:2 ~name:"ref1" () and r2 = Can_model.create ~bus ~idx:3 ~name:"ref2" () in
    let fa = fr 0x3A5 8 and fb = fr 0x3A6 5 and fr_ = fr 0x3A4 1 in
    submit a ~at:(us 30.) [ fa ]; submit b ~at:(us 30.) [ fb ];
    let inject = Sim.agent ~name:"inj" ~hz:1e5 (fun now -> if now >= us 10. && now < us 20. && r1.sent = [] then r1.queue <- [ fr_ ]) in
    ignore (Sim.run ~until:(us 1000.) [ s1.agent; s2.agent; ref_agent ~ppm:2000. r1; ref_agent ~ppm:(-1000.) r2; inject ]);
    let ids = List.map (fun (f : Can_model.frame) -> f.id) (bus_order r2) in
    total_frames := !total_frames + List.length ids;
    let p = check ~ours:[ a, [ fa ]; b, [ fb ] ] ~refs:[ r1, [ fr_ ]; r2, [] ]
            @ (if ids = [ 0x3A4; 0x3A5; 0x3A6 ] then [] else [ "bus order " ^ String.concat " " (List.map (Printf.sprintf "%03X") ids) ]) in
    ignore (result "two sequencers at +0.5% / -0.5%, refs +0.2% / -0.1%, 3-way arbitration" p [ s1; s2 ])
  end;
  (* T5: no node acknowledges: every attempt ends "no ACK" (status 2) *)
  begin
    let bus = Can_model.Bus.create [| Sim.ns 50.; Sim.ns 40. |] in
    let a = make_node ~name:"A" ~pins:pins_a ~bus_idx:0 in
    let s = tx_seq ~bus ~hz:clock_hz ~name:"seq" [ (0, 1, a) ] in
    let r = Can_model.create ~bus ~idx:1 ~skip_ack:true () in
    submit a ~at:(us 30.) [ fr 0x155 2 ];
    ignore (Sim.run ~until:(us 400.) [ s.agent; ref_agent r ]);
    a.queue <- [];
    let st = statuses a in
    total_frames := !total_frames + List.length st;
    let p = if st <> [] && List.for_all (( = ) 2) st then [] else [ Printf.sprintf "A's TX statuses [%s]" (String.concat "," (List.map string_of_int st)) ] in
    ignore (result (Printf.sprintf "A alone, reference not acknowledging: %d attempts, all 'no ACK'" (List.length st)) p [ s ])
  end;
  print_endline "Controls (each must be caught by the reference nodes):";
  let caught name ok = Printf.printf "  %-84s %s\n%!" name (if ok then "caught" else "MISSED"); if not ok then incr fails in
  let control ?(faults = Can_fw.no_faults) ?stream ?(b_too = false) f =
    let bus = Can_model.Bus.create [| Sim.ns 50.; Sim.ns 80.; Sim.ns 40. |] in
    let a = make_node ~name:"A" ~pins:pins_a ~bus_idx:0 and b = make_node ~name:"B" ~pins:pins_b ~bus_idx:1 in
    let s = tx_seq ~faults ~bus ~hz:clock_hz ~name:"seq" [ (0, 1, a); (2, 3, b) ] in
    let r = Can_model.create ~bus ~idx:2 () in
    submit a ~at:(us 30.) ?stream [ f ];
    if b_too then submit b ~at:(us 30.) [ fr 0x0F0 2 ];
    ignore (Sim.run ~until:(us 500.) [ s.agent; ref_agent r ]);
    a.queue <- []; b.queue <- [];
    total_cycles := !total_cycles + s.m.cycle; total_mismatch := !total_mismatch + s.m.mismatches;
    a, r in
  let errs r = String.concat "," (List.map (fun (_, e) -> Can_model.pp_err e) r.Can_model.errors) in
  let enc ?drop_stuff ?flip_crc (f : Can_model.frame) =
    Can_fw.tx_bytes ?drop_stuff ?flip_crc { Can_fw.id = f.id; rtr = f.rtr; dlc = f.dlc; data = f.data } in
  let f8 = { Can_model.id = 0x000; rtr = false; dlc = 8; data = [ 0; 0; 0xFF; 0xFF; 0; 0; 0xFF; 0xFF ] } in
  let a, r = control ~stream:(enc ~drop_stuff:0) f8 in
  caught (Printf.sprintf "A's stream missing its first stuff bit: ref errors [%s], ref good frames %d, A tx [%s]"
            (errs r) (List.length (ref_received r)) (String.concat "," (List.map string_of_int (statuses a))))
    (List.exists (fun (_, e) -> e = Can_model.Stuff) r.errors && ref_received r = [] && not (List.mem 1 (statuses a)));
  let a, r = control ~stream:(enc ~flip_crc:true) (fr 0x456 3) in
  caught (Printf.sprintf "A's CRC with its last bit flipped: ref errors [%s], ref good frames %d, A tx [%s]"
            (errs r) (List.length (ref_received r)) (String.concat "," (List.map string_of_int (statuses a))))
    (List.exists (fun (_, e) -> e = Can_model.Crc) r.errors && ref_received r = [] && not (List.mem 1 (statuses a)));
  let _, r = control ~faults:{ Can_fw.no_faults with no_arbitration_check = true } ~b_too:true (fr 0x123 2) in
  caught (Printf.sprintf "no arbitration check, A and B start together: ref errors [%s], ref good frames %d"
            (errs r) (List.length (List.filter (fun (_, _, ok, _) -> ok) r.received)))
    (r.errors <> [] && List.length (List.filter (fun (_, _, ok, _) -> ok) r.received) = 0);
  (* constrained random, as can_main.ml's but with two reference nodes as the receivers *)
  let n = try int_of_string Sys.argv.(1) with _ -> 20 in
  Printf.printf "Constrained random (%d runs): two sequencer instances (1 or 2 TX nodes each) and two reference nodes,\n\
                \  clocks within +-0.5 %%, delays 10-150 ns, random frames, often submitted simultaneously:\n" n;
  let contests = ref 0 and passed = ref 0 in
  for seed = 1 to n do
    Random.init (7000 + seed);
    let ppm () = Random.float 10000. -. 5000. in
    let nb2 = Random.bool () in
    let delays = Array.init 5 (fun _ -> Sim.ns (10. +. Random.float 140.)) in
    let bus = Can_model.Bus.create delays in
    let a = make_node ~name:"A" ~pins:pins_a ~bus_idx:0 and c = make_node ~name:"C" ~pins:pins_a ~bus_idx:2 in
    let b = make_node ~name:"B" ~pins:pins_b ~bus_idx:1 in
    let p1 = ppm () and p2 = ppm () and pr = ppm () and pr2 = ppm () in
    let s1 = tx_seq ~bus ~hz:(clock_hz *. (1. +. p1 /. 1e6)) ~name:"seq1" ((0, 1, a) :: (if nb2 then [ (2, 3, b) ] else [])) in
    let s2 = tx_seq ~bus ~hz:(clock_hz *. (1. +. p2 /. 1e6)) ~name:"seq2" [ (0, 1, c) ] in
    let r = Can_model.create ~bus ~idx:3 ~name:"ref1" () and r2 = Can_model.create ~bus ~idx:4 ~name:"ref2" () in
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
    let stop () = List.length r2.received >= nframes && a.queue = [] && c.queue = [] && b.queue = [] in
    let agents = [ s1.agent; s2.agent; ref_agent ~ppm:pr r; ref_agent ~ppm:pr2 r2; inject ] in
    let t_stop = Sim.run ~stop ~until:(us (1000. +. 400. *. float nframes)) agents in
    ignore (Sim.run ~until:(t_stop + us 100.) agents);
    let lost = List.length (List.filter (fun (_, _, v) -> v = 3) (a.tx_status @ b.tx_status @ c.tx_status)) + r.lost + r2.lost in
    contests := !contests + lost;
    total_frames := !total_frames + List.length r2.received;
    let p = check ~ours:([ a, fa; c, fc ] @ (if nb2 then [ b, fb ] else [])) ~refs:[ r, fref; r2, [] ] in
    let ok = result (Printf.sprintf "seed %2d: %d frames, %s, clocks %+.0f/%+.0f/%+.0f/%+.0f ppm, %d lost arbitrations" seed nframes
                       (if simultaneous then "simultaneous" else "spread") p1 p2 pr pr2 lost) p [ s1; s2 ] in
    if ok then incr passed
  done;
  Printf.printf "random: %d of %d runs pass; %d arbitration losses resolved\n" !passed n !contests;
  Printf.printf "totals: %d frames on the bus, %d cycles compared in lockstep, %d mismatches\n" !total_frames !total_cycles !total_mismatch;
  print_endline (if !fails = 0 then "CAN TX: ALL PASS" else Printf.sprintf "CAN TX: %d FAILURES" !fails);
  exit (if !fails = 0 then 0 else 1)
