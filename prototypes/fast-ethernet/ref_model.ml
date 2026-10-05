(* Reference model of 100BASE-X, written from the code tables rather than from the RTL, as lists
   of bits. The RTL in the other files is checked against this.

   - CRC-32: reflected 0xEDB88320, bit-serial, init and final complement 0xFFFFFFFF.
   - 4B/5B: 802.3 Table 24-1 / FDDI (checked against Wikipedia's table on 2026-09-25). Each
     5-bit code group is sent leftmost bit first as written in the table (ASSUMED: the FDDI
     convention; not checked against the 802.3 text, which was not available; it only matters
     for interoperating with a real partner). Each octet is sent low nibble first.
   - Stream: /J/K/ replaces the first preamble octet, then 6 x 0x55, SFD 0xD5, the frame and its
     FCS, then /T/R/, then /I/ (11111) until the next frame.
   - NRZI (FX): a 1 toggles the line. MLT-3 (TX): a 1 steps the line through 0, +1, 0, -1.
   - TX scrambler: x^11 + x^9 + 1, additive (keystream XOR), per ANSI TP-PMD. *)

let crc32 bytes =
  let crc = ref 0xFFFFFFFF in
  List.iter (fun b ->
      for i = 0 to 7 do
        let bit = (b lsr i) land 1 in
        let fb = (!crc land 1) lxor bit in
        crc := (!crc lsr 1) lxor (if fb = 1 then 0xEDB88320 else 0)
      done) bytes;
  (lnot !crc) land 0xFFFFFFFF

let with_fcs frame = let c = crc32 frame in frame @ List.init 4 (fun i -> (c lsr (8 * i)) land 0xFF)
let fcs_ok frame_with_fcs = List.length frame_with_fcs >= 5 &&
  (let n = List.length frame_with_fcs in
   let body = List.filteri (fun i _ -> i < n - 4) frame_with_fcs in
   with_fcs body = frame_with_fcs)

(* code groups as strings, leftmost first *)
let data_code = [| "11110"; "01001"; "10100"; "10101"; "01010"; "01011"; "01110"; "01111";
                   "10010"; "10011"; "10110"; "10111"; "11010"; "11011"; "11100"; "11101" |]
let sym_i = "11111" and sym_j = "11000" and sym_k = "10001" and sym_t = "01101" and sym_r = "00111"
let bits_of s = List.init (String.length s) (fun i -> if s.[i] = '1' then 1 else 0)

type sym = D of int | I | J | K | T | R | Bad

let code_of = function
  | D n -> data_code.(n) | I -> sym_i | J -> sym_j | K -> sym_k | T -> sym_t | R -> sym_r
  | Bad -> invalid_arg "code_of Bad"

let decode_code s =
  let rec find n = if n = 16 then None else if data_code.(n) = s then Some (D n) else find (n + 1) in
  match find 0 with
  | Some d -> d
  | None -> if s = sym_i then I else if s = sym_j then J else if s = sym_k then K
    else if s = sym_t then T else if s = sym_r then R else Bad

(* symbols for one frame (no FCS added here: pass the frame with its FCS) *)
let frame_symbols frame_with_fcs =
  let nibbles b = [ D (b land 0xF); D (b lsr 4) ] in
  [ J; K ] @ List.concat_map nibbles (List.init 6 (fun _ -> 0x55) @ [ 0xD5 ] @ frame_with_fcs) @ [ T; R ]

let symbols_to_bits syms = List.concat_map (fun s -> bits_of (code_of s)) syms

(* a stream: idles, frame, idles, frame, ... *)
let stream ?(gap = 12) frames =
  List.concat_map (fun f -> List.init gap (fun _ -> I) @ frame_symbols (with_fcs f)) frames
  @ List.init gap (fun _ -> I)

let nrzi_encode ?(init = 0) bits =
  let l = ref init in List.map (fun b -> l := !l lxor b; !l) bits
let nrzi_decode ?(init = 0) levels =
  let p = ref init in List.map (fun l -> let b = l lxor !p in p := l; b) levels

let mlt3_encode bits =
  let seq = [| 0; 1; 0; -1 |] and k = ref 0 in
  List.map (fun b -> if b = 1 then k := (!k + 1) land 3; seq.(!k)) bits
let mlt3_decode ?(init = 0) levels =
  let p = ref init in List.map (fun l -> let b = if l <> !p then 1 else 0 in p := l; b) levels

(* keystream of x^11 + x^9 + 1: s(n) = s(n-11) xor s(n-9) *)
let keystream ~seed n =
  let st = Array.init 11 (fun i -> (seed lsr i) land 1) in   (* st.(0) = s(n-1) ... st.(10) = s(n-11) *)
  List.init n (fun _ ->
      let b = st.(10) lxor st.(8) in
      Array.blit st 0 st 1 10; st.(0) <- b; b)
let scramble ~seed bits = List.map2 ( lxor ) bits (keystream ~seed (List.length bits))

(* Receiver: from a bit stream, find /J/K/ at any bit offset, then decode code groups until /T/R/
   or an invalid symbol; returns frames (with FCS) and whether each was delimited properly. *)
let decode_stream bits =
  let a = Array.of_list bits in
  let n = Array.length a in
  let group i = if i + 5 > n then None else Some (String.init 5 (fun k -> if a.(i + k) = 1 then '1' else '0')) in
  let frames = ref [] in
  let i = ref 0 in
  while !i + 10 <= n do
    if group !i = Some sym_j && group (!i + 5) = Some sym_k then begin
      let p = ref (!i + 10) and nib = ref [] and fin = ref false and ok = ref false in
      while not !fin do
        match group !p with
        | None -> fin := true
        | Some g -> (match decode_code g with
            | D d -> nib := d :: !nib; p := !p + 5
            | T -> (ok := (group (!p + 5) = Some sym_r)); fin := true
            | _ -> fin := true)
      done;
      let nibs = List.rev !nib in
      let rec bytes = function lo :: hi :: r -> (lo lor (hi lsl 4)) :: bytes r | _ -> [] in
      let by = bytes nibs in
      (* strip preamble + SFD *)
      let rec strip = function 0x55 :: r -> strip r | 0xD5 :: r -> Some r | _ -> None in
      (match strip by with
       | Some fr -> frames := (fr, !ok && List.length nibs mod 2 = 0) :: !frames
       | None -> frames := ([], false) :: !frames);
      i := !p
    end else incr i
  done;
  List.rev !frames

let random_frame ~rng len =
  (* destination broadcast, a fixed source, EtherType 0x88B5 (local experimental), random payload *)
  let hdr = [ 0xFF; 0xFF; 0xFF; 0xFF; 0xFF; 0xFF; 0x02; 0x00; 0x00; 0x00; 0x00; 0x01; 0x88; 0xB5 ] in
  hdr @ List.init (max 46 (len - 18)) (fun _ -> Random.State.int rng 256)

let self_test () =
  let r = Random.State.make [| 7 |] in
  let fs = List.init 20 (fun i -> random_frame ~rng:r (64 + 70 * i)) in
  let bits = symbols_to_bits (stream fs) in
  let got = decode_stream bits in
  assert (List.length got = List.length fs);
  List.iter2 (fun f (g, ok) -> assert ok; assert (g = with_fcs f); assert (fcs_ok g)) fs got;
  assert (nrzi_decode (nrzi_encode bits) = bits);
  assert (mlt3_decode (mlt3_encode bits) = bits);
  let ks = keystream ~seed:0x7FF 2047 in
  assert (scramble ~seed:0x7FF (scramble ~seed:0x7FF bits) = bits);
  (* maximal length: period 2047 *)
  let ks2 = keystream ~seed:0x7FF 4094 in
  assert (List.filteri (fun i _ -> i >= 2047) ks2 = ks);
  assert (crc32 (List.init 9 (fun i -> Char.code "123456789".[i])) = 0xCBF43926);
  (* 4B/5B: no more than 3 zeros in a row anywhere in a random data stream *)
  let s = String.concat "" (List.map string_of_int bits) in
  let rec max0 i run best = if i = String.length s then best
    else if s.[i] = '0' then max0 (i + 1) (run + 1) (max best (run + 1)) else max0 (i + 1) 0 best in
  max0 0 0 0
