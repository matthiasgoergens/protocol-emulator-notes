(* 10BASE-T transmitter. Bytes come from a frame buffer (here a ROM loaded from the host model);
   the transmitter sends preamble and SFD, the bytes LSB first, the FCS it computes, then TP_IDL,
   and during idle a link pulse every [nlp_period] cycles. [h] cycles per half bit. *)
open Hardcaml
open Signal

let crc32_step crc b = let fb = bit crc 0 ^: b in mux2 fb (srl crc 1 ^: of_int ~width:32 0xEDB88320) (srl crc 1)

let create ~clock ~clear ~h ~nlp_period ~start ~(frame : int list) =
  let spec = Reg_spec.create ~clock ~clear () in
  let open Always in
  let n = List.length frame in
  let rom = Array.of_list (List.map (of_int ~width:8) frame) in
  let s_idle = 0 and s_pre = 1 and s_data = 2 and s_fcs = 3 and s_tpidl = 4 and s_gap = 5 and s_nlp = 6 in
  let state = Variable.reg spec ~width:3 in
  let half = Variable.reg spec ~width:4 in            (* cycle within half bit *)
  let second = Variable.reg spec ~width:1 in          (* which half of the bit *)
  let bitidx = Variable.reg spec ~width:3 in
  let byteidx = Variable.reg spec ~width:12 in
  let crc = Variable.reg spec ~width:32 in
  let curbit = Variable.wire ~default:gnd in
  let level = Variable.reg spec ~width:1 and active = Variable.reg spec ~width:1 in
  let gap_cnt = Variable.reg spec ~width:24 in
  let nlp_cnt = Variable.reg spec ~width:24 in
  let pre_byte = mux2 (byteidx.value ==:. 7) (of_int ~width:8 0xD5) (of_int ~width:8 0x55) in
  let data_byte = mux (select byteidx.value 7 0) (Array.to_list rom) in
  let fcs_byte = mux (select byteidx.value 1 0) (List.init 4 (fun i -> ~:(select crc.value (8 * i + 7) (8 * i)))) in
  let cur_byte = mux2 (state.value ==:. s_pre) pre_byte (mux2 (state.value ==:. s_data) data_byte fcs_byte) in
  let b = mux bitidx.value (bits_lsb cur_byte) in
  let half_end = half.value ==:. (h - 1) in
  let next_bit =
    [ bitidx <-- bitidx.value +:. 1
    ; when_ (bitidx.value ==:. 7)
        [ byteidx <-- byteidx.value +:. 1
        ; switch state.value
            [ of_int ~width:3 s_pre, [ when_ (byteidx.value ==:. 7) [ state <--. s_data; byteidx <--. 0; crc <--. 0xFFFFFFFF ] ]
            ; of_int ~width:3 s_data, [ when_ (byteidx.value ==:. (n - 1)) [ state <--. s_fcs; byteidx <--. 0 ] ]
            ; of_int ~width:3 s_fcs, [ when_ (byteidx.value ==:. 3) [ state <--. s_tpidl; half <--. 0; byteidx <--. 0 ] ] ] ] ] in
  let sending = (state.value ==:. s_pre) |: (state.value ==:. s_data) |: (state.value ==:. s_fcs) in
  compile
    [ curbit <-- b
    ; switch state.value
        [ of_int ~width:3 s_idle, [ active <-- gnd; level <-- gnd
                                  ; nlp_cnt <-- nlp_cnt.value +:. 1
                                  ; when_ (nlp_cnt.value ==:. (nlp_period - 1)) [ nlp_cnt <--. 0; state <--. s_nlp; half <--. 0 ]
                                  ; when_ start [ state <--. s_pre; byteidx <--. 0; bitidx <--. 0; half <--. 0; second <-- gnd; active <-- vdd ] ]
        ; of_int ~width:3 s_nlp, [ active <-- vdd; level <-- vdd; half <-- half.value +:. 1; nlp_cnt <-- nlp_cnt.value +:. 1
                                 ; when_ (half.value ==:. (2 * h - 1)) [ state <--. s_idle ] ]
        ; of_int ~width:3 s_tpidl, [ active <-- vdd; level <-- vdd; half <-- half.value +:. 1
                                   ; when_ (half.value ==:. (3 * h - 1)) [ state <--. s_gap; gap_cnt <--. 0 ] ]
        ; of_int ~width:3 s_gap, [ active <-- gnd; level <-- gnd; gap_cnt <-- gap_cnt.value +:. 1
                                 ; when_ (gap_cnt.value ==:. (96 * h * 2 / 2 - 1)) [ state <--. s_idle; nlp_cnt <--. 0 ] ] ]
    ; when_ sending
        [ active <-- vdd
        ; (* first half of a 1 is low, of a 0 is high; second half the opposite *)
          level <-- mux2 second.value b (~:b)
        ; half <-- mux2 half_end (zero 4) (half.value +:. 1)
        ; when_ half_end
            [ second <-- ~:(second.value)
            ; when_ second.value
                ([ when_ (state.value ==:. s_data) [ crc <-- crc32_step crc.value b ] ] @ next_bit) ] ] ];
  (* the crc must be updated with each data bit as it goes out; also cover bits of the SFD? no: FCS
     covers destination address through payload only *)
  level.value, active.value, state.value

let circuit ~h ~nlp_period ~frame =
  let clock = input "clock" 1 and clear = input "clear" 1 and start = input "start" 1 in
  let level, active, state = create ~clock ~clear ~h ~nlp_period ~start ~frame in
  Circuit.create_exn ~name:"eth_tx" [ output "txp" (level &: active); output "txn" (~:level &: active); output "txen" active; output "state" state ]
