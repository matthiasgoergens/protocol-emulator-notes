(* Verilog of the chip for Tiny Tapeout: [emit.exe FILE [macros|regs] [SIZES] [PROG_WORDS]].
   The module is chip_tt (see src/tt_top.ml); SIZES are the four segment sizes, e.g. 1,1,1,1.
   Build output only: never committed (../../tt/scripts/regen_chip.sh). *)
let () =
  let arg i d = if Array.length Sys.argv > i then Sys.argv.(i) else d in
  let file = arg 1 "chip_tt.v" in
  let memories = match arg 2 "macros" with "macros" -> `Macros | "regs" -> `Behavioural | m -> failwith ("memories: " ^ m) in
  let sizes = Array.of_list (List.map int_of_string (String.split_on_char ',' (arg 3 "1,1,1,1"))) in
  let prog_words = int_of_string (arg 4 "512") in
  let cfg = { Chip_spec.layout = Upe.Spec.layout_of_sizes sizes; prog_words } in
  Chip_rtl.bug := "";
  let c = Tt_top.create ~cfg ~memories ~name:"chip_tt" () in
  let oc = open_out file in
  Hardcaml.Rtl.output ~output_mode:(To_channel oc) Verilog c;
  close_out oc
