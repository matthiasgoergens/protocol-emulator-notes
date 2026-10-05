(* [usb_dump.exe DIR]: the hardened low-speed device (RTL) answers GET_DESCRIPTOR(device, 18) at address 0
   from the transaction-level host model. The resolved D+/D- line is recorded every 4th clock of the 60 MHz
   simulation clock (15 MHz, 10 samples per 1.5 Mbit/s bit) into DIR/usb-ls.bin (one byte per sample, bit 0 = D+,
   bit 1 = D-), and the bytes the bus must carry in DIR/usb-ls.expected. For tools/sigrok-judge. *)
let () =
  let dir = Sys.argv.(1) in
  let buf = Buffer.create 65536 in
  let n = ref 0 in
  Bench.tap := (fun ~dp ~dm -> (if !n land 3 = 0 then Buffer.add_char buf (Char.chr (dp lor (dm lsl 1)))); incr n);
  let dut, _ = Dut_hard.make () in
  let b = Bench.create ~ppm:0 dut in
  let setup = Bench.get_descriptor ~typ:1 ~len:18 () in
  Bench.idle_bits b 20.0;   (* a capture starts on an idle bus *)
  Bench.control_read b ~addr:0 setup;
  let oc = open_out_bin (Filename.concat dir "usb-ls.bin") in
  Buffer.output_buffer oc buf; close_out oc;
  let oc = open_out (Filename.concat dir "usb-ls.expected") in
  let l = String.concat "," in
  Printf.fprintf oc "# samplerate_hz_assumed 15000000\nusb_dp 0\nusb_dm 1\nusb_addr 0\nusb_setup %s\nusb_device_data %s\n"
    (l (List.map string_of_int setup)) (l (List.map string_of_int (List.filteri (fun i _ -> i < 18) Descriptors.device)));
  close_out oc;
  Printf.printf "usb dump: %d samples, %d errors\n" (Buffer.length buf) (List.length b.Bench.errors);
  exit (if b.Bench.errors = [] then 0 else 1)
