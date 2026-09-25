(* A generic serial CRC checker, the one hardware assist the low-speed firmware needs.

   Protocol knowledge is configuration: polynomial, width, initial value, the residue a good
   frame leaves, bit order, and how many leading bits to skip. It serves USB (CRC5 0x05 and
   CRC16 0x8005, reflected, residues 0x0C and 0x800D), CAN (CRC15 0x4599, MSB first, no
   residue: the check value is 0), SMBus PEC and 1-Wire (CRC8), HDLC and SD (CRC16-CCITT,
   CRC7), and at width 32 Ethernet's FCS.

   Interface: four signals from the firmware (normally sequencer pins) and one back.
   - en: while low the register holds [init] and the skip counter holds [skip];
   - frame: strobes count only while it is high (the frame-delimiting strobes a bit layer sends
     at the end of a frame, with frame low, are then not data);
   - stb: on each rising edge of (stb and frame) while en is high, one bit is taken: the first
     [skip] are ignored, the rest are shifted into the register;
   - value: the bit, sampled at that edge;
   - ok: the register equals [check] (combinational from the register).

   Reflected (LSB-first) update, as USB sends bits: fb = crc[0] xor bit; crc = crc >> 1 xor
   (fb ? poly_reflected : 0). MSB-first update: fb = crc[w-1] xor bit; crc = (crc << 1 xor (fb ?
   poly : 0)) masked to w bits. The configuration is static here (inputs tied to constants); on
   the chip it would be a few configuration registers. *)
open Hardcaml
open Signal

type cfg = { width : int; poly : int; init : int; check : int; skip : int; msb_first : bool }

(* USB data packets: CRC16 over what follows the PID (the firmware arms the unit after the
   PID); the residue of a good packet is 0xB001 in the reflected register *)
let usb_crc16 = { width = 16; poly = 0xA001; init = 0xFFFF; check = 0xB001; skip = 0; msb_first = false }

let max_width = 16

let create ~cfg ~clock ~clear ~en ~frame ~stb ~value =
  let stb = stb &: frame in
  let spec = Reg_spec.create ~clock ~clear () in
  let w = max_width in
  let c x = of_int ~width:w x in
  let mask = c ((1 lsl cfg.width) - 1) in
  let crc = wire w and skip = wire 5 in
  let stb_prev = reg spec stb in
  let rise = stb &: ~:stb_prev in
  let fb_lsb = bit crc 0 ^: value in
  let next_lsb = srl crc 1 ^: mux2 fb_lsb (c cfg.poly) (zero w) in
  let fb_msb = mux (of_int ~width:5 (cfg.width - 1)) (bits_lsb crc) ^: value in
  let next_msb = (sll crc 1 ^: mux2 fb_msb (c cfg.poly) (zero w)) &: mask in
  let next = if cfg.msb_first then next_msb else next_lsb in
  let take = en &: rise &: (skip ==:. 0) in
  crc <== reg spec (mux2 en (mux2 take next crc) (c cfg.init));
  skip <== reg spec (mux2 en (mux2 (rise &: (skip <>:. 0)) (skip -:. 1) skip) (of_int ~width:5 cfg.skip));
  crc ==: c cfg.check

(* executable specification *)
module Model = struct
  type t = { cfg : cfg; mutable crc : int; mutable skip : int; mutable stb_prev : int }
  let create cfg = { cfg; crc = 0; skip = 0; stb_prev = 0 }
  let ok t = t.crc = t.cfg.check
  (* one clock with this clock's inputs (register semantics: ok reflects the state before) *)
  let step t ~en ~frame ~stb ~value =
    let stb = stb land frame in
    let rise = stb = 1 && t.stb_prev = 0 in
    let cfg = t.cfg in
    let mask = (1 lsl cfg.width) - 1 in
    let next =
      if cfg.msb_first then
        let fb = ((t.crc lsr (cfg.width - 1)) land 1) lxor value in
        ((t.crc lsl 1) lxor (if fb = 1 then cfg.poly else 0)) land mask
      else
        let fb = (t.crc land 1) lxor value in
        (t.crc lsr 1) lxor (if fb = 1 then cfg.poly else 0) in
    if en = 1 then begin
      if rise && t.skip = 0 then t.crc <- next;
      if rise && t.skip <> 0 then t.skip <- t.skip - 1
    end else begin t.crc <- cfg.init; t.skip <- cfg.skip end;
    t.stb_prev <- stb
end
