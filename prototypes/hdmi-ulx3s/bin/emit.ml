(* Writes the generated Verilog: emit.exe <outdir> [mutant]
   mutant (negative controls for the end-to-end simulation only): latency (the pattern's registered
   colour declared to be at the raster's latency, so syncs and pixels are misaligned by one),
   xnor (Gergo's XOR/XNOR rule), qm8 (Gergo's 2 * q_m[8] correction), control (a wrong control
   code)
     hdmi_pixel.v       640x480@60 test pattern, three TMDS encoders, 1 Hz LED at 25 MHz
     hdmi_serial_sdr.v  serialiser, one bit per 250 MHz cycle, 1 Hz LED at 250 MHz
     hdmi_serial_ddr.v  serialiser, two bits per 125 MHz cycle (to ODDRX1F), 1 Hz LED at 125 MHz
     hdmi_pixel_demo.v  the retro console's game through a frame buffer, instead of the pattern;
                        DEMO_FIELDS fields of packets (default 8) from DEMO_PACKETS (default
                        "packets.hex", resolved by the simulator or synthesis tool) *)
open! Base
open Hardcaml
open Hdmi_hw

let write dir circuit =
  let file = Stdlib.Filename.concat dir (Circuit.name circuit ^ ".v") in
  Rtl.output ~output_mode:(Rtl.Output_mode.To_file file) Verilog circuit

let () =
  let argv = Sys.get_argv () in
  let dir = argv.(1) in
  let mutant_name = if Array.length argv > 2 then argv.(2) else "none" in
  let misdeclare = String.equal mutant_name "latency" in
  let mutant =
    match mutant_name with
    | "none" | "latency" -> Tmds.Faithful
    | "xnor" -> Tmds.Xnor_rule_bit1
    | "qm8" -> Tmds.Swapped_qm8_correction
    | "control" -> Tmds.Wrong_control_code
    | s -> failwith ("unknown mutant " ^ s)
  in
  let m = Video_timing.vga_640x480_60 in
  write dir
    (Hdmi.pixel_circuit ~mutant ~blink_half_period:12_500_000
       ~source:(Hdmi.test_pattern ~misdeclare ~width:m.h.active ~height:m.v.active ()) ());
  let env name default = Option.value (Sys.getenv name) ~default in
  let fields = Int.of_string (env "DEMO_FIELDS" "8") and packet_file = env "DEMO_PACKETS" "packets.hex" in
  write dir
    (Hdmi.pixel_circuit ~name:"hdmi_pixel_demo" ~mutant ~blink_half_period:12_500_000
       ~source:(Hdmi_demo.Console_hdmi.source ~fields ~packet_file) ());
  write dir (Hdmi.serial_circuit ~name:"hdmi_serial_sdr" ~bits_per_cycle:1 ~blink_half_period:125_000_000 ());
  write dir (Hdmi.serial_circuit ~name:"hdmi_serial_ddr" ~bits_per_cycle:2 ~blink_half_period:62_500_000 ())
