(* The Hardcaml TMDS encoder against the independent model (../indep, written from the DVI 1.0
   specification by a separate author who did not see this encoder), with planted-bug controls,
   and the cross-check against Gergo Erdi's Clash encoder (../crosscheck).

   Exit status 0 only if the faithful encoder passes every check, and every mutant fails one. *)
open! Base
open Hardcaml
open Hdmi_hw
module I = Tmds_indep
module Printf = Stdlib.Printf

let failures = ref 0
let fail fmt = Printf.ksprintf (fun s -> Int.incr failures; Stdio.print_endline ("FAIL: " ^ s)) fmt

(* Reachable disparity values per the independent model's closure: even values -8 .. +8. *)
let reachable_cnts = List.init 9 ~f:(fun i -> (2 * i) - 8)

type verdict = { mutable ref_mismatch : int; mutable roundtrip : int; mutable invalid_word : int
               ; mutable cnt_vs_disparity : int; mutable control : int; mutable bound : int
               ; mutable max_abs_running : int }

let new_verdict () = { ref_mismatch = 0; roundtrip = 0; invalid_word = 0; cnt_vs_disparity = 0
                     ; control = 0; bound = 0; max_abs_running = 0 }

let caught v = v.ref_mismatch + v.roundtrip + v.invalid_word + v.cnt_vs_disparity + v.control + v.bound > 0

let signed_of_bits b = Bits.to_sint b

(* Exhaustive: every (value, reachable disparity) pair, and the four control codes. *)
let exhaustive mutant v =
  let sim = Cyclesim.create (Tmds.test_circuit ~mutant ()) in
  let i n = Cyclesim.in_port sim n and o n = Cyclesim.out_port sim n in
  let set n w x = i n := Bits.of_int ~width:w x in
  let eval () = Cyclesim.cycle sim in
  let reference = I.Ref_encoder.create () in
  List.iter reachable_cnts ~f:(fun cnt ->
      for d = 0 to 255 do
        set "cnt_in" Tmds.cnt_width cnt; set "de" 1 1; set "d" 8 d; set "c0" 1 0; set "c1" 1 0;
        eval ();
        let word = Bits.to_int !(o "word") and cnt' = signed_of_bits !(o "cnt_next") in
        I.Ref_encoder.set_cnt reference cnt;
        let rword = I.Ref_encoder.data reference d in
        if word <> rword || cnt' <> I.Ref_encoder.cnt reference then v.ref_mismatch <- v.ref_mismatch + 1;
        (match I.decode word with I.Data x when x = d -> () | _ -> v.roundtrip <- v.roundtrip + 1);
        if not (I.is_valid_data word) then v.invalid_word <- v.invalid_word + 1;
        if cnt' - cnt <> I.ones_minus_zeros word then v.cnt_vs_disparity <- v.cnt_vs_disparity + 1
      done);
  List.iter [ false, false; false, true; true, false; true, true ] ~f:(fun (c1, c0) ->
      List.iter reachable_cnts ~f:(fun cnt ->
          set "cnt_in" Tmds.cnt_width cnt; set "de" 1 0; set "d" 8 0x5a;
          set "c0" 1 (Bool.to_int c0); set "c1" 1 (Bool.to_int c1);
          eval ();
          let word = Bits.to_int !(o "word") and cnt' = signed_of_bits !(o "cnt_next") in
          let ok_decode = match I.decode word with I.Control r -> Bool.(r.c0 = c0 && r.c1 = c1) | _ -> false in
          if word <> I.control_word ~c0 ~c1 || (not ok_decode) || cnt' <> 0 then v.control <- v.control + 1))

(* Long random stream through the registered encoder: the running disparity is computed from the
   words on the wire (not from the encoder's own counter) and reset at control periods. *)
let stream mutant v ~words ~seed =
  let clock = Signal.input "clock" 1 and clear = Signal.input "clear" 1 in
  let spec = Reg_spec.create ~clock ~clear () in
  let de = Signal.input "de" 1 and d = Signal.input "d" 8 in
  let c0 = Signal.input "c0" 1 and c1 = Signal.input "c1" 1 in
  let word, _ = Tmds.create ~mutant ~spec ~de ~d ~c0 ~c1 () in
  let sim = Cyclesim.create (Circuit.create_exn ~name:"tmds_reg" [ Signal.output "word" word ]) in
  let i n = Cyclesim.in_port sim n and o = Cyclesim.out_port sim "word" in
  let rng = Random.State.make [| seed |] in
  i "clear" := Bits.vdd; Cyclesim.cycle sim; i "clear" := Bits.gnd;
  let running = ref 0 and prev_de = ref false in
  for k = 0 to words - 1 do
    (* data runs of 1..800 symbols separated by control runs of 1..20 *)
    let de_now = if !prev_de then Random.State.int rng 800 <> 0 else Random.State.int rng 20 = 0 in
    let de_now = if k = 0 then false else de_now in
    i "de" := Bits.of_bool de_now;
    i "d" := Bits.of_int ~width:8 (Random.State.int rng 256);
    i "c0" := Bits.of_int ~width:1 (Random.State.int rng 2);
    i "c1" := Bits.of_int ~width:1 (Random.State.int rng 2);
    Cyclesim.cycle sim;
    (* the word now on [o] encodes the inputs of this cycle (one register) *)
    let w = Bits.to_int !o in
    (match I.decode w with
     | I.Control _ -> running := 0
     | _ -> running := !running + I.ones_minus_zeros w);
    v.max_abs_running <- max v.max_abs_running (abs !running);
    if abs !running > 8 then v.bound <- v.bound + 1;
    prev_de := de_now
  done

let mutants =
  Tmds.[ "faithful", Faithful; "xnor rule tests d[1] (Gergo)", Xnor_rule_bit1
       ; "2*q_m[8] correction inverted (Gergo)", Swapped_qm8_correction
       ; "control 01 sends code of 10", Wrong_control_code; "no DC balance", No_dc_balance ]

let () =
  let words = 1_000_000 in
  Stdio.printf "%-38s %8s %8s %8s %8s %8s %8s %8s\n" "encoder" "vs-ref" "roundtr" "invalid"
    "cnt=disp" "control" "bound>8" "max|rd|";
  List.iter mutants ~f:(fun (name, m) ->
      let v = new_verdict () in
      exhaustive m v;
      stream m v ~words ~seed:42;
      Stdio.printf "%-38s %8d %8d %8d %8d %8d %8d %8d\n%!" name v.ref_mismatch v.roundtrip
        v.invalid_word v.cnt_vs_disparity v.control v.bound v.max_abs_running;
      match m with
      | Tmds.Faithful -> if caught v then fail "faithful encoder fails a check"
      | _ -> if not (caught v) then fail "mutant %S is not caught" name);
  Stdio.printf "(exhaustive: 9 disparity states x 256 values + 4 control codes x 9 states; stream: %d \
                words, seed 42)\n" words;
  if !failures > 0 then Stdlib.exit 1 else Stdio.print_endline "ALL PASS"
