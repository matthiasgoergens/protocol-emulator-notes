(* An NCO whose square-wave output is computed at four points per clock, feeding the four-phase
   stage: the sub-clock data source that firmware cannot be.

   Why not firmware: FM on the third harmonic of a clk/2 square wave needs an edge on nearly every
   clock at a data-dependent quarter, and occasionally two edges in one clock or none, because the
   modulation moves the edges tens of clocks against the grid (25 kHz deviation at a 1 kHz tone is
   +-25 cycles of the fundamental). The barrel issues one instruction per clock in total, so one
   pin write per edge would take every slot of every thread and leave none for loops or data. An
   NCO needs one frequency word per audio sample instead, which a thread can supply at leisure.

   acc (32 bits, fundamental cycles) advances by inc each clock. The level during quarter p is the
   square wave at acc + p * inc / 4 (three extra adders), i.e. the ideal wave sampled at the start of
   each quarter and held, which is exactly the "edges move to the next grid point" quantisation of
   notes/fm-radio-2026-09-24/fm_sim.py. The same accumulator also yields the half-clock (both clock
   edges) and clock-grid versions for comparison: pin 0 quarter grid, pin 1 half grid, pin 2 clock
   grid. The nibbles are registered, as the stage expects. *)
open Hardcaml
open Signal

let create ~clock ~clear ~inc =
  let spec = Reg_spec.create ~clock ~clear () in
  let acc = reg_fb spec ~width:32 ~f:(fun a -> a +: inc) in
  let i4 = srl inc 2 and i2 = srl inc 1 in
  let a = [| acc; acc +: i4; acc +: i2; acc +: i2 +: i4 |] in
  let l p = ~:(msb a.(p)) in
  let quarter = concat_lsb [ l 0; l 1; l 2; l 3 ] in
  let half = concat_lsb [ l 0; l 0; l 2; l 2 ] in
  let grid = concat_lsb [ l 0; l 0; l 0; l 0 ] in
  reg spec (concat_lsb [ quarter; half; grid ])

let circuit () =
  let clock = input "clock" 1 and clear = input "clear" 1 and inc = input "inc" 32 in
  Circuit.create_exn ~name:"nco4" [ output "sub" (create ~clock ~clear ~inc) ]
