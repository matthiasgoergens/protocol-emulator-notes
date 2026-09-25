(* PS/2 bench: our firmware against the independent models (and against itself), on the
   interpreter and the RTL in lockstep, with the host-side applications written in OCaml. *)

let clock_hz = 60e6
let spu = int_of_float (clock_hz /. 4. /. 1e6)   (* slots per microsecond: 15 *)
let timing = Ps2_fw.default_timing ~spu

(* The keyboard application behind our device thread: a queue of bytes to send, keyboard command
   semantics, retransmission after an abort. Talks to the thread through the doorbell pin, IN,
   and (value, kind) OUT pairs. *)
module Kbd_app = struct
  type t = { mutable queue : int list; mutable pending : int option; mutable events : (int * int) list;
             mutable expect_arg : bool; mutable leds : int list }
  let create codes = { queue = codes; pending = None; events = []; expect_arg = false; leds = [] }
  let req a = a.queue <> []
  let host_in a = match a.queue with b :: _ -> Some b | [] -> None
  let on_out a v =
    match a.pending with
    | None -> a.pending <- Some v
    | Some value ->
      a.pending <- None; a.events <- (value, v) :: a.events;
      (match v with
       | 5 -> a.queue <- List.tl a.queue
       | 1 ->
         let r =
           if a.expect_arg then (a.expect_arg <- false; a.leds <- value :: a.leds; [ 0xFA ])
           else match value with
             | 0xFF -> [ 0xFA; 0xAA ] | 0xED -> a.expect_arg <- true; [ 0xFA ] | 0xEE -> [ 0xEE ]
             | 0xF2 -> [ 0xFA; 0xAB; 0x83 ] | _ -> [ 0xFA ] in
         a.queue <- r @ a.queue
       | 2 -> a.queue <- 0xFE :: a.queue
       | _ -> ())
end

(* The PC application behind our host thread: scheduled commands, a log of events. *)
module Pc_app = struct
  type t = { mutable cmds : (int * int) list; mutable pending : int option; mutable events : (int * int * int) list;
             mutable now : int }
  let create cmds = { cmds; pending = None; events = []; now = 0 }
  let req a = match a.cmds with (at, _) :: _ -> a.now >= at | [] -> false
  let host_in a = match a.cmds with (_, b) :: _ -> Some b | [] -> None
  let on_out a v =
    match a.pending with
    | None -> a.pending <- Some v
    | Some value ->
      a.pending <- None; a.events <- (a.now, value, v) :: a.events;
      if v = 7 || v = 8 || v = 9 then a.cmds <- List.tl a.cmds
end

type port = { fw_clk : int; fw_data : int; fw_req : int; clk : Sim.Oc.t; data : Sim.Oc.t }

(* A sequencer agent: thread 0 may run the device firmware, thread 1 the host firmware. *)
let seq_agent ~mem ~ports ~req ~host_in ~on_out ~rtl =
  let m = Sim.Machine.create ~rtl mem in
  let contention = ref 0 in
  let fire now =
    let pin_in = ref 0 in
    List.iter (fun (t, p) ->
      pin_in := !pin_in lor (Sim.Oc.level p.clk ~now lsl p.fw_clk) lor (Sim.Oc.level p.data ~now lsl p.fw_data)
                lor ((if req t then 1 else 0) lsl p.fw_req)) ports;
    let t = Sim.Machine.thread m in
    let hi = host_in t in
    let eff = Sim.Machine.step m ~pin_in:!pin_in ~host_in:(Option.value hi ~default:0) ~host_in_valid:(hi <> None) in
    (match eff.host_out with Some (_, v) -> on_out t v | None -> ());
    let out = m.st.pin_out and oe = m.st.pin_oe in
    List.iter (fun (_, p) ->
      List.iter (fun (pin, line) ->
        let e = (oe lsr pin) land 1 and o = (out lsr pin) land 1 in
        if e = 1 && o = 1 then incr contention;
        Sim.Oc.set line ~who:"seq" ~pull:(e = 1 && o = 0) ~now) [ p.fw_clk, p.clk; p.fw_data, p.data ]) ports in
  m, contention, Sim.agent ~name:"seq" ~hz:clock_hz fire

type result = { name : string; ok : bool; detail : string; cycles : int; mismatches : int }

let report r =
  Printf.printf "  %-58s %s  (%d cycles, %d lockstep mismatches)%s\n" r.name (if r.ok then "PASS" else "FAIL")
    r.cycles r.mismatches (if r.detail = "" then "" else "\n      " ^ r.detail)

let is_response b = List.mem b [ 0xFA; 0xAA; 0xEE; 0xFE; 0xAB; 0x83 ]

(* Our device firmware against the model host. *)
let device_vs_model_host ?(faults = Ps2_fw.no_faults) ?(timing = timing) ?(rtl = true) ~name ~seed ~codes ~cmds ~inhibits ~rise () =
  ignore seed;
  let clk = Sim.Oc.create ~rise and data = Sim.Oc.create ~rise in
  let prog, _, _ = Ps2_fw.device ~faults { clk = 0; data = 1; req = 2 } timing in
  let mem = Array.init 4 (fun t -> if t = 0 then prog else Array.make 256 Isa_v.halt) in
  let app = Kbd_app.create codes in
  let port = { fw_clk = 0; fw_data = 1; fw_req = 2; clk; data } in
  let m, contention, seq = seq_agent ~mem ~ports:[ 0, port ] ~rtl
      ~req:(fun t -> t = 0 && Kbd_app.req app) ~host_in:(fun t -> if t = 0 then Kbd_app.host_in app else None)
      ~on_out:(fun t v -> if t = 0 then Kbd_app.on_out app v) in
  let host = Ps2_model.Host.create ~clk ~data () in
  host.cmds <- List.map (fun (at, byte, bad) -> { Ps2_model.Host.at; byte; bad_parity = bad }) cmds;
  host.inhibits <- inhibits;
  let model = Sim.agent ~name:"host" ~hz:Ps2_model.tick_hz (fun now -> Ps2_model.Host.fire host now) in
  let last_cmd = List.fold_left (fun a (t, _, _) -> max a t) 0 cmds in
  let stop () = app.queue = [] && host.cmds = [] && host.sending = None && host.inhibits = []
                && host.inhibit_until = 0 in
  ignore (Sim.run ~stop ~until:(last_cmd + Sim.us (3000. +. float (List.length codes + 10) *. 1500.)) [ seq; model ]);
  (* checks *)
  let got = List.rev_map (fun (_, b, p) -> b, p) host.received in
  let bad_parity = List.filter (fun (_, p) -> not p) got in
  let scans = List.filter (fun (b, _) -> not (is_response b)) got |> List.map fst in
  let acked = List.for_all (fun (_, _, a) -> a) host.cmd_results in
  let cmd_bytes = List.map (fun (_, b, _) -> b) cmds in
  let dev_cmds = List.filter_map (fun (v, k) -> if k = 1 || k = 2 then Some v else None) (List.rev app.events) in
  let responses = List.filter (fun (b, _) -> is_response b) got |> List.map fst in
  let problems = List.concat [
      (if host.violations <> [] then [ "host model: " ^ Ps2_model.pp_violations host.violations ] else []);
      (if bad_parity <> [] then [ Printf.sprintf "%d bytes with bad parity" (List.length bad_parity) ] else []);
      (if scans <> codes then [ Printf.sprintf "scan codes differ: got [%s]" (String.concat " " (List.map (Printf.sprintf "%02x") scans)) ] else []);
      (if not acked then [ "a command was not acknowledged" ] else []);
      (if dev_cmds <> cmd_bytes then [ Printf.sprintf "device saw commands [%s]" (String.concat " " (List.map (Printf.sprintf "%02x") dev_cmds)) ] else []);
      (if !contention > 0 then [ Printf.sprintf "%d cycles driving an open-collector line high" !contention ] else []);
      (if m.mismatches > 0 then [ "lockstep: " ^ Option.value m.first ~default:"" ] else []) ] in
  { name; ok = problems = []; detail = String.concat "\n      " problems; cycles = m.cycle; mismatches = m.mismatches },
  (host, app, responses)

(* The model device against our host firmware. *)
let host_vs_model_device ?(faults = Ps2_fw.no_faults) ?(rtl = true) ~name ~codes ~cmds ~dev_hz ~rise ?(bad_parity_at = -1) () =
  let clk = Sim.Oc.create ~rise and data = Sim.Oc.create ~rise in
  let prog, _, _ = Ps2_fw.host ~faults { clk = 4; data = 5; req = 6 } timing in
  let mem = Array.init 4 (fun t -> if t = 1 then prog else Array.make 256 Isa_v.halt) in
  let app = Pc_app.create cmds in
  let port = { fw_clk = 4; fw_data = 5; fw_req = 6; clk; data } in
  let now_ref = ref 0 in
  let m, contention, seq = seq_agent ~mem ~ports:[ 1, port ] ~rtl
      ~req:(fun t -> t = 1 && (app.now <- !now_ref; Pc_app.req app))
      ~host_in:(fun t -> if t = 1 then Pc_app.host_in app else None)
      ~on_out:(fun t v -> if t = 1 then Pc_app.on_out app v) in
  let seq = { seq with fire = (fun now -> now_ref := now; seq.fire now) } in
  let dev = Ps2_model.Device.create ~clk ~data ~hz:dev_hz () in
  dev.queue <- codes;
  let sent_count = ref 0 in
  let model = Sim.agent ~name:"dev" ~hz:Ps2_model.tick_hz (fun now ->
      if !sent_count = bad_parity_at && dev.state = Ps2_model.Device.Idle then dev.bad_parity_next <- true;
      Ps2_model.Device.fire dev now; sent_count := List.length dev.sent) in
  let stop () = app.cmds = [] && dev.queue = [] && dev.state = Ps2_model.Device.Idle && !now_ref > 0 in
  let last_cmd = List.fold_left (fun a (t, _) -> max a t) 0 cmds in
  ignore (Sim.run ~stop ~until:(last_cmd + Sim.us (float (List.length codes + List.length cmds + 10) *. 2000.)) [ seq; model ]);
  let evs = List.rev app.events in
  let got = List.filter_map (fun (_, v, k) -> if k = 1 || k = 2 then Some (v, k = 1) else None) evs in
  let sent = List.rev_map snd dev.sent in
  let cmd_bytes = List.map snd cmds in
  let dev_cmds = List.rev_map (fun (_, b, ok) -> b, ok) dev.received in
  let sent_ok = List.map fst got = sent in
  let parity_as_expected = List.mapi (fun i (_, ok) -> ok = (i <> bad_parity_at)) got |> List.for_all Fun.id in
  let acks = List.filter_map (fun (_, _, k) -> if k >= 7 then Some k else None) evs in
  let problems = List.concat [
      (if dev.violations <> [] then [ "device model: " ^ Ps2_model.pp_violations dev.violations ] else []);
      (if not sent_ok then [ Printf.sprintf "host firmware got [%s], device sent [%s]"
                                (String.concat " " (List.map (fun (b, ok) -> Printf.sprintf "%02x%s" b (if ok then "" else "!")) got))
                                (String.concat " " (List.map (Printf.sprintf "%02x") sent)) ] else []);
      (if not parity_as_expected then [ "parity verdicts not as expected" ] else []);
      (if List.map fst dev_cmds <> cmd_bytes || List.exists (fun (_, ok) -> not ok) dev_cmds then
         [ Printf.sprintf "device received [%s]" (String.concat " " (List.map (fun (b, ok) -> Printf.sprintf "%02x%s" b (if ok then "" else "!")) dev_cmds)) ] else []);
      (if List.exists (fun k -> k <> 7) acks || List.length acks <> List.length cmds then
         [ Printf.sprintf "command outcomes [%s]" (String.concat " " (List.map string_of_int acks)) ] else []);
      (if dev.aborted > 0 then [ Printf.sprintf "device aborted %d frames" dev.aborted ] else []);
      (if !contention > 0 then [ Printf.sprintf "%d cycles driving an open-collector line high" !contention ] else []);
      (if m.mismatches > 0 then [ "lockstep: " ^ Option.value m.first ~default:"" ] else []) ] in
  { name; ok = problems = []; detail = String.concat "\n      " problems; cycles = m.cycle; mismatches = m.mismatches },
  (dev, app)

(* Our device firmware (thread 0) and our host firmware (thread 1) on one sequencer, wired together. *)
let device_vs_host_firmware ?(rtl = true) ~name ~codes ~cmds ~rise () =
  let clk = Sim.Oc.create ~rise and data = Sim.Oc.create ~rise in
  let dprog, _, _ = Ps2_fw.device { clk = 0; data = 1; req = 2 } timing in
  let hprog, _, _ = Ps2_fw.host { clk = 4; data = 5; req = 6 } timing in
  let mem = Array.init 4 (fun t -> if t = 0 then dprog else if t = 1 then hprog else Array.make 256 Isa_v.halt) in
  let kbd = Kbd_app.create codes and pc = Pc_app.create cmds in
  let now_ref = ref 0 in
  let dport = { fw_clk = 0; fw_data = 1; fw_req = 2; clk; data } and hport = { fw_clk = 4; fw_data = 5; fw_req = 6; clk; data } in
  let m, contention, seq = seq_agent ~mem ~ports:[ 0, dport; 1, hport ] ~rtl
      ~req:(fun t -> if t = 0 then Kbd_app.req kbd else (pc.now <- !now_ref; Pc_app.req pc))
      ~host_in:(fun t -> if t = 0 then Kbd_app.host_in kbd else if t = 1 then Pc_app.host_in pc else None)
      ~on_out:(fun t v -> if t = 0 then Kbd_app.on_out kbd v else if t = 1 then Pc_app.on_out pc v) in
  let seq = { seq with fire = (fun now -> now_ref := now; seq.fire now) } in
  let stop () = kbd.queue = [] && pc.cmds = [] && !now_ref > Sim.us 100. in
  let last_cmd = List.fold_left (fun a (t, _) -> max a t) 0 cmds in
  ignore (Sim.run ~stop ~until:(last_cmd + Sim.us (float (List.length codes + 3 * List.length cmds + 10) *. 2000.)) [ seq ]);
  ignore (Sim.run ~until:(!now_ref + Sim.us 300.) [ seq ]);
  let evs = List.rev pc.events in
  let got = List.filter_map (fun (_, v, k) -> if k = 1 then Some v else None) evs in
  let bad = List.filter (fun (_, _, k) -> k = 2 || k = 3 || k = 6 || k = 8 || k = 9) evs in
  let scans = List.filter (fun b -> not (is_response b)) got in
  let kcmds = List.filter_map (fun (v, k) -> if k = 1 then Some v else None) (List.rev kbd.events) in
  let problems = List.concat [
      (if scans <> codes then [ Printf.sprintf "scan codes differ: [%s]" (String.concat " " (List.map (Printf.sprintf "%02x") scans)) ] else []);
      (if bad <> [] then [ Printf.sprintf "%d error events at the host" (List.length bad) ] else []);
      (if kcmds <> List.map snd cmds then [ "keyboard saw other commands" ] else []);
      (if !contention > 0 then [ "contention" ] else []);
      (if m.mismatches > 0 then [ "lockstep: " ^ Option.value m.first ~default:"" ] else []) ] in
  { name; ok = problems = []; detail = String.concat "\n      " problems; cycles = m.cycle; mismatches = m.mismatches },
  (List.filter is_response got)
