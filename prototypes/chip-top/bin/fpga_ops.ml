(* Export the UART, SPI and I2C demo's host side (Ds_host) as frames for the FPGA test bench's
   player (../fpga-kv260/README.md, "Frames").

     fpga_ops.exe OUT_DIR    writes OUT_DIR/ds.ops (one frame per line, hex) and OUT_DIR/ds.meta

   The host model (src/host.ml) decides per clock what the host drives on the strobe S, the read
   request R and the data lines D, and when it samples D. The exporter runs it on its own, clock by
   clock, and merges runs of identical clocks into frames. A frame is one 32-bit word:

     bits 15:0  clocks to hold the levels (1 to 65535); 0 ends the stream
     bits 19:16 D, the level the host drives on the data lines
     bit 20     the host drives D (otherwise it has released them to the chip)
     bit 21     S          bit 22  R
     bit 23     sample D in the frame's first clock
     bits 31:24 ui_in, the chip's general inputs (0 throughout this demo)

   The host's data samples are not needed here: the host's reaction to what it reads is only
   used after the demo, to decode the drained bytes, and that decoding is redone on the board's
   samples by ../fpga-kv260/host/check.py. *)

module D = Ds.Demo_cut

(* clocks of idle levels before the first command, so that the chip's reset synchroniser has
   released the core before the host starts *)
let lead_in = 32

let () =
  let dir = match Sys.argv with [| _; d |] -> d | _ -> prerr_endline "usage: fpga_ops.exe OUT_DIR"; exit 2 in
  let h = Host.create () in
  Host.submit h (Host.Idle lead_in);
  let clock = ref 0 and run_clock = ref (-1) in
  let _listings, _ = Ds_host.submit h ~on_run:(fun () -> run_clock := !clock) in
  (* per clock: (s, r, d, sampled) *)
  let levels = ref [] in
  while not (Host.idle h) do
    let s, r, d = Host.clock h ~d_in:0 in
    levels := (s, r, d, h.sampled) :: !levels;
    incr clock
  done;
  let levels = List.rev !levels in
  let word (s, r, d, sampled) n =
    let dv, drive = match d with Some v -> (v, 1) | None -> (0, 0) in
    n lor (dv lsl 16) lor (drive lsl 20) lor (s lsl 21) lor (r lsl 22) lor ((if sampled then 1 else 0) lsl 23)
  in
  (* a sampled clock starts a frame; following clocks with the same levels and no sample join it *)
  let frames = ref [] and cur = ref None in
  let flush () = match !cur with Some (l, n) -> frames := word l n :: !frames; cur := None | None -> () in
  List.iter (fun ((s, r, d, sampled) as l) ->
      match !cur with
      | Some (((s', r', d', _) as first), n) when (not sampled) && s = s' && r = r' && d = d' && n < 0xFFFF ->
        cur := Some (first, n + 1)
      | _ -> flush (); cur := Some (l, 1))
    levels;
  flush ();
  let frames = List.rev !frames in
  let samples = List.length (List.filter (fun (_, _, _, sm) -> sm) levels) in
  let oc = open_out (Filename.concat dir "ds.ops") in
  List.iter (Printf.fprintf oc "%08x\n") frames;
  Printf.fprintf oc "%08x\n" 0;
  close_out oc;
  let bytes l = String.concat "," (List.map (Printf.sprintf "%d") l) in
  let oc = open_out (Filename.concat dir "ds.meta") in
  Printf.fprintf oc
    "# the UART, SPI and I2C demo (prototypes/chip-top/bin/ds_host.ml) as player frames; written by fpga_ops.exe\n\
     frames %d\nclocks %d\nsamples %d\nrun_clock %d\ndemo_clocks %d\n\
     # pads: UART on uo_out[0], SCLK uo_out[1], MOSI uo_out[2], CS uo_out[3], SDA uio[6], SCL uio[7]\n\
     uart_bit_clocks %d\nspi_period_clocks %d\nuart_bytes %s\nspi_bytes %s\ni2c_bytes %s\n"
    (List.length frames) !clock samples !run_clock Ds_host.demo_clocks (D.bit_slots * D.slot) (D.spi_period * D.slot)
    (bytes D.uart_bytes) (bytes D.spi_bytes) (bytes D.i2c_bytes);
  close_out oc;
  Printf.printf "fpga_ops: %d frames, %d clocks, %d samples, run at clock %d -> %s\n" (List.length frames) !clock samples !run_clock dir
