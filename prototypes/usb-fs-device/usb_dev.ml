open Hardcaml
open Signal

let create ~clock ~clear ~dp_in ~dm_in =
  let rx_byte, rx_valid, rx_start, rx_end, _rx_err = Usb_rx.create ~clock ~clear ~dp:dp_in ~dm:dm_in in
  (* the transmitter and engine are mutually dependent through tx_ack/tx_busy and tx_start/data;
     break the loop with wires *)
  let tx_ack_w = wire 1 and tx_busy_w = wire 1 in
  let tx_start, tx_data, tx_valid, addr, configured =
    Usb_sie.create ~clock ~clear ~rx_byte ~rx_valid ~rx_start ~rx_end ~tx_ack:tx_ack_w ~tx_busy:tx_busy_w in
  let dp, dm, oe, tx_ack, tx_busy = Usb_tx.create ~clock ~clear ~start:tx_start ~data:tx_data ~data_valid:tx_valid in
  tx_ack_w <== tx_ack; tx_busy_w <== tx_busy;
  dp, dm, oe, addr, configured

let circuit () =
  let clock = input "clock" 1 and clear = input "clear" 1 in
  let dp_in = input "dp_in" 1 and dm_in = input "dm_in" 1 in
  let dp, dm, oe, addr, configured = create ~clock ~clear ~dp_in ~dm_in in
  Circuit.create_exn ~name:"usb_fs_device"
    [ output "dp_out" dp; output "dm_out" dm; output "oe" oe; output "addr" addr; output "configured" configured ]
