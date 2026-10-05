(* TMDS encoder for DVI/HDMI, one colour channel: 8-bit pixel or 2 control bits in, 10-bit
   word out, with running disparity.

   Written from the encoding flowchart of the DVI 1.0 specification (section 3.2.2, figure 3-5)
   and the control-code table (section 3.3.3).  The shape, a registered Mealy machine with one
   disparity accumulator, follows Gergo Erdi's Clash encoder (clash-flappysquare, branch
   ulx3s-hdmi, target/ulx3s/src/Hardware/ULX3S/TMDS.hs, MIT licence), which we cross-checked
   against.  Two places where his encoder departs from the flowchart, both measured in
   ../README.md: his XOR/XNOR choice tests bit 1 of the pixel where the flowchart tests bit 0, and
   in the two DC-balancing branches the 2 * q_m[8] correction is applied with q_m[8] inverted.
   This encoder follows the flowchart in both places.

   Bit 0 of a word is the first bit on the wire (the specification's q_out[0]). *)
open! Base
open Hardcaml
open Signal

(* The four control codes, indexed by {c1, c0}; DVI 1.0 section 3.3.3 lists them as
   q_out[0:9], so the strings there read in the opposite order to these integer literals. *)
let control_code ~c1 ~c0 =
  match c1, c0 with
  | false, false -> 0b11_0101_0100
  | false, true -> 0b00_1010_1011
  | true, false -> 0b01_0101_0100
  | true, true -> 0b10_1010_1011

let popcount4 s = tree ~arity:2 ~f:(reduce ~f:( +: )) (List.map (bits_lsb s) ~f:(fun b -> uresize b 4))

(* The running disparity, ones minus zeros of everything sent since the last control period,
   takes the even values -8 .. +8 (reachable-state closure in test/test_tmds.ml).  +8 does not fit
   in four signed bits, so the accumulator has five. *)
let cnt_width = 5

type mutant =
  | Faithful
  | Xnor_rule_bit1  (** Gergo's choice: test d[1] instead of d[0] *)
  | Swapped_qm8_correction  (** the 2 * q_m[8] terms with q_m[8] inverted *)
  | Wrong_control_code  (** {c1,c0} = 01 sends the code of 10 *)
  | No_dc_balance  (** never invert: stage 2 always takes the "else" branch *)

(* Combinational core: the word for this cycle and the next accumulator value. *)
let encode_comb ?(mutant = Faithful) ~cnt ~de ~d ~c0 ~c1 () =
  (* Stage 1: transition minimisation.  q_m[i] = q_m[i-1] XOR d[i], or XNOR if d has more than
     four ones, or exactly four and d[0] = 0. *)
  let n1_d = popcount4 d in
  let tie_bit = match mutant with Xnor_rule_bit1 -> bit d 1 | _ -> ~:(bit d 0) in
  let use_xnor = n1_d >:. 4 |: (n1_d ==:. 4 &: tie_bit) in
  let qm =
    let rec chain i prev acc =
      if i = 8 then List.rev acc
      else
        let x = prev ^: bit d i in
        let q = mux2 use_xnor ~:x x in
        chain (i + 1) q (q :: acc)
    in
    let d0 = bit d 0 in
    concat_lsb (chain 1 d0 [ d0 ])
  in
  let qm8 = ~:use_xnor in
  (* Stage 2: DC balance.  diff = N1(q_m[0:7]) - N0(q_m[0:7]) = 2 * N1 - 8. *)
  let n1_q = popcount4 qm in
  let diff = sll (uresize n1_q cnt_width) 1 -:. 8 in
  let qm8_s = uresize qm8 cnt_width in
  let two_qm8, two_not_qm8 =
    let t = sll qm8_s 1 and f = sll (uresize ~:qm8 cnt_width) 1 in
    match mutant with Swapped_qm8_correction -> f, t | _ -> t, f
  in
  let cnt_zero = cnt ==:. 0 and q_balanced = n1_q ==:. 4 in
  let cnt_pos = ~:(msb cnt) &: ~:cnt_zero and cnt_neg = msb cnt in
  let invert_branch = (cnt_pos &: (n1_q >:. 4)) |: (cnt_neg &: (n1_q <:. 4)) in
  let invert_branch = match mutant with No_dc_balance -> gnd | _ -> invert_branch in
  let word_balanced = concat_msb [ ~:qm8; qm8; mux2 qm8 qm ~:qm ] in
  let cnt_balanced = mux2 qm8 (cnt +: diff) (cnt -: diff) in
  let word_invert = concat_msb [ vdd; qm8; ~:qm ] in
  let cnt_invert = cnt +: two_qm8 -: diff in
  let word_keep = concat_msb [ gnd; qm8; qm ] in
  let cnt_keep = cnt -: two_not_qm8 +: diff in
  let first = cnt_zero |: q_balanced in
  let data_word = mux2 first word_balanced (mux2 invert_branch word_invert word_keep) in
  let data_cnt = mux2 first cnt_balanced (mux2 invert_branch cnt_invert cnt_keep) in
  let control_word =
    let code c1 c0 =
      let c1, c0 =
        match mutant with Wrong_control_code when (not c1) && c0 -> true, false | _ -> c1, c0
      in
      of_int ~width:10 (control_code ~c1 ~c0)
    in
    mux (concat_msb [ c1; c0 ]) [ code false false; code false true; code true false; code true true ]
  in
  ( mux2 de data_word control_word
  , mux2 de data_cnt (zero cnt_width) (* control periods reset the disparity *) )

(* Registered encoder: inputs on one clock edge, word on the next (one cycle of latency, as
   Gergo's [delay 0 . mealy ...]). *)
let create ?mutant ~spec ~de ~d ~c0 ~c1 () =
  let cnt = wire cnt_width in
  let word, cnt_next = encode_comb ?mutant ~cnt ~de ~d ~c0 ~c1 () in
  cnt <== reg spec cnt_next;
  reg spec word, cnt

(* A stand-alone circuit for the exhaustive tests: the accumulator can be preset, so every
   (value, disparity) pair can be driven directly. *)
let test_circuit ?mutant () =
  let cnt_in = input "cnt_in" cnt_width in
  let de = input "de" 1 and d = input "d" 8 and c0 = input "c0" 1 and c1 = input "c1" 1 in
  let word, cnt_next = encode_comb ?mutant ~cnt:cnt_in ~de ~d ~c0 ~c1 () in
  Circuit.create_exn ~name:"tmds_comb" [ output "word" word; output "cnt_next" cnt_next ]
