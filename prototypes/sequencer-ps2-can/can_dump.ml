(* [can_dump.exe DIR]: scenario S1 of can_main (our nodes A 0x123 and B 0x0F0 on one sequencer, interpreter and
   RTL in lockstep, B wins arbitration, A retransmits, then the reference node sends a remote frame),
   with the wired-AND bus level sampled at 20 MHz (40 samples per 500 kbit/s bit) as heard by the
   reference node. Writes DIR/can.bin (one byte per sample, bit 0 = bus) and DIR/can.expected, the frames
   in the order the reference node received them. For tools/sigrok-judge. *)
open Can_bench

let fr id dlc = { Can_model.id; rtr = false; dlc; data = List.init (min dlc 8) (fun i -> (id * 7 + i * 29) land 0xFF) }

let () =
  let dir = Sys.argv.(1) in
  let us = Sim.us in
  let bus = Can_model.Bus.create [| Sim.ns 60.; Sim.ns 90.; Sim.ns 40. |] in
  let a = make_node ~name:"A" ~pins:pins_a ~bus_idx:0 and b = make_node ~name:"B" ~pins:pins_b ~bus_idx:1 in
  let s = make_seq ~bus ~hz:clock_hz ~name:"seq" ~a ~b () in
  let r = Can_model.create ~bus ~idx:2 () in
  let fa = fr 0x123 3 and fb = fr 0x0F0 8 and fr_ = { Can_model.id = 0x7FF; rtr = true; dlc = 2; data = [] } in
  submit a ~at:(us 40.) [ fa ]; submit b ~at:(us 40.) [ fb ];
  let ra = ref_agent ~ppm:3000. r in
  let inject = Sim.agent ~name:"inj" ~hz:1e5 (fun now -> if now >= us 300. && now < us 310. then r.queue <- [ fr_ ]) in
  let buf = Buffer.create 65536 in
  let tap = Sim.agent ~name:"tap" ~hz:20e6 (fun now -> Buffer.add_char buf (Char.chr (Can_model.Bus.rx bus 2 ~now))) in
  ignore (Sim.run ~until:(us 900.) [ s.agent; ra; inject; tap ]);
  let order = List.rev_map (fun (_, f, _, _) -> f) r.Can_model.received in
  let oc = open_out_bin (Filename.concat dir "can.bin") in
  Buffer.output_buffer oc buf; close_out oc;
  let oc = open_out (Filename.concat dir "can.expected") in
  Printf.fprintf oc "# samplerate_hz_assumed 20000000\ncan_rx 0\ncan_bitrate 500000\n";
  List.iter (fun (f : Can_model.frame) ->
      Printf.fprintf oc "can_frame id=%d rtr=%d dlc=%d data=%s\n" f.id (Bool.to_int f.rtr) f.dlc
        (String.concat "," (List.map string_of_int f.data))) order;
  close_out oc;
  Printf.printf "can dump: %d frames, %d lockstep mismatches\n" (List.length order) s.m.Sim.Machine.mismatches;
  exit (if List.map (fun (f : Can_model.frame) -> f.id) order = [ 0x0F0; 0x123; 0x7FF ] && s.m.Sim.Machine.mismatches = 0 then 0 else 1)
