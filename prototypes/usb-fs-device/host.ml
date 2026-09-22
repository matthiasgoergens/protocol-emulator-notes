(* Bit-level USB full-speed host model, independent of the RTL: encodes packets to line samples
   (4 per bit) with sync, bit stuffing, NRZI and EOP, and decodes the device's line back to bytes.
   CRC constants were checked against known packet bytes (SETUP addr 0: 2D 00 10; the
   GET_DESCRIPTOR data packet C3 80 06 00 01 00 00 40 00 DD 94). *)

type line = J | K | SE0

let crc5 bits = List.fold_left (fun c b -> if (c land 1) lxor b = 1 then (c lsr 1) lxor 0x14 else c lsr 1) 0x1F bits
let crc16 bits = List.fold_left (fun c b -> if (c land 1) lxor b = 1 then (c lsr 1) lxor 0xA001 else c lsr 1) 0xFFFF bits
let bits_of_byte x = List.init 8 (fun i -> (x lsr i) land 1)
let bits_of_bytes bs = List.concat_map bits_of_byte bs

let token pid ~addr ~ep =
  let f = addr lor (ep lsl 7) in
  let c = (lnot (crc5 (List.init 11 (fun i -> (f lsr i) land 1)))) land 0x1F in
  [ pid; f land 0xFF; (f lsr 8) lor (c lsl 3) ]

let data_packet pid payload =
  let c = (lnot (crc16 (bits_of_bytes payload))) land 0xFFFF in
  pid :: payload @ [ c land 0xFF; c lsr 8 ]

let handshake pid = [ pid ]

(* bytes -> line states per bit, including sync (0x80 LSB first) and EOP *)
let encode bytes =
  let bits = bits_of_bytes (0x80 :: bytes) in
  let out = ref [] and cur = ref J and ones = ref 0 in
  let emit b =
    (if b = 1 then incr ones else ones := 0);
    (if b = 0 then cur := (match !cur with J -> K | K -> J | SE0 -> J));
    out := !cur :: !out;
    if !ones = 6 then begin ones := 0; cur := (match !cur with J -> K | _ -> J); out := !cur :: !out end in
  List.iter emit bits;
  List.rev !out @ [ SE0; SE0; J ]

let samples_per_bit = 4
let to_samples states = List.concat_map (fun s -> List.init samples_per_bit (fun _ -> s)) states

(* decode a list of (cycle, line) samples produced by the device into bytes, given the index of
   the first K sample; samples mid-bit thereafter *)
let decode (samples : line array) start =
  let n = Array.length samples in
  let at i = if i < n then samples.(i) else J in
  let bits = ref [] and last = ref J and i = ref (start + samples_per_bit / 2) and fin = ref false in
  while not !fin do
    (match at !i with
     | SE0 -> fin := true
     | s -> bits := (if s = !last then 1 else 0) :: !bits; last := s);
    i := !i + samples_per_bit;
    if !i >= n + samples_per_bit then fin := true
  done;
  let bits = List.rev !bits in
  (* strip sync: leading zeros then a one *)
  let rec strip = function 0 :: r -> strip r | 1 :: r -> Some r | _ -> None in
  match strip bits with
  | None -> None
  | Some rest ->
    (* unstuff *)
    let out = ref [] and ones = ref 0 and skip = ref false and bad = ref false in
    List.iter (fun b ->
      if !skip then (skip := false; if b = 1 then bad := true; ones := 0)
      else begin out := b :: !out; if b = 1 then incr ones else ones := 0; if !ones = 6 then (skip := true; ones := 0) end) rest;
    let bits = List.rev !out in
    let nbytes = List.length bits / 8 in
    let bytes = List.init nbytes (fun k -> List.fold_left (fun acc i -> acc lor (List.nth bits (8 * k + i) lsl i)) 0 (List.init 8 Fun.id)) in
    if !bad then None else Some bytes
