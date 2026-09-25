(* 100BASE-X PCS at two code bits per clock (62.5 MHz for 125 Mbaud), built from the generic
   units. [media] selects FX (NRZI) or TX (scrambler + MLT-3 on a pin pair). *)
open! Base
open Hardcaml
open Signal
open Units

type media = Fx | Tx

let k = 2   (* code bits per clock *)
let scr_taps = [ 11; 9 ]

(* ---------------- transmit ---------------- *)
(* Byte interface: the transmitter pulses [tx_ready] in the clock in which it takes [tx_data];
   [tx_valid] must stay high from the first byte to the last, which has [tx_last] set. One byte
   per 5 clocks. Output per clock: the 2 code bits (before any line code), and the line: for FX
   the NRZI level (2 bits), for TX pins A and B (2 bits each). *)
let tx ~media ~clock ~clear ~tx_valid ~tx_data ~tx_last =
  let spec = Reg_spec.create ~clock ~clear () in
  let slot = reg_fb spec ~width:3 ~f:(fun s -> mux2 (s ==:. 4) (zero 3) (s +:. 1)) in
  let load = slot ==:. 4 in
  let open Always in
  let st_idle = 0 and st_pre = 1 and st_data = 2 and st_fcs = 3 and st_tr = 4 and st_ipg = 5 in
  let state = Variable.reg spec ~width:3 and cnt = Variable.reg spec ~width:4 in
  let crc = Variable.reg (Reg_spec.override spec ~clear_to:(of_int ~width:32 0xFFFFFFFF)) ~width:32 in
  let sym i = Block_4b5b.encode (of_int ~width:5 i) in
  let pair a b = concat_lsb [ a; b ] in
  let byte_word b = pair (Block_4b5b.encode (uresize (select b 3 0) 5)) (Block_4b5b.encode (uresize (select b 7 4) 5)) in
  let idle_word = pair (sym Block_4b5b.sym_i) (sym Block_4b5b.sym_i) in
  let word = Variable.wire ~default:idle_word and ready = Variable.wire ~default:gnd in
  let fcs_byte = mux (select cnt.value 1 0) (List.init 4 ~f:(fun i -> ~:(select crc.value (8 * i + 7) (8 * i)))) in
  compile
    [ when_ load
        [ if_ (state.value ==:. st_idle)
            [ when_ tx_valid [ word <-- pair (sym Block_4b5b.sym_j) (sym Block_4b5b.sym_k); state <--. st_pre; cnt <--. 1 ] ]
          @@ elif (state.value ==:. st_pre)
            [ word <-- byte_word (mux2 (cnt.value ==:. 7) (of_int ~width:8 0xD5) (of_int ~width:8 0x55))
            ; cnt <-- cnt.value +:. 1
            ; when_ (cnt.value ==:. 7) [ state <--. st_data; crc <--. 0xFFFFFFFF ] ]
          @@ elif (state.value ==:. st_data)
            [ word <-- byte_word tx_data; ready <-- vdd; crc <-- crc32_byte crc.value tx_data
            ; when_ tx_last [ state <--. st_fcs; cnt <--. 0 ] ]
          @@ elif (state.value ==:. st_fcs)
            [ word <-- byte_word fcs_byte; cnt <-- cnt.value +:. 1
            ; when_ (cnt.value ==:. 3) [ state <--. st_tr ] ]
          @@ elif (state.value ==:. st_tr)
            [ word <-- pair (sym Block_4b5b.sym_t) (sym Block_4b5b.sym_r); state <--. st_ipg; cnt <--. 0 ]
            [ (* inter-packet gap: 12 octets of idle *)
              cnt <-- cnt.value +:. 1; when_ (cnt.value ==:. 11) [ state <--. st_idle ] ] ] ];
  let sh = reg_fb (Reg_spec.override spec ~clear_to:(ones 10)) ~width:10 ~f:(fun s -> mux2 load word.value (srl s 2)) in
  let code = select sh 1 0 in
  let line =
    match media with
    | Fx -> [ "line", Line_code.nrzi_encode ~spec ~k code ]
    | Tx ->
      let scr = Lfsr.additive ~spec ~taps:scr_taps ~k ~seed:0x7FF code in
      let a, b = Line_code.mlt3_pins ~spec ~k scr in
      [ "pin_a", a; "pin_b", b; "scrambled", scr ]
  in
  ready.value, code, line

(* ---------------- receive ---------------- *)
let rk = 3   (* up to 3 code bits per clock out of the CDR *)

(* 100BASE-TX descrambler with idle lock: while unlocked, assume the plaintext is idle (all
   ones), so the keystream is the complemented ciphertext; shift it in and count how many
   consecutive bits the LFSR predicted correctly; 40 in a row locks. Locked, it free-runs. It
   unlocks if no run of 30 plaintext ones (idle) has been seen for 2^14 clocks (262 us, longer
   than a maximum frame). *)
let descramble ~spec ~count cipher =
  let open Always in
  let st = Variable.reg spec ~width:11 and locked = Variable.reg spec ~width:1 in
  let run = Variable.reg spec ~width:6 and ones = Variable.reg spec ~width:6 in
  let wd = Variable.reg spec ~width:15 in
  let rec go i s lk r o idle outs =
    if i = rk then s, lk, r, o, idle, List.rev outs
    else
      let v = count >:. i and c = bit cipher i in
      let pred = Lfsr.next_bit ~taps:scr_taps s in
      let est = ~:c in
      let plain = mux2 lk (c ^: pred) vdd in
      let s' = mux2 v (Lfsr.shift_in s (mux2 lk pred est)) s in
      let hit = pred ==: est in
      let r' = mux2 (v &: ~:lk) (mux2 hit (mux2 (r ==:. 63) r (r +:. 1)) (zero 6)) r in
      let lk' = lk |: (v &: (r' >=:. 40)) in
      let o' = mux2 v (mux2 plain (mux2 (o ==:. 63) o (o +:. 1)) (zero 6)) o in
      let idle' = idle |: (v &: (o' >=:. 30)) in
      go (i + 1) s' lk' r' o' idle' (plain :: outs)
  in
  let s, lk, r, o, idle, outs = go 0 st.value locked.value run.value ones.value gnd [] in
  let timeout = wd.value ==:. 0x7FFF in
  compile
    [ st <-- s; run <-- mux2 timeout (zero 6) r; ones <-- o
    ; locked <-- (lk &: ~:timeout)
    ; wd <-- mux2 (idle |: ~:lk) (zero 15) (wd.value +:. 1) ];
  concat_lsb outs, locked.value

(* Inputs per clock: [count] (0..3) valid UIs from the CDR, and per UI either one NRZI level
   (FX: [levels] 3 bits) or a 2-bit sliced MLT-3 level (TX: [levels] 6 bits, UI i in bits
   2i+1..2i). Outputs bytes (after the SFD, including the FCS), frame_end with crc_ok. *)
let rx ~media ~clock ~clear ~count ~levels =
  let spec = Reg_spec.create ~clock ~clear () in
  let bits, locked =
    match media with
    | Fx -> Line_code.nrzi_decode ~spec ~k:rk ~count levels, vdd
    | Tx ->
      let lv = List.init rk ~f:(fun i -> select levels (2 * i + 1) (2 * i)) in
      let cipher = Line_code.mlt3_decode ~spec ~k:rk ~count lv in
      descramble ~spec ~count cipher
  in
  let open Always in
  let in_frame = Variable.reg spec ~width:1 and phase = Variable.reg spec ~width:1 in
  let lo = Variable.reg spec ~width:4 and sfd = Variable.reg spec ~width:1 and tp = Variable.reg spec ~width:1 in
  let crc = Variable.reg spec ~width:32 in
  let byte_valid = Variable.wire ~default:gnd and frame_end = Variable.wire ~default:gnd in
  let crc_ok = Variable.wire ~default:gnd and clear_align = Variable.wire ~default:gnd in
  let delim = concat_lsb [ Block_4b5b.vec "11000"; Block_4b5b.vec "10001" ] in
  let group, gv, found, _aligned =
    Aligner.create ~spec ~k:rk ~w:5 ~delim ~clear:clear_align.value ~count:(mux2 locked count (zero 2)) bits in
  let id, valid = Block_4b5b.decode group in
  let is_data = valid &: (id <:. 16) in
  let byte = concat_msb [ select id 3 0; lo.value ] in
  let finish ok = [ frame_end <-- vdd; crc_ok <-- ok; in_frame <-- gnd; clear_align <-- vdd ] in
  compile
    [ if_ found [ in_frame <-- vdd; phase <-- gnd; sfd <-- gnd; tp <-- gnd; crc <--. 0xFFFFFFFF ]
        [ when_ (gv &: in_frame.value)
            [ if_ tp.value
                (finish ((id ==:. Block_4b5b.sym_r) &: valid &: (crc.value ==:. crc_residual) &: ~:(phase.value) &: sfd.value))
              @@ elif is_data
                [ if_ ~:(phase.value) [ lo <-- select id 3 0; phase <-- vdd ]
                    [ phase <-- gnd
                    ; if_ sfd.value [ byte_valid <-- vdd; crc <-- crc32_byte crc.value byte ]
                      @@ elif (byte ==:. 0xD5) [ sfd <-- vdd ]
                      @@ elif (byte ==:. 0x55) []
                      (finish gnd) ] ]
              @@ elif (valid &: (id ==:. Block_4b5b.sym_t)) [ tp <-- vdd ]
              (finish gnd) ] ] ];
  byte, byte_valid.value, frame_end.value, crc_ok.value, locked

let tx_circuit media =
  let clock = input "clock" 1 and clear = input "clear" 1 in
  let tx_valid = input "tx_valid" 1 and tx_data = input "tx_data" 8 and tx_last = input "tx_last" 1 in
  let ready, code, line = tx ~media ~clock ~clear ~tx_valid ~tx_data ~tx_last in
  Circuit.create_exn ~name:(match media with Fx -> "fx_tx" | Tx -> "tx_tx")
    ([ output "tx_ready" ready; output "code" code ] @ List.map line ~f:(fun (n, s) -> output n s))

let rx_circuit media =
  let clock = input "clock" 1 and clear = input "clear" 1 in
  let count = input "count" 2 and levels = input "levels" (match media with Fx -> rk | Tx -> 2 * rk) in
  let byte, bv, fe, ok, locked = rx ~media ~clock ~clear ~count ~levels in
  Circuit.create_exn ~name:(match media with Fx -> "fx_rx" | Tx -> "tx_rx")
    [ output "rx_byte" byte; output "byte_valid" bv; output "frame_end" fe; output "crc_ok" ok; output "locked" locked ]
