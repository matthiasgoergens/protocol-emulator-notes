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
