(* [ps2_dump.exe DIR]: the keyboard firmware (interpreter and RTL in lockstep) sends four scan codes to
   the independent host model; the CLK and DATA lines are sampled at 1 MHz into DIR/ps2.bin (one byte
   per sample, bit 0 = CLK, bit 1 = DATA), with the bytes sent in DIR/ps2.expected. For tools/sigrok-judge. *)
open Ps2_bench

let codes = [ 0x1C; 0xF0; 0x1C; 0x32 ]

let () =
  let dir = Sys.argv.(1) in
  let buf = Buffer.create 65536 in
  let tap = (1e6, fun ~clk ~data -> Buffer.add_char buf (Char.chr (clk lor (data lsl 1)))) in
  let res, _ = device_vs_model_host ~tap ~name:"ps2 dump" ~seed:0 ~codes ~cmds:[] ~inhibits:[] ~rise:(Sim.us 2.) () in
  report res;
  let oc = open_out_bin (Filename.concat dir "ps2.bin") in
  Buffer.output_buffer oc buf; close_out oc;
  let oc = open_out (Filename.concat dir "ps2.expected") in
  Printf.fprintf oc "# samplerate_hz_assumed 1000000\nps2_clk 0\nps2_data 1\nps2_bytes %s\n"
    (String.concat "," (List.map string_of_int codes));
  close_out oc;
  exit (if res.ok then 0 else 1)
