open Hardcaml

(* Generate Verilog for the fabric flow, then simulate one byte and print the tx line
   sampled once per bit period as a cheap self-check. *)
let () =
  let circuit = Uart_tx.circuit () in
  let oc = open_out "uart_tx_hardcaml.v" in
  Rtl.output ~output_mode:(To_channel oc) Verilog circuit;
  close_out oc;
  let module Sim = Cyclesim in
  let sim = Sim.create circuit in
  let io_in = Sim.in_port sim "io_in" in
  let io_out = Sim.out_port sim "io_out" in
  let step () = Sim.cycle sim in
  io_in := Bits.of_int ~width:28 1; step ();            (* reset *)
  io_in := Bits.of_int ~width:28 2; step ();            (* load, div_sel = 0 -> 16 clocks per bit *)
  io_in := Bits.of_int ~width:28 0;
  let samples = Buffer.create 16 in
  for _bit = 0 to 9 do
    for _ = 1 to 8 do step () done;                     (* mid-bit sample *)
    Buffer.add_char samples (if Bits.to_int (Bits.select !io_out 0 0) = 1 then '1' else '0');
    for _ = 1 to 8 do step () done
  done;
  (* expected for 'A' = 0x41 LSB first: start 0, then 1 0 0 0 0 0 1 0, stop 1 *)
  Printf.printf "tx samples: %s (expect 0100000101)\n" (Buffer.contents samples)
