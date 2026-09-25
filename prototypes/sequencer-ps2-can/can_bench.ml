(* CAN bench: our nodes (two threads each, up to two nodes per sequencer; interpreter and RTL in
   lockstep) and reference nodes on one wired-AND bus with propagation delays and per-agent
   oscillator offsets. *)

let clock_hz = 60e6

(* 500 kbit/s at 60 MHz: 30 slots per bit, sample at 23 (77 %), SJW 3 slots (10 %) *)
let timing_500k = { Can_fw.n = 30; sp = 23; sjw = 3 }

(* ---------------------------------------------------------------- host driver *)

(* The receive interface: what the RX thread reports, decoded. This is the interface other
   threads or the host consume (see README). *)
type rx_frame = {
  at : int;                        (* time of the SOF report, fs *)
  frame : Can_model.frame option;  (* decoded when the header got through *)
  crc_ok : bool option;
  ack_level : int option;          (* bus level in the ACK slot: 0 = acknowledged *)
  end_code : int option;           (* 0 ok, 1 stuff, 2 crc, 3 form, 5 extended *)
  raw : int list;                  (* raw option: sampled levels, 2 = stuff bit *)
}

type rx_state = { mutable cur : rx_frame option; mutable bytes : int list; mutable frames : rx_frame list }

let decode_bytes bytes =
  (* 3, 8, 8 bits of header; then data and CRC bits, 7 in the first byte and 8 in the rest *)
  match bytes with
  | b0 :: b1 :: b2 :: rest ->
    let id = ((b0 land 3) lsl 9) lor (b1 lsl 1) lor (b2 lsr 7) in
    let rtr = (b2 lsr 6) land 1 = 1 and dlc = b2 land 15 in
    let nb = if rtr then 0 else min 8 dlc in
    let bits = List.concat (List.mapi (fun i b -> Can_fw.bits_of b (if i = 0 then 7 else 8)) rest) in
    if List.length bits < 8 * nb then None
    else
      let byte i = List.fold_left (fun a k -> (a lsl 1) lor List.nth bits (8 * i + k)) 0 [ 0; 1; 2; 3; 4; 5; 6; 7 ] in
      Some { Can_model.id; rtr; dlc; data = List.init nb byte }
  | _ -> None

let rx_event st ~now (tag, v) =
  let upd f = match st.cur with Some c -> st.cur <- Some (f c) | None -> () in
  if tag = Can_fw.tag_sof then begin
    (match st.cur with Some c -> st.frames <- c :: st.frames | None -> ());
    st.cur <- Some { at = now; frame = None; crc_ok = None; ack_level = None; end_code = None; raw = [] };
    st.bytes <- []
  end else if tag = Can_fw.tag_data then st.bytes <- st.bytes @ [ v ]
  else if tag = Can_fw.tag_crc then upd (fun c -> { c with crc_ok = Some (v = 1); frame = decode_bytes st.bytes })
  else if tag = Can_fw.tag_ack then upd (fun c -> { c with ack_level = Some (v land 1) })
  else if tag = Can_fw.tag_raw then upd (fun c -> { c with raw = c.raw @ [ (if v = 0x80 then 2 else v land 1) ] })
  else if tag = Can_fw.tag_end then begin
    upd (fun c -> { c with end_code = Some v; frame = (match c.frame with Some f -> Some f | None -> decode_bytes st.bytes) });
    (match st.cur with Some c -> st.frames <- c :: st.frames | None -> ());
    st.cur <- None
  end

type node = {
  name : string; pins : Can_fw.pins; bus_idx : int;
  mutable queue : (Can_model.frame * int list) list;   (* frame, its byte stream *)
  mutable pos : int;                                    (* next byte of the head's stream *)
  mutable not_before : int;                             (* host submits the head at this time *)
  mutable tx_status : (int * Can_model.frame * int) list;
  mutable retries : int;
  rx : rx_state;
}

let make_node ~name ~pins ~bus_idx =
  { name; pins; bus_idx; queue = []; pos = 0; not_before = 0; tx_status = []; retries = 0;
    rx = { cur = None; bytes = []; frames = [] } }

let submit nd ?(at = 0) ?(stream = fun f -> Can_fw.tx_bytes { Can_fw.id = f.Can_model.id; rtr = f.rtr; dlc = f.dlc; data = f.data }) frames =
  nd.queue <- nd.queue @ List.map (fun f -> f, stream f) frames;
  if at > nd.not_before then nd.not_before <- at

let tx_event nd ~now v =
  match nd.queue with
  | (f, _) :: rest ->
    nd.tx_status <- (now, f, v) :: nd.tx_status; nd.pos <- 0;
    if v = 1 then nd.queue <- rest
    else begin
      nd.retries <- nd.retries + 1;
      if nd.retries > 40 then nd.queue <- rest   (* give up: the checks will notice *)
    end
  | [] -> ()

(* ---------------------------------------------------------------- sequencer agent *)

type seq = { m : Sim.Machine.t; nodes : (int * node) list (* rx thread index, node *); agent : Sim.agent }

(* nodes: (rx thread, tx thread, node) *)
let seq_agent ?(rtl = true) ~bus ~hz ~name (nodes : (int * int * node * Isa_v.state option) list) mems =
  let mem = Array.init 4 (fun t -> match List.assoc_opt t mems with Some p -> p | None -> Array.make 256 Isa_v.halt) in
  let m = Sim.Machine.create ~rtl mem in
  let now_r = ref 0 in
  let fire now =
    now_r := now;
    let pin_in = ref m.st.pin_out in   (* output pads read back their own level *)
    List.iter (fun (_, _, nd, _) ->
      let lvl = Can_model.Bus.rx bus nd.bus_idx ~now in
      pin_in := (!pin_in land lnot (1 lsl nd.pins.rx)) lor (lvl lsl nd.pins.rx)) nodes;
    let t = Sim.Machine.thread m in
    let host = List.find_opt (fun (_, tt, _, _) -> tt = t) nodes in
    let hi = match host with
      | Some (_, _, nd, _) when now >= nd.not_before ->
        (match nd.queue with (_, s) :: _ when nd.pos < List.length s -> Some (List.nth s nd.pos) | _ -> None)
      | _ -> None in
    let eff = Sim.Machine.step m ~pin_in:!pin_in ~host_in:(Option.value hi ~default:0) ~host_in_valid:(hi <> None) in
    if eff.host_in_ready then (match host with Some (_, _, nd, _) -> nd.pos <- nd.pos + 1 | None -> ());
    (match eff.host_out with
     | Some (tag, v) ->
       List.iter (fun (rt, tt, nd, _) ->
         if t = rt then rx_event nd.rx ~now (tag, v)
         else if t = tt && tag = Can_fw.tag_tx then tx_event nd ~now v) nodes
     | None -> ());
    List.iter (fun (_, _, nd, _) ->
      let o = m.st.pin_out in
      let lvl = ((o lsr nd.pins.txd) land 1) land ((o lsr nd.pins.txe) land 1) in
      Can_model.Bus.drive bus nd.bus_idx ~now lvl) nodes in
  { m; nodes = List.map (fun (rt, _, nd, _) -> rt, nd) nodes; agent = Sim.agent ~name ~hz fire }

let pins_a = { Can_fw.rx = 0; txd = 1; txe = 2; flag = 3 }
let pins_b = { Can_fw.rx = 4; txd = 5; txe = 6; flag = 7 }

(* one sequencer with node A on threads 0/1 and optionally node B on threads 2/3 *)
let make_seq ?(rtl = true) ?(faults = Can_fw.no_faults) ?(raw = false) ?(timing = timing_500k) ~bus ~hz ~name ~a ?b () =
  let rx p = let prog, _, _ = Can_fw.rx ~faults ~raw p timing in prog in
  let tx p = let prog, _, _ = Can_fw.tx ~faults p timing in prog in
  let nodes = (0, 1, a, None) :: (match b with Some b -> [ (2, 3, b, None) ] | None -> []) in
  let mems = [ 0, rx a.pins; 1, tx a.pins ] @ (match b with Some b -> [ 2, rx b.pins; 3, tx b.pins ] | None -> []) in
  seq_agent ~rtl ~bus ~hz ~name nodes mems

(* a reference node as an agent: tq clock 8 MHz (16 tq per bit at 500 kbit/s) *)
let ref_agent ?(ppm = 0.) ?(phase = 0) ?(tq_hz = 8e6) node =
  Sim.agent ~phase ~name:node.Can_model.name ~hz:(tq_hz *. (1. +. ppm /. 1e6)) (fun now -> Can_model.tick node now)

let frames_of nd = List.rev (match nd.rx.cur with Some c -> c :: nd.rx.frames | None -> nd.rx.frames)
let good_frames nd = List.filter_map (fun r -> match r.frame, r.end_code with Some f, Some 0 -> Some f | _ -> None) (frames_of nd)
let acked nd = List.rev (List.filter_map (fun (_, f, v) -> if v = 1 then Some f else None) nd.tx_status)
