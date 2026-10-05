# One-bit DAC: CD audio from the host, out of two pins as a Bitstream-style DAC (2026-10-05)

The host (the demo board's RP2350) streams 16-bit stereo PCM into the chip. The sequencer and
the PE array turn it into two 6 MHz one-bit streams with noise shaping. Each stream drives a pin
into an RC/Sallen-Key filter. Everything in this file is simulation. Every number points to a
file in `results/`.

**Summary**

- **The pipeline:** host link → pump thread (ISA v2) → feed registers → one 8-PE run per channel
  (a CIFB sigma-delta of order 2, 3 or 4) → segment-end flag → pin.
- **What it needed:** three small generic additions to the array (section 2), each specified,
  modelled, built in the Hardcaml RTL and checked in lockstep:
  - a **lane loop-back** (E1). Without it, no modulator of order above 1 can close its loop on
    the array;
  - a **feed that repeats its word every R clocks** (E2);
  - an **arithmetic right shift of A** (X1).
- **Ideal pins** (`results/tones.txt`), dynamic range (DR) per AES17, 20 Hz-20 kHz:

  | order | mode A: 44.1 kHz link | mode B: host 4× FIR and noise shaping, 706 kB/s |
  |---|---|---|
  | 2 | 79 dB | 86 dB |
  | 3 | 76 dB | 93 dB |
  | 4 | 71 dB | 91 dB |

  Mode A is limited by the **16-bit PE datapath**: the first integrator needs 2.5-4 bits of
  headroom over the input, so the input word is 12-13.5 bits. In mode B, THD+N at -1 dBFS is
  -85.5 / -91.9 / -90.0 dB.
- **The pins are the real limit** (`results/impairments.txt`; order 3, mode B):
  - edge jitter: 30 ps rms of white jitter gives a DR of 80 dB, 100 ps gives 70 dB;
  - rise/fall asymmetry: 200 ps gives -73 dB THD+N, with H2 at -76 dB. A complementary pin
    pair or return-to-zero coding cancels it;
  - a rail shared with 8 switching fast pads gives a DR of 73 dB (at an assumed 1 ps/mV).

  So the hardware notes recommend re-clocking the outputs in an external flip-flop on a quiet
  supply.
- **Compressed audio** (section 8):
  - our IMA ADPCM and SBC decoders are bit-exact with ffmpeg and BlueZ's sbcdec on five streams
    (A2DP 44.1 and 48 kHz joint stereo, bitpool 53/51, SNR allocation, 4 subbands, dual channel);
  - the SBC CRC-8 runs on the PE array model and the RTL;
  - but the SBC filterbank (2.29 M MAC/s for stereo) does not fit the multiplier-less PEs or the
    1 KB of banks;
  - aptX was not attempted.
- **Underruns hold the last frame.** At the edges of a gap that adds nothing measurable (median
  +0.2 dB against the gapless output). Substituting zeros instead gives +19 dB median and +34 dB
  worst (`results/music.txt`).

## 1. The design at a glance

| block | use | load |
|---|---|---|
| host link | 4 bytes per stereo frame: L lo, L hi, R lo, R hi. Mode A: 44,117.6 frames/s = **176.5 kB/s**. Mode B: 176,470.6 frames/s = **705.9 kB/s** | 2.4 % / 9.4 % of the link's estimated 7.5 MB/s (architecture-v0 §2.7) |
| sequencer | thread 0 runs the pump: 27 words, plus 16 words for the underrun paths, and 4 bytes of the data bank | busy for 27 of the 340 slots per sample (mode A) or of 85 (mode B); the other 3 threads are free |
| PE array | left = segments 0+1+2 joined (PE 0-7), right = segment 3 (PE 8-15) | orders 2 / 3 / 4 use 4 / 6 / 8 PEs per channel, with the rest of each run passing tokens through |
| pins | 2. Each is a segment end's flag (F) through the pin source select (architecture-v0 §2.2), inverted | |

**Rates.**
- The chip clock is 60 MHz. The modulator steps once every 10 clocks: **6 MHz**, an
  oversampling ratio of 150 against a 20 kHz band.
- One host sample lasts 1,360 clocks = 136 steps, so fs = 60 MHz / 1,360 = **44,117.6 Hz**,
  400 ppm above 44.1 kHz. That is 0.7 cent of pitch.
  - In mode B the host's resampling filter can absorb the ratio exactly.
  - In mode A it does not matter for playback from a file.
  - The S/PDIF case is section 6.

**One modulator step** (`sim/dac.ml`). y is ±1, from the previous step; g = 1 means y = -1.
- FB_k: P ← sat((A >>> m_k) + (g ? a_k : -a_k)). K = -a_k, and Y is negated when g; g is the
  lane.
- I_k: S ← sat(S + A); P ← S. This is a non-delaying integrator.
- The last I_k also does: lane ← S'[15] (the next y), and F ← g (the pin bit).

**The token.** Each step is one token:
- E2 makes the feed present the held sample every 10 clocks;
- the token visits the 8 PEs one per clock (stream stepping), so a whole step is evaluated in
  order;
- E1 brings the last PE's lane, the new y, back to the first PE before the next token arrives.
  That needs a run length of at most the period, 8 ≤ 10.

So the run computes exactly the textbook CIFB loop with a one-step feedback delay. The state of
each integrator is a PE's S, and the 1-bit feedback "multiplication" by ±a_k is just a negated
constant. No multiplier is needed anywhere.

**Coefficients** (`analysis/explore_scaled.py`, `results/design.txt`):
- the NTF is (1 - z⁻¹)ᴺ / D(z), with D(z) having Butterworth poles placed so that the out-of-band
  gain is 4 (order 2, a pure differentiator), 1.7 (order 3) or 1.4 (order 4);
- the non-delaying CIFB coefficients are solved by polynomial matching;
- the inter-stage gains are powers of two (2^-m_k, from X1), chosen to equalise the state peaks.

| order | a_k | m_k | full scale of the word (0 dBFS) |
|---|---|---|---|
| 2 | 15689, 7845 | 0, 1 | 5567 (a_1 - 9 dB) |
| 3 | 11094, 8949, 9976 | 0, 2, 1 | 3936 (a_1 - 9 dB) |
| 4 | 6597, 7523, 9624, 15924 | 0, 3, 2, 1 | 2086 (a_1 - 10 dB) |

The full scale comes from the level sweep (`results/levels.txt`, `levels.png`). S/(THD+N) rises
10 dB per 10 dB of level until the 16-bit states start to saturate, 1-2 dB above the full scale
chosen. The saturating adds keep the loop bounded beyond that point: no limit cycles or runaway
appeared in any overload run. This is why higher order does not win in mode A. With unit or
power-of-two inter-stage gains, the first integrator's swing relative to the input grows with the
order: its peak is about 5.7× / 8× / 14× the input amplitude for order 2 / 3 / 4 (`design.txt`).
On 16 bits, that costs the input 2.5-4 bits.

## 2. The additions to the array, and why each is generic

All three are marked "onebit-dac" in `sim/spec.ml`, `model.ml` and `upe_rtl.ml`. Those files are
copies of `../unified-pe/verify` (commit 8651863); `../unified-pe` itself is untouched.

| addition | what | why it is needed here | other uses | area |
|---|---|---|---|---|
| **E1, lane loop** (control bit 6) | the lane at a segment's first PE comes from the lane register of the end of its joined run, whatever the A source | a sigma-delta of order N > 1 needs y at every stage, and y is decided at the end. The array's only backward paths are the segment loop-back, which uses up the A input (the sample has to come in there), and cb_in, which reaches back one PE and carries S[15]. With cb_in, only the PE just left of the last integrator sees y, and the g_in chain carries it only rightwards, past PEs that need y earlier. A thread in the loop (WAITC on a flag, then a broadcast write) would cap the step rate at about 3-4 MHz and use a thread per channel | any loop that feeds back a one-bit decision while data streams in: decision feedback, bang-bang phase detectors, sign-sign LMS, self-synchronising scramblers | E1 + E2 for 4 segments: **11,928 µm² synthesised** (`synth/reports/seg_ext.stat.txt`), most of it E2's 128 new flops |
| **E2, feed repeat** (mailbox sel 3 = period R) | with R ≠ 0, the feed's valid is one clock in R from a divider; a high-byte write commits {hi, lo} atomically and makes no token of its own | the modulator steps on tokens, and tokens are born only at a feed write. A thread re-sending the high byte gets 2 slots per 8 clocks. Two channels plus the bank reads to fetch the bytes cap the rate at about 1.9 MHz, and that uses one whole thread | the zero-order hold for any held value processed at a fixed sub-rate. gps-hotcold already assumed PEs "enabled every 16th / 256th clock" (`../gps-hotcold/README.md`) for exactly this. Also pacing PWM and NCOs | (in the E1 row) |
| **X1, A >>> m** (op bits 36:33) | X = A shifted right arithmetically by 0-15 when xsel = 1 | the inter-stage gains c_k = 2^-m. With c_k = 1 the states grow so much towards the end that a_1 falls to 724 for order 3, and the input to 10.5 bits (`analysis/explore_ntf.py`). A shift PE would add a PE per bit of shift | CIC normalisation, power-of-two FIR taps and IIR coefficients, scaling between any two PEs | **+1,585 µm² per PE** (15,944 against upe_v1's 14,359 in the same flow, `synth/reports/upe_onebit.stat.txt`): 11 %, 25k for 16 PEs. The designs use shifts of at most 3, so a 2-level shifter (0-3) would cost about half (est) |

**The three are expensive together:** about 37k µm² synthesised on top of an array of about
230k. Two cheaper variants, not synthesised:
- E2's counter cut to 4 bits and its committed word shared with the existing feed register
  (est. 40 % of the E2 area);
- X1 limited to shifts of 0-3.

E1 alone is a few mux2s per segment (est. under 100 µm²), and it is the one that is
indispensable.

**Verification of the additions.**
- **Random lockstep** (`results/lockstep.txt`), with every state bit of model and RTL compared
  every clock: the original 12 generators plus a "dac" generator that biases towards short
  repeat periods, lane loops and shifts. 13 × 200 trials, 1,466,952 clocks, **0 mismatches**.
- **Five planted bugs, one or more per addition, are all caught** (`results/controls_new.txt`):
  a logical shift, the lane loop taken from the own end, the repeat off by one, a high-byte write
  that still makes a token, and a non-atomic word.
- All 46 planted bugs (the original 41 and the 5 new ones) are caught by the extended lockstep (`results/controls_all.txt`).
- **The DAC configurations in lockstep with the RTL** (`results/rtl_lockstep.txt`). The pump,
  the host FIFO and both channels run on the model. The same per-clock inputs, setup included,
  are replayed into a fresh model and into the Hardcaml array, comparing every state bit every
  clock:
  - orders 2, 3 and 4 at normal level: 3 M clocks each (300k modulator steps);
  - orders 3 and 4 overdriven: 1 M clocks each, with 6,533 and 15,587 saturation events;
  - **0 mismatches**.
- **The fast model against the array model** (`results/check_fast.txt`): 600k steps per channel
  for each order, plus 300k overdriven, **0 bit mismatches**. Every long analysis uses the fast
  model (`Dac.fast_step`), which is bit-exact with the PE configuration on these stretches.

What lockstep cannot show is that model and RTL share no misreading of the additions. The planted
bugs show that the comparison is sensitive. The fast model, written separately as plain
arithmetic, and the audio results are the independent check that the configuration computes a
working modulator.

## 3. Host link, flow control and underruns

The pump (`Dac.pump_programme`; ISA v2 interpreter `../sequencer-v2/isa2.ml`, linked) works
like this:
- **WAITD** waits for the sample instant, and `LDA 0; BANK 0` points the bank at byte 0.
- **Each of the 4 bytes** then takes three slots. `WAITC host_in_valid` at dl = 0 is a one-slot
  branch. Then comes `IN`, then `STB` into the data bank.
- **Only when all four are in**, `LDA 0; BANK 0` again, and four `LDB; SEND` pairs go to port 4
  (left) or 5 (right). The port glue sends a port's first byte as the feed's low byte and its
  second as the high byte, which commits the word (E2). Both channels therefore commit in the
  same sample period: a stereo frame is never torn. The first version sent each byte as it
  arrived, and the review (below) showed that a stall between L and R would commit L alone.
- **LDD** re-arms the deadline (period / 4 - 26 slots), and `JMP` closes the loop.

**Underrun path U_k.** A missing byte k sends `OUT tag 1, imm k` to the host. U_k then reloads
the deadline so that it retries byte k at exactly the slot that byte would have had in the next
period; the bank pointer still points at byte k. The frame is delayed, never torn or dropped.

**Flow control.** The host link is a byte FIFO, 16 bytes in the simulation, which the host keeps
full at one byte per 8 clocks (`Dac.host_tick`). The chip pulls at its own sample clock, so the
host only has to stay ahead. 16 bytes cover 123 µs of host stall in mode A and 31 µs in mode B,
so a deeper FIFO (64+ bytes) is advisable for mode B. The depth is a host-link parameter
(architecture-v0 §2.7 has not designed it).

**Measured on the model with the RTL-checked array** (`results/pump_check.txt`, 800k clocks;
the host stalls from clock 400,000 to 520,000, starting between the left and the right half of
a frame):
- every commit lands at one phase of the sample period: phase 81 for the left, 97 for the right,
  in both modes;
- every sample period with a commit has exactly one left and one right commit: 0 torn frames,
  including mode B's stall, whose underruns were all at byte 2 (mid-frame);
- every sample lasts exactly 136 steps (mode A) or 34 (mode B);
- the pause gave 84 underrun reports, then one held run of 11,560 steps = 85 sample periods, and
  the stream continued with the next frame.

**Why hold.** Holding the last frame freezes the waveform, which is continuous in value, and the
stream resumes with the frame that would have come next. The result was measured on music with 8
gaps of 20 ms (`results/music.txt`, `wav/underrun_*.wav`). The high-passed peak at the gap edges
is +0.2 dB median against the gapless output (+3.0 dB worst), against +19.3 dB median and +33.7
worst for zero substitution.

Two things are left to the host. It knows where it is: an underrun is reported, and the bytes it
sent are its own.
- At the end of a stream it should fade to zero, because a held non-zero sample is a DC step
  into the coupling capacitor.
- If it skips ahead in the stream rather than resuming where it stopped, it should crossfade.

## 4. Analysis

**Chain.**
- `analysis/signals.py` makes the test signals and does the host's processing.
- `sim/main.exe render` runs the bit-exact fast model.
- `analysis/dac_common.py` models the pin and the filter, and computes the metrics.
- `analysis/analyse.py` runs it all: `uv run python analyse.py tones|impair|music`.
- `levels.py` and `figures.py` make the level sweep and the figures.

**Measurement.**
- THD+N and DR follow AES17 in spirit: 997 Hz; 20 Hz-20 kHz brick-wall in a Kaiser-windowed
  (β 38) FFT of 65,536 points at 93.75 kHz, after the analogue filter; the fundamental's ±40
  bins notched; A-weighting where stated.
- DR = THD+N at -60 dBFS + 60.
- "SNR idle" is the power of a 0 dBFS sine over the in-band noise with digital silence in.
- The signals carry 16-bit TPDF dither, as a CD master would, and the host's rounding to the
  modulator's scale adds its own TPDF dither.

**Mode B's host processing:**
- 4× oversampling with a 307-tap Kaiser FIR (passband 20 kHz, stopband from 24.1 kHz);
- requantisation to the modulator's scale with third-order error feedback, NTF (1 - z⁻¹)³, with
  dither;
- per channel that is about 11 M multiply-accumulates per second, a small fraction of an
  RP2350 core (est).

This is the Bitstream recipe: a digital interpolation filter ahead of the noise shaper. The
filter runs on the host because the PEs have no multiplier, and because the 16-bit datapath
makes linear interpolation on the PEs cost log2(R) bits at R = 136. Linear interpolation was
worked through and rejected: a CIC-2 interpolator has gain R, and a DDA needs 24-32-bit
accumulators fed by a 16-bit token.

### 4.1 Ideal pins (`results/tones.txt`)

| order, mode | THD+N at -1 dBFS | THD+N at -20 dBFS | DR (A-weighted) | SNR idle | H2 / H3 at -1 dBFS |
|---|---|---|---|---|---|
| 2, A | -77.8 | -58.6 | 78.8 (80.6) | 77.9 | -102 / -100 |
| 3, A | -75.4 | -56.3 | 76.3 (77.9) | 76.4 | -98 / -99 |
| 4, A | -69.9 | -50.9 | 70.9 (72.4) | 70.9 | -92 / -91 |
| 2, B | -85.5 | -66.6 | 85.7 (90.9) | 91.0 | -115 / -114 |
| **3, B** | **-91.9** | **-72.9** | **92.7 (95.4)** | **93.0** | -115 / -116 |
| 4, B | -90.0 | -70.9 | 90.9 (94.7) | 90.9 | -115 / -115 |

The limits differ by mode:
- **Mode A is the input word's dither noise.** The word is 12-13.5 bits. All three are within
  1 dB of the arithmetic for TPDF-dithered words of that size (order 3: a 3,936-LSB sine against
  0.25 LSB² of noise across 0-22 kHz gives 76.4 dB).
- **In mode B:**
  - order 2 is limited by its own noise shaping at an oversampling ratio of 150;
  - orders 3 and 4 are limited by what is left of the host's shaped requantisation noise
    together with the modulator's.

  Order 3 is the best compromise on 16 bits. Order 4 is quieter in the loop but has 5.5 dB less
  input range.

**Images of the 44.1 kHz hold** (`results/filter.txt`), for a 997 Hz tone after the analogue
filter:
- mode A puts images at 43.1 and 45.1 kHz at -37 dB: outside the audio band, but there;
- mode B has them at -99 dB;
- mode B's own hold images at 175.5 kHz are at -80 dB.

The spectrum of the bitstream for each order is in `results/spectra.png`.

### 4.2 Pin impairments (`results/impairments.txt`; all three orders, mode B)

**The model.** The audio band sees only each step's area in volt-seconds, so every impairment is
an area error per step (`dac_common._areas`):
- **jitter:** an edge displaced by dt changes the area by ∓V·dt. The model is white per-edge
  jitter, the worst case; a PLL's low-frequency wander matters much less;
- **rise/fall asymmetry:** δ = t_f,eff - t_r,eff adds V·δ/2 per edge, so the error is
  proportional to the number of transitions;
- **supply noise:** the high level is the IO rail. The noise is low-pass at 100 kHz and given by
  its in-band rms;
- **aggressor bounce:** 8 pads switching with random data at the audio edge move it by
  kd × bounce, with 0.4 V p-p bounce from the fast-ethernet pad study
  (`../fast-ethernet/README.md`);
- **differential:** the pin and its complement, subtracted;
- **RZ:** a 1 is high for the first half step.

Results for order 3:

| impairment | THD+N at -1 dBFS | DR | note |
|---|---|---|---|
| none | -91.9 | 92.7 | |
| jitter 10 / 30 / 100 / 300 / 1000 ps rms | -87.3 / -79.2 / -68.9 / -59.4 / -48.9 | 87.9 / 79.9 / 69.7 / 60.2 / 50.0 | -10 dB per decade, as the arithmetic says (100 ps: 3.3 V·100 ps/167 ns·√0.5 per step, white to 3 MHz, 0.67 % of it in-band, gives 71 dB against a 0.41 V rms full scale) |
| asymmetry 50 / 200 / 1000 ps | -84.3 / -72.9 / -59.0 | 83.6 / 72.6 / 64.4 | even order: H2 -88 / -76 / -62 dB |
| the same 200 ps, differential pair or RZ | -91.9 | 92.7 | cancelled. A pair has equal transition counts on both pins; RZ has two edges per 1 |
| jitter 100 ps, differential / RZ | -68.9 / -61.3 | 69.7 / 62.4 | a pair does not help against common clock jitter, and RZ is 7 dB worse (twice the edges, half the signal) |
| supply 1 / 10 / 100 µV in-band | -91.9 / -90.8 / -77.2 | 92.7 / 91.7 / 78.4 | the rail is the reference. A differential pair rejects the 10 µV case (-91.8) |
| shared rail, 8 pads, 0.4 V p-p, 1 / 0.3 ps/mV | -72.0 / -82.1 | 72.8 / 82.8 | the delay sensitivity is an assumption |
| quiet rail: 30 ps, 100 ps asymmetry, 3 µV | -76.1 | 76.0 | |
| shared rail: the same + 8 pads at 1 ps/mV | -70.6 | 71.2 | |

Orders 2 and 4 behave the same within 1-3 dB. Under any realistic pin impairment the order no
longer matters: **the pin, not the modulator, sets the quality.**

### 4.3 Music (`results/music.txt`, `results/wav/`)

The clip is a synthetic, freely usable 6 s stereo piece made in `signals.py`: piano-like
inharmonic notes and chords, bass, kick, snare, hi-hat, panning, peaks at -1 dBFS, 16-bit dither.
It went through the same chain, and the outputs are 48 kHz WAVs, 16-bit dithered and normalised
for listening (the numbers above come from the floating-point signal):
- `source_44k1.wav` is the source;
- `music_o{2,3,4}_modeB_ideal.wav` and `music_o3_modeA_ideal.wav` are the ideal outputs;
- `music_o3_modeB_quietrail.wav` and `music_o3_modeB_sharedrail.wav` have the impairments of
  the last two rows above;
- `underrun_{hold,zero}_o3_modeA.wav` are the underrun experiment.

## 5. Hardware notes

**Output filter (per channel; the simulated one).**
- The pin drives R1 = 1 kΩ into C1 = 2.2 nF to ground: a pole at 72 kHz, and a 3.3 mA peak
  load, which also slows the pin's own edges into a capacitor rather than into the cable.
- A unity-gain follower buffers it.
- Then comes a unity-gain Sallen-Key Butterworth at 40 kHz: 10 kΩ, 10 kΩ, 560 pF in feedback,
  270 pF to ground. Use C0G capacitors and thin-film resistors: a 1-bit DAC's linearity is the
  filter's.
- The response (`results/filter.txt`): -0.5 dB at 20 kHz, -20 dB at 100 kHz, -81 dB at 1 MHz.
- The residual ultrasonic noise at the output is 0.22 mV rms idle and 0.69 mV rms at -1 dBFS,
  against 369 mV rms of signal: harmless for a line input, but a reason not to drive a class-D
  amplifier's input directly without more filtering.
- The model takes the RC as unloaded; with a 1 kΩ source and 10 kΩ next, the second stage's input
  loads it by about 10 %, which shifts the ultrasonic corner, not the audio band.
- The DC block is 10 µF film into 47 kΩ (0.34 Hz).

**Level.**
- Full scale is 0.41 V rms single-ended from a 3.3 V pin: the pin swings 3.3 V, and the full
  scale is 0.355 of the feedback.
- For CD line level (2 V rms), give the Sallen-Key stage a gain of about 5. A gain of 2.5 is
  enough for a differential pair through a difference amplifier.
- **Headphones** (32 Ω, about 1 V rms): an op-amp that can drive the load, such as an OPA1622
  or NJM4556A, after the filter, with 10-22 Ω in series and the DC block before it. For the
  fully differential option, the difference stage itself can be that driver.

**What limits quality on real pins, and what to do.**
- **The pin's high level is the reference.** The IO rail's noise and droop multiply the signal
  (the 100 µV row: 78 dB). Ground bounce from pads switching on the same rail moves the audio
  edges (72-83 dB at 0.3-1 ps/mV). The pad study measured 0.37-0.41 V p-p on IOVDD/IOVSS with 8
  HDMI pads switching together, so:
  - never run HDMI, 100BASE-FX or other fast pads at the same time as the DAC on a shared ring;
  - put the two audio pins next to a supply pad pair and far from the fast pins;
  - on a Tiny Tapeout die the ring's supply is not ours to separate.
- **So the recommended board circuit re-clocks and re-references outside the chip.** Feed each
  audio pin to the D input of a single flip-flop (74LVC1G79 or 74AUC1G79) on a quiet LDO (an
  LT3042-class regulator, µV noise), clocked by the board's 60 MHz. Its Q drives the RC.
  - The chip's IO ring then sets neither the edge times nor the high level.
  - What remains is the flip-flop's own asymmetry and the clock's jitter.
  - The flip-flop's Q and Q̄ give the **differential pair** for free. It cancels the asymmetry
    (the 200 ps row goes back to ideal) and low-frequency supply noise, though not common clock
    jitter.
  - The architecture's complementary-pair mode (SHO cp, architecture-v0 §2.2) can give the same
    pair from the chip directly; then the pair still shares the chip's rail.
- **Clock jitter is the number to buy:**
  - the RP2350's PLL output as the 60 MHz reference is unspecified here. Its white per-cycle
    jitter must be well under 30 ps for an 80 dB DR;
  - a 60 MHz crystal oscillator clocking both the RP2350 (as its reference) and the re-clocking
    flip-flops is the safer board choice;
  - if a crystal oscillator replaces the RP2350 as the chip's clock source, the RP2350 then feeds
    the link in that domain.
- **RZ coding** (each 1 high for half a step) also cancels the asymmetry, but costs 7 dB against
  jitter. It would need the pin stage to AND the flag with a half-step strobe, which is not in the
  architecture.
- **The four-phase stage is not needed.** The modulator at 6 MHz already has an oversampling
  ratio of 150, and a faster rate only multiplies the edge errors.

## 6. Tie-in: optical in, one bit out

The S/PDIF work is on a separate branch; nothing here depends on it.

**Receive path.** S/PDIF is biphase mark, which the architecture's edge-tracking sampler already
lists among its modes (architecture-v0 §2.3). With it, the receive path is:
- the edge sampler;
- the matcher for the B/M/W preambles;
- the packer or a thread assembling 32-bit subframes;
- a thread that sends the 16 audio bits of each subframe on.

**The difficulty is the clock.** The incoming 44.1 kHz comes from the source's crystal and is
asynchronous to the chip's 60 MHz.
- The pump's fixed 1,360-clock instant would slip one frame about every 2.5 s at a 100 ppm
  difference. That is a held or dropped frame: no click with this pump's hold, but a periodic
  glitch.
- Committing each frame when it arrives instead puts ±1 step (167 ns) of timing error on the
  sample instants, which is far worse at high frequencies.

**The clean answer uses the RP2350 as the DSP, and it is mode B with one more step:**
1. the chip's receiver thread forwards samples to the host (OUT, 176 kB/s);
2. the host measures the ratio (frames received per chip-clock count);
3. it resamples asynchronously to the chip's 176,470.6 Hz, with a polyphase version of mode B's
   FIR;
4. it sends mode B words back into this pump.

The chip stays the timing master of the output, and the jitter of the S/PDIF link never reaches
the pins. The link then carries 176 kB/s up and 706 kB/s down. The PEs are all used by the
modulators at order 4, but at order 3 each run has two PEs spare. The receiver needs none (its
CRC-free path is the edge sampler, the matcher and a thread), so **an optical-in, one-bit-out
DAC fits beside order-3 modulators** with threads 1-3 free for the receiver.

## 7. Limits of this work, and open points

- **Nothing is measured on silicon or on a placed design.** The areas are Yosys syntheses of the
  PE and of a hand-written equivalent of the E1/E2 logic (`synth/rtl/seg_ext.v`). The array was
  not synthesised as a whole.
- **The impairment parameters are assumptions:** rise/fall asymmetry, pad delay sensitivity
  (ps/mV) and jitter. The sweeps show the sensitivities, not a predicted number. The pad study
  did not model supply inductance in its rise times.
- **The analogue model works per step.** Effects inside a step, for example an edge's shape
  interacting with the RC, enter only through the area, which is exact for the audio band. No
  op-amp nonlinearity, resistor or capacitor nonlinearity is modelled.
- **The host link** is a byte FIFO with a valid flag at 1 byte per 8 clocks (est), with the
  architecture's 4-bit link assumed behind it; its credit or ready signal back to the host is not
  designed.
- **Mode A's 76-79 dB** is the honest number for the 16-bit datapath with a 44.1 kHz link. Two
  ways to raise it were found but not built:
  - a 3-PE on-chip first-order requantiser (accumulate the words, mask the two low bits,
    difference) that would let the host send 2 fractional bits;
  - a 32-bit first integrator as a PE pair, which the token-per-step stream does not feed easily.
- **Idle tones:** the idle noise is listed (SNR idle), but no separate search for idle tones at
  very low DC inputs was made beyond the -100 dB sweep points.
- **The review:** one codex-luna pass (`results/codex-review.txt`), asked to refute five claims.
  - It found one real defect, the torn stereo frame on a mid-frame underrun. That is fixed
    (section 3) and re-tested.
  - It pointed out that "44.1 kHz" is 44,117.6 Hz. Mode A plays a 44.1 kHz file 400 ppm fast
    unless the host resamples; mode B's filter can absorb the ratio.
  - It could not refute the other claims. Its jitter arithmetic gives 81.5 dB at 30 ps against
    the measured 79.9.
  - It noted that the "2.5-4 bits of headroom" attribution comes from the first integrator's peak
    ratios in `results/design.txt` (5.7×, 8×, 14×), not from the level sweep. That is where the
    README takes it from.

## 8. Compressed audio in front of the DAC: IMA ADPCM and SBC (A2DP)

The scope extension asked for on-chip decoding on generic blocks. **What is built and checked:**
- **Bit-exact decoder models** (`sim/codec.ml`) for IMA ADPCM (WAV blocks) and for SBC: 8 and 4
  subbands; 4-16 blocks; mono, dual, stereo and joint stereo; loudness and SNR allocation;
  44.1 and 48 kHz. Their arithmetic is the arithmetic of the chosen blocks.
- **The SBC frame CRC-8 runs on the PE array model itself**, also in lockstep with the Hardcaml
  RTL.

**What is not:** the SBC synthesis filterbank does not run on the PEs, and the finding below
says why. aptX was not attempted. It is proprietary, its patent and licence status is
unverified here, and nothing in this directory implements it.

**Oracles** (`codec/run_codec.sh`, `results/codec/references.txt`):
- the streams are made from the synthetic clip with ffmpeg (adpcm_ima_wav) and BlueZ's sbcenc;
- the references are ffmpeg's decoders and BlueZ's sbcdec;
- sbcdec and ffmpeg agree with each other bit for bit on all four SBC streams. They are separate
  programs from one lineage, the BlueZ code, so this is one reference decoded twice, not two
  independent ones.

| stream | our decoder |
|---|---|
| IMA ADPCM, stereo, 1,024-byte blocks | **bit-exact** with ffmpeg (1,061,748 bytes) |
| SBC 44.1 kHz, 8 subbands, 16 blocks, joint stereo, loudness, bitpool 53 (the common A2DP high quality) | **bit-exact** with sbcdec and ffmpeg |
| SBC 48 kHz, 8 / 16, joint, bitpool 51 | **bit-exact** |
| SBC 44.1 kHz, 8 / 16, stereo, SNR allocation, bitpool 35 | **bit-exact** |
| SBC 44.1 kHz, 4 subbands, 8 blocks, dual channel, bitpool 20 | **bit-exact**, also with the CRC on the Hardcaml RTL in lockstep with the model (818,937 clocks, 0 mismatches) |

**Planted controls,** each caught (`references.txt`):
- the CRC byte of one frame flipped: that frame alone is rejected by the PE CRC;
- one scale-factor bit flipped: rejected, since the CRC covers the scale factors;
- a wrong bit allocation (the loudness offset of subband 0 off by one): 397,017 of 529,408
  samples differ, so the reference comparison fails;
- a fault in the PE CRC's result: every frame is rejected.

A rejected frame is skipped whole, using the length from its header, and the stream stays in
sync.

**End to end:**
- `wav/decoded_adpcm_o2_modeA.wav` and `wav/decoded_sbc_a2dp_j53_o2_modeA.wav` are our decoded
  PCM through the order-2 one-bit chain (ideal pins; the constant gain into the modulator folds
  into the decoder's last shift);
- the codecs' own loss against the source clip (`results/codec/chain.txt`) is a waveform SNR of
  32.9 dB for ADPCM and 31.7 dB for SBC at bitpool 53. That is a property of the codecs, not of
  the DAC.

### 8.1 IMA ADPCM on the sequencer and one PE

| part | block | cost |
|---|---|---|
| read the code bytes | thread, IN | ½ slot per sample |
| select the step terms | the thread branches on the nibble's bits (WAITC acc bit k at dl = 0, one slot each) and sends only the terms the nibble selects, from tables of step, step>>1, step>>2 and step>>3 in the data bank | 712 bytes of bank (4 × 89 × 2) |
| predictor | **one PE**: S ← sat(S + (g ? -A : A)), with g the sign bit through the segment's broadcast | 2.18 PE steps per sample, measured over the clip |
| step index | a second PE adds the index increment that the thread sends, with saturation clamping at 88 (the index kept at an offset of 32,679, so that 88 is 32,767); the thread clamps at 0 with one SKEQ. The tap's low byte, 0xA7 + index, is the bank address of the tables | 1 PE step per sample |

**The saturation argument.** The terms of one sample all have one sign, so the partial sums are
monotone. Saturating each add therefore equals the reference's single clip of the total. The
bit-exact match is the check; the model computes it this way.

**Thread cost:** about 27 slots per sample (est, not run: four branches, about seven slots per
selected term, the sign write and the index exchange). For stereo at 44.1 kHz that is about
2.4 M of a thread's 15 M slots/s, with 2 PEs per channel.

**What was not run** is the thread code itself and the bank layout. Eight byte tables addressed
by {page, 0xA7 + index} need eight pages, and the bank has four. A second index offset (another
PE and tap), or deriving step>>2 and step>>3 by X1 shifts in their own PEs, closes this. Neither
was built.

**Why the thread selects.** A PE has one condition g. The nibble's four bits cannot ride in the
token beside a 15-bit step, and the per-segment broadcast bits are written by the thread anyway.

### 8.2 SBC: what maps, and the finding that the filterbank does not

Measured per frame for the A2DP stream (44.1 kHz, 8/16, joint, bitpool 53: 119 bytes, 344.5
frames/s, 41 kB/s on the host link):
- 88 CRC bits;
- 246 elementary bit-allocation operations (compare, add, branch);
- 174 dequantisations, each a division by 2^b - 1;
- **6,656 multiply-accumulates**: 26 per output sample, of a 32-bit V by a 17-bit coefficient,
  wrapping at 32 bits.

| stage | block | rate at 44.1 kHz stereo | status |
|---|---|---|---|
| parse the header, joint bits, 4-bit scale factors and the fixed-width samples | a thread with the bit path (packer) or a deserialiser PE | about 1,000 fields per frame | modelled, not on the blocks |
| CRC-8 (x⁸+x⁴+x³+x²+1, init 0x0F) | **one PE in GF(2) mode**: S ← ((S << 1) \| 0) XOR (g ? 0x1D00 : 0), g = S[15] ^ data bit, the CRC in the high byte | 88 bits per frame. 179 array clocks per frame here, at two feed writes per bit; the bit-path CRC unit would take 88 | **run on the PE model and on the RTL**, bit-exact |
| bit allocation | a thread sequencing, with one PE as its adder and comparator through a feed and a tap | 85k operations/s; about 0.4 M slots/s at about 5 slots per round trip (est) | modelled |
| dequantisation | ((2a+1) << s) / (2^b - 1): a short series of shifted adds (x/(2^b-1) = Σ x >> kb, plus a correction), on 32-bit PE pairs | 60k/s, about 10 PE-pair steps each (est) | modelled |
| synthesis: 16×8 matrixing and an 80-tap window per block | **no PE configuration** | 2.29 M MAC/s | **not feasible on the array as specified** |

**Why the synthesis does not map.** The PE has no multiply. A constant multiply by shift-and-add
needs the coefficient in a static configuration (one PE per coefficient digit, and SBC has 208
coefficients). Bit-serial multiplication needs the operand that changes on every step either in
K, which cannot change while running, or as a bit stream on the lane, which only a thread writes,
one bit per mailbox write. At 26 MACs × 17 bits × 88.2k samples/s that is about 39 M bit-steps/s,
more than the mailbox and the threads together can deliver. The operands also have to stream
from memory at about 14 MB/s with a ring-buffer address pattern, which needs the bank-port
streaming features of gap G8 (not built).

**Memory per channel:**
- V: 160 words of 32 bits, 640 bytes as a ring, or 680 with the reference's 9-word copy;
- a 119-byte frame buffer;
- one block of dequantised samples, 32 bytes;
- coefficient tables, about 400 bytes, shared.

That is **about 1.9 KB for stereo, against the chip's 1 KB of gain-cell data bank**.

**What would make it fit:**
- **a multiplier.** One shared 16×16 MAC unit (mac16 with Booth, **17,004 µm²** synthesised,
  `../pe-synth/README.md`) fed by two bank streams does the bit-exact 32×17 product as two MACs:
  4.6 M of its 60 M MAC/s for SBC stereo;
- G8's bank streaming;
- 2 KB more data memory: two more 4-kbit banks or two 1 KB SRAM macros.

Without them, the realistic split decodes SBC on the host and streams PCM (sections 1-3).

### 8.3 The Bluetooth side (not built)

**Forwarding.** A Pico 2 W (RP2350 with a CYW43439) running an A2DP sink (for example
BTstack):
- receives AVDTP media packets: an RTP header, a 1-byte SBC media header with the frame count,
  then whole SBC frames;
- forwards the raw frames over the host link: about 41 kB/s at bitpool 53, 0.5 % of the
  link's estimated rate.

The chip's decoder finds the 0x9C sync word and uses the header for the length, as `codec.ml`
does.

**The clock.** As with S/PDIF (section 6), the phone's sample clock is asynchronous to the chip:
- with on-chip decoding the host never sees PCM, so it cannot resample;
- the options are the host dropping or repeating a whole SBC frame (2.9 ms, audible) when its
  buffer drifts, or a fractional trim of the pump's sample period, whose one-step timing error
  section 6 shows to be costly;
- with host-side decoding (the realistic split above), the host resamples into mode B.

## Files

| path | what |
|---|---|
| `sim/spec.ml`, `model.ml`, `upe_rtl.ml`, `rtlsim.ml`, `lockstep.ml` | the PE array, copied from `../unified-pe/verify` and extended (X1, E1, E2) |
| `sim/dac.ml` | the configurations, the fast model, the pump programme, the host FIFO, the system glue |
| `sim/codec.ml` | the IMA ADPCM and SBC decoders and the CRC-8 PE configuration (section 8) |
| `codec/run_codec.sh` | makes the test streams, runs the reference decoders and ours, the controls |
| `sim/main.ml` | `lockstep`, `controls`, `controls-new`, `check-fast`, `rtl-lockstep`, `pump-check`, `render`, `verilog-pe` |
| `sim/isa2.ml` | a symlink to `../../sequencer-v2/isa2.ml` |
| `run_rtl_lockstep.sh` | the DAC lockstep runs, niced, waiting while the load is above 20 |
| `analysis/` | the Python analysis (`uv run`); `explore_*.py` are the design exploration |
| `synth/` | the synthesis flow (copied from `../unified-pe/synth.sh`), RTL and reports |
| `results/` | every number above, and the WAVs |

**Build and run:**
```
cd sim; opam exec --switch=5.3.0 -- dune build ./main.exe
./_build/default/main.exe lockstep 200 400
cd ../analysis
uv run python levels.py
uv run python analyse.py all
uv run python figures.py
```
