(* Test scenarios, written against Bench and so run unchanged on every device under test. *)
open Bench

let report_of rng = List.init 8 (fun i -> if i = 1 then 0 else if i = 0 then Random.State.int rng 256 land 0x0F else Random.State.int rng 0x66)

let offer b r = b.dut.offer_report r; Queue.push r b.refd.Ref_device.reports

(* the full enumeration, reports, and the packets a device must ignore *)
let directed b ~addr =
  if b.verbose then print_endline "  -- enumeration (with a 10 ms bus reset after the first descriptor read)";
  enumerate b ~addr;
  if b.verbose then print_endline "  -- keep-alives, then interrupt IN on endpoint 1";
  for _ = 1 to 3 do keep_alive b; idle_bits b 30.0 done;
  ignore (in_tx b ~addr ~ep:1);                          (* nothing pending: NAK *)
  let r1 = [ 0x02; 0x00; 0x0B; 0x00; 0x00; 0x00; 0x00; 0x00 ] and r2 = [ 0x00; 0x00; 0x08; 0x0F; 0x00; 0x00; 0x00; 0x00 ] in
  offer b r1; idle_bits b 10.0;
  ignore (in_until_data b ~addr ~ep:1);
  offer b r2; idle_bits b 10.0;
  ignore (in_until_data b ~addr ~ep:1);
  ignore (in_tx b ~addr ~ep:1);
  if b.verbose then print_endline "  -- packets the device must ignore";
  send b (Ls_host.token ~corrupt_crc:true Ls_host.pid_in ~addr ~ep:0); expect_silence b "IN with a bad CRC5";
  gap b;
  send b (Ls_host.token Ls_host.pid_in ~addr:((addr + 1) land 0x7F) ~ep:0); expect_silence b "IN to another address";
  gap b;
  send b (Ls_host.token Ls_host.pid_setup ~addr ~ep:0); gap b;
  send b (Ls_host.data_packet ~corrupt_crc:true Ls_host.pid_data0 (get_descriptor ~typ:1 ~len:18 ()));
  expect_silence b "SETUP data with a bad CRC16";
  gap b;
  let stuffed = get_descriptor ~typ:1 ~len:0xFF () in      (* 0xFF in wLength forces a stuff bit *)
  assert (Ls_host.stuff_count (Ls_host.data_packet Ls_host.pid_data0 stuffed) > 0);
  send b (Ls_host.token Ls_host.pid_setup ~addr ~ep:0); gap b;
  send ~skip_stuff:0 b (Ls_host.data_packet Ls_host.pid_data0 stuffed);
  expect_silence b "SETUP data missing a stuff bit";
  gap b;
  (* the device must still work after all that *)
  control_read b ~addr (get_descriptor ~typ:1 ~len:18 ());
  if b.verbose then print_endline "  -- an unsupported request is stalled";
  control_read b ~addr [ 0x80; 0x06; 0x00; 0x03; 0x00; 0x00; 0xFF; 0x00 ];   (* string descriptor: none *)
  control_read b ~addr (get_descriptor ~typ:2 ~len:34 ())

(* constrained random traffic *)
let random_session b ~n =
  let rng = b.rng in
  let addr = ref (1 + Random.State.int rng 127) in
  let short_reset () = bus_reset b (300 + Random.State.int rng 6000); idle_bits b 20.0 in
  let set_address a = control_nodata b ~addr:0 [ 0x00; 0x05; a; 0x00; 0x00; 0x00; 0x00; 0x00 ] in
  let bring_up () =
    set_address !addr; idle_bits b 20.0;
    control_nodata b ~addr:!addr [ 0x00; 0x09; 0x01; 0x00; 0x00; 0x00; 0x00; 0x00 ] in
  short_reset (); bring_up ();
  for _ = 1 to n do
    let a = !addr in
    (match Random.State.int rng 20 with
     | 0 | 1 -> keep_alive b
     | 2 -> idle_bits b (Random.State.float rng 300.0)
     | 3 | 4 ->
       let typ = [| 1; 2; 0x22; 3; 7 |].(Random.State.int rng 5) in
       let req = if typ = 0x22 then 0x81 else 0x80 in
       control_read b ~addr:a (get_descriptor ~req ~typ ~len:(Random.State.int rng 256) ())
     | 5 ->
       (* a random request: supported ones behave, the rest are stalled *)
       let s = List.init 8 (fun _ -> Random.State.int rng 256) in
       let s = List.mapi (fun i x -> if i = 0 then [| 0x00; 0x80; 0x21; 0xA1; 0x02; 0x82 |].(Random.State.int rng 6) else if i = 1 then [| 0x00; 0x01; 0x03; 0x06; 0x08; 0x0A; 0x0B; 0x0C |].(Random.State.int rng 8) else x) s in
       (* keep SET_ADDRESS out of here: it is exercised on purpose below *)
       if not (List.nth s 0 = 0x00 && List.nth s 1 = 0x05) then
         (if List.nth s 0 land 0x80 <> 0 then control_read b ~addr:a s else control_nodata b ~addr:a s)
     | 6 -> control_nodata b ~addr:a [ 0x21; 0x0A; Random.State.int rng 256; 0x00; 0x00; 0x00; 0x00; 0x00 ]
     | 7 | 8 | 9 ->
       if Queue.is_empty b.refd.reports && Random.State.bool rng then (offer b (report_of rng); idle_bits b 5.0);
       ignore (in_tx b ~addr:a ~ep:1)
     | 10 ->
       (* the host's ACK is lost: the device must send the same data again *)
       if Queue.is_empty b.refd.reports then (offer b (report_of rng); idle_bits b 5.0);
       (match in_tx ~ack:false b ~addr:a ~ep:1 with
        | Some (Ref_device.Data _) -> idle_bits b 20.0; ignore (in_until_data b ~addr:a ~ep:1)
        | _ -> ())
     | 11 ->
       send b (Ls_host.token ~corrupt_crc:true [| Ls_host.pid_in; Ls_host.pid_setup; Ls_host.pid_out |].(Random.State.int rng 3) ~addr:a ~ep:(Random.State.int rng 2));
       expect_silence b "token with a bad CRC5"
     | 12 ->
       send b (Ls_host.token Ls_host.pid_in ~addr:((a + 1 + Random.State.int rng 126) land 0x7F) ~ep:(Random.State.int rng 2));
       expect_silence b "token to another address"
     | 13 ->
       let s = get_descriptor ~typ:1 ~len:(Random.State.int rng 256) () in
       send b (Ls_host.token Ls_host.pid_setup ~addr:a ~ep:0); gap b;
       send b (Ls_host.data_packet ~corrupt_crc:true Ls_host.pid_data0 s);
       expect_silence b "SETUP data with a bad CRC16"
     | 14 ->
       let s = get_descriptor ~typ:2 ~len:0xFF () in
       let p = Ls_host.data_packet Ls_host.pid_data0 s in
       send b (Ls_host.token Ls_host.pid_setup ~addr:a ~ep:0); gap b;
       send ~skip_stuff:(Random.State.int rng (Ls_host.stuff_count p)) b p;
       expect_silence b "SETUP data missing a stuff bit"
     | 15 ->
       (* OUT data to endpoint 0 outside a transfer, random payload *)
       ignore (out_tx b ~addr:a ~ep:0 ~pid:Ls_host.pid_data0 (List.init (Random.State.int rng 9) (fun _ -> Random.State.int rng 256)))
     | 16 -> ignore (out_tx b ~addr:a ~ep:1 ~pid:Ls_host.pid_data0 [ Random.State.int rng 256 ])
     | 17 -> addr := 1 + Random.State.int rng 127; control_nodata b ~addr:a [ 0x00; 0x05; !addr; 0x00; 0x00; 0x00; 0x00; 0x00 ]; idle_bits b 20.0
     | 18 -> short_reset (); bring_up ()
     | _ -> ignore (in_tx b ~addr:a ~ep:0));
    (* random gap between transactions, sometimes with a keep-alive in it *)
    idle_bits b (2.0 +. Random.State.float rng 40.0);
    if Random.State.int rng 8 = 0 then (keep_alive b; idle_bits b (2.0 +. Random.State.float rng 10.0))
  done
