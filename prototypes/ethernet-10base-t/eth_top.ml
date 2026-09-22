open Hardcaml
open Signal

(* transmitter and receiver side by side, as they would sit on the chip: txp/txn/txen to the
   resistor network and magnetics, rx/rx_active from a comparator *)
let circuit ~h ~nlp_period ~frame =
  let clock = input "clock" 1 and clear = input "clear" 1 and start = input "start" 1 in
  let rx = input "rx" 1 and rx_active = input "rx_active" 1 in
  let level, active, _ = Eth_tx.create ~clock ~clear ~h ~nlp_period ~start ~frame in
  let byte, byte_valid, frame_end, crc_ok, _, _ = Eth_rx.create ~clock ~clear ~h ~rx ~rx_active in
  Circuit.create_exn ~name:"eth_10base_t"
    [ output "txp" (level &: active); output "txn" (~:level &: active); output "txen" active
    ; output "rx_byte" byte; output "byte_valid" byte_valid; output "frame_end" frame_end; output "crc_ok" crc_ok ]
