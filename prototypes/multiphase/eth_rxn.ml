(* 10BASE-T receiver taking n samples per clock (n = 1, 2 or 4: one phase, both clock edges, four
   phases), otherwise the same design as ../ethernet-10base-t/eth_rx.ml: it recovers bits from
   mid-bit transitions, finds the SFD, assembles bytes LSB first and checks the CRC.

   Time is counted in sub-samples (1/n clock). Sample p of clock c is taken at (c + p/n) T. A
   transition is placed at the first sample that differs from its predecessor, and is mid-bit if at
   least [thr] sub-samples have passed since the last mid-bit transition. One transition per clock
   is handled; a half-bit is at least 2.6 clocks, so that loses nothing but glitches. With n = 1 and
   thr = 2h - 1 this is eth_rx's decision rule exactly (its since + 1 is the elapsed count here),
   which the test checks by running both on the same lines. *)
open Hardcaml
open Signal

let create ~clock ~clear ~n ~thr ~samples ~rx_active =
  let spec = Reg_spec.create ~clock ~clear () in
  let open Always in
  let s_q = reg spec (reg spec samples) and act_q = reg spec (reg spec rx_active) in
  let prev = reg spec (msb s_q) in
  let quiet = reg_fb spec ~width:4 ~f:(fun q -> mux2 act_q (zero 4) (mux2 (q ==:. 15) q (q +:. 1))) in
  (* seq.(0) = last sample of the previous clock, seq.(p+1) = sample p *)
  let seq = Array.init (n + 1) (fun i -> if i = 0 then prev else bit s_q (i - 1)) in
  let diffs = List.init n (fun p -> seq.(p + 1) <>: seq.(p)) in
  let transition = reduce ~f:( |: ) diffs &: act_q in
  (* index of the first transition, and the level after it *)
  let first_idx, new_level =
    List.fold_right (fun p (idx, lvl) ->
        (mux2 (List.nth diffs p) (of_int ~width:3 p) idx, mux2 (List.nth diffs p) seq.(p + 1) lvl))
      (List.init n Fun.id) (of_int ~width:3 0, gnd) in
  let w = 8 in
  let since = Variable.reg spec ~width:w in
  let elapsed = since.value +: uresize first_idx w in
  let restart = of_int ~width:w n -: uresize first_idx w in
  let in_frame = Variable.reg spec ~width:1 and synced = Variable.reg spec ~width:1 and first = Variable.reg spec ~width:1 in
  let shift = Variable.reg spec ~width:8 and bitcnt = Variable.reg spec ~width:3 in
  let crc = Variable.reg spec ~width:32 in
  let byte_valid = Variable.wire ~default:gnd and frame_end = Variable.wire ~default:gnd and crc_ok = Variable.wire ~default:gnd in
  let shifted = concat_msb [ new_level; select shift.value 7 1 ] in
  let mid = elapsed >=:. thr in
  let sat = (1 lsl w) - 1 - n in
  compile
    [ since <-- mux2 (since.value >=:. sat) since.value (since.value +:. n)
    ; if_ (~:(in_frame.value))
        [ when_ (act_q &: transition) [ in_frame <-- vdd; first <-- vdd; synced <-- gnd; since <-- restart; bitcnt <--. 0; crc <--. 0xFFFFFFFF ] ]
        [ when_ ((quiet >=:. 5) |: (since.value >=:. ((12 * n) + 1)))
            [ in_frame <-- gnd; frame_end <-- vdd; crc_ok <-- (crc.value ==:. Eth_rx.residual) ]
        ; when_ transition
            [ if_ first.value
                [ first <-- gnd; since <-- restart ]
                [ when_ mid
                    [ since <-- restart
                    ; if_ (~:(synced.value))
                        [ shift <-- shifted; when_ (shifted ==:. 0xD5) [ synced <-- vdd; bitcnt <--. 0 ] ]
                        [ shift <-- shifted; bitcnt <-- bitcnt.value +:. 1
                        ; crc <-- Eth_tx.crc32_step crc.value new_level
                        ; when_ (bitcnt.value ==:. 7) [ byte_valid <-- vdd ] ] ] ] ] ] ];
  shifted, byte_valid.value, frame_end.value, crc_ok.value

let circuit ~n ~thr =
  let clock = input "clock" 1 and clear = input "clear" 1 in
  let samples = input "samples" n and rx_active = input "rx_active" 1 in
  let byte, byte_valid, frame_end, crc_ok = create ~clock ~clear ~n ~thr ~samples ~rx_active in
  Circuit.create_exn ~name:(Printf.sprintf "eth_rx%d" n)
    [ output "rx_byte" byte; output "byte_valid" byte_valid; output "frame_end" frame_end; output "crc_ok" crc_ok ]
