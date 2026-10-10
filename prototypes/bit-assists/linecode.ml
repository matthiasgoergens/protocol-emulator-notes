(* The line coder: NRZI and Manchester, encode and decode, with an optional inversion. One bit
   stream in, one symbol stream out (encode), or the reverse (decode). A symbol is a line level for
   one symbol time: one bit time in NRZI and pass modes, half a bit time in Manchester.

   - Pass: the symbol is the bit (NRZ: UART, SPI, CAN, I2C data).
   - NRZI: a bit equal to [toggle_on] changes the line level, the other bit keeps it. USB
     (full and low speed) toggles on 0; 100BASE-FX and some magnetic and optical codes on 1.
   - Manchester: two symbols per bit, the complement of the bit and then the bit, so a 1 is low
     then high (IEEE 802.3: 10BASE-T, and MIL-STD-1553, DALI with [invert] as needed).
   [invert] complements every symbol on encode and every symbol before decoding, which turns
   802.3 Manchester into G. E. Thomas's convention and sets NRZI's level at the start of a frame.

   Encoder: on every symbol tick it emits one symbol; it takes a new bit at every tick in pass and
   NRZI modes and at every second tick in Manchester ([need_bit]). [restart] (the start of a frame)
   puts the NRZI level at 0 (the idle level, before inversion) and Manchester at a bit boundary.
   Decoder: one symbol per [valid]; NRZI and pass give one bit per symbol, Manchester one bit per
   two symbols, the second half's level, with [err] when the two halves are equal (a code
   violation). The NRZI reference is the last symbol, whatever the mode. The decoder's NRZI
   reference level and Manchester phase start at 0 after a clear;
   it has no restart, because a receiver decodes continuously across the gap before a frame (USB:
   the idle J before the sync is the reference for its first symbol).

   The model and the RTL are written separately; check.ml runs them in lockstep and against
   independent encoders (refs/). *)

type mode = Pass | Nrzi | Manchester

let mode_code = function Pass -> 0 | Nrzi -> 1 | Manchester -> 2
let mode_of_code = function 1 -> Nrzi | 2 -> Manchester | _ -> Pass

type cfg = { mode : mode; invert : bool; toggle_on : int }

let pass = { mode = Pass; invert = false; toggle_on = 0 }
let usb = { mode = Nrzi; invert = false; toggle_on = 0 }
let ieee_manchester = { mode = Manchester; invert = false; toggle_on = 0 }

let inv c s = if c.invert then 1 - s else s

(* ---- model: encoder ---- *)

type enc = { mutable level : int; mutable half : int; mutable cur : int }

let enc_init () = { level = 0; half = 0; cur = 0 }
let enc_restart e = e.level <- 0; e.half <- 0; e.cur <- 0
let need_bit c e = c.mode <> Manchester || e.half = 0

(* one symbol tick; [bit] is used only when [need_bit] *)
let enc_tick c e ~bit =
  let s =
    match c.mode with
    | Pass -> bit
    | Nrzi -> if bit = c.toggle_on then e.level <- 1 - e.level; e.level
    | Manchester ->
      if e.half = 0 then (e.cur <- bit; e.half <- 1; 1 - bit) else (e.half <- 0; e.cur)
  in
  inv c s

(* ---- model: decoder ---- *)

type dec = { mutable prev : int; mutable dhalf : int; mutable first : int }

let dec_init () = { prev = 0; dhalf = 0; first = 0 }

(* one symbol: (bit if one completes, violation) *)
let dec_step c d sym =
  let s = inv c sym in
  (* the NRZI reference is the last symbol seen, in every mode, so that a change of mode between
     frames starts from the line's real level *)
  let prev = d.prev in
  d.prev <- s;
  match c.mode with
  | Pass -> (Some s, false)
  | Nrzi -> (Some (if s <> prev then c.toggle_on else 1 - c.toggle_on), false)
  | Manchester ->
    if d.dhalf = 0 then (d.first <- s; d.dhalf <- 1; (None, false))
    else (d.dhalf <- 0; (Some s, d.first = s))

(* whole streams, for the tests *)
let encode_list c bits =
  let e = enc_init () in
  List.concat_map (fun b -> if c.mode = Manchester then (let s0 = enc_tick c e ~bit:b in [ s0; enc_tick c e ~bit:0 ]) else [ enc_tick c e ~bit:b ]) bits

let decode_list c syms =
  let d = dec_init () and out = ref [] and errs = ref 0 in
  List.iter (fun s -> match dec_step c d s with Some b, e -> out := b :: !out; if e then incr errs | None, _ -> ()) syms;
  (List.rev !out, !errs)

(* ---- RTL ---- *)
open Hardcaml
open Signal

type cfg_signals = { s_mode : Signal.t; (* 2 bits *) s_invert : Signal.t; s_toggle_on : Signal.t }

let cfg_const c = { s_mode = of_int ~width:2 (mode_code c.mode); s_invert = of_bool c.invert; s_toggle_on = of_int ~width:1 c.toggle_on }

let bug = ref ""
let is b = !bug = b

let bugs =
  [ "nrzi_toggle_polarity", "NRZI toggles on the other bit value";
    "manchester_halves_swapped", "Manchester sends the bit first, then its complement";
    "manchester_need_every_tick", "Manchester takes a new bit at every symbol";
    "invert_ignored_enc", "the encoder ignores invert";
    "nrzi_dec_reference_stuck", "the NRZI decoder never updates its reference level";
    "manchester_no_violation", "the Manchester decoder reports no code violations";
    "manchester_dec_first_half", "the Manchester decoder outputs the first half's level";
    "enc_restart_ignored", "restart does not reset the encoder (NRZI level, Manchester phase)" ]

(* Encoder: on [tick], emits a symbol into the registered [line] (visible from the next clock).
   [need_bit] is combinational: a new bit is taken at this tick. *)
type enc_out = { need_bit : Signal.t; line : Signal.t }

let encoder ~clock ~clear ~restart ~(cfg : cfg_signals) ~tick ~bit =
  let spec = Reg_spec.create ~clock ~clear () in
  let level = wire 1 and half = wire 1 and cur = wire 1 in
  let is_nrzi = cfg.s_mode ==:. 1 and is_man = cfg.s_mode ==:. 2 in
  let need = if is "manchester_need_every_tick" then vdd else ~:is_man |: ~:half in
  let tog = if is "nrzi_toggle_polarity" then ~:(cfg.s_toggle_on) else cfg.s_toggle_on in
  let lvl_next = level ^: (bit ==: tog) in
  let man_sym =
    if is "manchester_halves_swapped" then mux2 half (~:cur) bit else mux2 half cur (~:bit) in
  let sym = mux2 is_man man_sym (mux2 is_nrzi lvl_next bit) in
  let sym = if is "invert_ignored_enc" then sym else sym ^: cfg.s_invert in
  let line = reg spec ~enable:tick sym in
  let clr = if is "enc_restart_ignored" then gnd else restart in
  level <== reg spec (mux2 clr gnd (mux2 (tick &: is_nrzi) lvl_next level));
  half <== reg spec (mux2 clr gnd (mux2 (tick &: is_man) (if is "manchester_need_every_tick" then gnd else ~:half) half));
  cur <== reg spec (mux2 clr gnd (mux2 (tick &: is_man &: ~:half) bit cur));
  { need_bit = need; line }

(* Decoder: with [valid], one symbol [sym]; [out_valid], [out_bit], [err] are combinational. *)
type dec_out = { out_valid : Signal.t; out_bit : Signal.t; err : Signal.t }

let decoder ~clock ~clear ~(cfg : cfg_signals) ~valid ~sym =
  let spec = Reg_spec.create ~clock ~clear () in
  let s = sym ^: cfg.s_invert in
  let is_nrzi = cfg.s_mode ==:. 1 and is_man = cfg.s_mode ==:. 2 in
  let prev = wire 1 and dhalf = wire 1 and first = wire 1 in
  let nrzi_bit = mux2 (s <>: prev) cfg.s_toggle_on (~:(cfg.s_toggle_on)) in
  let man_bit = if is "manchester_dec_first_half" then first else s in
  let out_bit = mux2 is_man man_bit (mux2 is_nrzi nrzi_bit s) in
  let out_valid = valid &: (~:is_man |: dhalf) in
  let err = valid &: is_man &: dhalf &: (if is "manchester_no_violation" then gnd else first ==: s) in
  prev <== reg spec (mux2 (valid &: (if is "nrzi_dec_reference_stuck" then gnd else vdd)) s prev);
  dhalf <== reg spec (mux2 (valid &: is_man) (~:dhalf) dhalf);
  first <== reg spec (mux2 (valid &: is_man &: ~:dhalf) s first);
  { out_valid; out_bit; err }
