(* The host's side of the UART, SPI and I2C demo (demos.exe ds): what it sends through the host
   link and when. Shared by demos.ml, which runs it against the chip in simulation, and
   fpga_ops.ml, which exports it for the FPGA test bench (../fpga-kv260). *)

open Regs
module D = Ds.Demo_cut

(* thread t's base-ISA programme, translated to ISA v2 (../sequencer-v2/compat.ml) and moved to
   page 0, offset 64 t: the host-side loader's job *)
let store_image_base (progs : int array array) =
  List.concat
    (List.mapi
       (fun t p ->
         let words = Array.mapi (fun pc w -> Compat.relocate ~base:(64 * t) (Compat.of_base ~quarter:true ~pc_bits:6 ~addr:pc w)) p in
         [ (128 * t, List.concat_map (fun w -> [ w land 0xFF; w lsr 8 ]) (Array.to_list words)) ])
       (Array.to_list progs))

let demo_clocks = 6000

(* Queue the demo on [h]: load the store, the boot addresses and the pin map, set run, wait
   [demo_clocks], then drain HOSTOUT. [on_run] runs when the host reaches the run command.
   Returns the firmware listings and a reference that the drain fills with the I2C master's OUT
   bytes. *)
let submit (h : Host.t) ~on_run =
  let mem, listings = D.build () in
  Host.wreg h r_ctrl 2;
  List.iter (fun (a, data) -> Host.submit h (Host.Write { tgt = t_prog; addr = a; data })) (store_image_base mem);
  Host.submit h (Host.Write { tgt = t_reg; addr = r_boot_pc 0; data = [ 0; 64; 128; 192; 0 ] });
  (* logical pins: UART 0, SCLK 1, MOSI 2, CS 3 on uo_out[3:0] (undriven level 1); SDA 4 and SCL 5
     on uio[6] and uio[7], the open-drain pins, which they also read back *)
  let sel src undriven = src lor (undriven lsl 6) in
  Host.submit h (Host.Write { tgt = t_reg; addr = r_padsel 0; data = [ sel 0 1; sel 1 1; sel 2 1; sel 3 1 ] });
  Host.submit h (Host.Write { tgt = t_reg; addr = r_padsel 14; data = [ sel 4 0; sel 5 0 ] });
  Host.submit h (Host.Write { tgt = t_reg; addr = r_pinin 4; data = [ 14; 15 ] });
  Host.submit h (Host.Call on_run);
  Host.wreg h r_ctrl 3;                         (* run; the assists stay held *)
  Host.submit h (Host.Idle demo_clocks);
  let host_bytes = ref [] in
  Host.submit h (Host.Read { tgt = t_hostout; addr = 0; n = 8; k = (fun l ->
      let rec pairs = function t :: d :: r -> (if t land 0x80 <> 0 then [ d ] else []) @ pairs r | _ -> [] in
      host_bytes := pairs l) });
  listings, host_bytes
