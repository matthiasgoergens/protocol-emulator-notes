(* The CAN side of the I2C <-> CAN bridge with master's real CAN firmware, in two modes, built
   against master's prototypes/sequencer-ps2-can like can_events.ml (can_bridge.sh builds it).

   rx  A reference node sends the requests (plan from the seed); our node's RX thread (interpreter
       and RTL in lockstep) receives them. One request in six is hit by a 6 us dominant glitch, so
       every node flags an error and the reference node retransmits it, as CAN does. Log:
         R t write addr reg value     each request as planned
         F t tag value                the RX thread's reports (SOF, DATA, END)
   tx  Our node's TX thread sends the bridge's responses (read from a file of lines
         T t c1 c2 c3 d0 ..           the time the bridge produced them, in fs)
       while the reference node replays the requests at the same instants, so every response meets a
       request on the bus and loses arbitration first; the reference node's receive log must
       contain every response, in order.
       The TX thread takes a stream stuffed off the thread (Can_fw.tx_bytes), as the branch's host
       driver does today. *)

let reqs ~seed ~n =
  let rnd = Random.State.make [| seed |] in
  List.init n (fun i ->
    let addr = if Random.State.int rnd 8 = 0 then 0x21 else 0x48 in
    let write = Random.State.bool rnd in
    let t = Sim.us (200. +. (float i *. 700.) +. Random.State.float rnd 200.) in
    (t, write, addr, Random.State.int rnd 256, Random.State.int rnd 256, Random.State.int rnd 6 = 0))

let frame_of (_, write, addr, reg, value, _) =
  { Can_model.id = (if write then 0x124 else 0x123); rtr = false; dlc = 3;
    data = (if write then [ addr lsl 1; reg; value ] else [ addr lsl 1; reg; (addr lsl 1) lor 1 ]) }

let () =
  let mode = Sys.argv.(1) and out = Sys.argv.(2) in
  let seed = 7 and n = 40 in
  let plan = reqs ~seed ~n in
  let t = Can_bench.timing_500k in
  let bus = Can_model.Bus.create [| Sim.ns 60.; Sim.ns 40.; Sim.ns 10. |] in
  let r = Can_model.create ~bus ~idx:0 ~name:"requester" () in
  let an = Can_bench.make_node ~name:"bridge" ~pins:Can_bench.pins_a ~bus_idx:1 in
  let oc = open_out out in
  let pending = ref plan and glitches = ref [] in
  let horizon = ref (Sim.us (200. +. (float n *. 700.) +. 2000.)) in
  let responses = ref [] in
  let s =
    if mode = "rx" then begin
      let rx_prog, _, _ = Can_fw.rx Can_bench.pins_a t in
      let txd_idle = Array.make Isa_v.prog_len Isa_v.halt in
      txd_idle.(0) <- Isa_v.setp ~mask:(1 lsl Can_bench.pins_a.txd) ~value:1 ~oe:1;
      List.iter (fun ((tt, w, a, rg, v, _) as q) ->
        ignore q; Printf.fprintf oc "R %d %d %d %d %d\n" tt (if w then 1 else 0) a rg v) plan;
      Can_bench.seq_agent ~rtl:true ~bus ~hz:Can_bench.clock_hz ~name:"bridge" [ (0, 1, an, None) ] [ 0, rx_prog; 1, txd_idle ]
    end else begin
      let ic = open_in Sys.argv.(3) in
      (try while true do
          match List.map int_of_string (List.tl (String.split_on_char ' ' (String.trim (input_line ic)))) with
          | tt :: c1 :: c2 :: c3 :: data ->
            let id = ((c1 land 3) lsl 9) lor (c2 lsl 1) lor (c3 lsr 7) in
            responses := !responses @ [ (tt, { Can_model.id; rtr = false; dlc = c3 land 15; data }) ]
          | _ -> ()
        done with End_of_file -> ());
      close_in ic;
      (match List.rev !responses with (tt, _) :: _ -> horizon := max !horizon (tt + Sim.us 3000.) | [] -> ());
      Can_bench.make_seq ~rtl:true ~bus ~hz:Can_bench.clock_hz ~name:"bridge" ~a:an ()
    end in
  let to_submit = ref !responses in
  (* tx: the requester replays the requests at the very instants the responses are submitted, so
     every response meets a request on the bus and loses arbitration to its lower identifier *)
  if mode <> "rx" then
    pending := List.map2 (fun (tt, _) (_, w, a, rg, v, _) -> (tt, w, a, rg, v, false))
        !responses (List.filteri (fun i _ -> i < List.length !responses) plan);
  let feed = Sim.agent ~name:"feed" ~hz:1e6 (fun now ->
    (match !pending with
     | ((tt, _, _, _, _, bad) as q) :: rest when now >= tt ->
       r.queue <- r.queue @ [ frame_of q ];
       (* 80 us in is the register and value bytes; at 50 us the glitch sat on the address byte
          (0x90 or 0x42), mostly dominant already, and changed nothing *)
       if bad && mode = "rx" then glitches := (now + Sim.us 80.) :: !glitches;
       pending := rest
     | _ -> ());
    (match !to_submit with
     | (tt, f) :: rest when now >= tt -> Can_bench.submit an ~at:now [ f ]; to_submit := rest
     | _ -> ());
    let g = List.exists (fun g0 -> now >= g0 && now < g0 + Sim.us 6.) !glitches in
    Can_model.Bus.drive bus 2 ~now (if g then 0 else 1)) in
  let last_nbytes = ref 0 and last_cur = ref None and last_nframes = ref 0 in
  let watch = Sim.agent ~name:"watch" ~hz:Can_bench.clock_hz (fun now ->
    if mode = "rx" then begin
      (match an.rx.cur, !last_cur with
       | Some _, None -> Printf.fprintf oc "F %d %d 0\n" now Can_fw.tag_sof; last_nbytes := 0
       | Some c, Some p when c.at <> p.Can_bench.at -> Printf.fprintf oc "F %d %d 0\n" now Can_fw.tag_sof; last_nbytes := 0
       | _ -> ());
      let nb = List.length an.rx.bytes in
      if nb > !last_nbytes && an.rx.cur <> None then begin
        List.iteri (fun i v -> if i >= !last_nbytes then Printf.fprintf oc "F %d %d %d\n" now Can_fw.tag_data v) an.rx.bytes;
        last_nbytes := nb
      end;
      let nfr = List.length an.rx.frames in
      if nfr > !last_nframes then begin
        (match an.rx.frames with c :: _ -> Printf.fprintf oc "F %d %d %d\n" now Can_fw.tag_end (Option.value c.end_code ~default:9) | [] -> ());
        last_nframes := nfr
      end;
      last_cur := an.rx.cur
    end) in
  ignore (Sim.run ~until:!horizon [ s.agent; Can_bench.ref_agent ~ppm:900. r; feed; watch ]);
  if mode = "rx" then begin
    let fr = Can_bench.frames_of an in
    Printf.printf "rx: %d requests planned, %d glitched; requester sent %d frames, %d errors; our RX thread: %d records, %d ok, %d errors; \
                   RTL/interpreter mismatches %d\n"
      n (List.length !glitches) (List.length r.sent) (List.length r.errors) (List.length fr)
      (List.length (List.filter (fun x -> x.Can_bench.end_code = Some 0) fr))
      (List.length (List.filter (fun x -> match x.Can_bench.end_code with Some c -> c <> 0 | None -> true) fr)) s.m.mismatches
  end else begin
    let got_t = List.rev (List.filter (fun (_, _, _, own) -> not own) r.received) in
    let got = List.map (fun (_, f, _, _) -> f) got_t in
    let delays = List.map2 (fun (ts, _) (tr, _, _, _) -> tr - ts) (List.filteri (fun i _ -> i < List.length got_t) !responses) got_t in
    let codes = Hashtbl.create 4 in
    List.iter (fun (_, _, v) -> Hashtbl.replace codes v (1 + Option.value (Hashtbl.find_opt codes v) ~default:0)) an.tx_status;
    let req_first = List.length (List.filter (fun (tr, _, _, own) -> own && List.exists (fun (ts, _) -> tr > ts && tr - ts < Sim.us 400.) !responses) r.received) in
    Printf.printf "tx: submit-to-delivery delay min %.0f us, max %.0f us; requests delivered while a response waited: %d; TX status codes %s\n"
      (float (List.fold_left min max_int delays) /. 1e9) (float (List.fold_left max 0 delays) /. 1e9) req_first
      (String.concat ", " (Hashtbl.fold (fun k v acc -> Printf.sprintf "%d x%d" k v :: acc) codes []));
    let want = List.map snd !responses in
    List.iter (fun (f : Can_model.frame) ->
      Printf.fprintf oc "G %03x %d %s\n" f.id f.dlc (String.concat " " (List.map string_of_int f.data))) got;
    Printf.printf "tx: %d responses submitted to our TX thread; the requester received %d frames from it, equal and in order: %b; \
                   our node lost arbitration %d times and retransmitted; RTL/interpreter mismatches %d\n"
      (List.length want) (List.length got) (got = want)
      (List.length (List.filter (fun (_, _, v) -> v = 3) an.tx_status)) s.m.mismatches
  end;
  close_out oc
