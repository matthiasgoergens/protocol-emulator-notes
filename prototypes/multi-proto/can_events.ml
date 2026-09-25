(* Event generator for the CAN analyser, built against master's prototypes/sequencer-ps2-can
   (can_events.sh exports it with git archive into /var/tmp and builds this file there).

   The analyser's CAN front end is that branch's real RX thread (Can_fw.rx ~raw:true, interpreter
   and RTL in lockstep, Isa_v) listening on its bus model, with two of its reference nodes (A and B)
   transmitting: single frames, arbitration contests, and one frame broken by a 3 us dominant
   glitch, so that every node signals an error. The RX thread's tagged reports are logged as they
   come out, plus two probes an analyser would wire to the transceivers' TXD pins: the levels
   nodes A and B drive at each sampled bit, and a mark on the bit where one of them lost
   arbitration.

   Log lines (time in fs, the branch's kernel):
     B t level ta tb mark    one per sampled bit (RAW or STUFF report); mark: 1 stuff, 2 lost
     F t tag value           SOF, DATA, CRC, ACK, END reports (tags as Can_fw)
   The analyser's field ticks (at 17 x fsc) are kept clear of traffic, as in cantv.ml. *)

let fclk_tv = 17. *. 315e6 /. 88.
let tick_fs f =
  let cyc = 1 + (4 * ((967 * ((262 * f) + 21)) + 172)) + 1 in
  int_of_float (float cyc /. fclk_tv *. 1e15)
let field_fs = int_of_float (4. *. 967. *. 262. /. fclk_tv *. 1e15)

let ids = [| 0x0A5; 0x1B2; 0x23C; 0x341; 0x4F0; 0x512; 0x6AA; 0x7C3 |]

let () =
  let out = try Sys.argv.(1) with _ -> "can_events.log" in
  let seed = try int_of_string Sys.argv.(2) with _ -> 3 in
  let with_glitch = (try Sys.argv.(3) with _ -> "glitch") = "glitch" in
  let rnd = Random.State.make [| seed |] in
  let t = Can_bench.timing_500k in
  let tr = { t with Can_fw.sp = t.sp - 1 } in                    (* raw mode samples one slot earlier *)
  let bus = Can_model.Bus.create [| Sim.ns 50.; Sim.ns 80.; Sim.ns 40.; Sim.ns 10. |] in
  let an = Can_bench.make_node ~name:"analyser" ~pins:Can_bench.pins_a ~bus_idx:2 in
  let rx_prog, rx_len, _ = Can_fw.rx ~raw:true Can_bench.pins_a tr in
  (* listen-only apart from the RX thread's ACK and error flags: thread 1 only holds TXD recessive
     (without it TXD resets to 0 and the node would hold the bus dominant for ever) *)
  let txd_idle = Array.make Isa_v.prog_len Isa_v.halt in
  txd_idle.(0) <- Isa_v.setp ~mask:(1 lsl Can_bench.pins_a.txd) ~value:1 ~oe:1;
  let s = Can_bench.seq_agent ~rtl:true ~bus ~hz:Can_bench.clock_hz ~name:"analyser" [ (0, 1, an, None) ] [ 0, rx_prog; 1, txd_idle ] in
  let ra = Can_model.create ~bus ~idx:0 ~name:"A" () and rb = Can_model.create ~bus ~idx:1 ~name:"B" () in
  (* the traffic plan: (time, A's frame option, B's frame option) *)
  let fr id dlc = { Can_model.id; rtr = false; dlc; data = List.init dlc (fun _ -> Random.State.int rnd 256) } in
  let quiet_from = (2 * field_fs) - Sim.us 700. in
  let plan = ref [] and tt = ref (Sim.us 300.) and k = ref 0 and glitch_at = ref 0 in
  while !tt < quiet_from - Sim.us 900. do
    let near = List.exists (fun f -> !tt > tick_fs f - Sim.us 600. && !tt < tick_fs f + Sim.us 40.) [ 0; 1; 2 ] in
    if near then tt := !tt + Sim.us 60.
    else begin
      let pick () = let r = Random.State.int rnd 36 in let rec go s acc = if r < acc + (8 - s) then s else go (s + 1) (acc + 8 - s) in go 0 0 in
      let a, b =
        if !k mod 7 = 3 then Some (fr ids.(1) (Random.State.int rnd 9)), Some (fr ids.(2) (Random.State.int rnd 9))
        else if Random.State.bool rnd then Some (fr ids.(pick ()) (Random.State.int rnd 9)), None
        else None, Some (fr ids.(pick ()) (Random.State.int rnd 9)) in
      if !k = 23 && with_glitch then glitch_at := !tt + Sim.us 60.;
      plan := (!tt, a, b) :: !plan;
      tt := !tt + Sim.us (330. +. Random.State.float rnd 300.);
      incr k
    end
  done;
  (* the last transmission: a short contest, all of it inside the 64-bit waveform *)
  plan := (quiet_from - Sim.us 400., Some (fr ids.(1) 0), Some (fr ids.(2) 0)) :: !plan;
  let plan = ref (List.rev !plan) in
  let oc = open_out out in
  (* the arbitration mark comes from the probes alone: a node that drove the SOF dominant and then
     sends recessive while the bus is dominant, outside a stuff bit, lost here *)
  let act_a = ref false and act_b = ref false and first = ref true in
  let prev_raw = ref 0 and prev_frames = ref 0 in
  let feed = Sim.agent ~name:"feed" ~hz:1e6 (fun now ->
    (match !plan with
     | (t0, a, b) :: rest when now >= t0 ->
       (match a with Some f -> ra.queue <- ra.queue @ [ f ] | None -> ());
       (match b with Some f -> rb.queue <- rb.queue @ [ f ] | None -> ());
       plan := rest
     | _ -> ());
    (* the glitch: a fourth attachment pulls the bus dominant for 3 us *)
    Can_model.Bus.drive bus 3 ~now (if !glitch_at > 0 && now >= !glitch_at && now < !glitch_at + Sim.us 3. then 0 else 1)) in
  (* the logger: the RX thread's reports, read from the node's decoded state as they arrive *)
  let log = Sim.agent ~name:"log" ~hz:Can_bench.clock_hz (fun now ->
    let cur = match an.rx.cur with Some c -> c | None -> { Can_bench.at = 0; frame = None; crc_ok = None; ack_level = None; end_code = None; raw = [] } in
    let nraw = List.length cur.raw in
    if nraw > !prev_raw then begin
      let v = List.nth cur.raw (nraw - 1) in
      let lvl = Can_model.Bus.rx bus 2 ~now in
      let ta = Can_model.Bus.level_at bus.hist.(0) now and tb = Can_model.Bus.level_at bus.hist.(1) now in
      let l = if v = 2 then lvl else v in
      if !first then (act_a := ta = 0; act_b := tb = 0; first := false);
      let lost = v <> 2 && ((!act_a && ta = 1 && l = 0) || (!act_b && tb = 1 && l = 0)) in
      if !act_a && ta = 1 && l = 0 then act_a := false;
      if !act_b && tb = 1 && l = 0 then act_b := false;
      let mark = if v = 2 then 1 else if lost then 2 else 0 in
      Printf.fprintf oc "B %d %d %d %d %d\n" now (if v = 2 then lvl else v) ta tb mark
    end;
    prev_raw := nraw;
    ignore prev_frames) in
  (* frame reports: wrap rx_event so that each report is also logged *)
  let n_rep = ref 0 in
  let orig = an.rx in
  ignore orig;
  let agents = [ s.agent; Can_bench.ref_agent ~ppm:1500. ra; Can_bench.ref_agent ~ppm:(-1200.) rb; feed; log ] in
  (* the RX thread's host_out is decoded by Can_bench into an.rx; we log the tagged reports by
     watching the decoded state change, which loses nothing: SOF opens a record, DATA appends a
     byte, CRC/ACK/END fill fields *)
  let last_nbytes = ref 0 and last_cur = ref None and last_nframes = ref 0 in
  let watch = Sim.agent ~name:"watch" ~hz:Can_bench.clock_hz (fun now ->
    let nfr = List.length an.rx.frames in
    (match an.rx.cur, !last_cur with
     | Some c, None -> Printf.fprintf oc "F %d %d 0\n" now Can_fw.tag_sof; incr n_rep; last_nbytes := 0; prev_raw := List.length c.raw; first := true
     | Some c, Some p when c.at <> p.Can_bench.at -> Printf.fprintf oc "F %d %d 0\n" now Can_fw.tag_sof; incr n_rep; last_nbytes := 0; prev_raw := List.length c.raw; first := true
     | _ -> ());
    let nb = List.length an.rx.bytes in
    if nb > !last_nbytes && an.rx.cur <> None then begin
      List.iteri (fun i v -> if i >= !last_nbytes then Printf.fprintf oc "F %d %d %d\n" now Can_fw.tag_data v) an.rx.bytes;
      last_nbytes := nb
    end;
    if nfr > !last_nframes then begin
      (match an.rx.frames with
       | c :: _ -> Printf.fprintf oc "F %d %d %d\n" now Can_fw.tag_end (Option.value c.end_code ~default:9)
       | [] -> ());
      last_nframes := nfr
    end;
    last_cur := an.rx.cur) in
  ignore (Sim.run ~until:(2 * field_fs) (agents @ [ watch ]));
  close_out oc;
  let frames = Can_bench.frames_of an in
  let ok = List.length (List.filter (fun r -> r.Can_bench.end_code = Some 0) frames) in
  let errs = List.length (List.filter (fun r -> match r.Can_bench.end_code with Some c -> c <> 0 | None -> false) frames) in
  Printf.printf "ref A sent %d, errors %d; ref B sent %d, errors %d; frames left in queues %d\n"
    (List.length ra.sent) (List.length ra.errors) (List.length rb.sent) (List.length rb.errors) (List.length ra.queue + List.length rb.queue);
  Printf.printf "RX thread (%d words, raw mode, SP %d): %d frame records, %d ok, %d with an error end code; A lost %d, B lost %d \
                 arbitration; RTL/interpreter mismatches %d\n"
    rx_len tr.sp (List.length frames) ok errs ra.lost rb.lost s.m.mismatches
