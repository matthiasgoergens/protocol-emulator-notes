(* Low-speed protocol engine for a HID boot keyboard, adapted from ../usb-fs-device/usb_sie.ml.
   Control endpoint 0: GET_DESCRIPTOR for the device, configuration and HID report descriptors,
   SET_ADDRESS, SET_CONFIGURATION, SET_IDLE; STALL for anything else. Endpoint 1 is an interrupt
   IN endpoint returning an 8-byte boot report when one is pending and NAK otherwise, with data
   toggles. Changes from the full-speed engine: descriptors from descriptors.ml in a 7-bit
   addressed ROM, the interrupt endpoint in place of the bulk loopback, packets with a stuff
   error are dropped, a bus reset returns the engine to the default state, and the response
   delay is in low-speed bit times. *)
open Hardcaml
open Signal

let pid_out = 0xE1 and pid_in = 0x69 and pid_setup = 0x2D
let pid_data0 = 0xC3 and pid_data1 = 0x4B and pid_ack = 0xD2 and pid_nak = 0x5A and pid_stall = 0x1E

let crc16_step crc b = let fb = bit crc 0 ^: b in mux2 fb (srl crc 1 ^: of_int ~width:16 0xA001) (srl crc 1)
let crc16_byte crc byte = List.fold_left crc16_step crc (bits_lsb byte)
let crc5_step crc b = let fb = bit crc 0 ^: b in mux2 fb (srl crc 1 ^: of_int ~width:5 0x14) (srl crc 1)

(* [resp_delay]: clocks from the receiver's end-of-packet (first SE0 sample) to the start of the
   reply. The host's EOP is two bits of SE0 then J; a reply must start between 2 and 6.5 bit
   times after the SE0-to-J edge, i.e. between about 140 and 320 clocks after the first SE0
   sample at 40 clocks per bit. 190 aims at 3.3 bit times. *)
let create ?(resp_delay = 190) ?(check_crc = true) ~clock ~clear ~bus_reset ~rx_byte ~rx_valid ~rx_start ~rx_end ~rx_err
    ~tx_ack ~tx_busy ~report ~report_valid () =
  let spec = Reg_spec.create ~clock ~clear () in
  (* protocol state that a bus reset returns to default *)
  let rspec = Reg_spec.create ~clock ~clear:(clear |: bus_reset) () in
  let open Always in
  let r w = Variable.reg spec ~width:w and rr w = Variable.reg rspec ~width:w in
  let addr = rr 7 and pend_addr = rr 7 and addr_pending = rr 1 and configured = rr 1 in
  let cnt = r 4 and pid = r 8 and b1 = r 8 and b2 = r 8 and crc = r 16 and bad = r 1 in
  let buf = Array.init 8 (fun _ -> r 8) in
  let expect_setup = rr 1 and expect_out = rr 1 and out_ep = rr 4 in
  let ctrl = rr 3 in
  let c_idle = of_int ~width:3 0 and c_data_in = of_int ~width:3 1 and c_status_in = of_int ~width:3 2
  and c_status_out = of_int ~width:3 3 and c_stall = of_int ~width:3 4 in
  let desc_base = rr 7 and total = rr 7 and ptr = rr 7 and zlp = rr 1 and ep0_toggle = rr 1 in
  let rep = Array.init 8 (fun _ -> r 8) and rep_pending = r 1 and in_toggle = rr 1 in
  let resp_pending = rr 1 and resp_count = rr 9 and resp_pid = rr 8 and resp_len = rr 4 and resp_src = rr 1 and resp_is_data = rr 1 in
  let awaiting_ack = rr 1 and sent_len = rr 4 and ack_ep1 = rr 1 in
  let tx_idx = rr 5 and tx_crc = rr 16 and tx_active = rr 1 in
  let tx_start = Variable.wire ~default:gnd in
  let rx_valid = rx_valid &: ~:tx_busy and rx_start = rx_start &: ~:tx_busy and rx_end = rx_end &: ~:tx_busy in
  let rx_err = rx_err &: ~:tx_busy in
  let pid_ok = select pid.value 3 0 ==: ~:(select pid.value 7 4) in
  let tok_addr = select b1.value 6 0 in
  let tok_ep = concat_msb [ select b2.value 2 0; bit b1.value 7 ] in
  let tok_bits = bits_lsb b1.value @ bits_lsb b2.value in
  let crc5_res = List.fold_left crc5_step (of_int ~width:5 0x1F) tok_bits in
  let token_ok = pid_ok &: (cnt.value ==:. 3) &: (crc5_res ==:. 0x06) &: ~:(bad.value) in
  let for_us = tok_addr ==: addr.value in
  let is_token p = pid.value ==:. p in
  let crc_good = if check_crc then crc.value ==:. 0xB001 else vdd in
  let data_ok = pid_ok &: crc_good &: (cnt.value >=:. 3) &: ~:(bad.value) in
  let payload_len = cnt.value -:. 3 in
  let is_data = is_token pid_data0 |: is_token pid_data1 in
  let remaining = total.value -: ptr.value in
  let chunk = mux2 (remaining >:. 8) (of_int ~width:7 8) remaining in
  let respond ~p ~len ~src ~data =
    [ resp_pending <-- vdd; resp_count <--. 0; resp_pid <-- of_int ~width:8 p; resp_len <-- len; resp_src <-- src; resp_is_data <-- data ] in
  let respond_hs p = respond ~p ~len:(zero 4) ~src:gnd ~data:gnd in
  let data_pid tg = mux2 tg (of_int ~width:8 pid_data1) (of_int ~width:8 pid_data0) in
  let respond_data ~tg ~len ~src = [ resp_pending <-- vdd; resp_count <--. 0; resp_pid <-- data_pid tg; resp_len <-- len; resp_src <-- src; resp_is_data <-- vdd; awaiting_ack <-- vdd; sent_len <-- len ] in
  let setup b = buf.(b).value in
  let wlen_l = setup 6 and wlen_h = setup 7 in
  let dtype = setup 3 in
  let n x = of_int ~width:7 x in
  let is_get_std = (setup 0 ==:. 0x80) &: (setup 1 ==:. 0x06) &: ((dtype ==:. 1) |: (dtype ==:. 2)) in
  let is_get_rep = (setup 0 ==:. 0x81) &: (setup 1 ==:. 0x06) &: (dtype ==:. 0x22) in
  let desc_len = mux2 (dtype ==:. 1) (n (List.length Descriptors.device))
      (mux2 (dtype ==:. 2) (n (List.length Descriptors.config)) (n (List.length Descriptors.report))) in
  let desc_b = mux2 (dtype ==:. 1) (n Descriptors.dev_base) (mux2 (dtype ==:. 2) (n Descriptors.cfg_base) (n Descriptors.rep_base)) in
  let wlen_ge_desc = (wlen_h <>:. 0) |: (wlen_l >=: uresize desc_len 8) in
  let tot = mux2 wlen_ge_desc desc_len (select wlen_l 6 0) in
  let decode_setup =
    [ ep0_toggle <-- vdd; ptr <--. 0
    ; if_ (is_get_std |: is_get_rep)
        [ desc_base <-- desc_b; total <-- tot; ctrl <-- c_data_in
        (* a zero-length packet ends the data stage when it returned less than asked and the
           last packet was full *)
        ; zlp <-- ((select tot 2 0 ==:. 0) &: ~:((wlen_h ==:. 0) &: (wlen_l ==: uresize tot 8))) ]
        [ if_ ((setup 0 ==:. 0x00) &: (setup 1 ==:. 0x05))
            [ pend_addr <-- select (setup 2) 6 0; addr_pending <-- vdd; ctrl <-- c_status_in ]
            [ if_ ((setup 0 ==:. 0x00) &: (setup 1 ==:. 0x09))
                [ configured <-- (setup 2 <>:. 0); in_toggle <-- gnd; ctrl <-- c_status_in ]
                [ if_ ((setup 0 ==:. 0x21) &: (setup 1 ==:. 0x0A))
                    [ ctrl <-- c_status_in ]
                    [ ctrl <-- c_stall ] ] ] ] ] in
  let rom_bytes = Descriptors.rom in
  let rom = mux (desc_base.value +: ptr.value +: uresize (tx_idx.value -:. 1) 7) (List.map (of_int ~width:8) rom_bytes) in
  let rep_byte = mux (select (tx_idx.value -:. 1) 2 0) (Array.to_list (Array.map (fun (v : Variable.t) -> v.value) rep)) in
  let src_byte = mux2 resp_src.value rep_byte rom in
  let tx_len_total = mux2 resp_is_data.value (uresize resp_len.value 5 +:. 3) (of_int ~width:5 1) in
  let tx_valid = tx_active.value &: (tx_idx.value <: tx_len_total) in
  let idx_is_data = (tx_idx.value >=:. 1) &: (tx_idx.value <=: uresize resp_len.value 5) in
  let tx_data =
    mux2 (tx_idx.value ==:. 0) resp_pid.value
      (mux2 idx_is_data src_byte
         (mux2 (tx_idx.value ==: uresize resp_len.value 5 +:. 1) (~:(select tx_crc.value 7 0)) (~:(select tx_crc.value 15 8)))) in
  compile
    [ (* the application offers a report; it is taken when none is pending *)
      when_ (report_valid &: ~:(rep_pending.value))
        ((rep_pending <-- vdd) :: List.init 8 (fun i -> rep.(i) <-- select report (8 * i + 7) (8 * i)))
    ; when_ rx_start [ cnt <--. 0; crc <--. 0xFFFF; bad <--. 0 ]
    ; when_ rx_err [ bad <--. 1 ]
    ; when_ rx_valid
        [ when_ (cnt.value ==:. 0) [ pid <-- rx_byte ]
        ; when_ (cnt.value ==:. 1) [ b1 <-- rx_byte ]
        ; when_ (cnt.value ==:. 2) [ b2 <-- rx_byte ]
        ; when_ (cnt.value >=:. 1) [ crc <-- crc16_byte crc.value rx_byte ]
        ; proc (List.init 8 (fun i -> when_ (cnt.value ==:. (i + 1)) [ buf.(i) <-- rx_byte ]))
        ; when_ (cnt.value <>:. 15) [ cnt <-- cnt.value +:. 1 ] ]
    ; when_ rx_end
        [ if_ ((is_token pid_in |: is_token pid_out |: is_token pid_setup) &: token_ok &: for_us)
            [ if_ (is_token pid_setup) [ expect_setup <-- vdd; expect_out <-- gnd ] []
            ; if_ (is_token pid_out) [ expect_out <-- vdd; expect_setup <-- gnd; out_ep <-- tok_ep ] []
            ; when_ (is_token pid_in)
                [ expect_setup <-- gnd; expect_out <-- gnd
                ; if_ (tok_ep ==:. 0)
                    [ switch ctrl.value
                        [ c_data_in, respond_data ~tg:ep0_toggle.value ~len:(select chunk 3 0) ~src:gnd @ [ ack_ep1 <-- gnd ]
                        ; c_status_in, respond_data ~tg:vdd ~len:(zero 4) ~src:gnd @ [ ack_ep1 <-- gnd ]
                        ; c_stall, respond_hs pid_stall
                        ; c_idle, respond_hs pid_nak
                        ; c_status_out, respond_hs pid_nak ] ]
                    [ if_ (tok_ep ==:. 1)
                        [ if_ (rep_pending.value &: configured.value)
                            (respond_data ~tg:in_toggle.value ~len:(of_int ~width:4 8) ~src:vdd @ [ ack_ep1 <-- vdd ])
                            (respond_hs pid_nak) ]
                        (respond_hs pid_stall) ] ] ]
            [ when_ (is_data &: expect_setup.value)
                [ expect_setup <-- gnd
                ; when_ (data_ok &: (payload_len ==:. 8)) (respond_hs pid_ack @ decode_setup) ]
            ; when_ (is_data &: expect_out.value)
                [ expect_out <-- gnd
                ; when_ data_ok
                    [ if_ (out_ep.value ==:. 0)
                        [ if_ (ctrl.value ==: c_stall) (respond_hs pid_stall)
                            (respond_hs pid_ack @ [ when_ ((ctrl.value ==: c_status_out) |: (ctrl.value ==: c_data_in)) [ ctrl <-- c_idle ] ]) ]
                        (respond_hs pid_stall) ] ]
            ; when_ (is_token pid_ack &: pid_ok &: awaiting_ack.value &: ~:(bad.value) &: (cnt.value ==:. 1))
                [ awaiting_ack <-- gnd
                ; if_ ack_ep1.value [ rep_pending <-- gnd; in_toggle <-- ~:(in_toggle.value) ]
                    [ switch ctrl.value
                        [ c_data_in, [ ptr <-- ptr.value +: uresize sent_len.value 7; ep0_toggle <-- ~:(ep0_toggle.value)
                                     ; when_ ((sent_len.value <>:. 8) |: ((ptr.value +: uresize sent_len.value 7 ==: total.value) &: ~:(zlp.value)))
                                         [ ctrl <-- c_status_out ]
                                     ; when_ ((ptr.value +: uresize sent_len.value 7 ==: total.value) &: zlp.value &: (sent_len.value ==:. 8)) [ zlp <-- gnd ] ]
                        ; c_status_in, [ ctrl <-- c_idle; when_ addr_pending.value [ addr <-- pend_addr.value; addr_pending <-- gnd ] ] ] ] ] ] ]
    ; when_ resp_pending.value
        [ resp_count <-- resp_count.value +:. 1
        ; when_ (resp_count.value ==:. resp_delay) [ resp_pending <-- gnd; tx_start <-- vdd; tx_active <-- vdd; tx_idx <--. 0; tx_crc <--. 0xFFFF ] ]
    ; when_ (tx_active.value &: tx_ack)
        [ tx_idx <-- tx_idx.value +:. 1; when_ idx_is_data [ tx_crc <-- crc16_byte tx_crc.value src_byte ] ]
    ; when_ (tx_active.value &: ~:tx_busy &: ~:(tx_start.value) &: (tx_idx.value <>:. 0)) [ tx_active <-- gnd ] ];
  tx_start.value, tx_data, tx_valid, addr.value, configured.value, rep_pending.value
