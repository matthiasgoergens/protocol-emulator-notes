open Hardcaml

let h = 3                      (* 60 MHz clock: three cycles per half bit, 100 ns per bit *)
let nlp_test_period = 4000     (* link pulses every 4000 cycles in the test; 16 ms on the chip *)

let frame = Eth_model.udp_frame ~dst_mac:[ 0xFF; 0xFF; 0xFF; 0xFF; 0xFF; 0xFF ] ~src_mac:[ 0x02; 0x00; 0x00; 0x12; 0x34; 0x56 ]
    ~src_ip:[ 192; 168; 1; 200 ] ~dst_ip:[ 192; 168; 1; 255 ] ~src_port:4096 ~dst_port:4096
    ~payload:(List.map Char.code [ 'h'; 'e'; 'l'; 'l'; 'o'; ' '; 'f'; 'r'; 'o'; 'm'; ' '; 'a'; 's'; 'i'; 'c' ])

let hex bs = String.concat " " (List.map (Printf.sprintf "%02x") bs)

(* run the transmitter and capture differential samples: +1, -1 or 0 *)
let run_tx ~cycles =
  let c = Eth_tx.circuit ~h ~nlp_period:nlp_test_period ~frame in
  let sim = Cyclesim.create c in
  let clear = Cyclesim.in_port sim "clear" and start = Cyclesim.in_port sim "start" in
  let txp = Cyclesim.out_port sim "txp" and txn = Cyclesim.out_port sim "txn" and txen = Cyclesim.out_port sim "txen" in
  clear := Bits.vdd; Cyclesim.cycle sim; clear := Bits.gnd;
  let out = Array.make cycles 0 in
  for i = 0 to cycles - 1 do
    start := Bits.of_int ~width:1 (if i = 100 then 1 else 0);
    Cyclesim.cycle sim;
    out.(i) <- (if Bits.to_int !txen = 1 then (if Bits.to_int !txp = 1 then 1 else if Bits.to_int !txn = 1 then -1 else 0) else 0)
  done;
  out

(* feed samples into the receiver; return the frames it produced with their crc flags *)
let run_rx (samples : int array) =
  let c = Eth_rx.circuit ~h in
  let sim = Cyclesim.create c in
  let clear = Cyclesim.in_port sim "clear" and rx = Cyclesim.in_port sim "rx" and act = Cyclesim.in_port sim "rx_active" in
  let byte = Cyclesim.out_port sim "rx_byte" and bv = Cyclesim.out_port sim "byte_valid" and fe = Cyclesim.out_port sim "frame_end" and ok = Cyclesim.out_port sim "crc_ok" in
  clear := Bits.vdd; Cyclesim.cycle sim; clear := Bits.gnd;
  let frames = ref [] and cur = ref [] in
  Array.iter (fun s ->
    rx := Bits.of_int ~width:1 (if s > 0 then 1 else 0); act := Bits.of_int ~width:1 (if s <> 0 then 1 else 0);
    Cyclesim.cycle sim;
    if Bits.to_int !bv = 1 then cur := Bits.to_int !byte :: !cur;
    if Bits.to_int !fe = 1 then (frames := (List.rev !cur, Bits.to_int !ok = 1) :: !frames; cur := [])) samples;
  for _ = 1 to 40 do rx := Bits.gnd; act := Bits.gnd; Cyclesim.cycle sim; if Bits.to_int !fe = 1 then (frames := (List.rev !cur, Bits.to_int !ok = 1) :: !frames; cur := []) done;
  List.rev !frames

let () =
  (* model self-checks *)
  assert (Eth_model.crc32 (List.map Char.code [ '1'; '2'; '3'; '4'; '5'; '6'; '7'; '8'; '9' ]) = 0xCBF43926);
  Printf.printf "crc32 residual after data+fcs = %08x (receiver uses %08x)\n" Eth_model.residual Eth_rx.residual;
  assert (Eth_model.residual = Eth_rx.residual);
  let enc = Array.of_list (Eth_model.encode_frame ~h frame) in
  (match Eth_model.decode ~h enc with
   | [ bs ] when bs = frame @ Eth_model.fcs_bytes frame -> print_endline "model encode/decode round trip ok"
   | fs -> Printf.printf "model round trip FAILED: %d frames\n" (List.length fs); exit 1);
  Printf.printf "frame: %d bytes, fcs %s\n" (List.length frame) (hex (Eth_model.fcs_bytes frame));
  let ok = ref true in
  (* transmitter *)
  let tx = run_tx ~cycles:20000 in
  let decoded = Eth_model.decode ~h tx in
  (match decoded with
   | (bs :: _) -> let want = frame @ Eth_model.fcs_bytes frame in
     Printf.printf "transmitter frame decoded by the model: %s\n" (if bs = want then "matches, FCS correct" else "MISMATCH\n got " ^ hex bs ^ "\n want " ^ hex want);
     if bs <> want then ok := false
   | [] -> print_endline "transmitter: model decoded nothing -> FAIL"; ok := false);
  (* timing: every mid-bit transition of the frame is exactly 2h cycles after the previous one *)
  let trans = ref [] in
  Array.iteri (fun i s -> if i > 0 && s <> 0 && tx.(i - 1) <> 0 && s <> tx.(i - 1) then trans := i :: !trans) tx;
  let trans = List.rev !trans in
  let rec gaps = function a :: (b :: _ as r) -> (b - a) :: gaps r | _ -> [] in
  let gs = gaps trans in
  let n_h = List.length (List.filter (( = ) h) gs) and n_2h = List.length (List.filter (( = ) (2 * h)) gs) and n_other = List.length (List.filter (fun g -> g <> h && g <> 2 * h) gs) in
  Printf.printf "transition spacings: %d half-bit, %d full-bit, %d other (expect 0 other)\n" n_h n_2h n_other;
  if n_other <> 0 then ok := false;
  (* link pulses in idle: positive pulses of 2h cycles, spaced nlp_test_period apart *)
  let pulses = ref [] in
  let i = ref 0 in
  while !i < Array.length tx do
    if tx.(!i) = 1 && (!i = 0 || tx.(!i - 1) = 0) then begin
      let j = ref !i in while !j < Array.length tx && tx.(!j) = 1 do incr j done;
      if !j - !i = 2 * h && (!j >= Array.length tx || tx.(!j) = 0) then pulses := !i :: !pulses; i := !j
    end else incr i
  done;
  let pulses = List.rev !pulses in
  let pgaps = gaps pulses in
  Printf.printf "link pulses: %d found, spacings %s (expect %d)\n" (List.length pulses) (String.concat "," (List.map string_of_int pgaps)) nlp_test_period;
  if not (List.length pulses >= 2 && List.for_all (( = ) nlp_test_period) (List.filteri (fun k _ -> k > 0) pgaps)) then ok := false;
  (* receiver on the model's encoding *)
  (match run_rx enc with
   | [ (bs, c) ] -> Printf.printf "receiver on model frame: %d bytes, crc_ok=%b -> %s\n" (List.length bs) c
       (if bs = frame @ Eth_model.fcs_bytes frame && c then "ok" else "MISMATCH"); if not (bs = frame @ Eth_model.fcs_bytes frame && c) then ok := false
   | fs -> Printf.printf "receiver on model frame: %d frames -> FAIL\n" (List.length fs); ok := false);
  (* receiver on a corrupted frame *)
  let bad = Array.copy enc in
  let k = 2 * h * 8 * 8 + 2 * h * 8 * 20 + h in  (* somewhere in the 20th byte after the SFD *)
  bad.(k) <- - bad.(k); bad.(k + 1) <- - bad.(k + 1); bad.(k + 2) <- - bad.(k + 2);
  (match run_rx bad with
   | [ (_, c) ] -> Printf.printf "receiver on corrupted frame: crc_ok=%b -> %s\n" c (if c then "MISMATCH, accepted" else "rejected, ok"); if c then ok := false
   | fs -> Printf.printf "receiver on corrupted frame: %d frames\n" (List.length fs));
  (* loopback: transmitter output into the receiver *)
  (match run_rx tx with
   | (bs, c) :: _ -> Printf.printf "receiver on transmitter output: crc_ok=%b, bytes match=%b -> %s\n" c (bs = frame @ Eth_model.fcs_bytes frame)
       (if c && bs = frame @ Eth_model.fcs_bytes frame then "ok" else "MISMATCH"); if not (c && bs = frame @ Eth_model.fcs_bytes frame) then ok := false
   | [] -> print_endline "loopback: no frame -> FAIL"; ok := false);
  (* emit the combined top for synthesis *)
  let oc = open_out "eth_10base_t.v" in
  Rtl.output ~output_mode:(To_channel oc) Verilog (Eth_top.circuit ~h ~nlp_period:960_000 ~frame); close_out oc;
  print_endline (if !ok then "ETHERNET PASS" else "ETHERNET FAIL");
  exit (if !ok then 0 else 1)
