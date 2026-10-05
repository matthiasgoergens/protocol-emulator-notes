(* The test bench: a low-speed bus between the host model and a device under test, with a
   transaction-level host that judges every reply against the reference device.

   Bus: when the host drives, the line is the host's state; when the device drives (oe), the
   device's; both at once is contention and an error; neither is idle J (the device's pull-up on
   D-). The device sees the resolved line, including its own transmissions, as on real wires.

   Every reply is checked for: bytes equal to the reference device's answer (a slower device may
   NAK where data is due, if [nak_ok]); a clean decode (sync, NRZI, stuffing, whole bytes, EOP of
   about two bits); a turnaround between 2 and 6.5 of the host's bit times, measured from the
   SE0-to-J edge of the host's EOP to the device's SOP; no transmission when none is due. *)

type dut = {
  name : string;
  step : dp:int -> dm:int -> unit;       (* one clock with the resolved line *)
  out : unit -> int * int * int;         (* dp, dm, oe driven now *)
  offer_report : int list -> unit;       (* the application offers an 8-byte report *)
  nak_ok : bool;
  mismatches : unit -> int;              (* lockstep mismatches between two models, if any *)
}

type t = {
  dut : dut;
  ppm : int;
  rng : Random.State.t;
  refd : Ref_device.t;
  mutable now : int;
  mutable errors : string list;
  mutable last_eop_j : int;
  mutable turnarounds : float list;
  mutable naks_tolerated : int;
  mutable replies : int;
  mutable packets_sent : int;
  mutable keep_alives : int;
  mutable resets : int;
  mutable silent_ok : int;
  verbose : bool;
}

let create ?(verbose = false) ?(seed = 1) ~ppm dut =
  { dut; ppm; rng = Random.State.make [| seed |]; refd = Ref_device.create (); now = 0; errors = []; last_eop_j = 0;
    turnarounds = []; naks_tolerated = 0; replies = 0; packets_sent = 0; keep_alives = 0; resets = 0; silent_ok = 0; verbose }

let error b s =
  if List.length b.errors < 20 then b.errors <- Printf.sprintf "[%s clk %d] %s" b.dut.name b.now s :: b.errors
  else if List.length b.errors = 20 then b.errors <- "(more errors suppressed)" :: b.errors

let t_bit b = Ls_host.bit_period b.ppm

let device_state b =
  let dp, dm, oe = b.dut.out () in
  if oe = 1 then Ls_host.of_pins dp dm else None

(* one clock; [host] is the host's drive, if any. Returns the device's driven state, if any. *)
let tick b host =
  let dev = let dp, dm, oe = b.dut.out () in if oe = 1 then Some (dp, dm) else None in
  let dp, dm =
    match host, dev with
    | Some s, None -> Ls_host.phy s
    | None, Some p -> p
    | None, None -> Ls_host.phy Ls_host.J
    | Some s, Some _ -> error b "bus contention: host and device drive together"; Ls_host.phy s in
  b.dut.step ~dp ~dm;
  b.now <- b.now + 1;
  dev

(* host idle for [clocks]; the device must stay silent unless [allow] *)
let idle ?(allow = false) b clocks =
  for _ = 1 to clocks do
    match tick b None with
    | Some _ when not allow -> error b "device transmits when no reply is due"
    | _ -> ()
  done

let idle_bits b bits = idle b (int_of_float (Float.round (bits *. t_bit b)))

let send_states b states =
  let sched, fin = Ls_host.schedule ~ppm:b.ppm ~start:b.now states in
  let n = Array.length sched in
  Array.iteri (fun i (c0, s) ->
    let c1 = if i + 1 < n then fst sched.(i + 1) else fin in
    if i = n - 1 then b.last_eop_j <- c0;
    for _ = c0 to c1 - 1 do ignore (tick b (Some s)) done) sched

let send ?skip_stuff b bytes = b.packets_sent <- b.packets_sent + 1; send_states b (Ls_host.encode ?skip_stuff bytes)

let keep_alive b = b.keep_alives <- b.keep_alives + 1; send_states b Ls_host.keep_alive

let bus_reset b clocks =
  b.resets <- b.resets + 1;
  for _ = 1 to clocks do ignore (tick b (Some Ls_host.SE0)) done;
  Ref_device.reset b.refd

(* wait for the device's reply: up to 18 bit times after our EOP for SOP, then capture until it
   releases the bus *)
type rx = No_reply | Reply of Ls_host.rx_result * float

let receive b =
  let limit = b.last_eop_j + int_of_float (18.0 *. t_bit b) in
  let rec wait_sop () =
    if b.now >= limit then None
    else match tick b None with
      | Some (1, 0) -> Some (b.now - 1)          (* K: the device's SOP *)
      | Some (0, 1) | None -> wait_sop ()        (* J before SOP is allowed (the bus idles J) *)
      | Some _ -> error b "device drives SE0 before SOP"; wait_sop () in
  match wait_sop () with
  | None -> No_reply
  | Some sop ->
    let runs = ref [] and cur = ref Ls_host.K and len = ref 1 in
    let rec capture () =
      match tick b None with
      | Some (dp, dm) ->
        let s = match Ls_host.of_pins dp dm with Some s -> s | None -> error b "device drives SE1"; Ls_host.SE0 in
        if s = !cur then incr len else (runs := (!len, !cur) :: !runs; cur := s; len := 1);
        capture ()
      | None -> runs := (!len, !cur) :: !runs in
    capture ();
    let ta = float_of_int (sop - b.last_eop_j) /. t_bit b in
    b.turnarounds <- ta :: b.turnarounds;
    if ta < 2.0 || ta > 6.5 then error b (Printf.sprintf "turnaround %.2f bit times outside 2..6.5" ta);
    b.replies <- b.replies + 1;
    Reply (Ls_host.decode_runs ~t:(t_bit b) (List.rev !runs), ta)

let show_reply = function
  | No_reply -> "no reply"
  | Reply (Ls_host.Bad e, _) -> "undecodable: " ^ e
  | Reply (Ls_host.Packet bs, ta) -> Printf.sprintf "%s (%.2f bits)" (String.concat " " (List.map (Printf.sprintf "%02x") bs)) ta

let show_ref = function
  | Ref_device.Data (p, d) -> Printf.sprintf "data %02x [%s]" p (String.concat " " (List.map (Printf.sprintf "%02x") d))
  | Nak -> "NAK" | Stall -> "STALL" | Ack -> "ACK" | Silent -> "silence"

let classify = function
  | No_reply -> Some Ref_device.Silent
  | Reply (Ls_host.Bad _, _) -> None
  | Reply (Ls_host.Packet [ p ], _) when p = Ls_host.pid_ack -> Some Ack
  | Reply (Ls_host.Packet [ p ], _) when p = Ls_host.pid_nak -> Some Nak
  | Reply (Ls_host.Packet [ p ], _) when p = Ls_host.pid_stall -> Some Stall
  | Reply (Ls_host.Packet (p :: rest), _) when (p = Ls_host.pid_data0 || p = Ls_host.pid_data1) && List.length rest >= 2 ->
    if Ls_host.crc16_ok rest then Some (Data (p, List.filteri (fun i _ -> i < List.length rest - 2) rest)) else None
  | Reply (Ls_host.Packet _, _) -> None

let gap b = idle_bits b (2.0 +. Random.State.float b.rng 4.0)

(* compare a reply with the reference. Returns the classified reply. *)
let judge b what ~expect r =
  let got = classify r in
  let ok = match got, expect with
    | Some g, e when g = e -> true
    | Some Nak, Ref_device.Data _ when b.dut.nak_ok -> b.naks_tolerated <- b.naks_tolerated + 1; true
    | _ -> false in
  if b.verbose then Printf.printf "    %-28s %s%s\n" what (show_reply r) (if ok then "" else "  <- expected " ^ show_ref expect);
  if not ok then error b (Printf.sprintf "%s: got %s, expected %s" what (show_reply r) (show_ref expect));
  got

(* ---------- transactions ---------- *)

let setup_stage b ~addr setup =
  let rec attempt n =
    send b (Ls_host.token Ls_host.pid_setup ~addr ~ep:0); gap b;
    send b (Ls_host.data_packet Ls_host.pid_data0 setup);
    let r = receive b in
    match classify r with
    | Some Ack -> ignore (Ref_device.setup b.refd setup); if b.verbose then Printf.printf "    %-28s %s\n" "SETUP" (show_reply r); true
    | _ when n > 1 -> gap b; attempt (n - 1)
    | _ -> ignore (judge b "SETUP" ~expect:Ack r); false in
  attempt 3

(* one IN transaction; [ack] = whether the host acknowledges data. Returns the classified reply. *)
let in_tx ?(ack = true) b ~addr ~ep =
  let expect = Ref_device.in_ b.refd ~ep in
  send b (Ls_host.token Ls_host.pid_in ~addr ~ep);
  let r = receive b in
  let got = judge b (Printf.sprintf "IN ep%d" ep) ~expect r in
  (match got with
   | Some (Data _) when got = Some expect ->
     gap b;
     if ack then (send b [ Ls_host.pid_ack ]; Ref_device.ack b.refd)
   | _ -> ());
  gap b; got

let out_tx b ~addr ~ep ~pid data =
  send b (Ls_host.token Ls_host.pid_out ~addr ~ep); gap b;
  send b (Ls_host.data_packet pid data);
  let expect = Ref_device.out b.refd ~ep in
  let r = receive b in
  let got = judge b (Printf.sprintf "OUT ep%d" ep) ~expect r in
  gap b; got

(* retry INs that are NAKed (a slower device may NAK while it prepares) *)
let in_until_data ?(tries = 200) b ~addr ~ep =
  let rec go n =
    match in_tx b ~addr ~ep with
    | Some Nak when n > 0 -> idle_bits b 10.0; go (n - 1)
    | Some Nak -> error b "gave up after repeated NAKs"; Some Ref_device.Nak
    | r -> r in
  go tries

let control_read b ~addr setup =
  if setup_stage b ~addr setup then begin
    let rec data_stage () =
      match b.refd.Ref_device.ep0 with
      | Ref_device.Data_in _ -> (match in_until_data b ~addr ~ep:0 with Some (Data _) -> data_stage () | _ -> ())
      | Stalled -> ignore (in_tx b ~addr ~ep:0)
      | _ -> () in
    data_stage ();
    if b.refd.ep0 = Ref_device.Status_out then ignore (out_tx b ~addr ~ep:0 ~pid:Ls_host.pid_data1 [])
  end

let control_nodata b ~addr setup =
  if setup_stage b ~addr setup then begin
    match b.refd.Ref_device.ep0 with
    | Ref_device.Status_in _ -> ignore (in_until_data b ~addr ~ep:0)
    | Stalled -> ignore (in_tx b ~addr ~ep:0)
    | _ -> ()
  end

(* a packet the device must ignore: no reply, and no change of state *)
let expect_silence b what =
  match receive b with
  | No_reply -> b.silent_ok <- b.silent_ok + 1; if b.verbose then Printf.printf "    %-28s no reply\n" what
  | r -> error b (Printf.sprintf "%s: expected silence, got %s" what (show_reply r))

let get_descriptor ?(req = 0x80) ~typ ~len () = [ req; 0x06; 0x00; typ; 0x00; 0x00; len land 0xFF; len lsr 8 ]

(* the enumeration a host performs *)
let enumerate b ~addr =
  control_read b ~addr:0 (get_descriptor ~typ:1 ~len:64 ());
  bus_reset b 600_000; idle_bits b 20.0;
  control_nodata b ~addr:0 [ 0x00; 0x05; addr; 0x00; 0x00; 0x00; 0x00; 0x00 ];
  idle_bits b 20.0;
  control_read b ~addr (get_descriptor ~typ:1 ~len:18 ());
  control_read b ~addr (get_descriptor ~typ:2 ~len:9 ());
  control_read b ~addr (get_descriptor ~typ:2 ~len:255 ());
  control_nodata b ~addr [ 0x00; 0x09; 0x01; 0x00; 0x00; 0x00; 0x00; 0x00 ];
  control_nodata b ~addr [ 0x21; 0x0A; 0x00; 0x00; 0x00; 0x00; 0x00; 0x00 ];
  control_read b ~addr (get_descriptor ~req:0x81 ~typ:0x22 ~len:(List.length Descriptors.report + 64) ())

let summary b =
  let tas = b.turnarounds in
  let mn = List.fold_left min infinity tas and mx = List.fold_left max neg_infinity tas in
  Printf.sprintf "%s ppm %+d: %d clocks, %d packets sent, %d replies (turnaround %.2f..%.2f bits), %d NAKs while preparing, %d silences as required, %d keep-alives, %d resets, lockstep mismatches %d, errors %d"
    b.dut.name b.ppm b.now b.packets_sent b.replies mn mx b.naks_tolerated b.silent_ok b.keep_alives b.resets (b.dut.mismatches ()) (List.length b.errors)
