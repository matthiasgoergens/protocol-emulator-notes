open Hardcaml

let circuit = Usb_dev.circuit ()

let emit () =
  let oc = open_out "usb_fs_device.v" in
  Rtl.output ~output_mode:(To_channel oc) Verilog circuit; close_out oc

(* Simulation: the host drives dp/dm when transmitting; otherwise the bus idles at J unless the
   device drives it. Returns the device's response bytes and the turnaround in bit times. *)
type bus = { sim : Cyclesim.t_port_list; dp_in : Bits.t ref; dm_in : Bits.t ref; clear : Bits.t ref;
             dp_out : Bits.t ref; dm_out : Bits.t ref; oe : Bits.t ref; addr : Bits.t ref; configured : Bits.t ref;
             mutable cycle : int; mutable log : string list }

let make () =
  let sim = Cyclesim.create circuit in
  let i n = Cyclesim.in_port sim n and o n = Cyclesim.out_port sim n in
  let b = { sim; dp_in = i "dp_in"; dm_in = i "dm_in"; clear = i "clear"; dp_out = o "dp_out"; dm_out = o "dm_out"; oe = o "oe";
            addr = o "addr"; configured = o "configured"; cycle = 0; log = [] } in
  b.clear := Bits.vdd; Cyclesim.cycle sim; b.clear := Bits.gnd;
  b.dp_in := Bits.vdd; b.dm_in := Bits.gnd;
  for _ = 1 to 40 do Cyclesim.cycle sim done;
  b

let drive b (s : Host.line) =
  let dp, dm = match s with Host.J -> 1, 0 | K -> 0, 1 | SE0 -> 0, 0 in
  b.dp_in := Bits.of_int ~width:1 dp; b.dm_in := Bits.of_int ~width:1 dm

let device_line b =
  if Bits.to_int !(b.oe) = 1 then
    (match Bits.to_int !(b.dp_out), Bits.to_int !(b.dm_out) with 1, 0 -> Host.J | 0, 1 -> K | _ -> SE0)
  else Host.J

let step b = Cyclesim.cycle b.sim; b.cycle <- b.cycle + 1

let send b bytes =
  List.iter (fun s -> drive b s; step b) (Host.to_samples (Host.encode bytes));
  drive b Host.J

(* wait up to [max_bits] bit times for the device to start driving; capture until it stops *)
let receive b ~max_bits =
  let waited = ref 0 and started = ref false in
  while not !started && !waited < max_bits * Host.samples_per_bit do
    step b; incr waited;
    if Bits.to_int !(b.oe) = 1 then started := true
  done;
  if not !started then None
  else begin
    let samples = ref [] in
    (* the device is driving now; capture until oe drops *)
    while Bits.to_int !(b.oe) = 1 do samples := device_line b :: !samples; step b done;
    let arr = Array.of_list (List.rev !samples) in
    let first_k = let rec f i = if i >= Array.length arr then 0 else if arr.(i) = Host.K then i else f (i + 1) in f 0 in
    let turnaround_bits = float_of_int (!waited + first_k) /. float_of_int Host.samples_per_bit in
    Some (Host.decode arr first_k, turnaround_bits)
  end

let idle b n = for _ = 1 to n do step b done

let show = function None -> "no response" | Some (None, _) -> "undecodable" | Some (Some bs, t) ->
  Printf.sprintf "%s (turnaround %.2f bit times)" (String.concat " " (List.map (Printf.sprintf "%02x") bs)) t

(* USB 2.0 7.1.19: a full-speed device must answer within 6.5 bit times and not before 2 *)
let expect name got want =
  let ok = match got with Some (Some bs, t) -> bs = want && t >= 2.0 && t <= 6.5 | _ -> false in
  Printf.printf "  %-34s %s -> %s\n" name (show got) (if ok then "ok" else "MISMATCH, expected " ^ String.concat " " (List.map (Printf.sprintf "%02x") want));
  ok

let control_in b ~addr ~setup ~expect_data =
  (* SETUP stage *)
  send b (Host.token Usb_sie.pid_setup ~addr ~ep:0); send b (Host.data_packet Usb_sie.pid_data0 setup);
  let r1 = receive b ~max_bits:20 in
  let ok = ref (expect "setup ack" r1 [ Usb_sie.pid_ack ]) in
  idle b 16;
  (* data stage: IN packets until short packet *)
  let got = ref [] and toggle = ref 1 and fin = ref false in
  while not !fin do
    send b (Host.token Usb_sie.pid_in ~addr ~ep:0);
    (match receive b ~max_bits:20 with
     | Some (Some (pid :: rest), _) when pid = (if !toggle = 1 then Usb_sie.pid_data1 else Usb_sie.pid_data0) ->
       let payload = List.filteri (fun i _ -> i < List.length rest - 2) rest in
       let crc_ok = Host.crc16 (Host.bits_of_bytes rest) = 0xB001 in
       if not crc_ok then (Printf.printf "  data crc bad\n"; ok := false);
       got := !got @ payload; toggle := 1 - !toggle;
       send b (Host.handshake Usb_sie.pid_ack); idle b 16;
       if List.length payload < 8 || List.length !got >= List.length expect_data then fin := true
     | r -> Printf.printf "  data stage: %s\n" (show r); ok := false; fin := true)
  done;
  Printf.printf "  %-34s %s -> %s\n" "data" (String.concat " " (List.map (Printf.sprintf "%02x") !got)) (if !got = expect_data then "ok" else "MISMATCH");
  if !got <> expect_data then ok := false;
  (* status stage: OUT zero-length DATA1 *)
  send b (Host.token Usb_sie.pid_out ~addr ~ep:0); send b (Host.data_packet Usb_sie.pid_data1 []);
  ok := expect "status ack" (receive b ~max_bits:20) [ Usb_sie.pid_ack ] && !ok;
  idle b 16; !ok

let control_no_data b ~addr ~setup =
  send b (Host.token Usb_sie.pid_setup ~addr ~ep:0); send b (Host.data_packet Usb_sie.pid_data0 setup);
  let ok = ref (expect "setup ack" (receive b ~max_bits:20) [ Usb_sie.pid_ack ]) in
  idle b 16;
  send b (Host.token Usb_sie.pid_in ~addr ~ep:0);
  ok := expect "status zero-length DATA1" (receive b ~max_bits:20) (Host.data_packet Usb_sie.pid_data1 []) && !ok;
  send b (Host.handshake Usb_sie.pid_ack); idle b 16; !ok

let () =
  emit ();
  (* host-model self-check against known bytes *)
  assert (Host.token Usb_sie.pid_setup ~addr:0 ~ep:0 = [ 0x2D; 0x00; 0x10 ]);
  assert (Host.data_packet Usb_sie.pid_data0 [ 0x80; 0x06; 0x00; 0x01; 0x00; 0x00; 0x40; 0x00 ] = [ 0xC3; 0x80; 0x06; 0x00; 0x01; 0x00; 0x00; 0x40; 0x00; 0xDD; 0x94 ]);
  assert (Host.decode (Array.of_list (Host.to_samples (Host.encode [ 0xC3; 0x80; 0x06; 0xFF; 0xFF; 0x7E ]))) 0 = Some [ 0xC3; 0x80; 0x06; 0xFF; 0xFF; 0x7E ]);
  print_endline "host model self-checks pass";
  let b = make () in
  let ok = ref true in
  print_endline "== enumeration at address 0";
  ok := control_in b ~addr:0 ~setup:[ 0x80; 0x06; 0x00; 0x01; 0x00; 0x00; 0x08; 0x00 ] ~expect_data:(List.filteri (fun i _ -> i < 8) Usb_sie.device_descriptor) && !ok;
  print_endline "== set address 5";
  ok := control_no_data b ~addr:0 ~setup:[ 0x00; 0x05; 0x05; 0x00; 0x00; 0x00; 0x00; 0x00 ] && !ok;
  Printf.printf "  device address register: %d\n" (Bits.to_int !(b.addr));
  print_endline "== device descriptor at address 5";
  ok := control_in b ~addr:5 ~setup:[ 0x80; 0x06; 0x00; 0x01; 0x00; 0x00; 0x12; 0x00 ] ~expect_data:Usb_sie.device_descriptor && !ok;
  print_endline "== configuration descriptor, 9 then 32 bytes";
  ok := control_in b ~addr:5 ~setup:[ 0x80; 0x06; 0x00; 0x02; 0x00; 0x00; 0x09; 0x00 ] ~expect_data:(List.filteri (fun i _ -> i < 9) Usb_sie.config_descriptor) && !ok;
  ok := control_in b ~addr:5 ~setup:[ 0x80; 0x06; 0x00; 0x02; 0x00; 0x00; 0x20; 0x00 ] ~expect_data:Usb_sie.config_descriptor && !ok;
  print_endline "== set configuration 1";
  ok := control_no_data b ~addr:5 ~setup:[ 0x00; 0x09; 0x01; 0x00; 0x00; 0x00; 0x00; 0x00 ] && !ok;
  Printf.printf "  configured flag: %d\n" (Bits.to_int !(b.configured));
  print_endline "== bulk loopback on endpoint 1";
  send b (Host.token Usb_sie.pid_in ~addr:5 ~ep:1);
  ok := expect "IN on empty buffer" (receive b ~max_bits:20) [ Usb_sie.pid_nak ] && !ok; idle b 16;
  let msg = [ 0x68; 0x65; 0x6C; 0x6C; 0x6F; 0x21; 0x21; 0x21 ] in
  send b (Host.token Usb_sie.pid_out ~addr:5 ~ep:1); send b (Host.data_packet Usb_sie.pid_data0 msg);
  ok := expect "OUT data ack" (receive b ~max_bits:20) [ Usb_sie.pid_ack ] && !ok; idle b 16;
  send b (Host.token Usb_sie.pid_in ~addr:5 ~ep:1);
  ok := expect "IN returns the data" (receive b ~max_bits:20) (Host.data_packet Usb_sie.pid_data0 msg) && !ok;
  send b (Host.handshake Usb_sie.pid_ack); idle b 16;
  send b (Host.token Usb_sie.pid_in ~addr:5 ~ep:1);
  ok := expect "IN again is NAK" (receive b ~max_bits:20) [ Usb_sie.pid_nak ] && !ok; idle b 16;
  print_endline "== corrupted OUT data must be rejected (no handshake at all)";
  (let bad = Host.data_packet Usb_sie.pid_data0 msg in
   let bad = List.mapi (fun i x -> if i = 2 then x lxor 0x01 else x) bad in
   send b (Host.token Usb_sie.pid_out ~addr:5 ~ep:1); send b bad;
   ok := (match receive b ~max_bits:20 with None -> Printf.printf "  no response -> ok\n"; true | r -> Printf.printf "  %s -> MISMATCH, device accepted corrupt data\n" (show r); false) && !ok);
  idle b 16;
  print_endline "== wrong address is ignored";
  send b (Host.token Usb_sie.pid_in ~addr:6 ~ep:1);
  ok := (match receive b ~max_bits:20 with None -> Printf.printf "  no response -> ok\n"; true | r -> Printf.printf "  %s -> MISMATCH\n" (show r); false) && !ok;
  print_endline (if !ok then "USB DEVICE PASS" else "USB DEVICE FAIL");
  exit (if !ok then 0 else 1)
