# One-bit DAC: CD audio from the host, out of two pins as a Bitstream-style DAC (2026-10-05)

The host (the demo board's RP2350) streams 16-bit stereo PCM into the chip. The sequencer and
the PE array turn it into two 6 MHz one-bit streams with noise shaping. Each stream drives a pin
into an RC/Sallen-Key filter. Everything in this file is simulation. Every number points to a
file in `results/`.

**Summary.**
- **The pipeline:** host link → pump thread (ISA v2) → feed registers → one 8-PE run per channel
  (CIFB sigma-delta, order 2, 3 or 4) → segment-end flag → pin.
- **What it needed:** three small generic additions to the array, specified, modelled, built in
  the Hardcaml RTL and checked in lockstep (section 2): a **lane loop-back** (E1), a **feed that
  repeats its word every R clocks** (E2) and an **arithmetic right shift of A** (X1). Without E1
  no modulator of order above 1 can close its loop on the array.
- **Results, ideal pins** (`results/tones.txt`):
  - with 44.1 kHz on the link (mode A), dynamic range 79 / 76 / 71 dB for order 2 / 3 / 4.
    The limit is the 16-bit PE datapath. The first integrator needs 2.5-4 bits of headroom over
    the input, so the input is only 12-13.5 bits;
  - with 4× oversampling and noise-shaped requantisation on the host (mode B, 706 kB/s on the
    link), 86 / 93 / 91 dB. THD+N at -1 dBFS is -85.5 / -91.9 / -90.0 dB.
- **The real limits are the pins** (`results/impairments.txt`, order 3, mode B):
  - 30 ps rms of white edge jitter gives 80 dB, and 100 ps gives 70 dB;
  - 200 ps of rise/fall asymmetry gives 73 dB THD+N with H2 at -76 dB, and a complementary pin
    pair or return-to-zero coding cancels it;
  - a rail shared with 8 switching fast pads gives 72 dB (at an assumed 1 ps/mV).
  So the hardware notes recommend re-clocking the two outputs in an external flip-flop on a quiet
  supply.
- **Underruns hold the last frame:** no click at the gap's edges (median +0.2 dB against the
  gapless output), where substituting zeros gives a median of +19 dB and a worst case of +34 dB.

(Sections 1 to 7 follow.)
