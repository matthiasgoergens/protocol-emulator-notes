(* The Tiny Tapeout top level: the chip core between the four-phase pin stage
   (../multiphase/stage.ml, unchanged) and Tiny Tapeout's pins.

   Phases: Tiny Tapeout gives one clock and no delay line is placed yet (README, "Phases"), so the
   stage runs on both clock edges: phases 0 and 1 on the rising edge, 2 and 3 on the falling edge.
   The core's nibbles are folded onto the half grid (n0 n0 n2 n2), so lanes 1 and 3 never toggle,
   and the input samples of quarters 1 and 3 are taken at the same instants as 0 and 2.

   Reset: rst_n through a two-flop synchroniser, active high into the core and the stage.

   Memories: [`Behavioural] keeps the core's behavioural RAMs (Yosys makes flip-flop arrays of
   them); [`Macros] puts IHP's single-port SRAM macros under them, RM_IHPSG13_1P_512x16 for the
   programme store and RM_IHPSG13_1P_1024x8 for the bank, with BIST tied off. The macros read
   every clock (REN) and write through, which is the behaviour of [Chip_rtl.behavioural_mem]. *)
open Hardcaml
open Signal

let macro_name ~words ~width = Printf.sprintf "RM_IHPSG13_1P_%dx%d_c2_bm_bist" words width

let macro_mem : Chip_rtl.mem =
 fun ~clock ~size ~width ~addr ~we ~wdata ->
  let abits = address_bits_for size in
  let inst =
    Instantiation.create () ~name:(macro_name ~words:size ~width)
      ~instance:(Printf.sprintf "sram_%dx%d" size width)
      ~inputs:
        [ "A_CLK", clock; "A_MEN", vdd; "A_WEN", we; "A_REN", vdd; "A_ADDR", select addr (abits - 1) 0;
          "A_DIN", wdata; "A_DLY", vdd; "A_BM", ones width;
          "A_BIST_CLK", gnd; "A_BIST_EN", gnd; "A_BIST_MEN", gnd; "A_BIST_WEN", gnd; "A_BIST_REN", gnd;
          "A_BIST_ADDR", zero abits; "A_BIST_DIN", zero width; "A_BIST_BM", zero width ]
      ~outputs:[ "A_DOUT", width ]
  in
  Base.Map.find_exn inst "A_DOUT"

let fold_half n = concat_lsb [ bit n 0; bit n 0; bit n 2; bit n 2 ]

(* Tiny Tapeout's [ena] is not used, and Hardcaml leaves unused inputs out of a module, so the
   tt_um_ wrapper with Tiny Tapeout's exact port list is a few lines of hand-written Verilog
   (../../tt/src/chip_project.v) around this module. *)
let create ?(cfg = Chip_spec.default_config) ~memories ~name () =
  let ui_in = input "ui_in" 8 and uio_in = input "uio_in" 8 in
  let clk = input "clk" 1 and rst_n = input "rst_n" 1 in
  let clocks = [| clk; clk; ~:clk; ~:clk |] in
  let sync = Reg_spec.create ~clock:clk () in
  let reset = reg sync (reg sync (~:rst_n)) in
  let clocking = Mphase.Stage.Phases { clocks; clear = reset } in
  let pads = concat_lsb [ ui_in; uio_in ] in
  let smp = Mphase.Stage.input_stage clocking ~pads in
  let mems = match memories with `Behavioural -> Chip_rtl.behavioural | `Macros -> { Chip_rtl.prog_mem = macro_mem; bank_mem = macro_mem } in
  let core = Chip_rtl.create ~cfg ~mems ~clock:clk ~reset ~smp () in
  let folded = concat_lsb (List.init Regs.n_pads (fun i -> fold_half (select core.pad_nib (4 * i + 3) (4 * i)))) in
  let pins = Mphase.Stage.output_stage clocking ~sub:folded in
  let oe = reg (Reg_spec.create ~clock:clk ~clear:reset ()) core.uio_oe in
  Circuit.create_exn ~name
    [ output "uo_out" (select pins 7 0); output "uio_out" (select pins 15 8); output "uio_oe" oe ]
