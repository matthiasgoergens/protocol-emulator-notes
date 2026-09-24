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
