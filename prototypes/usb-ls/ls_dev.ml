(* The hardened low-speed keyboard: receiver, engine and transmitter at 60 MHz (40 clocks per
   bit). Options exist only for the controls: [ls:false] swaps J and K (full-speed polarity),
   [resp_delay] moves the reply, [check_crc:false] accepts corrupted data. *)
open Hardcaml
open Signal

let cpb = 40
let reset_clocks = 160   (* 2.67 us of SE0: above the 2.5 us minimum, above a 1.33 us keep-alive *)

let create ?(ls = true) ?resp_delay ?check_crc ~clock ~clear ~dp_in ~dm_in ~report ~report_valid () =
  let rx_byte, rx_valid, rx_start, rx_end, rx_err, bus_reset =
    Ls_rx.create ~ls ~cpb ~reset_clocks ~clock ~clear ~dp:dp_in ~dm:dm_in () in
  let tx_ack_w = wire 1 and tx_busy_w = wire 1 in
  let tx_start, tx_data, tx_valid, addr, configured, rep_pending =
    Ls_sie.create ?resp_delay ?check_crc ~clock ~clear ~bus_reset ~rx_byte ~rx_valid ~rx_start ~rx_end ~rx_err
      ~tx_ack:tx_ack_w ~tx_busy:tx_busy_w ~report ~report_valid () in
  let dp, dm, oe, tx_ack, tx_busy = Ls_tx.create ~ls ~cpb ~clock ~clear ~start:tx_start ~data:tx_data ~data_valid:tx_valid () in
  tx_ack_w <== tx_ack; tx_busy_w <== tx_busy;
  dp, dm, oe, addr, configured, rep_pending, bus_reset

let circuit ?ls ?resp_delay ?check_crc () =
  let clock = input "clock" 1 and clear = input "clear" 1 in
  let dp_in = input "dp_in" 1 and dm_in = input "dm_in" 1 in
  let report = input "report" 64 and report_valid = input "report_valid" 1 in
  let dp, dm, oe, addr, configured, rep_pending, bus_reset =
    create ?ls ?resp_delay ?check_crc ~clock ~clear ~dp_in ~dm_in ~report ~report_valid () in
  Circuit.create_exn ~name:"usb_ls_device"
    [ output "dp_out" dp; output "dm_out" dm; output "oe" oe; output "addr" addr; output "configured" configured
    ; output "report_pending" rep_pending; output "bus_reset" bus_reset ]
