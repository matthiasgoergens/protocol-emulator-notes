(* Jane Street's Uart.Tx (github.com/janestreet/hardcaml_hobby_boards, src/uart.ml, MIT), as
   Verilog for the miter in this directory. Nothing of hardcaml_hobby_boards is copied here: this
   file is compiled next to the unmodified upstream sources by build_hobby_tx.sh.

   The configuration is fixed as our UART programme's: 8 data bits, no parity, one stop bit,
   [clocks_per_bit] (argument 2, default 20 = 5 slots of 4 clocks).
   Usage: emit_hobby_tx.exe [CLOCKS_PER_BIT] > FILE *)
open Base
open Hardcaml
open Signal
module Tx = Uart.Tx
module T = Uart_types

let () =
  let argv = Sys.get_argv () in
  let cpb = if Array.length argv > 1 then Int.of_string argv.(1) else 20 in
  let clock = input "clock" 1 and clear = input "clear" 1 in
  let data_in = input "data_in" 8 and data_in_valid = input "data_in_valid" 1 in
  let config =
    { Uart.Config.data_bits = T.Data_bits.Enum.Of_signal.of_enum Eight
    ; parity = T.Parity.Enum.Of_signal.of_enum None
    ; stop_bits = T.Stop_bits.Enum.Of_signal.of_enum One
    ; clocks_per_bit = of_int_trunc ~width:16 cpb
    } in
  let scope = Scope.create ~flatten_design:true () in
  let o =
    Tx.create scope
      { Tx.I.clocking = { Clocking.clock; clear }
      ; config
      ; data_in = uresize data_in ~width:9
      ; data_in_valid
      } in
  let circuit =
    Circuit.create_exn ~name:"hobby_uart_tx"
      [ output "txd" o.txd; output "data_in_ready" o.data_in_ready ] in
  Rtl.print Verilog circuit
