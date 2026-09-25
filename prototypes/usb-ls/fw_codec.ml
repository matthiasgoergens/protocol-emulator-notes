(* Device-side precomputation for the firmware: packets to line symbols, packed for the SHO
   pair instruction. Written separately from the host model (ls_host.ml) so that the two do not
   share mistakes.

   A symbol is two bits, bit 0 for D+ and bit 1 for D-: J = 2 (D- high), K = 1, SE0 = 0. Four
   symbols per byte, the first in bits 1:0. A reply is front-padded with J (at least one) to a
   multiple of four symbols; the line is idle J already, so padding only moves the SOP later.
   0xFF (four SE1s, never sent) terminates a reply in the FIFO. *)

let sym_j = 2 and sym_k = 1 and sym_se0 = 0
let terminator = 0xFF

let crc16 bytes =
  let c = ref 0xFFFF in
  List.iter (fun byte ->
    for i = 0 to 7 do
      let b = (byte lsr i) land 1 in
      c := if (!c land 1) lxor b = 1 then (!c lsr 1) lxor 0xA001 else !c lsr 1
    done) bytes;
  (lnot !c) land 0xFFFF

let crc5_11 v =
  let c = ref 0x1F in
  for i = 0 to 10 do
    let b = (v lsr i) land 1 in
    c := if (!c land 1) lxor b = 1 then (!c lsr 1) lxor 0x14 else !c lsr 1
  done;
  (lnot !c) land 0x1F

(* the two bytes after the PID of a token for (addr, ep) *)
let token_tail ~addr ~ep =
  let f = addr lor (ep lsl 7) in
  (f land 0xFF, (f lsr 8) lor (crc5_11 f lsl 3))

let data_bytes pid payload = let c = crc16 payload in pid :: payload @ [ c land 0xFF; c lsr 8 ]

(* bytes to symbols: sync, bytes LSB first, a stuffed zero after six ones, NRZI (a zero flips
   the line), EOP *)
let symbols ?(jk_swap = false) bytes =
  let j, k = if jk_swap then sym_k, sym_j else sym_j, sym_k in
  let line = ref j and ones = ref 0 and out = ref [] in
  let send b =
    if b = 0 then (line := (if !line = j then k else j); ones := 0) else incr ones;
    out := !line :: !out;
    if !ones = 6 then begin line := (if !line = j then k else j); ones := 0; out := !line :: !out end in
  List.iter (fun byte -> for i = 0 to 7 do send ((byte lsr i) land 1) done) (0x80 :: bytes);
  List.rev !out @ [ sym_se0; sym_se0; j ]

let pack ?(jk_swap = false) syms =
  let j = if jk_swap then sym_k else sym_j in
  let n = List.length syms in
  let pad = 4 - (n mod 4) in                     (* 1..4 *)
  let all = Array.of_list (List.init pad (fun _ -> j) @ syms) in
  List.init (Array.length all / 4) (fun i ->
    all.(4 * i) lor (all.(4 * i + 1) lsl 2) lor (all.(4 * i + 2) lsl 4) lor (all.(4 * i + 3) lsl 6))

let reply ?jk_swap bytes = pack ?jk_swap (symbols ?jk_swap bytes)

let () =
  (* the SETUP token for address 0 and a known data packet, from the specification *)
  assert (token_tail ~addr:0 ~ep:0 = (0x00, 0x10));
  assert (data_bytes 0xC3 [ 0x80; 0x06; 0x00; 0x01; 0x00; 0x00; 0x40; 0x00 ] = [ 0xC3; 0x80; 0x06; 0x00; 0x01; 0x00; 0x00; 0x40; 0x00; 0xDD; 0x94 ]);
  (* a handshake is 1 pad + 8 sync + 8 PID + 3 EOP = 20 symbols, five bytes *)
  assert (List.length (reply [ 0xD2 ]) = 5)
