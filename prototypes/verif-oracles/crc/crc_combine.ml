(* The CRC of a concatenation from the CRCs of its parts, re-derived from first principles.

   Idea credited to Edward Kmett, "Parallel and Incremental CRCs" (comonad.com, 2013): a CRC is a
   monoid homomorphism once each value is paired with its length. The derivation and the code
   below are ours (the post's code carries no stated licence, so none of it is used).

   Model. Polynomials over GF(2) are ints, bit i the coefficient of x^i. P is the generator of
   degree w; [poly] holds P without its x^w term, as the CRC catalogue writes it. Feed the message
   bits m_1 .. m_n (in transmission order: MSB first, or LSB first for a reflected CRC) into the
   direct (non-augmented) shift register starting from state s. Each bit does
       r <- r * x + m_i * x^w   (mod P)
   so after n bits
       R(s, m) = s * x^n + M(x) * x^w   (mod P),   M(x) = sum m_i x^(n-i).
   R is affine in s and linear in m, hence for a message a followed by b (|b| bits):
       R(s, a ++ b) = R(R(s, a), b) = R(s, a) * x^|b| + R(0, b)               (1)
   and R(0, b) = R(s, b) + s * x^|b|, so with s = init:
       R(init, a ++ b) = (R(init, a) + init) * x^|b| + R(init, b)              (2)
   The catalogue CRC is out(R(init, m)) with out r = reflect_w(r) (if refout) xor xorout, an
   invertible map, so with in_ = out^-1:
       crc(a ++ b) = out( (in_(crc a) + init) * x^(8|b|) + in_(crc b) )        (3)
   The multiplication by x^(8|b|) mod P is computed as one w-bit carry-less multiply by the
   constant x^(8|b|) mod P, itself found by square-and-multiply in O(log |b|) multiplies. That
   is what makes the combine cheap: no pass over b's bytes, whatever its length.

   zlib's crc32_combine is (3) specialised to CRC-32/ISO-HDLC, where init = xorout = all ones and
   the init term cancels; the planted control "zlib's formula on every CRC" below shows (3) is needed for the
   catalogue CRCs whose init differs from xorout (IBM-3740, MPEG-2). *)

type crc = Refs.crc

let mask w = (1 lsl w) - 1

let reflect = Refs.reflect

(* a * b mod P, a and b of degree < w: Horner over b's bits from the top *)
let mulmod ~w ~poly a b =
  let top = 1 lsl (w - 1) and m = mask w in
  let r = ref 0 in
  for i = w - 1 downto 0 do
    r := if !r land top <> 0 then ((!r lsl 1) land m) lxor poly else (!r lsl 1) land m;
    if (b lsr i) land 1 = 1 then r := !r lxor a
  done;
  !r

(* x^n mod P for n >= 0, by square-and-multiply; x mod P = 2 since w >= 2 *)
let xpow ~w ~poly n =
  assert (n >= 0 && w >= 2);
  let rec go acc base n =
    if n = 0 then acc
    else go (if n land 1 = 1 then mulmod ~w ~poly acc base else acc) (mulmod ~w ~poly base base) (n lsr 1) in
  go 1 2 n

(* the same, one bit at a time: the slow definition xpow is tested against *)
let xpow_slow ~w ~poly n =
  let r = ref 1 in
  for _ = 1 to n do r := mulmod ~w ~poly !r 2 done;
  !r

(* r * x^nbits mod P *)
let shift_bits (c : crc) r nbits = mulmod ~w:c.width ~poly:c.poly r (xpow ~w:c.width ~poly:c.poly nbits)

let out (c : crc) r = (if c.refout then reflect r c.width else r) lxor c.xorout
let in_ (c : crc) v = let v = v lxor c.xorout in if c.refout then reflect v c.width else v

(* (3): the CRC of a ++ b, given crc a, crc b and the length of b in bytes *)
let combine (c : crc) ~crc_a ~crc_b ~len_b =
  out c (shift_bits c (in_ c crc_a lxor c.init) (8 * len_b) lxor in_ c crc_b)

(* (1) on raw registers: a part run from init, the other from 0 (the two-segment split) *)
let combine_raw (c : crc) ~reg_a ~reg_b0 ~len_b = out c (shift_bits c reg_a (8 * len_b) lxor reg_b0)

(* Planted faults: each must be caught by the tests in crc_oracle.ml. *)
type fault = Ok_ | Bits_not_bytes | No_init_term | No_reflection | Zlib_formula

let combine_faulty fault (c : crc) ~crc_a ~crc_b ~len_b =
  match fault with
  | Ok_ -> combine c ~crc_a ~crc_b ~len_b
  | Bits_not_bytes -> out c (shift_bits c (in_ c crc_a lxor c.init) len_b lxor in_ c crc_b)
  | No_init_term -> out c (shift_bits c (in_ c crc_a) (8 * len_b) lxor in_ c crc_b)
  | No_reflection ->
    let in_ v = v lxor c.xorout and out r = r lxor c.xorout in
    out (shift_bits c (in_ crc_a lxor c.init) (8 * len_b) lxor in_ crc_b)
  | Zlib_formula ->
    (* zlib's crc32_combine generalised: shift the first CRC as it stands, xor the second;
       init and xorout are ignored, which is right exactly when init = xorout *)
    let rf v = if c.refout then reflect v c.width else v in
    rf (shift_bits c (rf crc_a) (8 * len_b)) lxor crc_b

let fault_name = function
  | Ok_ -> "none" | Bits_not_bytes -> "shift by x^|b| (bits counted as bytes)"
  | No_init_term -> "init term dropped" | No_reflection -> "reflection ignored"
  | Zlib_formula -> "zlib's formula on every CRC"
