(* A generic bit-serial CRC unit: any width up to 32, any polynomial, init, xorout, and either bit
   order, all set at run time. One bit per enabled clock.

   The host precomputes the configuration from a catalogue entry (width, poly, init, refin, refout,
   xorout, as in the Rocksoft/reveng model; refin = refout is assumed, which covers every CRC the
   chip's protocols use):
   - reflected (LSB-first protocols: Ethernet, USB, Modbus, 1-Wire): the register shifts right and
     the polynomial is given bit-reversed within [width];
   - normal (MSB-first protocols: CAN, SMBus, HDLC variants): the register shifts left within the
     [mask] of the width and the polynomial is given as is.
   [check] is true when the raw register equals [residue]: the receive check "data followed by its
   own CRC leaves a constant", which is how Ethernet (0xDEBB20E3), USB data (0xB001) and CAN (0)
   check a frame without knowing where the CRC started. [value] is register xor xorout, the CRC to
   send.

   Serves: CRC-32 (Ethernet FCS), CRC-16/USB and CRC-5/USB (USB), CRC-15/CAN, CRC-8/SMBUS (SMBus
   PEC), CRC-8/MAXIM (1-Wire), CRC-16/MODBUS, CRC-16/KERMIT (X.25-style framing), and others of
   the same shape. *)

type cfg = { width : int; poly : int; init : int; reflected : bool; xorout : int; residue : int }

let mask_of w = if w >= 32 then 0xFFFFFFFF else (1 lsl w) - 1
let reverse ~width v = let r = ref 0 in for i = 0 to width - 1 do if (v lsr i) land 1 = 1 then r := !r lor (1 lsl (width - 1 - i)) done; !r

(* host-side preparation from a catalogue entry *)
type catalogue = { name : string; w : int; p : int; i : int; refl : bool; xo : int; check_value : int; residue_value : int }

let cfg_of (c : catalogue) =
  { width = c.w; poly = (if c.refl then reverse ~width:c.w c.p else c.p); init = c.i; reflected = c.refl;
    xorout = c.xo; residue = c.residue_value }

(* Catalogue entries (parameters, check value for "123456789" and residue) as I know them from
   the reveng CRC catalogue; the check values are what the model below is tested against. *)
let catalogue = [
  { name = "CRC-32/ISO-HDLC (Ethernet)"; w = 32; p = 0x04C11DB7; i = 0xFFFFFFFF; refl = true; xo = 0xFFFFFFFF; check_value = 0xCBF43926; residue_value = 0xDEBB20E3 };
  { name = "CRC-16/USB"; w = 16; p = 0x8005; i = 0xFFFF; refl = true; xo = 0xFFFF; check_value = 0xB4C8; residue_value = 0xB001 };
  { name = "CRC-5/USB"; w = 5; p = 0x05; i = 0x1F; refl = true; xo = 0x1F; check_value = 0x19; residue_value = 0x06 };
  { name = "CRC-15/CAN"; w = 15; p = 0x4599; i = 0; refl = false; xo = 0; check_value = 0x059E; residue_value = 0 };
  { name = "CRC-8/SMBUS"; w = 8; p = 0x07; i = 0; refl = false; xo = 0; check_value = 0xF4; residue_value = 0 };
  { name = "CRC-8/MAXIM-DOW (1-Wire)"; w = 8; p = 0x31; i = 0; refl = true; xo = 0; check_value = 0xA1; residue_value = 0 };
  { name = "CRC-16/MODBUS"; w = 16; p = 0x8005; i = 0xFFFF; refl = true; xo = 0; check_value = 0x4B37; residue_value = 0 };
  { name = "CRC-16/KERMIT"; w = 16; p = 0x1021; i = 0; refl = true; xo = 0; check_value = 0x2189; residue_value = 0 };
]

(* ---- model ---- *)

let step (c : cfg) crc bit =
  let mask = mask_of c.width in
  if c.reflected then begin
    let fb = (crc lxor bit) land 1 in
    (crc lsr 1) lxor (if fb = 1 then c.poly else 0)
  end else begin
    let top = (crc lsr (c.width - 1)) land 1 in
    let fb = top lxor bit in
    ((crc lsl 1) land mask) lxor (if fb = 1 then c.poly else 0)
  end

(* the wire order of a byte's bits: LSB first for reflected CRCs, MSB first otherwise *)
let bits_of_byte (c : cfg) b = List.init 8 (fun i -> if c.reflected then (b lsr i) land 1 else (b lsr (7 - i)) land 1)
let run c bits = List.fold_left (step c) c.init bits
let crc_of_bytes c bytes = (run c (List.concat_map (bits_of_byte c) bytes)) lxor c.xorout

(* the CRC as it goes on the wire, as bits, after the data: for reflected CRCs LSB of the value
   first, for normal ones MSB first *)
let crc_bits c v = List.init c.width (fun i -> if c.reflected then (v lsr i) land 1 else (v lsr (c.width - 1 - i)) land 1)

(* ---- RTL ---- *)
open Hardcaml
open Signal

type cfg_signals = { s_poly : Signal.t; s_init : Signal.t; s_mask : Signal.t; s_refl : Signal.t; s_xorout : Signal.t; s_residue : Signal.t }

let create ~clock ~clear ~(cfg : cfg_signals) ~start ~bit ~valid =
  let spec = Reg_spec.create ~clock ~clear () in
  let topmask = cfg.s_mask ^: srl cfg.s_mask 1 in
  let crc = reg_fb spec ~width:32 ~f:(fun crc ->
      let right = srl crc 1 ^: mux2 (lsb crc ^: bit) cfg.s_poly (zero 32) in
      let top = (crc &: topmask) <>:. 0 in
      let left = (sll crc 1 &: cfg.s_mask) ^: mux2 (top ^: bit) cfg.s_poly (zero 32) in
      mux2 start cfg.s_init (mux2 valid (mux2 cfg.s_refl right left) crc)) in
  crc, crc ^: cfg.s_xorout, crc ==: cfg.s_residue

let cfg_inputs () =
  { s_poly = input "poly" 32; s_init = input "init" 32; s_mask = input "mask" 32; s_refl = input "refl" 1;
    s_xorout = input "xorout" 32; s_residue = input "residue" 32 }

let circuit () =
  let clock = input "clock" 1 and clear = input "clear" 1 in
  let cfg = cfg_inputs () in
  let start = input "start" 1 and bit = input "bit" 1 and valid = input "valid" 1 in
  let raw, value, check = create ~clock ~clear ~cfg ~start ~bit ~valid in
  Circuit.create_exn ~name:"crc_unit" [ output "raw" raw; output "value" value; output "check" check ]

let set_cfg sim (c : cfg) =
  let i n v w = Cyclesim.in_port sim n := Bits.of_int ~width:w v in
  i "poly" c.poly 32; i "init" c.init 32; i "mask" (mask_of c.width) 32; i "refl" (if c.reflected then 1 else 0) 1;
  i "xorout" c.xorout 32; i "residue" c.residue 32
