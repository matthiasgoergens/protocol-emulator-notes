(* The hardened device in Cyclesim, behind the bench's device interface. *)
open Hardcaml

let make ?(name = "hardened") ?ls ?resp_delay ?check_crc () =
  let circ = Ls_dev.circuit ?ls ?resp_delay ?check_crc () in
  let sim = Cyclesim.create circ in
  let i n = Cyclesim.in_port sim n and o n = Cyclesim.out_port sim n in
  let dp_in = i "dp_in" and dm_in = i "dm_in" and clear = i "clear" and report = i "report" and report_valid = i "report_valid" in
  let dp_out = o "dp_out" and dm_out = o "dm_out" and oe = o "oe" in
  clear := Bits.vdd; dp_in := Bits.gnd; dm_in := Bits.vdd; Cyclesim.cycle sim; clear := Bits.gnd;
  let pending = Queue.create () in
  let step ~dp ~dm =
    dp_in := Bits.of_int ~width:1 dp; dm_in := Bits.of_int ~width:1 dm;
    (match Queue.take_opt pending with
     | Some r ->
       report := Bits.of_int64 ~width:64 (List.fold_right (fun x acc -> Int64.logor (Int64.shift_left acc 8) (Int64.of_int x)) r 0L);
       report_valid := Bits.vdd
     | None -> report_valid := Bits.gnd);
    Cyclesim.cycle sim in
  let out () = Bits.to_int !dp_out, Bits.to_int !dm_out, Bits.to_int !oe in
  { Bench.name; step; out; offer_report = (fun r -> Queue.push r pending); nak_ok = false; mismatches = (fun () -> 0) },
  circ
