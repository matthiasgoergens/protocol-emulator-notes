(* The ARP / ping demo: requests from the independent host stack (host_stack.py, scapy) go down
   the line into the node; the node's transmit line is judged by the clause-14 checker, decoded,
   compared with the engine's OCaml model, and written out for the host stack to judge. *)

let pr fmt = Printf.printf (fmt ^^ "\n%!")

let read_requests path =
  let ic = open_in path in
  let rec go acc = match input_line ic with
    | line ->
      (match String.split_on_char ' ' line with
       | hex :: e :: label :: _ ->
         let b = List.init (String.length hex / 2) (fun k -> int_of_string ("0x" ^ String.sub hex (2 * k) 2)) in
         go ((b, e = "1", label) :: acc)
       | _ -> go acc)
    | exception End_of_file -> close_in ic; List.rev acc in
  go []

let hex l = String.concat "" (List.map (Printf.sprintf "%02x") l)

let run ?(subset = false) ?(gap_us = 300.0) ?(tail_ms = 20.0) ?(mem = Array.init Isa.n_threads (fun t -> Tx_fw.program t)) ?(quiet = false) ~requests ~replies_out () =
  let reqs = read_requests requests in
  let t = ref 2000.0 in
  (* each request starts [gap_us] after the previous one ended: 300 us leaves room for the longest
     reply (about 215 us) plus the 9.6 us deferral, so the line is never driven from both ends *)
  let bursts = List.map (fun (b, _, _) -> let x = Line.make_burst ~start_ns:!t b in t := Line.end_ns x +. (gap_us *. 1000.0); x) reqs in
  let cycles = int_of_float ((!t +. (tail_ms *. 1e6)) *. 60e-3) in
  let r = Node.simulate ~mem ~cycles bursts in
  let tick_ns = 1e9 /. 60e6 /. 4.0 in
  let c = Clause14.check ~tick_ns r.runs in
  (* attribute each transmitted frame to the last request that ended before it started *)
  let ends = List.map (fun b -> Line.end_ns b) bursts in
  let attributed = List.filter_map (function
      | Clause14.Frame { t_ns; bytes = Some b; _ } ->
        let idx = List.fold_left (fun (k, best) e -> (k + 1, if e < t_ns then k else best)) (0, -1) ends |> snd in
        Some (idx, b)
      | _ -> None) c.events in
  let oc = open_out replies_out in
  List.iter (fun (i, b) -> Printf.fprintf oc "%d %s\n" i (hex b)) attributed;
  close_out oc;
  (* the engine's model, request by request *)
  let model = List.mapi (fun i (b, _, _) ->
      match Engine.reply ~fcs_ok:(Eth_model.crc32_reg b = Eth_model.residual) b with Ok rep -> Some (i, rep) | Error _ -> None) reqs
              |> List.filter_map Fun.id in
  (* with requests closer than a reply takes, some are dropped as busy: then every reply sent must
     still be the model's reply to one of the requests *)
  let model_agrees =
    if subset then List.for_all (fun (_, b) -> List.exists (fun (_, m) -> m = b) model) attributed   (* deferral blurs which request came last *)
    else model = attributed in
  if not quiet then begin
    let mn l = List.fold_left Float.min infinity l and mx l = List.fold_left Float.max neg_infinity l in
    pr "  %d requests, %d replies sent (engine counter %d); drops: bad FCS %d, runt %d, too long %d, no match %d, busy %d"
      (List.length reqs) (List.length attributed) r.replies r.drops.(0) r.drops.(1) r.drops.(2) r.drops.(3) r.drops.(4);
    pr "  transmit line: %d link pulses, %d frames, TP_IDL %.1f..%.1f ns, %d clause-14 violations%s"
      (List.length c.nlp_widths) (List.length (Clause14.frames_of c)) (mn c.tp_idls) (mx c.tp_idls) (List.length c.violations)
      (match c.violations with v :: _ -> " (first: " ^ v ^ ")" | [] -> "");
    pr "  replies equal to the engine model's, request by request: %b" model_agrees;
    let lat = List.filter_map (function
        | Clause14.Frame { t_ns; bytes = Some _; _ } ->
          let e = List.fold_left (fun best e -> if e < t_ns then e else best) neg_infinity ends in Some ((t_ns -. e) /. 1e3)
        | _ -> None) c.events in
    pr "  latency from the end of a request to the start of its reply: %.1f..%.1f us" (mn lat) (mx lat)
  end;
  (c.violations = [] && model_agrees, attributed, r)

(* planted faults: each must make the host stack (or the checker) fail *)
let controls ~requests ~dir =
  let icmp_adj k = { Engine.icmp_echo with prog = List.map (function Engine.Adj_hi (i, _) -> Engine.Adj_hi (i, k) | Engine.Adj_lo (i, _) -> Engine.Adj_lo (i, k) | o -> o) Engine.icmp_echo.prog } in
  let icmp_noswap = { Engine.icmp_echo with prog = List.map (function Engine.Copy i when i >= 26 && i < 34 -> Engine.Copy i | o -> o) Engine.icmp_echo.prog
                                                   |> List.mapi (fun j o -> if j >= 26 && j < 34 then Engine.Copy j else o) } in
  let arp_any_ip = { Engine.arp_bcast with mask = Array.mapi (fun i m -> if i >= 38 then 0 else m) Engine.arp_bcast.mask } in
  let cases = [
    ("ICMP checksum adjusted by 0x0801 instead of 0x0800", (fun () -> Engine.templates_override := Some [ Engine.arp_bcast; Engine.arp_ucast; icmp_adj 0x0801 ]), None);
    ("ICMP reply without the IP address swap", (fun () -> Engine.templates_override := Some [ Engine.arp_bcast; Engine.arp_ucast; icmp_noswap ]), None);
    ("ARP template ignores the target IP", (fun () -> Engine.templates_override := Some [ arp_any_ip; Engine.arp_ucast; Engine.icmp_echo ]), None);
    ("FCS appended most significant byte first", (fun () -> Engine.fcs_reversed := true), None);
    ("transmit firmware: thread 1 one slot late", (fun () -> ()), Some (Array.init 4 (fun t -> Tx_fw.program ~late_thread:1 t)));
  ] in
  List.mapi (fun k (name, set, mem) ->
      set ();
      let out = Filename.concat dir (Printf.sprintf "replies-control%d.txt" k) in
      let ok, _, _ = run ?mem ~quiet:true ~tail_ms:1.0 ~requests ~replies_out:out () in
      Engine.templates_override := None; Engine.fcs_reversed := false;
      (name, ok, out)) cases
