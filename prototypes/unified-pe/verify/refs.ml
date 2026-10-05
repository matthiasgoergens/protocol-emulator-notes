(* Independent references for the configuration library. None of these uses the PE model or
   its encoding; each is the textbook form of the computation. *)

(* ---- CRCs: the bit-serial textbook algorithms, catalogue parameters (reveng CRC catalogue) ---- *)
type crc = { name : string; width : int; poly : int; init : int; refin : bool; refout : bool; xorout : int; check : int }

let catalogue =
  [ { name = "CRC-16/XMODEM"; width = 16; poly = 0x1021; init = 0; refin = false; refout = false; xorout = 0; check = 0x31c3 };
    { name = "CRC-16/IBM-3740"; width = 16; poly = 0x1021; init = 0xffff; refin = false; refout = false; xorout = 0; check = 0x29b1 };
    { name = "CRC-16/KERMIT"; width = 16; poly = 0x1021; init = 0; refin = true; refout = true; xorout = 0; check = 0x2189 };
    { name = "CRC-16/USB"; width = 16; poly = 0x8005; init = 0xffff; refin = true; refout = true; xorout = 0xffff; check = 0xb4c8 };
    { name = "CRC-32/ISO-HDLC"; width = 32; poly = 0x04c11db7; init = 0xffffffff; refin = true; refout = true; xorout = 0xffffffff; check = 0xcbf43926 };
    { name = "CRC-32/BZIP2"; width = 32; poly = 0x04c11db7; init = 0xffffffff; refin = false; refout = false; xorout = 0xffffffff; check = 0xfc891918 };
    { name = "CRC-32/MPEG-2"; width = 32; poly = 0x04c11db7; init = 0xffffffff; refin = false; refout = false; xorout = 0; check = 0x0376e6e7 } ]

let reflect v n =
  let r = ref 0 in
  for i = 0 to n - 1 do if (v lsr i) land 1 = 1 then r := !r lor (1 lsl (n - 1 - i)) done;
  !r

(* reflected CRCs use the right-shifting algorithm with the reflected polynomial; the others
   the left-shifting one: two different textbook loops, neither shaped like the PE's *)
let crc c (msg : string) =
  let mask = (1 lsl c.width) - 1 in
  let r =
    if c.refin then begin
      let rp = reflect c.poly c.width in
      let r = ref (reflect c.init c.width) in
      String.iter
        (fun ch ->
          r := !r lxor Char.code ch;
          for _ = 1 to 8 do r := if !r land 1 = 1 then (!r lsr 1) lxor rp else !r lsr 1 done)
        msg;
      if c.refout then !r else reflect !r c.width
    end
    else begin
      let r = ref c.init in
      String.iter
        (fun ch ->
          r := !r lxor (Char.code ch lsl (c.width - 8));
          for _ = 1 to 8 do
            r := if (!r lsr (c.width - 1)) land 1 = 1 then ((!r lsl 1) lxor c.poly) land mask else (!r lsl 1) land mask
          done)
        msg;
      if c.refout then reflect !r c.width else !r
    end
  in
  (r lxor c.xorout) land mask

(* ---- GPS C/A code (IS-GPS-200, G1 = 1 + x^3 + x^10, G2 = 1 + x^2 + x^3 + x^6 + x^8 + x^9 + x^10,
   output G1[10] xor G2[a] xor G2[b]) ---- *)
let ca_taps = [| (2, 6); (3, 7); (4, 8); (5, 9); (1, 9); (2, 10); (1, 8); (2, 9); (3, 10) |]

let ca_code prn =
  let a, b = ca_taps.(prn - 1) in
  let g1 = Array.make 11 1 and g2 = Array.make 11 1 in
  Array.init 1023 (fun _ ->
      let chip = g1.(10) lxor g2.(a) lxor g2.(b) in
      let f1 = g1.(3) lxor g1.(10) in
      let f2 = g2.(2) lxor g2.(3) lxor g2.(6) lxor g2.(8) lxor g2.(9) lxor g2.(10) in
      for i = 10 downto 2 do g1.(i) <- g1.(i - 1); g2.(i) <- g2.(i - 1) done;
      g1.(1) <- f1;
      g2.(1) <- f2;
      chip)

(* the first 10 chips as the octal number the ICD tabulates (PRN 1: 1440, 2: 1620, 3: 1710) *)
let first10_octal code =
  let v = ref 0 in
  for i = 0 to 9 do v := (!v lsl 1) lor code.(i) done;
  int_of_string (Printf.sprintf "%o" !v)

(* ---- filters ---- *)
let convolve h x n = (* y[n] = sum_k h[k] x[n-k], x zero before 0 *)
  let s = ref 0 in
  Array.iteri (fun k hk -> if n - k >= 0 && n - k < Array.length x then s := !s + (hk * x.(n - k))) h;
  !s

let boxcar r = Array.make r 1

let poly_mul a b =
  let c = Array.make (Array.length a + Array.length b - 1) 0 in
  Array.iteri (fun i ai -> Array.iteri (fun j bj -> c.(i + j) <- c.(i + j) + (ai * bj)) b) a;
  c

let clamp16 v = max (-0x8000) (min 0x7fff v)
let to_signed v = let v = v land 0xffff in if v >= 0x8000 then v - 0x10000 else v
