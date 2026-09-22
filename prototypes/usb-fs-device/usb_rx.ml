(* USB full-speed receiver at 4 samples per bit (48 MHz clock, 12 Mbit/s).
   Line: dp dm = 10 J, 01 K, 00 SE0. Sampling phase resets on every transition and samples two
   cycles later (mid-bit). NRZI: a bit is 1 if the line did not change since the last sample.
   Bit stuffing: after six ones the next bit is a stuffed zero and is dropped; counting starts at
   the sync pattern's final one. Bytes are assembled LSB first. SE0 ends the packet. *)
open Hardcaml
open Signal

let create ~clock ~clear ~dp ~dm =
  let spec = Reg_spec.create ~clock ~clear () in
  let open Always in
  let dp_q = reg spec (reg spec dp) and dm_q = reg spec (reg spec dm) in
  let line = concat_msb [ dp_q; dm_q ] in
  let line_prev = reg spec line in
  let transition = line <>: line_prev in
  let is_k = line ==: of_string "01" and is_se0 = line ==: of_string "00" and is_j = line ==: of_string "10" in
  let phase = Variable.reg spec ~width:2 in
  let sample_en = (phase.value ==:. 1) &: ~:transition in
  let state = Variable.reg spec ~width:2 in
  let idle = of_int ~width:2 0 and sync = of_int ~width:2 1 and data = of_int ~width:2 2 and eop = of_int ~width:2 3 in
  let last_k = Variable.reg spec ~width:1 in
  let ones = Variable.reg spec ~width:3 in
  let shift = Variable.reg spec ~width:8 in
  let bitcnt = Variable.reg spec ~width:3 in
  let byte_valid = Variable.wire ~default:gnd in
  let byte_w = Variable.wire ~default:shift.value in
  let pkt_start = Variable.wire ~default:gnd in
  let pkt_end = Variable.wire ~default:gnd in
  let err = Variable.wire ~default:gnd in
  let bit = is_k ==: last_k.value in
  let shifted = concat_msb [ bit; select shift.value 7 1 ] in
  compile
    [ phase <-- mux2 transition (zero 2) (phase.value +:. 1)
    ; when_ sample_en
        [ switch state.value
            [ idle, [ when_ is_k [ state <-- sync; last_k <-- vdd; bitcnt <--. 0 ] ]
            ; sync, [ if_ is_se0 [ state <-- idle ]
                        [ last_k <-- is_k
                        ; when_ bit [ state <-- data; pkt_start <-- vdd; ones <--. 1; bitcnt <--. 0 ] ] ]
            ; data, [ if_ is_se0 [ state <-- eop; pkt_end <-- vdd ]
                        [ last_k <-- is_k
                        ; if_ (ones.value ==:. 6)
                            [ ones <--. 0; when_ bit [ err <-- vdd ] ]
                            [ ones <-- mux2 bit (ones.value +:. 1) (zero 3)
                            ; shift <-- shifted
                            ; bitcnt <-- bitcnt.value +:. 1
                            ; when_ (bitcnt.value ==:. 7) [ byte_valid <-- vdd; byte_w <-- shifted ] ] ] ]
            ; eop, [ when_ is_j [ state <-- idle ] ] ] ] ];
  byte_w.value, byte_valid.value, pkt_start.value, pkt_end.value, err.value
