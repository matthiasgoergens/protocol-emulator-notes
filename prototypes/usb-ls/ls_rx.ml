(* USB receiver, parameterised by clocks per bit (40 for low speed at 60 MHz) and by line
   polarity (low speed: J is D- high; full speed: J is D+ high). Adapted from
   ../usb-fs-device/usb_rx.ml: a two-flop synchroniser, a phase counter reset on every
   transition that samples mid-bit, NRZI decode, bit unstuffing, sync detection, bytes LSB first,
   SE0 ending the packet. Differences: the sampling phase is cpb/2 after a transition; a stuff
   error (a seventh one) is reported and makes the engine drop the packet; SE0 held for more than
   [reset_clocks] (2.5 us is the specification's minimum for a reset) raises bus_reset, while the
   host's two-bit keep-alive EOPs (1.33 us) do not. *)
open Hardcaml
open Signal

let clog2 n = let rec f b = if 1 lsl b >= n then b else f (b + 1) in f 0

let create ?(ls = true) ~cpb ~reset_clocks ~clock ~clear ~dp ~dm () =
  let spec = Reg_spec.create ~clock ~clear () in
  let open Always in
  let dp_q = reg spec (reg spec dp) and dm_q = reg spec (reg spec dm) in
  let line = concat_msb [ dp_q; dm_q ] in
  let line_prev = reg spec line in
  let transition = line <>: line_prev in
  let j_code, k_code = if ls then "01", "10" else "10", "01" in
  let is_k = line ==: of_string k_code and is_se0 = line ==: of_string "00" and is_j = line ==: of_string j_code in
  let pw = max 2 (clog2 cpb) in
  let phase = Variable.reg spec ~width:pw in
  let sample_en = (phase.value ==:. (cpb / 2 - 2)) &: ~:transition in
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
  let rw = clog2 (reset_clocks + 2) in
  let se0_cnt = Variable.reg spec ~width:rw in
  let bus_reset = Variable.wire ~default:gnd in
  compile
    [ phase <-- mux2 (transition |: (phase.value ==:. (cpb - 1))) (zero pw) (phase.value +:. 1)
    ; if_ is_se0
        [ when_ (se0_cnt.value <>:. reset_clocks + 1) [ se0_cnt <-- se0_cnt.value +:. 1 ]
        ; when_ (se0_cnt.value ==:. reset_clocks) [ bus_reset <-- vdd ] ]
        [ se0_cnt <--. 0 ]
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
  byte_w.value, byte_valid.value, pkt_start.value, pkt_end.value, err.value, bus_reset.value
