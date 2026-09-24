(* Step 1 of "PAL over 10BASE-T": can the Ethernet receiver run from the PAL clock?

   PAL chasing the beam wants 12 x fsc = 53.203425 MHz; the receiver was built for 60 MHz, where a
   Manchester half-bit is exactly 3 clocks. At the PAL clock a half-bit is 2.66 clocks. The receiver
   classifies transitions by thresholds (mid-bit if at least 2h-2 clocks after the last mid-bit
   transition; frame end after 4h clocks without one), so it may not need whole numbers.

   The line is generated in continuous time (10 Mbit/s, with a transmitter clock offset in ppm and
   random edge jitter) and sampled at the receiver's clock; the receiver RTL (the prototype's own
   eth_rx.ml, with h = 3) must return every frame intact with a good CRC. *)
open Hardcaml

let rx_clk = (match Sys.getenv_opt "RX_CLK" with Some f -> float_of_string f | None -> 53.203425e6)

(* the line level at time t (seconds): +1 / -1 inside the frame, 0 before and after *)
let line_of ~frame ~ppm ~jitter ~seed =
  let bits = List.concat_map Eth_model.bits_of_byte (List.init 7 (fun _ -> 0x55) @ [ 0xD5 ] @ frame @ Eth_model.fcs_bytes frame) in
  let bits = Array.of_list bits in
  let half = 50e-9 *. (1.0 +. ppm *. 1e-6) in
  let t0 = 1e-6 in
  Random.init seed;
  (* edge times with jitter: each half-bit boundary moves by up to +-jitter *)
  let n = 2 * Array.length bits in
  let edges = Array.init (n + 1) (fun k -> t0 +. (float k *. half) +. (if k = 0 || k = n then 0.0 else (Random.float 2.0 -. 1.0) *. jitter)) in
  let tp_idl_end = edges.(n) +. (3.0 *. half *. 2.0) in
  fun t ->
    if t < edges.(0) then 0
    else if t >= edges.(n) then (if t < tp_idl_end then 1 else 0)
    else begin
      (* binary search for the half-bit containing t *)
      let lo = ref 0 and hi = ref n in
      while !hi - !lo > 1 do let mid = (!lo + !hi) / 2 in if edges.(mid) <= t then lo := mid else hi := mid done;
      let k = !lo in
      let b = bits.(k / 2) in
      if k mod 2 = 0 then (if b = 1 then -1 else 1) else (if b = 1 then 1 else -1)
    end

let receive ~frame ~ppm ~jitter ~seed =
  let line = line_of ~frame ~ppm ~jitter ~seed in
  let sim = Cyclesim.create (Eth_rx.circuit ~h:3) in
  let i n = Cyclesim.in_port sim n and o n = Cyclesim.out_port sim n in
  i "clear" := Bits.vdd; Cyclesim.cycle sim; i "clear" := Bits.gnd;
  let frames = ref [] and cur = ref [] in
  let cycles = int_of_float (rx_clk *. (2e-6 +. (float (8 * (List.length frame + 12)) *. 100e-9))) in
  for c = 0 to cycles do
    let v = line (float c /. rx_clk) in
    i "rx" := Bits.of_int ~width:1 (if v > 0 then 1 else 0);
    i "rx_active" := Bits.of_int ~width:1 (if v <> 0 then 1 else 0);
    Cyclesim.cycle sim;
    if Bits.to_int !(o "byte_valid") = 1 then cur := Bits.to_int !(o "rx_byte") :: !cur;
    if Bits.to_int !(o "frame_end") = 1 then (frames := (List.rev !cur, Bits.to_int !(o "crc_ok") = 1) :: !frames; cur := [])
  done;
  List.rev !frames

let () =
  Random.init 2027;
  let trials = ref 0 and good = ref 0 in
  let results = Hashtbl.create 16 in
  List.iter (fun ppm ->
    List.iter (fun jitter ->
      let ok = ref 0 and n = 20 in
      for k = 1 to n do
        let len = 46 + Random.int 200 in
        let frame = List.init len (fun _ -> Random.int 256) in
        let got = receive ~frame ~ppm ~jitter:(jitter *. 1e-9) ~seed:(k + (1000 * int_of_float ppm)) in
        incr trials;
        if got = [ (frame @ Eth_model.fcs_bytes frame, true) ] then (incr ok; incr good)
      done;
      Hashtbl.replace results (ppm, jitter) (!ok, n)) [ 0.0; 2.0; 3.0; 4.0; 5.0 ]) [ -100.0; 0.0; 100.0 ];
  Printf.printf "Ethernet receiver RTL (h = 3) sampled at %.6f MHz; 20 random frames per cell\n" (rx_clk /. 1e6);
  Printf.printf "  transmitter clock offset | jitter 0 ns | 2 ns | 3 ns | 4 ns | 5 ns\n";
  List.iter (fun ppm ->
    Printf.printf "  %+6.0f ppm               |" ppm;
    List.iter (fun j -> let (ok, n) = Hashtbl.find results (ppm, j) in Printf.printf " %2d/%d |" ok n) [ 0.0; 2.0; 3.0; 4.0; 5.0 ];
    print_newline ()) [ -100.0; 0.0; 100.0 ];
  Printf.printf "total %d of %d frames received intact with a good CRC\n" !good !trials
