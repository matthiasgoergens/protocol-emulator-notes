(* Bridge A as ../../sequencer-v2/ports/multi-proto/bridge_a.ml and ../../verif-oracles/hazard-mp
   assemble it: T0 UART RX (pin 0, RTS pin 2) -> inbox 1; T1 I2C master (SDA 3, SCL 4) <- inbox 1,
   -> inbox 2; T2 UART TX (pin 1) <- inbox 2; T3 an unrelated SPI master loop on pins 5..7. One
   array of words per thread, for page t. *)
open Bridge_lib

let threads () =
  let (t0, _, _), (t1, _, _), (t2, _, _) =
    uart_rx ~rx:0 ~rts:(Some 2) ~dst:1 (), i2c_master ~sda:3 ~scl:4 ~own:1 ~reply:2 (), uart_tx ~tx:1 ~own:2 () in
  let t3 = Asm.of_base ~loop:true (Compiler.spi_master { sclk = 5; mosi = 6; cs = 7; period = 12; sbytes = [ 0x96 ] }) ~plen:128 in
  [| t0; t1; t2; t3 |]

(* the UART's bit period in clocks, and the I2C master's byte-code operations *)
let uart_bit_clocks = 4 * bit_slots
let op_start = op_start and op_stop = op_stop and op_write = op_write and op_read = op_read
let op_ack = op_ack and op_nack = op_nack
