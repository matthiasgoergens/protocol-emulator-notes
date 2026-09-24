(* Checks for the pin sampler: lockstep against the model, a planted-fault control, then receive
   paths each judged by an independent reference. *)
open Hardcaml

let make ?fault (c : Model.cfg) =
  let sim = Cyclesim.create (Sampler.circuit ?fault ()) in
  let i n = Cyclesim.in_port sim n and o n = Cyclesim.out_port sim n in
  i "clear" := Bits.vdd; Cyclesim.cycle sim; i "clear" := Bits.gnd;
  i "clocked" := Bits.of_int ~width:1 (if c.clocked then 1 else 0);
  i "period" := Bits.of_int ~width:12 c.period; i "width" := Bits.of_int ~width:3 c.width;
  i "trig_pin" := Bits.of_int ~width:2 c.trig_pin; i "trig_val" := Bits.of_int ~width:1 c.trig_val;
  i "offset" := Bits.of_int ~width:12 c.offset; i "frame_len" := Bits.of_int ~width:8 c.frame_len;
  sim, i, o

(* one clock on the RTL: returns the entry popped this clock, if any *)
let rtl_step (sim, i, o) ~pins ~pop =
  let valid = Bits.to_int !(o "valid") = 1 in
  let head = if pop && valid then Some (Bits.to_int !(o "data"), Bits.to_int !(o "count")) else None in
  i "pins" := Bits.of_int ~width:4 pins; i "pop" := Bits.of_int ~width:1 (if pop then 1 else 0);
  Cyclesim.cycle sim;
  head

let lockstep ?fault ~seed ~cycles () =
  Random.init seed;
  let c = { Model.clocked = Random.bool (); period = 1 + Random.int 5; width = [| 1; 2; 4 |].(Random.int 3);
            trig_pin = Random.int 4; trig_val = Random.int 2; offset = Random.int 4;
            frame_len = (if Random.bool () then 0 else 1 + Random.int 20) } in
  let m = Model.create c and r = make ?fault c in
  let bad = ref 0 in
  for _ = 1 to cycles do
    let pins = Random.int 16 and pop = Random.int 3 = 0 in
    let a = Model.step m ~pins ~pop and b = rtl_step r ~pins ~pop in
    if a <> b then incr bad
  done;
  !bad, c.width

let () =
  let total = ref 0 in
  for seed = 1 to 300 do total := !total + fst (lockstep ~seed ~cycles:2000 ()) done;
  Printf.printf "lockstep, 300 random configurations x 2000 clocks: %d mismatching pops -> %s\n" !total (if !total = 0 then "PASS" else "FAIL");
  (* control: the planted fault writes n (16 / width) instead of 0 as the count of a full word. In
     the 4-bit field that is 8 at width 2 and 4 at width 4, but 16 wraps to 0 at width 1, so the
     fault can show only at widths 2 and 4, and only where a full word is popped *)
  let caught = ref 0 and by_width = Array.make 5 0 and cfgs = Array.make 5 0 in
  for seed = 1 to 300 do
    (* the width comes back from the run itself: replaying the random draws is unreliable, since
       OCaml does not fix the evaluation order of a record's fields *)
    let bad, w = lockstep ~fault:true ~seed ~cycles:2000 () in
    cfgs.(w) <- cfgs.(w) + 1;
    if bad > 0 then (incr caught; by_width.(w) <- by_width.(w) + 1)
  done;
  Printf.printf "control by width: caught at width 1 in %d of %d, width 2 in %d of %d, width 4 in %d of %d\n"
    by_width.(1) cfgs.(1) by_width.(2) cfgs.(2) by_width.(4) cfgs.(4);
  Printf.printf "control, planted count fault: caught in %d of 300 configurations -> %s\n" !caught
    (if !caught > 0 && by_width.(1) = 0 then "caught, and never at width 1" else "UNEXPECTED")

(* ---- receive paths, each judged by an independent reference ---- *)

let verdict name ok detail = Printf.printf "%-9s %s -> %s\n" name detail (if ok then "PASS" else "FAIL")

(* drain every entry the host sees; the host pops whenever an entry is valid *)
let capture r ~pins_at ~cycles =
  let got = ref [] in
  for c = 0 to cycles - 1 do
    match rtl_step r ~pins:(pins_at c) ~pop:true with Some e -> got := e :: !got | None -> ()
  done;
  List.rev !got

let vectors ~width (w, n) = let n = if n = 0 then 16 / width else n in List.init n (fun k -> (w lsr (k * width)) land ((1 lsl width) - 1))

(* UART receive: a reference transmitter writes the line (idle high, start, 8 data LSB first, stop)
   with random gaps between bytes; timed mode triggers on the falling start edge and samples 10 bits
   from mid start bit; the host keeps frames with start 0 and stop 1 *)
let () =
  Random.init 7;
  let p = 16 in
  let bytes = List.init 12 (fun _ -> Random.int 256) in
  let line = List.concat_map (fun b ->
      List.init (Random.int 40) (fun _ -> 1) @ List.concat_map (fun v -> List.init p (fun _ -> v))
        ([ 0 ] @ List.init 8 (fun i -> (b lsr i) land 1) @ [ 1 ])) bytes @ List.init 50 (fun _ -> 1) in
  let line = Array.of_list (List.init 20 (fun _ -> 1) @ line) in
  let r = make { Model.clocked = false; period = p; width = 1; trig_pin = 0; trig_val = 0; offset = (p / 2) - 1; frame_len = 10 } in
  let frames = capture r ~pins_at:(fun c -> line.(c)) ~cycles:(Array.length line) in
  let got = List.filter_map (fun e ->
      match vectors ~width:1 e with
      | 0 :: rest when List.length rest = 9 && List.nth rest 8 = 1 ->
        Some (List.fold_left (fun a i -> a lor (List.nth rest i lsl i)) 0 (List.init 8 Fun.id))
      | _ -> None) frames in
  verdict "UART RX" (got = bytes) (Printf.sprintf "%d bytes with random gaps, %d frames captured, decoded equal %b" (List.length bytes) (List.length frames) (got = bytes))

(* SPI full duplex: the streamer RTL drives SCK (streamer pin 0) and MOSI (pin 1); a reference mode-0
   slave shifts its reply out on MISO, MSB first, presenting each bit before the rising edge and
   changing on the falling edge; the sampler, clocked on SCK rising, captures MISO in 8-bit frames *)
let () =
  let sent = [ 0x9F; 0x00; 0x00; 0x00; 0x05; 0xAB ] and reply = [ 0xEF; 0x40; 0x18; 0xC3; 0x01; 0x7E ] in
  let vecs = List.concat_map (fun b -> List.concat (List.init 8 (fun i -> let d = (b lsr (7 - i)) land 1 in [ d lsl 1; (d lsl 1) lor 1 ]))) sent in
  let words =
    let rec go acc l = match l with [] -> List.rev acc | _ ->
      let ch = List.filteri (fun i _ -> i < 8) l and rest = List.filteri (fun i _ -> i >= 8) l in
      let w = List.fold_left (fun (w, k) v -> (w lor (v lsl (2 * k)), k + 1)) (0, 0) ch |> fst in
      go ((w, if List.length ch = 8 then 0 else List.length ch) :: acc) rest in go [] vecs in
  let st = Cyclesim.create (Streamer.circuit ()) in
  let si n = Cyclesim.in_port st n and so n = Cyclesim.out_port st n in
  si "clear" := Bits.vdd; Cyclesim.cycle st; si "clear" := Bits.gnd;
  si "period" := Bits.of_int ~width:12 6; si "width" := Bits.of_int ~width:3 2; si "od_mask" := Bits.of_int ~width:4 0;
  si "idle_out" := Bits.of_int ~width:4 0; si "idle_oe" := Bits.of_int ~width:4 3;
  (* sampler pins: 0 = MISO, 1 = SCK *)
  let r = make { Model.clocked = true; period = 1; width = 1; trig_pin = 1; trig_val = 1; offset = 0; frame_len = 8 } in
  let q = ref words and reply_bits = List.concat_map (fun b -> List.init 8 (fun i -> (b lsr (7 - i)) land 1)) reply in
  let slave_bits = ref reply_bits and miso = ref (List.hd reply_bits) and prev_sck = ref 0 in
  let mosi_bits = ref [] and got = ref [] in
  for _ = 0 to 6 * List.length vecs + 60 do
    let push = !q <> [] && Bits.to_int !(so "full") = 0 in
    si "host_push" := Bits.of_int ~width:1 (if push then 1 else 0);
    let (w, n) = match !q with e :: _ -> e | [] -> (0, 0) in
    si "host_data" := Bits.of_int ~width:16 w; si "host_count" := Bits.of_int ~width:4 n;
    Cyclesim.cycle st;
    if push then q := List.tl !q;
    let out = Bits.to_int !(so "pin_out") in
    let sck = out land 1 and mosi = (out lsr 1) land 1 in
    (* the slave: on a rising edge it reads MOSI; on a falling edge it moves to its next bit *)
    if !prev_sck = 0 && sck = 1 then mosi_bits := mosi :: !mosi_bits;
    if !prev_sck = 1 && sck = 0 then begin
      slave_bits := (match !slave_bits with _ :: r -> r | [] -> []);
      miso := (match !slave_bits with b :: _ -> b | [] -> 1)
    end;
    prev_sck := sck;
    (match rtl_step r ~pins:(!miso lor (sck lsl 1)) ~pop:true with Some e -> got := e :: !got | None -> ())
  done;
  (* each frame's vectors, in capture order, are the byte MSB first *)
  let got = List.rev_map (fun e -> List.fold_left (fun a b -> (a lsl 1) lor b) 0 (vectors ~width:1 e)) !got in
  let mosi = List.rev !mosi_bits in
  let slave_saw = List.init (List.length mosi / 8) (fun k -> List.fold_left (fun a i -> (a lsl 1) lor List.nth mosi (8 * k + i)) 0 (List.init 8 Fun.id)) in
  verdict "SPI RX" (got = reply && slave_saw = sent)
    (Printf.sprintf "master sent %d bytes, slave saw them %b; slave replied %d bytes, sampler captured %s"
       (List.length sent) (slave_saw = sent) (List.length reply) (String.concat " " (List.map (Printf.sprintf "%02x") got)))

(* I2C ACK readback: the streamer RTL drives an open-drain write (SCL = streamer pin 0, SDA = pin 1,
   ACK slots released); a reference slave counts bits on SCL rising edges and pulls SDA low through
   each ACK slot, except that it NACKs the byte at index [nack]; lines are wired-AND with pull-ups.
   The sampler (pins: 0 = SDA line, 1 = SCL line) clocks on SCL rising in 9-bit frames *)
let () =
  let data = [ 0xA0; 0x12; 0x34; 0x56; 0x78 ] and nack = 3 in
  let v ~scl ~sda = scl lor (sda lsl 1) in
  let bit d = [ v ~scl:0 ~sda:d; v ~scl:1 ~sda:d; v ~scl:1 ~sda:d; v ~scl:0 ~sda:d ] in
  let start = [ v ~scl:1 ~sda:1; v ~scl:1 ~sda:0; v ~scl:0 ~sda:0 ] and stop = [ v ~scl:0 ~sda:0; v ~scl:1 ~sda:0; v ~scl:1 ~sda:1 ] in
  let vecs = start @ List.concat_map (fun b -> List.concat (List.init 8 (fun i -> bit ((b lsr (7 - i)) land 1))) @ bit 1) data @ stop in
  let words =
    let rec go acc l = match l with [] -> List.rev acc | _ ->
      let ch = List.filteri (fun i _ -> i < 8) l and rest = List.filteri (fun i _ -> i >= 8) l in
      let w = List.fold_left (fun (w, k) v -> (w lor (v lsl (2 * k)), k + 1)) (0, 0) ch |> fst in
      go ((w, if List.length ch = 8 then 0 else List.length ch) :: acc) rest in go [] vecs in
  let st = Cyclesim.create (Streamer.circuit ()) in
  let si n = Cyclesim.in_port st n and so n = Cyclesim.out_port st n in
  si "clear" := Bits.vdd; Cyclesim.cycle st; si "clear" := Bits.gnd;
  si "period" := Bits.of_int ~width:12 5; si "width" := Bits.of_int ~width:3 2; si "od_mask" := Bits.of_int ~width:4 3;
  si "idle_out" := Bits.of_int ~width:4 0; si "idle_oe" := Bits.of_int ~width:4 0;
  let r = make { Model.clocked = true; period = 1; width = 1; trig_pin = 1; trig_val = 1; offset = 0; frame_len = 9 } in
  let q = ref words and prev_scl = ref 1 and bitcount = ref 0 and byte_index = ref 0 and pull = ref false in
  let got = ref [] in
  for _ = 0 to 5 * List.length vecs + 60 do
    let push = !q <> [] && Bits.to_int !(so "full") = 0 in
    si "host_push" := Bits.of_int ~width:1 (if push then 1 else 0);
    let (w, n) = match !q with e :: _ -> e | [] -> (0, 0) in
    si "host_data" := Bits.of_int ~width:16 w; si "host_count" := Bits.of_int ~width:4 n;
    Cyclesim.cycle st;
    if push then q := List.tl !q;
    let out = Bits.to_int !(so "pin_out") and oe = Bits.to_int !(so "pin_oe") in
    let master pin = if (oe lsr pin) land 1 = 1 then (out lsr pin) land 1 else 1 in
    let scl = master 0 in
    let sda = if !pull then 0 else master 1 in
    (* the slave *)
    if !prev_scl = 0 && scl = 1 then incr bitcount;
    if !prev_scl = 1 && scl = 0 then begin
      if !bitcount = 8 then pull := !byte_index <> nack
      else if !bitcount = 9 then begin pull := false; bitcount := 0; incr byte_index end
    end;
    prev_scl := scl;
    (match rtl_step r ~pins:(sda lor (scl lsl 1)) ~pop:true with Some e -> got := e :: !got | None -> ())
  done;
  if Sys.getenv_opt "I2C_DEBUG" <> None then
    List.iter (fun e -> Printf.printf "  entry %s\n" (String.concat "" (List.map string_of_int (vectors ~width:1 e)))) (List.rev !got);
  let frames = List.filter (fun e -> List.length (vectors ~width:1 e) = 9) (List.rev !got) in
  let bytes = List.map (fun e -> List.fold_left (fun a b -> (a lsl 1) lor b) 0 (List.filteri (fun i _ -> i < 8) (vectors ~width:1 e))) frames in
  let acks = List.map (fun e -> List.nth (vectors ~width:1 e) 8) frames in
  let want_acks = List.mapi (fun i _ -> if i = nack then 1 else 0) data in
  verdict "I2C ACK" (bytes = data && acks = want_acks)
    (Printf.sprintf "bytes read back equal %b; ACK bits %s (expected %s: the slave NACKs byte %d)" (bytes = data)
       (String.concat "" (List.map string_of_int acks)) (String.concat "" (List.map string_of_int want_acks)) nack)

(* 10BASE-T capture: the Ethernet model's waveform on the comparator (pin 0) and activity (pin 1);
   timed mode triggers on activity and captures both pins every clock; the host decodes the capture
   with the model's decoder. This checks capture fidelity; decoding on chip is for the array *)
let () =
  let h = 3 in
  let frame = Eth_model.udp_frame ~dst_mac:[ 0xFF; 0xFF; 0xFF; 0xFF; 0xFF; 0xFF ] ~src_mac:[ 0x02; 0; 0; 0x12; 0x34; 0x56 ]
      ~src_ip:[ 192; 168; 1; 200 ] ~dst_ip:[ 192; 168; 1; 255 ] ~src_port:4096 ~dst_port:4096
      ~payload:(List.map Char.code [ 's'; 'a'; 'm'; 'p'; 'l'; 'e'; 'r' ]) in
  let wave = Array.of_list (List.init 30 (fun _ -> 0) @ Eth_model.encode_frame ~h frame) in
  let r = make { Model.clocked = false; period = 1; width = 2; trig_pin = 1; trig_val = 1; offset = 0; frame_len = 0 } in
  let pins c = let s = wave.(c) in (if s > 0 then 1 else 0) lor (if s <> 0 then 2 else 0) in
  let entries = capture r ~pins_at:pins ~cycles:(Array.length wave) in
  let samples = Array.of_list (List.concat_map (fun e ->
      List.map (fun v -> if v land 2 = 0 then 0 else if v land 1 = 1 then 1 else -1) (vectors ~width:2 e)) entries) in
  let frames = Eth_model.decode ~h samples in
  let want = frame @ Eth_model.fcs_bytes frame in
  verdict "10BASE-T" (frames = [ want ])
    (Printf.sprintf "%d clocks captured in %d words, host decoded %d frame(s), equal to the sent frame %b"
       (Array.length samples) (List.length entries) (List.length frames) (frames = [ want ]))
