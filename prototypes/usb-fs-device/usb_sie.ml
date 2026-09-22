(* USB full-speed device protocol engine: control endpoint 0 with GET_DESCRIPTOR (device,
   configuration), SET_ADDRESS and SET_CONFIGURATION; bulk endpoint 1 loopback with an 8-byte
   buffer. Fixed logic because a device must answer a token within a few bit times. *)
open Hardcaml
open Signal

let device_descriptor = [ 0x12; 0x01; 0x00; 0x02; 0xFF; 0x00; 0x00; 0x08; 0x09; 0x12; 0x01; 0x00; 0x00; 0x01; 0x00; 0x00; 0x00; 0x01 ]
let config_descriptor =
  [ 0x09; 0x02; 0x20; 0x00; 0x01; 0x01; 0x00; 0x80; 0x32 ]     (* configuration, total 32 bytes *)
  @ [ 0x09; 0x04; 0x00; 0x00; 0x02; 0xFF; 0x00; 0x00; 0x00 ]   (* interface, 2 endpoints *)
  @ [ 0x07; 0x05; 0x01; 0x02; 0x08; 0x00; 0x00 ]               (* EP1 OUT bulk, 8 bytes *)
  @ [ 0x07; 0x05; 0x81; 0x02; 0x08; 0x00; 0x00 ]               (* EP1 IN bulk, 8 bytes *)
let rom_bytes = device_descriptor @ config_descriptor
let dev_len = List.length device_descriptor and cfg_len = List.length config_descriptor

let pid_out = 0xE1 and pid_in = 0x69 and pid_setup = 0x2D and pid_sof = 0xA5
let pid_data0 = 0xC3 and pid_data1 = 0x4B and pid_ack = 0xD2 and pid_nak = 0x5A and pid_stall = 0x1E

let crc16_step crc b = let fb = bit crc 0 ^: b in mux2 fb (srl crc 1 ^: of_int ~width:16 0xA001) (srl crc 1)
let crc16_byte crc byte = List.fold_left crc16_step crc (bits_lsb byte)
let crc5_step crc b = let fb = bit crc 0 ^: b in mux2 fb (srl crc 1 ^: of_int ~width:5 0x14) (srl crc 1)

let create ~clock ~clear ~rx_byte ~rx_valid ~rx_start ~rx_end ~tx_ack ~tx_busy =
  let spec = Reg_spec.create ~clock ~clear () in
  let open Always in
  let r w = Variable.reg spec ~width:w in
  let addr = r 7 and pend_addr = r 7 and addr_pending = r 1 and configured = r 1 in
  let cnt = r 4 and pid = r 8 and b1 = r 8 and b2 = r 8 and crc = r 16 in
  let buf = Array.init 8 (fun _ -> r 8) in
  let expect_setup = r 1 and expect_out = r 1 and out_ep = r 4 in
  let ctrl = r 3 in
  let c_idle = of_int ~width:3 0 and c_data_in = of_int ~width:3 1 and c_status_in = of_int ~width:3 2
  and c_status_out = of_int ~width:3 3 and c_stall = of_int ~width:3 4 in
  let desc_base = r 6 and total = r 6 and ptr = r 6 and zlp = r 1 and ep0_toggle = r 1 in
  let obuf = Array.init 8 (fun _ -> r 8) and olen = r 4 and ofull = r 1 and in_toggle = r 1 in
  let resp_pending = r 1 and resp_delay = r 5 and resp_pid = r 8 and resp_len = r 4 and resp_src = r 1 and resp_is_data = r 1 in
  let awaiting_ack = r 1 and sent_len = r 4 and ack_ep1 = r 1 in
  let tx_idx = r 5 and tx_crc = r 16 and tx_active = r 1 in
  let tx_start = Variable.wire ~default:gnd in
  (* rx event masking while transmitting (a real bus echoes our own packets) *)
  let rx_valid = rx_valid &: ~:tx_busy and rx_start = rx_start &: ~:tx_busy and rx_end = rx_end &: ~:tx_busy in
  let pid_ok = select pid.value 3 0 ==: ~:(select pid.value 7 4) in
  let tok_addr = select b1.value 6 0 in
  let tok_ep = concat_msb [ select b2.value 2 0; bit b1.value 7 ] in
  let tok_bits = bits_lsb b1.value @ bits_lsb b2.value in
  let crc5_res = List.fold_left crc5_step (of_int ~width:5 0x1F) tok_bits in
  let token_ok = pid_ok &: (cnt.value ==:. 3) &: (crc5_res ==:. 0x06) in
  let for_us = tok_addr ==: addr.value in
  let is_token p = pid.value ==:. p in
  let data_ok = pid_ok &: (crc.value ==:. 0xB001) &: (cnt.value >=:. 3) in
  let payload_len = cnt.value -:. 3 in
  let is_data = is_token pid_data0 |: is_token pid_data1 in
  let remaining = total.value -: ptr.value in
  let chunk = mux2 (remaining >:. 8) (of_int ~width:6 8) remaining in
  let respond ~p ~len ~src ~data =
    [ resp_pending <-- vdd; resp_delay <--. 0; resp_pid <-- of_int ~width:8 p; resp_len <-- len; resp_src <-- src; resp_is_data <-- data ] in
  let respond_hs p = respond ~p ~len:(zero 4) ~src:gnd ~data:gnd in
  let data_pid tg = mux2 tg (of_int ~width:8 pid_data1) (of_int ~width:8 pid_data0) in
  let respond_data ~tg ~len ~src = [ resp_pending <-- vdd; resp_delay <--. 0; resp_pid <-- data_pid tg; resp_len <-- len; resp_src <-- src; resp_is_data <-- vdd; awaiting_ack <-- vdd; sent_len <-- len ] in
  let setup b = buf.(b).value in
  let wlen_l = setup 6 and wlen_h = setup 7 in
  let dsel = setup 3 in
  let desc_len = mux2 (dsel ==:. 1) (of_int ~width:6 dev_len) (of_int ~width:6 cfg_len) in
  let desc_b = mux2 (dsel ==:. 1) (of_int ~width:6 0) (of_int ~width:6 dev_len) in
  let wlen_ge_desc = (wlen_h <>:. 0) |: (wlen_l >=: uresize desc_len 8) in
  let tot = mux2 wlen_ge_desc desc_len (select wlen_l 5 0) in
  let decode_setup =
    [ ep0_toggle <-- vdd; ptr <--. 0
    ; if_ ((setup 0 ==:. 0x80) &: (setup 1 ==:. 0x06) &: ((dsel ==:. 1) |: (dsel ==:. 2)))
        [ desc_base <-- desc_b; total <-- tot; ctrl <-- c_data_in
        ; zlp <-- (wlen_ge_desc &: (select tot 2 0 ==:. 0) &: ~:((wlen_h ==:. 0) &: (wlen_l ==: uresize tot 8))) ]
        [ if_ ((setup 0 ==:. 0x00) &: (setup 1 ==:. 0x05))
            [ pend_addr <-- select (setup 2) 6 0; addr_pending <-- vdd; ctrl <-- c_status_in ]
            [ if_ ((setup 0 ==:. 0x00) &: (setup 1 ==:. 0x09))
                [ configured <-- vdd; ctrl <-- c_status_in ]
                [ ctrl <-- c_stall ] ] ] ] in
  let rom = mux (desc_base.value +: ptr.value +: uresize (tx_idx.value -:. 1) 6) (List.map (of_int ~width:8) rom_bytes) in
  let ep1_byte = mux (select (tx_idx.value -:. 1) 2 0) (Array.to_list (Array.map (fun (v : Variable.t) -> v.value) obuf)) in
  let src_byte = mux2 resp_src.value ep1_byte rom in
  let tx_len_total = mux2 resp_is_data.value (uresize resp_len.value 5 +:. 3) (of_int ~width:5 1) in
  let tx_valid = tx_active.value &: (tx_idx.value <: tx_len_total) in
  let idx_is_data = (tx_idx.value >=:. 1) &: (tx_idx.value <=: uresize resp_len.value 5) in
  let tx_data =
    mux2 (tx_idx.value ==:. 0) resp_pid.value
      (mux2 idx_is_data src_byte
         (mux2 (tx_idx.value ==: uresize resp_len.value 5 +:. 1) (~:(select tx_crc.value 7 0)) (~:(select tx_crc.value 15 8)))) in
  compile
    [ (* receive bookkeeping *)
      when_ rx_start [ cnt <--. 0; crc <--. 0xFFFF ]
    ; when_ rx_valid
        [ when_ (cnt.value ==:. 0) [ pid <-- rx_byte ]
        ; when_ (cnt.value ==:. 1) [ b1 <-- rx_byte ]
        ; when_ (cnt.value ==:. 2) [ b2 <-- rx_byte ]
        ; when_ (cnt.value >=:. 1) [ crc <-- crc16_byte crc.value rx_byte ]
        ; proc (List.init 8 (fun i -> when_ (cnt.value ==:. (i + 1)) [ buf.(i) <-- rx_byte ]))
        ; when_ (cnt.value <>:. 15) [ cnt <-- cnt.value +:. 1 ] ]
    ; (* packet end: tokens, data, handshakes *)
      when_ rx_end
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
                        [ if_ ofull.value (respond_data ~tg:in_toggle.value ~len:olen.value ~src:vdd @ [ ack_ep1 <-- vdd ]) (respond_hs pid_nak) ]
                        (respond_hs pid_stall) ] ] ]
            [ when_ (is_data &: expect_setup.value)
                [ expect_setup <-- gnd
                ; when_ (data_ok &: (payload_len ==:. 8)) (respond_hs pid_ack @ decode_setup) ]
            ; when_ (is_data &: expect_out.value)
                [ expect_out <-- gnd
                ; when_ data_ok
                    [ if_ (out_ep.value ==:. 0)
                        [ if_ (ctrl.value ==: c_stall) (respond_hs pid_stall) (respond_hs pid_ack @ [ when_ (ctrl.value ==: c_status_out) [ ctrl <-- c_idle ] ]) ]
                        [ if_ ofull.value (respond_hs pid_nak)
                            (respond_hs pid_ack @ [ ofull <-- vdd; olen <-- select payload_len 3 0 ]
                             @ List.init 8 (fun i -> obuf.(i) <-- buf.(i).value)) ] ] ]
            ; when_ (is_token pid_ack &: pid_ok &: awaiting_ack.value)
                [ awaiting_ack <-- gnd
                ; if_ ack_ep1.value [ ofull <-- gnd; in_toggle <-- ~:(in_toggle.value) ]
                    [ switch ctrl.value
                        [ c_data_in, [ ptr <-- ptr.value +: uresize sent_len.value 6; ep0_toggle <-- ~:(ep0_toggle.value)
                                     ; when_ ((sent_len.value <>:. 8) |: ((ptr.value +: uresize sent_len.value 6 ==: total.value) &: ~:(zlp.value)))
                                         [ ctrl <-- c_status_out ]
                                     ; when_ ((ptr.value +: uresize sent_len.value 6 ==: total.value) &: zlp.value &: (sent_len.value ==:. 8)) [ zlp <-- gnd ] ]
                        ; c_status_in, [ ctrl <-- c_idle; when_ addr_pending.value [ addr <-- pend_addr.value; addr_pending <-- gnd ] ] ] ] ] ] ]
    ; (* response timing: pkt_end fires at the first SE0 sample, about ten cycles before the host's
         EOP ends; USB wants at least two bit times (8 cycles) of gap after that, so wait 20 *)
      when_ resp_pending.value
        [ resp_delay <-- resp_delay.value +:. 1
        ; when_ (resp_delay.value ==:. 20) [ resp_pending <-- gnd; tx_start <-- vdd; tx_active <-- vdd; tx_idx <--. 0; tx_crc <--. 0xFFFF ] ]
    ; when_ (tx_active.value &: tx_ack)
        [ tx_idx <-- tx_idx.value +:. 1; when_ idx_is_data [ tx_crc <-- crc16_byte tx_crc.value src_byte ] ]
    ; when_ (tx_active.value &: ~:tx_busy &: ~:(tx_start.value) &: (tx_idx.value <>:. 0)) [ tx_active <-- gnd ] ];
  tx_start.value, tx_data, tx_valid, addr.value, configured.value
