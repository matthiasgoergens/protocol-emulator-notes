(* CAN checks: our nodes against a reference node on a bus with delays and oscillator offsets. *)
open Can_bench

let us = Sim.us
let pp_frames fs = String.concat ", " (List.map Can_model.pp_frame fs)

let () =
  let t = timing_500k in
  let rxp, rxl, _ = Can_fw.rx pins_a t and txp, txl, _ = Can_fw.tx pins_a t in
  Printf.printf "CAN firmware at N=%d SP=%d SJW=%d slots: RX thread %d words, TX thread %d words\n" t.n t.sp t.sjw rxl txl;
  ignore rxp; ignore txp;
  (* smoke: A sends one frame; B and the reference node receive *)
  let bus = Can_model.Bus.create [| Sim.ns 50.; Sim.ns 80.; Sim.ns 30. |] in
  let a = make_node ~name:"A" ~pins:pins_a ~bus_idx:0 and b = make_node ~name:"B" ~pins:pins_b ~bus_idx:1 in
  let s = make_seq ~bus ~hz:clock_hz ~name:"seq" ~a ~b () in
  let r = Can_model.create ~bus ~idx:2 () in
  let f = { Can_model.id = 0x123; rtr = false; dlc = 3; data = [ 0xDE; 0xAD; 0xBE ] } in
  submit a ~at:(us 40.) [ f ];
  ignore (Sim.run ~until:(us 400.) [ s.agent; ref_agent ~ppm:2000. r ]);
  Printf.printf "A tx: %s\n" (String.concat "," (List.map (fun (_, f, v) -> Printf.sprintf "%s:%d" (Can_model.pp_frame f) v) a.tx_status));
  Printf.printf "B rx: %s\n" (String.concat "; " (List.map (fun rf ->
      Printf.sprintf "%s crc=%s ack=%s end=%s" (match rf.frame with Some f -> Can_model.pp_frame f | None -> "?")
        (match rf.crc_ok with Some b -> string_of_bool b | None -> "-") (match rf.ack_level with Some l -> string_of_int l | None -> "-")
        (match rf.end_code with Some c -> string_of_int c | None -> "-")) (frames_of b)));
  Printf.printf "A rx: %d frames, good %s\n" (List.length (frames_of a)) (pp_frames (good_frames a));
  Printf.printf "ref rx: %s; errors %s\n" (String.concat ", " (List.map (fun (_, f, ok, _) -> Can_model.pp_frame f ^ if ok then "" else "!") r.received))
    (String.concat "," (List.map (fun (_, e) -> Can_model.pp_err e) r.errors));
  Printf.printf "lockstep mismatches %d over %d cycles\n" s.m.mismatches s.m.cycle
