(* Generic, parameterised line-side units, meant to be reused across protocols. Convention for
   every multi-bit-per-clock port: bit 0 is the first bit in time. Where a stream carries a
   variable number of bits per clock (after an oversampling CDR, 0..k), a [count] input says how
   many of the low bits are valid.

   Unit                 used here for                   also serves
   Lfsr.additive        100BASE-TX scrambler            PCIe 1/2 and USB 3 (x^16+x^5+x^4+x^3+1),
                        (x^11+x^9+1)                    SONET/SDH frame scrambler (x^7+x^6+1),
                                                        802.11 (x^7+x^4+1), PRBS test generators
   Lfsr.multiplicative  (not needed by 100BASE-X)       10GBASE-R / 64b66b (x^58+x^39+1),
                                                        DVB, ATM cell scramblers (self-synchronising)
   Line_code.nrzi       100BASE-FX                      USB full/low speed (invert: 0 toggles),
                                                        FDDI, SD/HDLC-style NRZI links
   Line_code.mlt3_pins  100BASE-TX, as one-pin-per-     FDDI over copper (TP-PMD, CDDI)
                        step on a resistor pair
   Line_code.manchester (the 10BASE-T prototype)        10BASE-T, DALI, IEEE 802.15.4 O-QPSK chips,
                                                        BMC for USB Power Delivery and AES3
                                                        (differential Manchester = manchester of
                                                        nrzi)
   Block_4b5b           100BASE-X                       FDDI, USB Power Delivery (4b5b + BMC)
   Aligner              /J/K/ delimiter search           any comma/delimiter alignment: 8b10b
                                                        K28.5, USB SYNC, HDLC flag 0x7E *)
open! Base
open Hardcaml
open Signal

let xor_list = function [] -> gnd | l -> List.reduce_exn l ~f:( ^: )
let bits_for n = let rec go b = if (1 lsl b) > n then b else go (b + 1) in max 1 (go 0)

module Lfsr = struct
  (* Fibonacci form: s(n) = xor_{t in taps} s(n - t). State bit i holds s(n - 1 - i), so a step
     shifts toward the MSB and puts the new bit at bit 0. *)
  let next_bit ~taps st = xor_list (List.map taps ~f:(fun t -> bit st (t - 1)))
  let shift_in st b = concat_lsb [ b; select st (width st - 2) 0 ]

  (* Additive (synchronous) scrambler: out = data xor keystream. [count] bits of [data] are valid
     and the keystream advances by [count]. [load] (enable, value) overwrites the state, which
     is how a descrambler is synchronised. *)
  let additive ~spec ~taps ~k ~seed ?count ?load data =
    let n = List.fold taps ~init:0 ~f:max in
    let st = Always.Variable.reg (Reg_spec.override spec ~clear_to:(of_int ~width:n seed)) ~width:n in
    let count = match count with Some c -> c | None -> of_int ~width:(bits_for k) k in
    let rec go i s outs =
      if i = k then s, List.rev outs
      else
        let ks = next_bit ~taps s in
        let s' = mux2 (count >:. i) (shift_in s ks) s in
        go (i + 1) s' ((bit data i ^: ks) :: outs)
    in
    let final, outs = go 0 st.value [] in
    let final = match load with None -> final | Some (en, v) -> mux2 en v final in
    Always.(compile [ st <-- final ]);
    concat_lsb outs

  (* Multiplicative (self-synchronising): the scrambler feeds back its output, the descrambler
     its input, so the descrambler needs no synchronisation (errors multiply by the tap count). *)
  let multiplicative ~spec ~taps ~k ~descramble data =
    let n = List.fold taps ~init:0 ~f:max in
    let st = Always.Variable.reg spec ~width:n in
    let rec go i s outs =
      if i = k then s, List.rev outs
      else
        let o = bit data i ^: next_bit ~taps s in
        let fb = if descramble then bit data i else o in
        go (i + 1) (shift_in s fb) (o :: outs)
    in
    let final, outs = go 0 st.value [] in
    Always.(compile [ st <-- final ]);
    concat_lsb outs
end

module Line_code = struct
  (* NRZI: a 1 toggles the line (FX); [invert] makes a 0 toggle it (USB). *)
  let nrzi_encode ~spec ~k ?(invert = false) data =
    let lvl = Always.Variable.reg spec ~width:1 in
    let rec go i l outs =
      if i = k then l, List.rev outs
      else let d = if invert then ~:(bit data i) else bit data i in
        let l' = l ^: d in go (i + 1) l' (l' :: outs)
    in
    let final, outs = go 0 lvl.value [] in
    Always.(compile [ lvl <-- final ]);
    concat_lsb outs

  (* NRZI decode with a variable number of valid levels per clock *)
  let nrzi_decode ~spec ~k ?(invert = false) ~count levels =
    let prev = Always.Variable.reg spec ~width:1 in
    let rec go i p outs =
      if i = k then p, List.rev outs
      else let l = bit levels i in
        let b = l ^: p in
        let b = if invert then ~:b else b in
        go (i + 1) (mux2 (count >:. i) l p) (b :: outs)
    in
    let final, outs = go 0 prev.value [] in
    Always.(compile [ prev <-- final ]);
    concat_lsb outs

  (* MLT-3 on two pins A and B, line level = A - B. A 1 toggles A when the line is at +-1, and B
     when it is at 0, so exactly one pin moves per step, each pin moves at most every second
     step, and the zero level alternates between (0,0) (after +1) and (1,1) (after -1). Starts
     at (1,1) so that the first step goes to +1, like the reference. *)
  let mlt3_pins ~spec ~k data =
    let a = Always.Variable.reg (Reg_spec.override spec ~clear_to:vdd) ~width:1 and b = Always.Variable.reg (Reg_spec.override spec ~clear_to:vdd) ~width:1 in
    let rec go i a b oa ob =
      if i = k then a, b, List.rev oa, List.rev ob
      else
        let d = bit data i in
        let nz = a ^: b in
        let a' = a ^: (d &: nz) and b' = b ^: (d &: ~:nz) in
        go (i + 1) a' b' (a' :: oa) (b' :: ob)
    in
    let fa, fb, oa, ob = go 0 a.value b.value [] [] in
    Always.(compile [ a <-- fa; b <-- fb ]);
    concat_lsb oa, concat_lsb ob

  (* MLT-3 decode from sliced levels (2 bits per UI: bit 0 = above +threshold, bit 1 = below
     -threshold), variable count: a 1 wherever the level differs from the previous UI's. *)
  let mlt3_decode ~spec ~k ~count (levels : Signal.t list) =
    let prev = Always.Variable.reg spec ~width:2 in
    let rec go i p outs =
      if i = k then p, List.rev outs
      else let l = List.nth_exn levels i in
        go (i + 1) (mux2 (count >:. i) l p) ((l <>: p) :: outs)
    in
    let final, outs = go 0 prev.value [] in
    Always.(compile [ prev <-- final ]);
    concat_lsb outs

  (* Manchester (IEEE 802.3 convention: 1 = low then high): k bits -> 2k half-bits *)
  let manchester data =
    concat_lsb (List.concat_map (bits_lsb data) ~f:(fun d -> [ ~:d; d ]))
end

module Block_4b5b = struct
  (* symbol ids: 0..15 data, 16 I, 17 J, 18 K, 19 T, 20 R *)
  let codes = [| "11110"; "01001"; "10100"; "10101"; "01010"; "01011"; "01110"; "01111";
                 "10010"; "10011"; "10110"; "10111"; "11010"; "11011"; "11100"; "11101";
                 "11111"; "11000"; "10001"; "01101"; "00111" |]
  let sym_i = 16 and sym_j = 17 and sym_k = 18 and sym_t = 19 and sym_r = 20
  (* as a 5-bit vector with the first transmitted (leftmost) bit at index 0 *)
  let vec s = concat_lsb (List.init (String.length s) ~f:(fun i -> if Char.equal s.[i] '1' then vdd else gnd))
  let encode id = mux id (Array.to_list (Array.map codes ~f:vec))
  (* decode: returns (id, valid) with id in 0..20 *)
  let decode g =
    let hits = Array.to_list (Array.mapi codes ~f:(fun i c -> (g ==: vec c), i)) in
    let id = List.fold hits ~init:(zero 5) ~f:(fun acc (h, i) -> mux2 h (of_int ~width:5 i) acc) in
    id, List.reduce_exn (List.map hits ~f:fst) ~f:( |: )
end

(* Bit accumulator and delimiter aligner: takes up to [k] bits per clock ([count] valid), searches
   for a [2w]-bit delimiter while not aligned, and after finding it emits aligned [w]-bit
   groups (one per clock at most, which holds whenever k < w). Output: (group, group_valid,
   found, aligned) where found pulses when the delimiter completes, i.e. the next group is the
   first after it. *)
module Aligner = struct
  (* [clear] drops alignment (the frame decoder asserts it at the end of a frame); while not
     aligned, every incoming bit position is checked against the delimiter. *)
  let create ~spec ~k ~w ~delim ~clear ~count bits =
    let aw = 2 * w in
    let sh = Always.Variable.reg spec ~width:aw in           (* newest bit at the top *)
    let fill = Always.Variable.reg spec ~width:4 in          (* bits collected in current group *)
    let aligned = Always.Variable.reg spec ~width:1 in
    let rec go i s f al gv g found =
      if i = k then s, f, al, gv, g, found
      else
        let v = count >:. i in
        let s1 = mux2 v (concat_msb [ bit bits i; select s (aw - 1) 1 ]) s in
        let hit = v &: ~:al &: (s1 ==: delim) in
        let f_inc = f +:. 1 in
        let complete = v &: al &: (f_inc ==:. w) in
        let f' = mux2 (hit |: complete) (zero 4) (mux2 (v &: al) f_inc f) in
        let g' = mux2 complete (select s1 (aw - 1) w) g in
        go (i + 1) s1 f' (al |: hit) (gv |: complete) g' (found |: hit)
    in
    let s, f, al, gv, g, found = go 0 sh.value fill.value aligned.value gnd (zero w) gnd in
    Always.(compile [ sh <-- s; fill <-- f; aligned <-- (al &: ~:clear) ]);
    g, gv, found, aligned.value
end

(* CRC-32 (802.3), one byte per call, bit-serial unrolled, register not complemented *)
let crc32_byte crc byte =
  List.fold (bits_lsb byte) ~init:crc ~f:(fun c b ->
      let fb = bit c 0 ^: b in
      mux2 fb (srl c 1 ^: of_int ~width:32 0xEDB88320) (srl c 1))
let crc_residual = 0xDEBB20E3
