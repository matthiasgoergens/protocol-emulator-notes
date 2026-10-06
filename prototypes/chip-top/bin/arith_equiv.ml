(* The PE's parallel-prefix adder and comparisons (../blocks/upe/upe_rtl.ml, prefix_add and
   signed_ge) against Hardcaml's own operators, for formal/arith_equiv: [arith_equiv.exe
   prefix|plain FILE]. Widths as the PE uses them: x + yn + c in 17 bits, signed 16-bit >= both
   ways, and the window's 8-bit difference. *)
open Hardcaml
open Signal
module U = Upe.Upe_rtl

let () =
  let which = Sys.argv.(1) and file = Sys.argv.(2) in
  let x = input "x" 16 and y = input "y" 16 and c = input "c" 1 and a = input "a" 8 and k = input "k" 8 in
  let sum, ge, le, d =
    if which = "plain" then
      (uresize x 17 +: uresize y 17 +: uresize c 17, x >=+ y, x <=+ y, a -: k)
    else (U.prefix_add (uresize x 17) (uresize y 17) c, U.signed_ge x y, U.signed_ge y x, U.prefix_add a (~:k) vdd)
  in
  let circ = Circuit.create_exn ~name:"arith" [ output "sum" sum; output "ge" ge; output "le" le; output "d" d ] in
  let oc = open_out file in
  Rtl.output ~output_mode:(To_channel oc) Verilog circ;
  close_out oc
