(* Checks for the pin-vector streamer: lockstep of the RTL against the model on random
   configurations and host traffic, then protocols built purely by precomputation, each judged by an
   independent reference (a UART receiver, an SPI slave, the Ethernet model's encoder). *)
open Hardcaml

let sim_of ?fault () =
  let sim = Cyclesim.create (Streamer.circuit ?fault ()) in
  let i n = Cyclesim.in_port sim n and o n = Cyclesim.out_port sim n in
  sim, i, o

let lockstep ?fault ~seed ~cycles () =
  Random.init seed;
  let width = [| 1; 2; 4 |].(Random.int 3) in
  let cfg = { Model.period = 1 + Random.int 6; width; od_mask = Random.int 16; idle_out = Random.int 16; idle_oe = Random.int 16 } in
  let m = Model.create cfg in
  let sim, i, o = sim_of ?fault () in
  i "clear" := Bits.vdd; Cyclesim.cycle sim; i "clear" := Bits.gnd;
  i "period" := Bits.of_int ~width:12 cfg.period; i "width" := Bits.of_int ~width:3 width;
  i "od_mask" := Bits.of_int ~width:4 cfg.od_mask; i "idle_out" := Bits.of_int ~width:4 cfg.idle_out;
  i "idle_oe" := Bits.of_int ~width:4 cfg.idle_oe;
  let bad = ref 0 in
  for _ = 1 to cycles do
    (* bursty host traffic, so the FIFO both fills and runs dry *)
    let push = Random.int 4 = 0 && not (Model.full m) in
    let data = Random.int 0x10000 and count = (if Random.bool () then 0 else Random.int 16) in
    i "host_push" := Bits.of_int ~width:1 (if push then 1 else 0);
    i "host_data" := Bits.of_int ~width:16 data; i "host_count" := Bits.of_int ~width:4 count;
    Cyclesim.cycle sim;
    Model.step m;
    if push then Model.push ~count m data;
      let ro = Bits.to_int !(o "pin_out") and roe = Bits.to_int !(o "pin_oe") in
    if ro <> m.out || roe <> m.oe then begin
      incr bad;
      if !bad <= 3 then Printf.printf "  seed %d: rtl out=%x oe=%x, model out=%x oe=%x\n" seed ro roe m.out m.oe
    end
  done;
  !bad

let () =
  let total = ref 0 in
  for seed = 1 to 200 do total := !total + lockstep ~seed ~cycles:2000 () done;
  Printf.printf "lockstep, 200 random configurations x 2000 clocks: %d mismatching clocks -> %s\n" !total
    (if !total = 0 then "PASS" else "FAIL")

(* control: a planted fault (7 vectors per word at width 2 instead of 8) must be caught *)
let () =
  let caught = ref 0 and w2 = ref 0 in
  for seed = 1 to 200 do
    Random.init seed;
    let width = [| 1; 2; 4 |].(Random.int 3) in
    if width = 2 then incr w2;
    if lockstep ~fault:true ~seed ~cycles:2000 () > 0 then incr caught
  done;
  Printf.printf "control, planted fault at width 2: caught in %d of 200 configurations (%d of them use width 2) -> %s\n"
    !caught !w2 (if !caught > 0 && !caught <= !w2 then "caught" else "MISSED or spurious")

(* ---- protocols by precomputation on the RTL: the host keeps the FIFO topped up, the CPU does nothing ---- *)

(* pack a list of vectors (each [width] bits) into 16-bit words, first vector in the low bits *)
let pack ~width vs =
  let per = 16 / width in
  let rec go acc = function
    | [] -> List.rev acc
    | l ->
      let chunk = List.filteri (fun i _ -> i < per) l and rest = List.filteri (fun i _ -> i >= per) l in
      let w = List.fold_left (fun (w, k) v -> (w lor (v lsl (k * width)), k + 1)) (0, 0) chunk |> fst in
      let n = List.length chunk in
      go ((w, if n = per then 0 else n) :: acc) rest in
  go [] vs

(* run the streamer RTL with host words; returns per-clock (out, oe) *)
(* control mode: flip bits 1 and 3 of the third word, so each reference must report a failure. (Bit 1
   alone was a bad control for SPI: at width 2 it is MOSI during SCK low, which a mode-0 slave
   rightly ignores.) *)
let corrupt = ref false

let run_rtl ~period ~width ~od_mask ~idle_out ~idle_oe ~words ~cycles =
  let words = if !corrupt then List.mapi (fun k (w, n) -> if k = 2 then (w lxor 10, n) else (w, n)) words else words in
  let sim, i, o = sim_of () in
  i "clear" := Bits.vdd; Cyclesim.cycle sim; i "clear" := Bits.gnd;
  i "period" := Bits.of_int ~width:12 period; i "width" := Bits.of_int ~width:3 width;
  i "od_mask" := Bits.of_int ~width:4 od_mask; i "idle_out" := Bits.of_int ~width:4 idle_out;
  i "idle_oe" := Bits.of_int ~width:4 idle_oe;
  let q = ref words in
  Array.init cycles (fun _ ->
    let push = !q <> [] && Bits.to_int !(o "full") = 0 in
    i "host_push" := Bits.of_int ~width:1 (if push then 1 else 0);
    let (w, n) = match !q with e :: _ -> e | [] -> (0, 0) in
    i "host_data" := Bits.of_int ~width:16 w; i "host_count" := Bits.of_int ~width:4 n;
    Cyclesim.cycle sim;
    if push then q := List.tl !q;
    (Bits.to_int !(o "pin_out"), Bits.to_int !(o "pin_oe")))

let bytes = [ 0x48; 0x65; 0x6C; 0x6C; 0x6F; 0x00; 0xFF; 0xA5; 0x5A ]
let verdict name ok detail =
  if !corrupt then Printf.printf "control %-8s (bits flipped) -> %s\n" name (if ok then "MISSED" else "caught")
  else Printf.printf "%-8s %s -> %s\n" name detail (if ok then "PASS" else "FAIL")

(* UART 8N1: precomputation adds start (0) and stop (1) bits; reference: an independent receiver
   that finds each falling start edge and samples every bit in its middle *)
let uart () =
  let p = 16 in
  let bits = List.concat_map (fun b -> [ 0 ] @ List.init 8 (fun i -> (b lsr i) land 1) @ [ 1 ]) bytes in
  let trace = run_rtl ~period:p ~width:1 ~od_mask:0 ~idle_out:1 ~idle_oe:1 ~words:(pack ~width:1 bits)
      ~cycles:(p * (List.length bits + 20)) in
  let line c = fst trace.(c) land 1 in
  let got = ref [] and c = ref 1 in
  while !c < Array.length trace - (10 * p) do
    if line (!c - 1) = 1 && line !c = 0 then begin
      let mid k = line (!c + (k * p) + (p / 2)) in
      if mid 0 = 0 && mid 9 = 1 then got := List.fold_left (fun a i -> a lor (mid (1 + i) lsl i)) 0 (List.init 8 Fun.id) :: !got;
      c := !c + (10 * p) - (p / 2)
    end else incr c
  done;
  let got = List.rev !got in
  verdict "UART" (got = bytes) (Printf.sprintf "%d bytes sent, receiver decoded %d, equal %b" (List.length bytes) (List.length got) (got = bytes))

(* SPI mode 0, MSB first: pins 0 = SCK, 1 = MOSI; two vectors per bit (SCK low with data, SCK high);
   reference: a slave sampling MOSI on each rising edge of SCK *)
let spi () =
  let vecs = List.concat_map (fun b -> List.concat (List.init 8 (fun i -> let d = (b lsr (7 - i)) land 1 in [ d lsl 1; (d lsl 1) lor 1 ]))) bytes in
  let trace = run_rtl ~period:5 ~width:2 ~od_mask:0 ~idle_out:0 ~idle_oe:3 ~words:(pack ~width:2 vecs)
      ~cycles:(5 * (List.length vecs + 20)) in
  let bits = ref [] in
  for c = 1 to Array.length trace - 1 do
    let sck c = fst trace.(c) land 1 and mosi c = (fst trace.(c) lsr 1) land 1 in
    if sck (c - 1) = 0 && sck c = 1 then bits := mosi c :: !bits
  done;
  let bits = List.rev !bits in
  let got = List.init (List.length bits / 8) (fun k -> List.fold_left (fun a i -> (a lsl 1) lor List.nth bits (8 * k + i)) 0 (List.init 8 Fun.id)) in
  verdict "SPI" (got = bytes) (Printf.sprintf "%d rising SCK edges, slave decoded %d bytes, equal %b" (List.length bits) (List.length got) (got = bytes))

(* I2C write, open drain on both pins: pin 0 = SCL, 1 = SDA; four vectors per bit; START and STOP
   as SDA edges while SCL is high; the ACK slot released. Reference: pull-ups (a released pin reads
   1), START/STOP detection, SDA sampled on each rising SCL edge, 9 bits per byte *)
let i2c () =
  let v ~scl ~sda = scl lor (sda lsl 1) in
  let bit d = [ v ~scl:0 ~sda:d; v ~scl:1 ~sda:d; v ~scl:1 ~sda:d; v ~scl:0 ~sda:d ] in
  let start = [ v ~scl:1 ~sda:1; v ~scl:1 ~sda:0; v ~scl:0 ~sda:0 ] and stop = [ v ~scl:0 ~sda:0; v ~scl:1 ~sda:0; v ~scl:1 ~sda:1 ] in
  let frame = [ 0x50 lsl 1 ] @ bytes in   (* address 0x50, write *)
  let vecs = start @ List.concat_map (fun b -> List.concat (List.init 8 (fun i -> bit ((b lsr (7 - i)) land 1))) @ bit 1) frame @ stop in
  let trace = run_rtl ~period:4 ~width:2 ~od_mask:3 ~idle_out:0 ~idle_oe:0 ~words:(pack ~width:2 vecs)
      ~cycles:(4 * (List.length vecs + 20)) in
  let line c pin = let (out, oe) = trace.(c) in if (oe lsr pin) land 1 = 1 then (out lsr pin) land 1 else 1 in
  let starts = ref 0 and stops = ref 0 and bits = ref [] in
  for c = 1 to Array.length trace - 1 do
    let scl = line c 0 and sda = line c 1 and sda0 = line (c - 1) 1 and scl0 = line (c - 1) 0 in
    if scl = 1 && scl0 = 1 && sda0 = 1 && sda = 0 then incr starts;
    if scl = 1 && scl0 = 1 && sda0 = 0 && sda = 1 then incr stops;
    if scl0 = 0 && scl = 1 then bits := sda :: !bits
  done;
  let bits = List.rev !bits in
  let got = List.init (List.length bits / 9) (fun k -> List.fold_left (fun a i -> (a lsl 1) lor List.nth bits (9 * k + i)) 0 (List.init 8 Fun.id)) in
  let acks = List.init (List.length bits / 9) (fun k -> List.nth bits (9 * k + 8)) in
  let ok = !starts = 1 && !stops = 1 && got = frame && List.for_all (( = ) 1) acks in
  verdict "I2C" ok (Printf.sprintf "%d START, %d STOP, decoded %d bytes (address + data), equal %b, ACK slots released %b"
                      !starts !stops (List.length got) (got = frame) (List.for_all (( = ) 1) acks))

(* 10BASE-T: one pin, 3 clocks per half-bit, Manchester half-bits plus TP_IDL precomputed; when the
   words run out the idle state drops the output enable. Reference: the Ethernet model's encoder,
   clock for clock, including TP_IDL and the idle gap (sample 0 = output disabled) *)
let ethernet () =
  let h = 3 in
  let frame = Eth_model.udp_frame ~dst_mac:[ 0xFF; 0xFF; 0xFF; 0xFF; 0xFF; 0xFF ] ~src_mac:[ 0x02; 0; 0; 0x12; 0x34; 0x56 ]
      ~src_ip:[ 192; 168; 1; 200 ] ~dst_ip:[ 192; 168; 1; 255 ] ~src_port:4096 ~dst_port:4096
      ~payload:(List.map Char.code [ 's'; 't'; 'r'; 'e'; 'a'; 'm'; 'e'; 'r' ]) in
  let model = Array.of_list (Eth_model.encode_frame ~h frame) in
  let wire = List.init 7 (fun _ -> 0x55) @ [ 0xD5 ] @ frame @ Eth_model.fcs_bytes frame in
  let half = List.concat_map (fun b -> [ 1 - b; b ]) (List.concat_map Eth_model.bits_of_byte wire) @ [ 1; 1; 1 ] in
  let words = pack ~width:1 half in
  let cycles = Array.length model + 40 in
  let trace = run_rtl ~period:h ~width:1 ~od_mask:0 ~idle_out:0 ~idle_oe:0 ~words ~cycles in
  (* the first vector is driven in clock 1 (the host's first push lands at the end of clock 0) *)
  let off = 1 in
  let pin c = let (out, oe) = trace.(c + off) in if oe land 1 = 0 then 0 else if out land 1 = 1 then 1 else -1 in
  let bad = ref 0 and first = ref (-1) in
  for c = 0 to Array.length model - 1 do
    if pin c <> model.(c) then (incr bad; if !first < 0 then first := c)
  done;
  verdict "10BASE-T" (!bad = 0)
    (Printf.sprintf "%d clocks (frame, TP_IDL and idle gap) compared with the Ethernet model: %d mismatches%s" (Array.length model) !bad
       (if !first >= 0 then Printf.sprintf ", first at clock %d" !first else ""))

let () =
  List.iter (fun f -> f ()) [ uart; spi; i2c; ethernet ];
  corrupt := true;
  List.iter (fun f -> f ()) [ uart; spi; i2c; ethernet ]
