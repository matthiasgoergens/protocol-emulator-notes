(* FM on the third harmonic through the actual RTL: the NCO (nco.ml) drives the four-phase stage
   (stage.ml, sub-step model) and the stage's pins are written out at quarter-clock resolution for
   fm_eval.py. Pin 0: quarter grid (four-phase stage); pin 1: half grid (both clock edges); pin 2:
   clock grid. Parameters as in notes/fm-radio-2026-09-24/fm_sim.py: 66.5 MHz clock, fundamental
   clk/2 (third harmonic 99.75 MHz), 25 kHz deviation at the fundamental, 1 kHz tone, 4 ms.

   The "firmware" is modelled as the host: every [update] clocks it writes a new frequency word,
   chosen from the ideal phase at the step boundaries so the phase never drifts (a thread would
   do the same from a table: one IN and one write per 16 clocks). Output file: argv 1. *)
open Hardcaml

let clk = 66.5e6
let f0 = clk /. 2.0
let dev0 = 75e3 /. 3.0
let ftone = 1e3
let clocks = 266_000   (* 4 ms: an integer number of tone and carrier periods *)
let update = 16
let latency = 4        (* clocks from the NCO's input to the stage's pins, dropped at the start *)

let phase t = (f0 *. t) +. (dev0 *. sin (2.0 *. Float.pi *. ftone *. t) /. (2.0 *. Float.pi *. ftone))
let two32 = 4294967296.0
(* the ideal phase in 32-bit fixed point, unwrapped (fits an Int64: 1.3e5 cycles x 2^32) *)
let fixed t = Int64.of_float (Float.round (phase t *. two32))

let () =
  let out = Sys.argv.(1) in
  let sim = Cyclesim.create (Nco.circuit ()) in
  let inc = Cyclesim.in_port sim "inc" and sub = Cyclesim.out_port sim "sub" in
  Cyclesim.in_port sim "clear" := Bits.vdd; Cyclesim.cycle sim; Cyclesim.in_port sim "clear" := Bits.gnd;
  let stage = Stage.Sim.create ~n_out:3 ~n_in:1 () in
  let buf = Bytes.create (4 * clocks) in
  let total = clocks + latency in
  let acc_model = ref 0L in
  for c = 0 to total - 1 do
    if c mod update = 0 then begin
      (* the word that brings the NCO's (unwrapped) accumulator to the ideal phase at the end of
         the step; tracking the accumulator exactly means rounding never accumulates *)
      let t1 = float (c + update) /. clk in
      let d = Int64.sub (fixed t1) !acc_model in
      let step = Int64.div (Int64.add d (Int64.of_int (update / 2))) (Int64.of_int update) in
      acc_model := Int64.add !acc_model (Int64.mul step (Int64.of_int update));
      inc := Bits.of_int64 ~width:32 (Int64.logand step 0xFFFF_FFFFL)
    end;
    Cyclesim.cycle sim;
    let pins, _ = Stage.Sim.step stage ~sub:(Bits.to_int !sub) ~pads:(fun _ -> 0) in
    if c >= latency then
      Array.iteri (fun p v -> Bytes.set buf (4 * (c - latency) + p) (Char.chr v)) pins
  done;
  let oc = open_out_bin out in
  output_bytes oc buf; close_out oc;
  Printf.printf "wrote %d quarters (%d clocks) to %s\n" (4 * clocks) clocks out
