(* IEC 60958 framing as a reference encoder: what a correct transmitter puts on the line.

   This is the host-side, executable reading of the standard that the chip's transmitter is
   compared against, UI for UI, and that the receive tests use as a foreign source. The decoders
   (oracle.ml, and sigrok's spdif decoder) are written separately and share nothing with it.

   Sources (public; copies of the text under /var/tmp/spdif/refs, see README):
   - Subframe of 32 time slots: 0..3 preamble, 4..27 audio (24-bit: LSB in slot 4; 20-bit: LSB
     in slot 8, slots 4..7 auxiliary), 28 validity, 29 user, 30 channel status, 31 parity, such
     that slots 4..31 carry an even number of ones. Frames of two subframes; preamble X (here "M")
     starts subframe 1, Z ("B") replaces it once every 192 frames, Y ("W") starts subframe 2.
     Biphase mark on slots 4..31: every symbol starts with a transition, a 1 has a second one in
     the middle. Preambles, as eight states after a preceding state 0: X 11100010, Y 11100100,
     Z 11101000. AES3-1992 (r1997) sections 2.2, 2.3, 2.4; IEC 60958-1 has the same frame.
   - Consumer channel status, mode 0: IEC 60958-3:2006 section 5.2 (the public preview pages):
     bit 0 = 0 consumer; bit 1 = 0 linear PCM; bit 2 = Cp, 1 = no copyright asserted (copy
     permitted); bits 3..5 = 000, no pre-emphasis; bits 6..7 = 00, mode 0; bits 8..15 category
     code, bit 8 = LSB; bits 16..19 source number; bits 20..23 channel number (1000 = left, 0100 =
     right); bits 24..27 sampling frequency (0000 = 44.1 kHz, 0100 = 48 kHz, 1100 = 32 kHz);
     bits 28..29 clock accuracy (00 = level II); bit 32 = 0 (maximum word length 20 bits);
     bits 33..35 = 100 (16 bits when the maximum is 20); bits 36..39 original sampling frequency
     (0000 = not indicated).
   - Category code of a CD player (IEC 60908): "1000000L", i.e. byte value 0x01 with L in bit 15.
     The value is the ALSA header's IEC958_AES1_CON_IEC908_CD (/usr/include/alsa/asoundef.h:80),
     which agrees with the laser-optical group "100" as I remember it.
     FROM MEMORY, NOT CHECKED AGAINST THE STANDARD'S TEXT (the preview pages stop before
     section 5.3 and the annexes): that for the laser-optical group the L bit has the reversed
     sense, L = 1 meaning "original / commercially released" and L = 0 "first generation or
     higher copy". ALSA only says "this bit depends on the category code". *)

type preamble = B | M | W

let preamble_name = function B -> "B" | M -> "M" | W -> "W"

(* eight states after a preceding state 0 (AES3 2.4); after a 1, the complement *)
let preamble_states = function B -> [| 1; 1; 1; 0; 1; 0; 0; 0 |] | M -> [| 1; 1; 1; 0; 0; 0; 1; 0 |] | W -> [| 1; 1; 1; 0; 0; 1; 0; 0 |]

type rate = R44 | R48 | R32

let rate_hz = function R44 -> 44100. | R48 -> 48000. | R32 -> 32000.
let rate_name = function R44 -> "44.1 kHz" | R48 -> "48 kHz" | R32 -> "32 kHz"
let ui_ns rate = 1e9 /. (128. *. rate_hz rate)

(* ---- channel status ---- *)

type cs_params = {
  copy_permitted : bool;     (* Cp, bit 2 *)
  l_bit : int;               (* bit 15 *)
  category : int;            (* bits 8..14, bit 8 = LSB (bit 15 is L) *)
  rate : rate;
  word16 : bool;             (* bits 32..35 = 0,1,0,0: 16-bit words in a 20-bit field *)
}

let cd_params rate = { copy_permitted = true; l_bit = 1; category = 0x01; rate; word16 = true }

(* the 192 bits of one channel's channel-status block; channel 0 = left, 1 = right *)
let channel_status (p : cs_params) ~channel =
  let b = Array.make 192 0 in
  let set i v = b.(i) <- v land 1 in
  set 0 0; set 1 0; set 2 (if p.copy_permitted then 1 else 0);
  for i = 0 to 6 do set (8 + i) (p.category lsr i) done;
  set 15 p.l_bit;
  (* channel number: 1 = left (bit 20), 2 = right (bit 21) *)
  if channel = 0 then set 20 1 else set 21 1;
  (match p.rate with
   | R44 -> ()
   | R48 -> set 25 1
   | R32 -> set 24 1; set 25 1);
  if p.word16 then set 33 1;
  b

(* ---- subframes ---- *)

(* the data bits of a subframe as an int whose bit k is time slot k (k = 4..31) *)
type subframe = { pre : preamble; slots : int }

let parity_of x = let rec go x a = if x = 0 then a else go (x land (x - 1)) (a lxor 1) in go x 0

(* audio: a 24-bit two's-complement sample word placed in slots 4..27 (LSB in 4) *)
let make_subframe ?(v = 0) ?(u = 0) ~pre ~audio24 ~c () =
  let s = ((audio24 land 0xffffff) lsl 4) lor ((v land 1) lsl 28) lor ((u land 1) lsl 29) lor ((c land 1) lsl 30) in
  let p = parity_of (s lsr 4) in
  { pre; slots = s lor (p lsl 31) }

let audio24_of_16 s16 = (s16 land 0xffff) lsl 8
let audio24 sf = (sf.slots lsr 4) land 0xffffff
let sign24 x = if x land 0x800000 <> 0 then x - 0x1000000 else x
let sample16 sf = let a = sign24 (audio24 sf) in a asr 8
let slot sf k = (sf.slots lsr k) land 1
let parity_ok sf = parity_of (sf.slots lsr 4) = 0

(* frames 0..n-1 of a stereo stream; [samples i] = (left, right) 24-bit words of frame i;
   [frame0] is the frame index within the block of the first frame *)
let stream ?(frame0 = 0) ?(v = fun _ _ -> 0) ?(u = fun _ _ -> 0) ~cs:(csl, csr) ~samples n =
  List.concat (List.init n (fun i ->
      let f = (frame0 + i) mod 192 in
      let l, r = samples i in
      [ make_subframe ~pre:(if f = 0 then B else M) ~audio24:l ~c:csl.(f) ~v:(v i 0) ~u:(u i 0) ();
        make_subframe ~pre:W ~audio24:r ~c:csr.(f) ~v:(v i 1) ~u:(u i 1) () ]))

(* ---- line coding ---- *)

(* UI levels (64 per subframe), continuing from the previous level [prev] *)
let ui_levels ?(prev = 0) (sfs : subframe list) =
  let out = Buffer.create 4096 in
  let lv = ref prev in
  let put x = lv := x; Buffer.add_char out (if x = 1 then '1' else '0') in
  List.iter (fun sf ->
      let st = preamble_states sf.pre in
      let inv = !lv in   (* after a 1 the complement *)
      Array.iter (fun s -> put (s lxor inv)) st;
      for k = 4 to 31 do
        put (1 - !lv);
        if slot sf k = 1 then put (1 - !lv) else put !lv
      done) sfs;
  Array.init (Buffer.length out) (fun i -> if Buffer.nth out i = '1' then 1 else 0)

(* transitions: t.(i) = 1 if UI i starts with a change of level (relative to [prev]) *)
let transitions ?(prev = 0) levels =
  Array.mapi (fun i x -> if x <> (if i = 0 then prev else levels.(i - 1)) then 1 else 0) levels

let levels_of_transitions ?(prev = 0) t =
  let lv = ref prev in
  Array.map (fun x -> lv := !lv lxor x; !lv) t

(* the transition bytes of the preambles, MSB first in time *)
let pre_byte p =
  let st = preamble_states p in
  let t = transitions ~prev:0 st in
  Array.fold_left (fun a x -> (a lsl 1) lor x) 0 t
