(* Write Verilog for synthesis: the ISA variant, the CRC assist (USB CRC16 configuration, and a
   programmable one with the configuration as inputs), the firmware system top, and the
   hardened device (also written by main_hard). *)
open Hardcaml

let write name circ =
  let oc = open_out (name ^ ".v") in
  Rtl.output ~output_mode:(To_channel oc) Verilog circ; close_out oc

let () =
  write "deadline_sequencer_ls" (Sequencer_ls.circuit ());
  (let open Signal in
   let clock = input "clock" 1 and clear = input "clear" 1 in
   let en = input "en" 1 and frame = input "frame" 1 and stb = input "stb" 1 and value = input "value" 1 in
   write "crc_usb16" (Circuit.create_exn ~name:"crc_usb16"
                        [ output "ok" (Crc_unit.create ~cfg:Crc_unit.usb_crc16 ~clock ~clear ~en ~frame ~stb ~value) ]));
  (let open Signal in
   let clock = input "clock" 1 and clear = input "clear" 1 in
   let en = input "en" 1 and frame = input "frame" 1 and stb = input "stb" 1 and value = input "value" 1 in
   let poly = input "poly" 16 and init = input "init" 16 and check = input "check" 16 and mask = input "mask" 16 in
   let top = input "top" 4 and skip_n = input "skip_n" 5 and msb_first = input "msb_first" 1 in
   write "crc_prog" (Circuit.create_exn ~name:"crc_prog"
                       [ output "ok" (Crc_unit.create_prog ~clock ~clear ~poly ~init ~check ~mask ~top ~skip_n ~msb_first ~en ~frame ~stb ~value) ]));
  write "usb_ls_firmware_system" (Fw_sys.circuit ());
  write "usb_ls_device" (Ls_dev.circuit ())
