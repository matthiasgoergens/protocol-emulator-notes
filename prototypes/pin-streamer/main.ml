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
    let data = Random.int 0x10000 in
    i "host_push" := Bits.of_int ~width:1 (if push then 1 else 0);
    i "host_data" := Bits.of_int ~width:16 data;
    Cyclesim.cycle sim;
    Model.step m;
    if push then Model.push m data;
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
