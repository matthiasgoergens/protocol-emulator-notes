# One-bit synthesiser: a prototype

The simplest audio path the chip can have: a one-bit stream on a digital
pin into a resistor-capacitor filter and an amplifier, no DAC. It is the
output stage of the noise-cancelling demo on its own, plus a tone source
to drive it, so it can be built and heard before any microphone exists.

## What is here

- `synth.ml`: a phase accumulator (24 bits) with a 256-entry 12-bit sine
  table, a note sequencer stepping through a ROM of (tuning word, duration)
  pairs, and a second-order sigma-delta modulator with saturating 20-bit
  integrators that runs every 16th clock. At 48 MHz that is a 3 MHz
  one-bit stream, an oversampling ratio of 62.5 for a 24 kHz band. The
  melody is data: frequencies and durations become tuning words and tick
  counts on the host.
- `main.ml`: emits Verilog and measures the modulator from the outside.
  The one-bit stream is windowed and transformed directly (no low-pass
  filter in the way), over a window holding exactly ten cycles of the
  tone, so the tone does not leak into the noise bins.

## Results

| Measurement | Value |
| --- | --- |
| 1 kHz tone level | −12.0 dB, exactly the table amplitude at the chosen attenuation |
| 2nd and 3rd harmonics | below −100 dB |
| In-band signal-to-noise, 0 to 20 kHz, of the raw bit stream | 68.0 dB |
| Melody | four notes played in order, then wraps |
| Synthesis on sg13g2, flattened | 1,136 cells, 14,779 um2, 108 flip-flops |
| Place and route at 48 MHz (`pnr-metrics/synth48/`) | die 37285 um2, utilisation 68 %, routing violations 0, setup slack +14.5 / +13.5 / +11.4 ns at fast / typical / slow |

The first measurement attempt read 27 dB, which was the measurement's
fault: a short moving-average filter left the shaped noise in the error
and its group delay misaligned the reference, and a window with 4.4 tone
cycles leaked the tone into the harmonic bins. The direct spectrum with an
integer number of cycles is the honest number.

Build and run: `opam exec --switch=5.3.0 -- dune build && dune exec ./main.exe`
(Hardcaml v0.17).
