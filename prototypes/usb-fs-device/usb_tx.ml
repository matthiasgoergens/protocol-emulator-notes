(* USB full-speed transmitter: sync, bytes LSB first with bit stuffing, NRZI, EOP (SE0 SE0 J),
   one bit per four cycles. The engine presents bytes on data/data_valid; data_ack pulses when a
   byte is taken; when data_valid is low at a byte boundary the packet ends. *)
open Hardcaml
open Signal

let create ~clock ~clear ~start ~data ~data_valid =
  let spec = Reg_spec.create ~clock ~clear () in
  let open Always in
  let state = Variable.reg spec ~width:3 in
  let s_idle = of_int ~width:3 0 and s_sync = of_int ~width:3 1 and s_data = of_int ~width:3 2
  and s_eop1 = of_int ~width:3 3 and s_eop2 = of_int ~width:3 4 and s_eopj = of_int ~width:3 5 in
  let phase = Variable.reg spec ~width:2 in
  let k = Variable.reg spec ~width:1 and se0 = Variable.reg spec ~width:1 and oe = Variable.reg spec ~width:1 in
  let bitidx = Variable.reg spec ~width:4 in
  let ones = Variable.reg spec ~width:3 in
  let byte = Variable.reg spec ~width:8 in
  let data_ack = Variable.wire ~default:gnd in
  let cur_bit = mux (select bitidx.value 2 0) (bits_lsb byte.value) in
  let emit b = [ k <-- mux2 b k.value (~:(k.value)); ones <-- mux2 b (ones.value +:. 1) (zero 3) ] in
  let load_and_emit_first = [ byte <-- data; data_ack <-- vdd; bitidx <--. 1 ] @ emit (bit data 0) in
  let at_bit = phase.value ==:. 3 in
  compile
    [ switch state.value
        [ s_idle, [ oe <-- gnd; se0 <-- gnd; k <-- gnd
                  ; when_ start [ state <-- s_sync; phase <--. 0; oe <-- vdd; k <-- vdd; bitidx <--. 1; ones <--. 0 ] ]
        ; s_sync, [ phase <-- phase.value +:. 1
                  ; when_ at_bit
                      [ if_ (bitidx.value ==:. 8)
                          [ if_ data_valid ([ state <-- s_data; ones <--. 1 ] @ [ byte <-- data; data_ack <-- vdd; bitidx <--. 1 ]
                                            @ [ k <-- mux2 (bit data 0) k.value (~:(k.value)); ones <-- mux2 (bit data 0) (of_int ~width:3 2) (zero 3) ])
                              [ state <-- s_eop1; se0 <-- vdd ] ]
                          [ k <-- mux2 (bitidx.value ==:. 7) k.value (~:(k.value)); bitidx <-- bitidx.value +:. 1 ] ] ]
        ; s_data, [ phase <-- phase.value +:. 1
                  ; when_ at_bit
                      [ if_ (ones.value ==:. 6)
                          [ k <-- ~:(k.value); ones <--. 0 ]
                          [ if_ (bitidx.value ==:. 8)
                              [ if_ data_valid load_and_emit_first [ state <-- s_eop1; se0 <-- vdd ] ]
                              (emit cur_bit @ [ bitidx <-- bitidx.value +:. 1 ]) ] ] ]
        ; s_eop1, [ phase <-- phase.value +:. 1; when_ at_bit [ state <-- s_eop2 ] ]
        ; s_eop2, [ phase <-- phase.value +:. 1; when_ at_bit [ state <-- s_eopj; se0 <-- gnd; k <-- gnd ] ]
        ; s_eopj, [ phase <-- phase.value +:. 1; when_ at_bit [ state <-- s_idle; oe <-- gnd ] ] ] ];
  let dp = mux2 se0.value gnd (~:(k.value)) and dm = mux2 se0.value gnd k.value in
  dp, dm, oe.value, data_ack.value, state.value <>: s_idle
