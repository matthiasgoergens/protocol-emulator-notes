(* 10BASE-T receiver, digital side: takes a comparator output (1 = positive differential) and an
   activity flag (squelch), recovers bits from mid-bit transitions, finds the SFD, assembles bytes
   LSB first, runs CRC-32 and reports frame end with the residual check. [h] cycles per half bit. *)
open Hardcaml
open Signal

let residual = 0xDEBB20E3

let create ~clock ~clear ~h ~rx ~rx_active =
  let spec = Reg_spec.create ~clock ~clear () in
  let open Always in
  let rx_q = reg spec (reg spec rx) and act_q = reg spec (reg spec rx_active) in
  let rx_prev = reg spec rx_q in
  (* cycles the activity flag has been low: a frame ends only after a whole bit time without
     activity, so a squelch flicker mid-frame does not truncate it (found by differential fuzzing:
     a 2-cycle dropout at frame byte 42 ended the frame, while the host model decoded it) *)
  let quiet = reg_fb spec ~width:4 ~f:(fun q -> mux2 act_q (zero 4) (mux2 (q ==:. 15) q (q +:. 1))) in
  let transition = (rx_q <>: rx_prev) &: act_q in
  let since = Variable.reg spec ~width:6 in            (* cycles since last mid-bit transition *)
  let in_frame = Variable.reg spec ~width:1 and synced = Variable.reg spec ~width:1 and first = Variable.reg spec ~width:1 in
  let shift = Variable.reg spec ~width:8 and bitcnt = Variable.reg spec ~width:3 in
  let crc = Variable.reg spec ~width:32 in
  let byte_valid = Variable.wire ~default:gnd and frame_end = Variable.wire ~default:gnd and crc_ok = Variable.wire ~default:gnd in
  let bit_w = Variable.wire ~default:gnd and bit_valid = Variable.wire ~default:gnd in
  let shifted = concat_msb [ rx_q; select shift.value 7 1 ] in
  let mid_window = since.value >=:. (2 * h - 2) in     (* a transition this late is mid-bit *)
  compile
    [ since <-- mux2 (since.value ==:. 63) since.value (since.value +:. 1)
    ; if_ (~:(in_frame.value))
        [ when_ (act_q &: transition) [ in_frame <-- vdd; first <-- vdd; synced <-- gnd; since <--. 0; bitcnt <--. 0; crc <--. 0xFFFFFFFF ] ]
        [ (* end of frame: no activity, or no transition for two bit times *)
          when_ ((quiet >=:. (2 * h - 1)) |: (since.value >=:. (4 * h))) [ in_frame <-- gnd; frame_end <-- vdd; crc_ok <-- (crc.value ==:. residual) ]
        ; when_ transition
            [ if_ first.value
                [ (* first transition after idle is a bit boundary; the next one is mid-bit *) first <-- gnd; since <--. 0 ]
                [ when_ mid_window
                    [ since <--. 0; bit_w <-- rx_q; bit_valid <-- vdd
                    ; if_ (~:(synced.value))
                        [ shift <-- shifted; when_ (shifted ==:. 0xD5) [ synced <-- vdd; bitcnt <--. 0 ] ]
                        [ shift <-- shifted; bitcnt <-- bitcnt.value +:. 1
                        ; crc <-- Eth_tx.crc32_step crc.value rx_q
                        ; when_ (bitcnt.value ==:. 7) [ byte_valid <-- vdd ] ] ] ] ] ] ];
  shifted, byte_valid.value, frame_end.value, crc_ok.value, bit_w.value, bit_valid.value

let circuit ~h =
  let clock = input "clock" 1 and clear = input "clear" 1 and rx = input "rx" 1 and rx_active = input "rx_active" 1 in
  let byte, byte_valid, frame_end, crc_ok, _, _ = create ~clock ~clear ~h ~rx ~rx_active in
  Circuit.create_exn ~name:"eth_rx" [ output "rx_byte" byte; output "byte_valid" byte_valid; output "frame_end" frame_end; output "crc_ok" crc_ok ]
