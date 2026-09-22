(* One-bit synthesiser: a numerically controlled oscillator (phase accumulator plus sine table),
   a note sequencer whose melody is a ROM of (tuning word, duration) pairs, and a second-order
   sigma-delta modulator that turns 16-bit samples into a one-bit stream for an RC filter and an
   amplifier. The modulator runs every [div] clock cycles; at 48 MHz and div 16 that is 3 MHz,
   an oversampling ratio of 62.5 for a 24 kHz band. *)
open Hardcaml
open Signal

let phase_bits = 24
let div = 16
let sine_table = List.init 256 (fun i -> int_of_float (Float.round (2047.0 *. sin (2.0 *. Float.pi *. float i /. 256.0))))

(* tuning word for frequency f at modulator rate fs: f / fs * 2^24 *)
let tuning ~fs f = int_of_float (Float.round (f /. fs *. float (1 lsl phase_bits)))

let create ~clock ~clear ~(notes : (int * int) list) ~(amp_shift : int) =
  let spec = Reg_spec.create ~clock ~clear () in
  let open Always in
  let tick_cnt = Variable.reg spec ~width:4 in
  let tick = tick_cnt.value ==:. (div - 1) in
  let phase = Variable.reg spec ~width:phase_bits in
  let note_idx = Variable.reg spec ~width:5 in
  let dur_cnt = Variable.reg spec ~width:24 in
  let n = List.length notes in
  let note_tw = mux note_idx.value (List.map (fun (tw, _) -> of_int ~width:phase_bits tw) notes) in
  let note_dur = mux note_idx.value (List.map (fun (_, d) -> of_int ~width:24 d) notes) in
  (* sine lookup on the top 8 phase bits, 12-bit signed, scaled to 16 bits then attenuated *)
  let sine = mux (select phase.value (phase_bits - 1) (phase_bits - 8)) (List.map (fun v -> of_int ~width:12 (v land 0xFFF)) sine_table) in
  let sample = sra (sll (sresize sine 16) 4) amp_shift in           (* 16-bit signed sample *)
  (* second-order sigma-delta, CIFB, 20-bit integrators with saturation *)
  let i1 = Variable.reg spec ~width:20 and i2 = Variable.reg spec ~width:20 in
  let y = Variable.reg spec ~width:1 in
  let fs = of_int ~width:20 (1 lsl 15) in
  let fb = mux2 y.value fs (negate fs) in
  let sat v = let hi = of_int ~width:20 ((1 lsl 18) - 1) and lo = of_int ~width:20 (-(1 lsl 18)) in
    mux2 (v >+ hi) hi (mux2 (v <+ lo) lo v) in
  let i1n = sat (i1.value +: (sresize sample 20 -: fb)) in
  let i2n = sat (i2.value +: (i1n -: fb)) in
  compile
    [ tick_cnt <-- mux2 tick (zero 4) (tick_cnt.value +:. 1)
    ; when_ tick
        [ phase <-- phase.value +: note_tw
        ; if_ (dur_cnt.value ==: note_dur -:. 1)
            [ dur_cnt <--. 0; note_idx <-- mux2 (note_idx.value ==:. (n - 1)) (zero 5) (note_idx.value +:. 1) ]
            [ dur_cnt <-- dur_cnt.value +:. 1 ]
        ; i1 <-- i1n; i2 <-- i2n; y <-- ~:(msb i2n) ] ];
  y.value, sample, tick, note_idx.value

let circuit ~notes ~amp_shift =
  let clock = input "clock" 1 and clear = input "clear" 1 in
  let pdm, sample, tick, note = create ~clock ~clear ~notes ~amp_shift in
  Circuit.create_exn ~name:"one_bit_synth"
    [ output "pdm" pdm; output "sample" sample; output "tick" tick; output "note" note ]
