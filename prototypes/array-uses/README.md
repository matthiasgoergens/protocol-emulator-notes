# What is the systolic array for? Candidate problems against upe_v0 and the RP2350 (2026-09-25)

The array is a solution in search of a problem. `notes/architecture-v0.md` §4a finds that no
protocol needs it, and that its value is in video (sprites and tiles), full-resolution
Ethernet-to-TV, GPS tracking and DSP at the pins. This study looks for problems beyond those
four. Each candidate is scored on four things:
- how it maps onto the unified PE **upe_v0** (architecture §2.4) and the 16-PE array;
- its throughput at 60 MHz;
- whether the **RP2350 host** could do it as well;
- its value as a demo, and the effort.

Two candidates are prototyped in OCaml on a cycle-exact model of upe_v0, with rendered output.

Every number points to a file in `results/` or `out/`, or is marked **est**. This study used
models only (the host machine was loaded), run one at a time under `nice ionice`.

## The short answer

- **Beyond the four known uses, only one candidate makes the array earn its area: a
  direct-sampling shortwave receiver.** An external 8-bit ADC is clocked at 60 MS/s, so it sees
  the whole 0–30 MHz band. Four PEs make one AM channel:
  - 16 PEs give four channels, which is 240 M sample-channels per second;
  - two Cortex-M33 cores manage 17.6 M, not even one channel at 60 MS/s (`results/evaluation.txt`,
    `results/host_cycles.txt`).

  It is prototyped (`ddc.ml`), and each channel recovers its station with correlation 0.985–0.999.
  It is still DSP at the pins, the fourth known use, fed by an ADC rather than a 1-bit pin. It
  needs eight input pins, and it inherits a −9.5 dB image from mixing with a square wave.
- **Everything else in the brief runs on the host.** For each candidate, one of three things holds:
  - the application's rate is a small fraction of what the RP2350 does (Viterbi for GNSS
    navigation data, PDM microphones, cellular automata, shortest paths);
  - a better host algorithm removes the brute force the array would do (Myers bit-vectors for
    edit distance, synchronous averaging for time-domain reflectometry, the GCD method for CRC
    recovery, hash chains for LZ);
  - the problem does not fit a PE with one 16-bit link and a static operation (dynamic time
    warping, Viterbi's add-compare-select, raycasting, Mandelbrot).
- **The prior art's two strongest small-array problems, Viterbi and Reed-Solomon, rank low
  on *our* PE.**
  - Viterbi's add-compare-select needs two operands per step and shuffle wiring. On upe_v0 it
    becomes a streaming design through the banks, of about 5 clocks per butterfly: about
    2× the host, and short of a 1 Mbit/s CCSDS link (est).
  - Reed-Solomon syndromes run about 3.6× the host (est), but no link we can reach needs them
    faster than the host computes them.
  - So neither is prototyped. Shipped ACS arrays are dedicated arrays of one ACS per state
    (`notes/prior-art-systolic-uses.md` §4), which ours is not.
- **At its best, the array is 1–4× the host on plain word arithmetic**, because 16 PEs × 60 MHz is
  about 1 G simple operations per second against 0.3–0.8 G for the RP2350. An order of magnitude
  appears only in three cases:
  - an operation the M33 lacks: ±1 multiply-accumulate on multi-bit samples, 9.6×; top-K
    insertion, 26×;
  - brute force that a better algorithm makes pointless: CRC search, 32×;
  - data at 60 MS/s that the host cannot touch: the receiver, 13.6×.
- **Verdict on size: these problems justify no growth beyond 16 PEs, and on their own about 8.**
  - Eight PEs keep a two-channel receiver, or the synthesiser at two voices plus noise.
  - Twelve or sixteen are justified, if at all, by the uses §4a already lists (video, GPS
    tracking), not by anything found here.
  - The architecture's fallback of cutting to 12 or 8 PEs if placement forces it (decision
    D15) costs nothing on this list except receiver channels.

## Evaluation table

`evaluate.ml` → `results/evaluation.txt`. The table's inputs:
- **Array rate:** PEs × 60 MHz divided by the PE-clocks per item of a upe_v0 configuration, which
  is "designed" where the architecture or a prototype gives it, otherwise est.
- **Host rate:** two Cortex-M33 cores at 150 MHz, from the static cycle count of the kernel's
  inner loop (`host/kernels.c`, `host/mca.py` → `results/host_cycles.txt`: llvm-mca 22.1.8,
  `-mcpu=cortex-m33`, no unrolling). The "+2" column adds a taken-branch penalty the model
  does not charge.
- **Need:** the rate the application requires.

The host figures are a pipeline model with single-cycle SRAM, not a measurement on an RP2350.
Throughputs are rounded; the file has the exact figures.

| workload | fit to upe_v0 | array, 16 PEs | host | ratio | need | who should do it | demo value | effort |
|---|---|---|---|---|---|---|---|---|
| **HF AM receiver, 8-bit ADC at 60 MS/s** (prototyped) | 4 PEs per channel: NCO + accumulating square-LO mixer, for I and Q | 240 M sample-ch/s | 17.6 M | 13.6 | 60 M per channel | **array** | high: shortwave radio from a Tiny Tapeout chip | done as a model; needs the ADC on 8 input pins |
| 1-bit correlation (GPS tracking, binary NN) | designed (gps) | 960 M MAC/s | 768 M | 1.2 | 236 M (GPS) | host on paper, see note | known use | done elsewhere |
| multi-bit × ±1 code (DSSS) | designed | 960 M | 100 M | 9.6 | none found | host | low | low |
| edit distance | needs a second link; est | 7.5 M rows | 10.3 M (Myers) | 0.7 | none found | host | low | high |
| **Viterbi K=7 (CCSDS)** | no direct fit: bank streaming, two passes, per-word control bits; est | 18 M butterflies/s (bank-bound) | 8.3 M | 2.2 | 32 M at 1 Mbit/s; 8 k for GNSS | neither at 1 Mbit/s; host for GNSS | medium (the prior-art favourite) | high, and it needs extensions |
| dynamic time warping | does not map (one link, static op) | 192 M with a second link (est) | 14.3 M | 13.4 | none at a rate | host | low–medium (timing fingerprints) | high |
| min-plus relaxation | designed, 2 PEs | 240 M | 30 M | 8.0 | 6.6 M (est) | host | low | low |
| polyphonic synthesis (prototyped) | 3 PEs per 32-bit square voice, 2 per noise voice, 1 sigma-delta | 4 voices + noise at 60 MHz | 568 voices at 48 kHz | — | 16 voices | host could; array is self-contained | medium: audible, chiptune | done as a model |
| 1-D cellular automaton | GF(2), est | 80 M | 16.7 M | 4.8 | 0.125 M | host | medium on a TV | medium |
| Mandelbrot | no multiplier, est | 18.5 M it/s | 14.3 M | 1.3 | 49 M | neither | high | not worth it |
| Reed-Solomon syndromes | GF(2) mode, est | 107 M | 30 M | 3.6 | none reachable | host | medium | medium |
| CRC polynomial search | designed | 960 M | 30 M | 32 | one-off | host, by the GCD method | low | low |
| raycaster | no fit (branchy DDA) | — | 27 M steps/s | — | 0.26 M | host (+ a bank line buffer) | high | medium, but no array |
| LZ77 match | 32-byte window, est | 480 M | 30 M | 16 | — | host (hash chains) | low | — |
| PDM decimation | designed | 40 M bytes/s | 37.5 M | 1.1 | 0.38 M | host | low | low |
| top-16 of a stream | designed | 960 M | 37.5 M | 25.6 | 60 M | array only for rising data | low | low |

**Candidates added and dropped without a host kernel:**
- **Spread-spectrum time-domain reflectometry** (a cable-fault finder on the Ethernet pins):
  the probe is periodic. Folding the captured bits by period and then correlating once does the
  same work with L/16 fewer operations than 16 correlators do (L is the code length). One PE and
  a bank, or the host through a PIO capture (`k4_fold`, 8 cycles per 32-sample step), do it
  easily. It is a good debugging demo, but not an array job.
- **Coincidence counting, TCSPC and SPAD time-of-flight histograms:** the events are sparse,
  so timestamps from the pin stage and histograms on the host beat dense per-clock
  accumulators.
- **Phased ultrasonic arrays and multichannel DDS/AWG:** one NCO PE per output would do. The
  RP2350's PIO plays precomputed periodic patterns just as well.
- **Keyword spotting:** a binary-weight network of a few M MAC per inference, against the
  host's 768 M binary MAC/s.

**GPS note:** the correlation row counts only the multiply-accumulates. On the host, GPS
tracking also generates each channel's carrier and code sign per sample. That is about
3 cycles per sample per channel (est), about 120 M cycles/s for 12 channels. So the host total
is about 60 % of both cores (est), consistent with gps's "most of its cycles". The array keeps
it as a known use; nothing here changes that.

## Prototype 1: a four-channel shortwave AM receiver (`ddc.ml`)

The scene is shortwave radio from a chip whose clock is also the ADC clock:
- an 8-bit ADC at 60 MS/s, so the whole 0–30 MHz band is visible at once;
- three AM stations 50–105 kHz apart in the 49 m band, each carrying its own programme;
- one strong station at 18.450 MHz;
- Gaussian noise, and 8-bit quantisation (3 of 72 M samples clip, `results/ddc.txt`).

**Configuration** (16 upe_v0 PEs in one chain; the sample walks through all of them, P ← A):
- **For each of four channels, four PEs:** an NCO (S ← S + K wrapping, lane out = S[15]), then an
  accumulator S ← S + (g ? −A : A) with g = the lane. That one PE both mixes with a square-wave
  LO and integrates, as the first stage of a CIC filter.
- **The same pair again for Q:** its NCO starts a quarter turn ahead, less two steps for the two
  clocks by which the sample arrives later.
- **Host side:** every 240 clocks the host reads the eight accumulators and differences them, a
  boxcar decimator to 250 kS/s. Then, per channel, a 5 kHz filter and an envelope detector
  produce audio at 50 kS/s.
- The PE model is the lockstep-checked one (below). Nothing about the PE is invented, except
  the assumption that the ADC's eight pins can drive a segment feed.

**Results** (`results/ddc_check.txt`, an independent numpy check that fits each channel's audio
against each station's programme):

| channel | tuned to | its own station: correlation, signal/residual | other stations: largest correlation |
|---|---|---|---|
| 0 | 5.950 MHz (melody) | 0.999, 27.8 dB | 0.009 |
| 1 | 6.000 MHz (two tones) | 0.985, 15.2 dB | 0.017 |
| 2 | 6.055 MHz (chirp) | 0.998, 23.3 dB | 0.018 |
| 3 | 6.150 MHz, an empty frequency | the 18.450 MHz station, 0.999 | 0.003 |

- **Planted fault:** with the model's "negate by g" disabled, every channel's correlation with
  every station falls to at most 0.05 (`results/ddc_fault_check.txt`). The check can fail.
- **The price of mixing without a multiplier, measured:**
  - The 18.450 MHz station appears on the empty channel 3 at 0.336 of the gain of a directly
    received one, per carrier count: −9.5 dB, the square wave's third harmonic (1/3).
  - Channel 1's weaker figure is a second artefact of the same kind. Its LO period is 10
    samples, so the sampled square wave's 9th and 11th harmonics alias to within 3–4 kHz of
    6 MHz. The envelope then beats at 2,930 Hz, predicted to the hertz from the LO's tuning word
    (`results/ddc_spur.txt`).
  - A real receiver needs an 8 × 8 mixer at one segment start (not in upe_v0; est 2–3k µm²
    synthesised), or LO frequencies chosen away from 60/N MHz and a band-pass filter before
    the ADC.
- **Artefacts:** `out/ddc-ch0.wav` … `ddc-ch3.wav`, `out/ddc-spectrogram.png`, and the raw
  decimated I/Q for the first 20,000 frames in `out/ddc-iq.txt`.
- **What the RP2350 would need:**
  - The same loop per sample and channel (`k3b_ddc_cic1`) is 17 cycles, so 17.6 M
    sample-channels/s on both cores: 0.29 of one channel at 60 MS/s.
  - With SIMD and unrolling, perhaps 3–4 cycles (est), which is still one channel at most.
  - Capture alone, 60 MB/s through PIO and DMA, is plausible (est); the arithmetic is not.
  - The prior art is the KiwiSDR pattern (a fast ADC, an FPGA doing the down-conversion, a
    small computer doing the rest): from memory, not checked here.

## Prototype 2: a five-voice chiptune synthesiser (`synth.ml`)

**Configuration** (one 16-PE chain; the sum word walks down it and collects every voice):
- **4 square voices:** a 32-bit NCO from two PEs (low half: lane out = carry; high half: carry-in
  from the lane, lane out = S[15]), then P ← A + (g ? −K : K), with K the amplitude;
- **1 noise voice:** a Galois LFSR PE (x^16 + x^5 + x^3 + x^2 + 1), then the same ± PE;
- **an offset PE and a first-order sigma-delta PE:** the pin is the carry register, filtered by
  two RC poles at 20 kHz and sampled to 48 kHz.
- **The tune:** 4 s, with notes and envelopes changed every 4 ms by reloading the configuration
  (`out/synth-*.wav`, `out/synth-spectrogram.png`).

**Independent check** (`analyse_synth.py` → `results/synth_check.txt`):
- The WAV is fitted by least squares against four floating-point square-wave voices synthesised
  from the schedule that the run logged.
- Every voice comes out at 29,720–30,017 against an ideal 30,000.
- Control: shifting the melody's reference by a semitone drops its gain to 131.

**A finding for the architecture: reconfiguring a running segment is not free.**
- **The setup:** the host changes K (pitch or amplitude) by shifting the whole segment chain, 128
  bytes at the link's estimated 7.5 MB/s. The segment is stopped meanwhile: 1,017 clocks
  (17 µs) per change, 0.42 % of the time at 250 changes per second (`results/synth.txt`). Every
  reload leaves exactly the intended configuration (0 mismatches, `results/synth-hold.txt`, `synth-toggle.txt`).
- **The cost:** 1,000 stops of 17 µs cost 16 dB in tonal signal against residual (25.0 dB
  when the change is instant, 8.8 dB when the pin shows whatever the half-shifted configuration
  produces, 7.3 dB when the pin holds its last bit). The loss comes from the pin's full-scale
  level during the stop.
- **A pin that toggles while its segment is paused** (the modulator's zero) recovers 22.5 dB
  (`results/synth_check.txt`). The same variants are audible in `out/synth-chain*.wav`.
- **The phase slip remains:** the stopped NCOs lose 17 µs of phase per change. The reference
  must model it: without it the fit collapses to −18.8 dB.
- **Suggestion, est:** a shadow K register per PE with a segment-wide commit strobe, 16 flops
  ≈ 0.8k µm² synthesised per PE, would make pitch, amplitude, NCO and receiver retuning free. It
  is cheaper than double-buffering the whole 64-bit configuration (≈ 3.1k µm²).

**Against the host:** the RP2350 synthesises hundreds of voices at 48 kHz (`k9_voices`, 11
cycles per voice-sample). The array's case here is only that the chip plays music by itself, at
a 60 MHz one-bit output that needs no DAC. It is a good, cheap demo, not an area argument.

## The PE model and its check (`upe.ml`, `lockstep.ml`)

- **`upe.ml`:** a cycle-for-cycle transcription of `../unified-pe/rtl/upe.v` with
  `-DNO_POP -DNO_LUT -DBITSEL` (upe_v0). It includes the 8-byte configuration chain, so it
  models what a PE does while it is being reconfigured.
- **`row.ml`:** the segment wiring as architecture §2.4 describes it: A and valid from the left,
  the lane, the pair wires, carry-back from the right, and the configuration chain.
- **`lockstep.ml`:** compares every output on every cycle against the Verilog under Icarus 13.0,
  on three seeds of 20,000 random cycles. The stimulus has random op words (every mode,
  including unused encodings), configuration bursts shifted while the PE runs, clears and init
  strobes.
  - **Result:** 0 of 59,976 cycles differ.
  - **Planted fault:** with "negate by g" disabled, 9,509 differ (`results/lockstep.txt`).
  - This is a first step on gap G1 (an executable specification for upe_v0), for a single PE.
    The row wiring is not lockstepped against RTL; the two prototypes check it end to end
    instead.
- **Observation:** `clear` does not reset the configuration chain, so a PE's outputs are
  unknown (x in simulation) until its first configuration is shifted in. That is harmless if the
  loader always runs first, but it is worth a line in the verification plan.

## Why the rest does not fit, in one paragraph

upe_v0 is a stream machine with one 16-bit word in and one out per clock, and one configuration
at a time. Dynamic programming wants two or three operands per cell per step: DTW, edit
distance, and the Viterbi ACS with its two path metrics and its shuffle. Each attempt to map
them needed per-word behaviour that the static op word cannot give:
- **Viterbi, attempted in detail:** it works only if the bank supplies control bits beside each
  metric and writes half-words, with two passes per decoded bit.

A cheap extension would be a second input link, or a lane bit that selects between two op
words (est +2.4k µm² per PE). It would bring DTW to about 13× the host (est). But no rate-bound
application for DTW was found, so this study does not recommend that extension.

## Files

| file | what |
|---|---|
| `upe.ml`, `row.ml` | the upe_v0 model and the segment wiring |
| `lockstep.ml`, `rtl/tb_upe.v` | lockstep against `../unified-pe/rtl/upe.v` (`main.exe lockstep 20000`) |
| `synth.ml`, `analyse_synth.py` | prototype 2 (`main.exe synth 4.0 out`; `SYNTH_ONLY=direct\|chain\|hold\|toggle`) |
| `ddc.ml`, `analyse_ddc.py`, `spur_check.py` | prototype 1 (`main.exe ddc 1.2 out`) |
| `evaluate.ml` | the table (`main.exe evaluate`) |
| `host/kernels.c`, `host/mca.py` | host inner loops and their llvm-mca cycle counts |

Build: `opam exec --switch=5.3.0 -- dune build`. Analyses: `uv run --with numpy --with scipy
--with matplotlib analyse_synth.py out results/synth_check.txt`, and the same for
`analyse_ddc.py`.

## Open

- The host numbers are static models. One run on an RP2350 (the demo board's own chip) of
  `k1b`, `k3b` and `k6` would pin the ratios.
- The receiver assumes the ADC's pins feed a segment directly. The architecture's pin stage and
  feed would have to allow 8 parallel input bits per clock.
- The Viterbi and DTW mappings are sketches with estimated clock counts, not models.
