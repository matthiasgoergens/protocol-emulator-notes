# GPS hot/cold: a geocaching gadget from the generic blocks (2026-09-25)

A gadget that tells you by sound whether you are getting closer to a cache. Two tiers:

1. **Tier 1 (works in simulation, end to end):** an off-the-shelf GPS module sends NMEA at 9600
   baud. A sequencer thread receives it; the host MCU parses it and computes distance and
   bearing in integer arithmetic; two PEs per ear and the pin's XOR drive a speaker through an RC
   filter. Beep rate means distance, beep shape means warmer or colder, and stereo gives
   direction.
2. **Tier 2 (feasible, modelled bit-exactly):** a raw 1-bit GPS front end feeds the chip. The
   PE array, configured as a correlator, does acquisition and tracking. The host does the loop
   filters and the position. A synthetic sky yields a position fix.

Everything is a **configuration of the generic blocks**: the four-thread deadline sequencer,
the pin sampler, the PE row (`../pe-synth`'s pe16), the sample banks (`../systolic-storage`),
and the multiphase stage's XOR output. It needs one small PE extension (the "tag lane", below)
and one small generic assist (an LFSR/CRC generator). All of it is simulation. Every number
points to a file in `results/`.

## Tier 1: NMEA to audio

### Mapping

| function | block | configuration |
|---|---|---|
| UART receive, 9600 8N1 | sequencer thread 0 | 16-word programme (`seq/uart_rx.ml`): poll for the start edge, check mid start bit, 8 × SHI at mid-bit, check the stop bit, OUT the byte to the host |
| NMEA parse, checksum, distance, bearing, trend, sound plan | host (RP2350) | `tier1/navfix.py`, `tier1/sonify.py`: integer only |
| tone | 1 PE per ear | NCO: wrapping add of k, enabled every 256th clock (255.75 kHz); tag_out = MSB, a square wave in 3.9 Hz steps |
| volume and envelope | 1 PE per ear | first-order sigma-delta: wrapping add of A', enabled every 16th clock (4.092 MHz); tag_out = carry |
| pin | output stage | XOR of the two tag outputs, as the multiphase stage combines its lanes: a square wave of amplitude 1 − 2A' (A' = ½ is silence) |
| speaker | board | two RC poles at 6 kHz, then an amplifier or piezo |

The PE array cannot parse NMEA: it has no byte compare, no multiply and no shift. Neither can
the sequencer, which has no arithmetic. The parse is a string job, and it goes to the RP2350
on the demo board. It is one checked sentence a second, so there is no point in hardware for it.
The audio needs only the tag-lane extension (wrap and tag_out); nothing new.

Clock: 65.472 MHz = 4 × 16.368 MHz. That is tier 2's front-end clock, and it makes a 9600 baud
bit exactly 1705 slots. The sequencer closes 66 MHz (`../deadline-sequencer`).

### Results

- **UART receive on the sequencer** (`results/tier1/uart_rx_*.txt`):
  - Interpreter: the first 5,000 bytes of the NMEA stream, sent back to back, came back 5,000
    of 5,000 correct (341 M cycles).
  - RTL (Cyclesim) in lockstep with the interpreter, 24 bytes: 0 mismatching cycles.
  - Baud error sweep (60 bytes back to back, 4 start phases): no errors from −5 % to +5 %, all
    bytes wrong at ±6 %. That is the textbook tolerance of mid-bit sampling.
- **Parser** (`results/tier1/check_nav.txt`): the parser agrees with pynmea2 1.19.0 on all
  701 RMC sentences of the walk. It compares time, validity, and latitude and longitude exactly
  in 10⁻⁵-arcminute units, plus speed and course. Both reject the one sentence with a flipped
  bit. Control: with our checksum test disabled, 702 sentences are accepted, so the checksum is
  what rejects it.
- **Precision of the integer navigation** (`results/tier1/check_nav.txt`).
  - Method: coordinates in 10⁻⁵ arcminute. The host computes two Q16 scale constants once per
    cache, from the WGS84 radii at the cache. From each fix: one 32×32 multiply per axis, a
    20-step vectoring CORDIC for range and bearing, and one Q16 gain multiply.
  - Reference: geographiclib's geodesic, over 4,000 random pairs at 1–500 m at each of six
    latitudes.
  - Arithmetic alone:
    - distance error ≤ 1.6 cm up to 45°, and ≤ 3.3 cm at 75° (the flat-earth approximation);
    - bearing error ≤ 0.07° beyond 5 m.
  - Including the NMEA rounding: distance ≤ 3.8 cm with 5-decimal modules (NEO-6M style),
    ≤ 24 cm with 4-decimal ones.
  - GPS itself is 2–5 m, so the arithmetic is not the limit.
  - Control: scaling east by cos 0° instead of cos(lat) gives errors up to 185 m at 45°, and
    the check shows it.
- **Walk and audio** (`results/tier1/hotcold.png`, `plans.csv`, `audio_checks.txt`).
  - The walk: a synthetic 702 s walk in Singapore. It starts 450 m out, heads the wrong way,
    turns, zigzags in, overshoots and stands at the cache. GPS error is Gauss–Markov
    (σ 2 m, τ 60 s) plus 0.7 m white noise. Distance against the true position: rms 1.96 m,
    max 5.4 m.
  - The integer distance agrees with the geodesic of each reported fix within 2.2 cm.
  - The rendered audio, measured from the outside:
    - silence between beeps: −106 dBFS;
    - beep pitch within 0.33 % of the plan over 619 beeps;
    - beep period from onsets within 0.1 ms of the plan;
    - stereo level ratio within 0.14 dB (95 %) of the planned pan.
  - An earlier run in which the plans were off by one second after the dropped sentence failed
    these checks by 99 % in pitch and 320 ms in period. The checks can fail.
  - Clips (22 kHz stereo WAV):
    - `results/tier1/audio/clip1_start_colder.wav`: no fix, then walking away;
    - `clip2_warmer.wav`: approaching;
    - `clip3_arrival.wav`: the last approach and the "found" warble.
  - The full 702 s render is reproducible (`tier1/sonify.py`) and was not committed (62 MB).

### The sound design

| cue | encoding |
|---|---|
| distance | beep period 85 ms × √(d / 1 m): 150 ms at 3 m, 270 ms at 10 m, 600 ms at 50 m, 1.9 s at 500 m (a 48-entry ROM in half-octaves of d) |
| found | under 6 m, a continuous 1320/1760 Hz warble. Under 6 m, not 4 m, because standing still at the cache the fixes scatter 3–5 m (`plans.csv`) |
| warmer / colder | smoothed distance falling or rising by more than 2.5 m in 5 s (leaving below 1 m: hysteresis). Warmer is two notes up (880 → 1320 Hz), colder two notes down (440 → 330 Hz), neutral one 660 Hz note |
| direction | target bearing minus course over ground, 16 sectors, constant-power stereo pan. Behind you, both ears are quiet. No cue under 0.4 m/s, where course over ground is noise |
| no fix | a soft tick every 3 s |

## Tier 2: raw GPS on the chip

### Signal chain and mapping

The front end (MAX2769-class; see the parts list) gives one-bit samples at 16.368 MHz with the
IF at 4.092 MHz (fs/4). Our blocks:

| step | block | configuration, and why |
|---|---|---|
| capture | pin sampler, timed mode, period 20 clocks | keeps every 5th front-end sample: **3.2736 MS/s**. The IF aliases to 818.4 kHz, which is fs/4 again. That gives 3.2 samples per chip, non-commensurate, so code phase is not stuck on a grid. **1 ms is 3,274 bits: one 4 kbit bank.** No decimation logic at all; the cost is measured below (2.3 dB) |
| sample store | two sample banks, 4 kbit each | double buffer: capture into one, replay the other many times at the clock rate |
| carrier NCO | 1 PE per arm (acquisition), 2 per arm (tracking) | wrapping add of k; tag_out = MSB. 16 bit (50 Hz steps) is enough for acquisition. Tracking needs 32 bit: two PEs, with the carry through the tag. The Q arm's NCO starts a quarter turn ahead |
| carrier wipe-off | 1 PE per arm | x = the sample as ±1, y = 0; the tag (the NCO's MSB) negates x |
| correlators | K PEs per arm | x = neighbour, y = state, add; the tag (the broadcast code chip) negates x. The wiped sample walks one PE per clock, so PE j integrates code offset j |
| code generator | 1 PE (2 for tracking) plus an LFSR assist | code NCO: wrapping add of k = 20480 (exactly 5/16 chip per sample); its carry steps a G1/G2 LFSR loaded by the host |
| detection, loops, navigation, position | host (RP2350) | I² + Q², non-coherent sums and peak search; FLL/PLL/DLL filters at 1 kHz; bit sync, parity, TOW; least squares |

`tier2/pe_array.py` models the row clock by clock, pe16 with the extension.
`acq.py verify` checks it against the closed form and against the FFT-based search that the
Monte Carlo uses. Over six passes (K = 16, both arms, including a full 3,274-sample block) there
are 0 mismatches. With the correlators' tag negation disconnected, 7 of 8 sums differ
(`results/tier2/acq_verify.txt`). So the Monte Carlo's numbers are the numbers the PE row would
produce.

**The limit of that check** (raised by the codex review):
- `pe_array.py` is a Python model of pe16's datapath semantics plus the proposed extension. It
  is not pe16's RTL.
- It has no `en` input (every PE is enabled every clock in this use), and it does not model
  configuration or readout.
- The extension does not exist in RTL yet.

So the check proves that this configuration computes the correlation. It does not prove
equivalence to pe16. The next step is extension RTL, and lockstep of that RTL against this
model.

### The PE extension: a one-bit tag lane

pe16's op is static configuration, so it cannot multiply by a data-dependent ±1. Every Gold-code
correlation needs exactly that. The smallest generic fix is one bit that travels beside the
16-bit neighbour word:

- **tag_in:** from the left neighbour, or from a row-wide broadcast line (1 configuration bit);
- **tag use:** none, negate the neighbour operand, or carry-in (2 bits);
- **wrap:** a wrapping add instead of a saturating one (1 bit);
- **tag_out:** tag_in (registered), state MSB, or carry out (2 bits).

Three of these six bits fit in pe16's unused op-byte bits 7:5. The other three need a fourth
configuration byte, or a narrower tag_out encoding.

- **Cost: an estimate of about 510 µm² synthesised per PE, +8 %.**
  - The parts: 16 XOR2 (232 µm²), one tag flop (49), three configuration flops (147), and a few
    muxes (about 80), from LEF areas (`../systolic-storage/results/lef_areas.txt`).
  - Not synthesised: the host is loaded, and this study is models only.
- **Other uses**, all from the same bits:
  - ±1-code correlators: Barker and m-sequence ranging (ultrasonic, radar), CDMA, DSSS sync;
  - a soft-decision version of the systolic matcher (multi-bit samples, ±1 template);
  - binary-weight neural layers: XNOR-accumulate is negate-accumulate;
  - Walsh–Hadamard transforms;
  - PDM microphone decimation: an integrator of ±1 is s ← s ± 1. This is the noise-cancelling
    demo's input;
  - quadrature-encoder and up/down counters;
  - NCOs and phase accumulators (wrap and MSB out), for FM/AM tone synthesis and the tier 1
    audio;
  - first-order sigma-delta DACs (carry out);
  - multi-word arithmetic: 32-bit accumulators from two PEs, with carry through the tag.

**The LFSR assist** is a configurable-polynomial shift register, loadable by the host, stepped
by a tag. Estimate: about 3.5k µm² with a 32-bit register and a latch tap mask. It is the
same block as a CRC-16/CRC-32 generator (USB, Ethernet), a PRBS source for link tests, and a
scrambler or whitener.

### Acquisition results

- **Implementation loss** (`results/tier2/acq_loss.txt`): coherent 1 ms at 45 dB-Hz, over 200
  blocks.

  | receiver | loss |
  |---|---|
  | float receiver after the 2.5 MHz filter and the 1-of-5 subsampling | 2.33 dB below C/N0·T |
  | one-bit samples | a further 2.06 dB (theory: 1.96) |
  | one-bit NCO carrier | a further 0.88 dB (theory: about 0.9) |
  | **chip, total** | **5.3 dB** |

  The 2.33 dB is the price of subsampling without decimation logic: the filter's 2.5 MHz of
  noise and signal folds into a 1.64 MHz Nyquist band. I did not measure a narrower filter or a
  decimating front end, so how much of the 2.33 dB is recoverable is open.
- **Detection against C/N0** (`results/tier2/acq_mc.txt`, `acq_pd.png`).
  - Search: 21 bins × 500 Hz, 3,274 code offsets. PRN, Doppler and code phase are random.
  - Threshold: the largest peak/mean over 150 noise-only searches (Pfa below about 0.7 % per
    search).
  - Trials: 60 per C/N0 level.
  - 50 % detection at about **42 dB-Hz with 5 ms non-coherent** and about 40 dB-Hz with 10 ms.
    90 % at about 44 and 42.
  - Open-sky signals are typically 40–50 dB-Hz. So this acquires under open sky, and not
    indoors or under trees without longer integration.
- **Acquisition time and area** (`results/tier2/acq_timing.txt`).
  - Clock: 65.472 MHz. One pass replays a bank through two rows of K correlators, and a block is
    processed while the next one is captured.

  | K | PEs | chip time per PRN per 1 ms block | cold, 32 PRNs, N = 5 | warm, 8 PRNs, 9 bins, N = 5 | PE area placed (+ extension, + LFSR) |
  |---|---|---|---|---|---|
  | 4 | 13 | 868 ms | 139 s | 15 s | 142k µm² |
  | 8 | 21 | 437 ms | 70 s | 7.5 s | 226k µm² |
  | 16 | 37 | 221 ms | 35 s | 3.8 s | 396k µm² |
  | 32 | 69 | 114 ms | 18 s | 2.0 s | 736k µm² |

  - These are chip time only. The table excludes the host's peak search, the loading of NCO and
    LFSR start states between passes, and bank switching (codex review). The host work overlaps
    with the next pass, but the state loading does not; it is a few words per pass, so small
    against 3,300 clocks, and it is not counted.
  - "1 ms" blocks are 3,274 samples, which is 1.00012 ms.
  - Add 56k µm² for the two 4 kbit banks (placed).
  - Placed PE area is `../pe-synth`'s 9,852 µm² per PE, plus the extension at an assumed 1.5×
    placement ratio.
  - **K = 4 fits the ~14-PE arrays of `../systolic-storage` (D2): about 200k µm² with the
    banks.** It gives a 2.5-minute cold start and 15 s warm. K = 32 alone would fill the whole
    0.7 mm² of 6 × 4 tiles.
  - The array is shared with every other demo, so the GPS demo costs only the extension and the
    LFSR assist.
- **Tracking capacity** (`results/tier2/acq_timing.txt`, last line): a channel needs 14 PEs:
  - E, P and L on both arms (6);
  - two mixers (2);
  - 32-bit carrier NCOs, two PEs per arm (4);
  - a 32-bit code NCO (2).

  One replay of about 3,300 clocks per code period. 19 replays fit in a millisecond, so 12
  channels use 61 % of a 14-PE array's time. The rest is left for acquiring new satellites.
  - E and L are one sample (0.3125 chip) either side of P, because the data lane's pipeline
    register is the delay.
  - A code period does not align with the fixed 3,274-sample banks, so tracking reads across a
    bank boundary. It needs a third bank, or a replay window that spans two.

### End-to-end fix (`results/tier2/fix.txt`, `fix.json`, `fix.png`)

This is one scenario, one seed, from `tier2/fix.py`.
- **The sky:** seven satellites above 15° over the tier 1 cache, at 40.6–46.9 dB-Hz, with a
  −1.8 kHz TCXO carrier offset. 9.5 s of 1-bit samples at 3.2736 MS/s.
- **Acquisition** (chip arithmetic, N = 5 ms, the Monte Carlo threshold): 5 satellites found and
  no false ones.
  - Missed: PRN 2 and PRN 12, at 40.6 and 40.8 dB-Hz. This is consistent with the Monte Carlo's
    Pd of about 0.1 at 40 dB-Hz.
  - Acquired code phase within 0.43 chip and Doppler (after a 100 Hz refinement) within 105 Hz
    of the truth (`results/tier2/diag_track.txt`, from `tier2/diag_track.py`). The code errors
    are all the same sign (0.14–0.43 chip late), which is consistent with the IF filter's group
    delay. That delay is common to all satellites, so the clock term absorbs it.
- **Tracking.** Correlators: bit-exact integer E/P/L on 1-bit samples, with 32-bit carrier and
  code NCOs. Each NCO is two PEs, carry through the tag. Host loops, once per code period:
  - an FLL (first 300 ms);
  - a 15 Hz Costas PLL;
  - a 2 Hz carrier-aided second-order DLL.

  All 5 lock, with PLL phase error rms 11–19°. Bit sync histograms are clean (24/24, 25/25 …
  sign changes on one epoch). Every channel found subframe 1 with a parity-checked TLM and HOW,
  and decoded TOW = 408,090 s, which is the true value.
- **Ranging accuracy** against the true light time, common mode removed: per-satellite sd of
  1.4–3.2 m, and means within ±2.3 m.
- **Position:** 15 fixes every 100 ms over the last 1.5 s, from 5 satellites, HDOP 3.1,
  VDOP 4.2.
  - Horizontal error: mean 9.7 m, max 21 m.
  - Vertical rms: 15 m.
  - Range residual rms: 0.94 m.

  The error is ranging noise times a poor five-satellite geometry. It is not a bias of the
  method: the per-satellite means are metre-level.
- **Two bugs the truth comparison found:**
  - My first Q arm used +sin, so the Costas and FLL discriminators had the wrong sign. The phase
    error rms was 52°, which is uniform, and nothing decoded.
  - Then **16-bit** tracking NCOs (50 Hz and 50 chip/s steps) left the PLL unable to lock and
    wound up the DLL. **Tracking needs 32-bit NCOs.** That is why the carry-in tag mode is in
    the extension.
- **Assisted:** the host is given the true ephemerides, which the generator also uses. Receive
  time comes from the usual trick (t_rx = latest t_tx + 70 ms, the error going into the solved
  clock bias). So the fix tests code-phase ranging, TOW decode and the solver, not ephemeris
  decoding.
- **Not modelled:** multipath, ionosphere and troposphere, satellite clocks, ephemeris decode
  (assisted), the front end's AGC and 2-bit mode. Only one sky was run.

### Honest comparison: the naive thing

The RP2350 alone could capture 1-bit samples with PIO: 3.3 Mbit/s is easy. Acquisition by FFT
(one 4k-point complex FFT per Doppler bin per millisecond) is plausibly a few tens of
milliseconds per PRN per block on a 150 MHz Cortex-M33. That would beat K = 4 on this chip.
**This is an estimate: I found no measured Cortex-M33 FFT timing, and none was run here.** The
chip's advantage is continuous tracking. 12 channels × 6 correlators at 3.27 MS/s is about
240 M sign-accumulates per second. The chip does that in a fixed schedule on 11 PEs. A
Cortex-M33 would need bit-slicing tricks and most of its cycles. The demo's point is that a
programmable protocol chip's generic array does GPS at all, and deterministically. It is not
that a microcontroller cannot.

## Parts list

**Not verified live.** Web search was unavailable in this session (the session's quota was
spent, and vendor sites did not respond to fetches). Every part number below is from memory
and must be checked before ordering. Only the two dataset and PocketSDR facts at the end were
fetched.

| part | role | notes |
|---|---|---|
| MAX2769 (Maxim, now Analog Devices) GPS L1 front end | tier 2 RF to 1–2 bit samples | my recollection: SPI-configurable, preconfigured modes, 16.368 MHz TCXO, 1- or 2-bit sign/magnitude output, IF around 4 MHz. **The default IF and sample rate this model assumes (4.092 / 16.368 MHz) must be checked against the datasheet, as must lifecycle status and stock.** Successor: MAX2771 (L1/L2/L5) |
| alternatives | tier 2 | NTLab NT1065 (four channels), MAX2771. SiGe/Skyworks SE4110L appears delisted (its product page is a 404). Ready boards: Pocket SDR FE by T. Takasu (MAX2771-based by my recollection; its README, fetched, gives 2/4/8-channel boards at up to 32–48 Msps) |
| active GPS patch antenna, SMA, 3.3 V bias | tier 2 | the front end supplies the bias through an inductor |
| u-blox NEO-6M/M8N or any NMEA module | tier 1 | 9600 baud default, 5-decimal minutes on NEO-6M-class modules |
| 16.368 MHz TCXO → 65.472 MHz clock (for example a Si5351 or the RP2350's PLL from the TCXO) | tier 2 clock | makes the chip clock 4× the sample clock (below) |
| RC (2 × 2.7 kΩ / 10 nF ≈ 6 kHz), PAM8302-class amplifier or earphones | tier 1 audio | a piezo directly on the pin also works with square-wave beeps |
| RP2350 demo board | host | NMEA parse, loops, least squares |

Recorded IF data for a later check against a real sky: GNSS-SDR hosts files on SourceForge
(`https://sourceforge.net/projects/gnss-sdr/files/data/`, fetched). They include
`GPS_L1_CA_ID_1_Fs_4Msps_2ms.dat` (64 kB) and `2013_04_04_GNSS_SIGNAL_at_CTTC_SPAIN.tar.gz`
(1.2 GB). Their bit depth and IF are not on the listing, and they were not used here.

## What is needed to make it real

- **Tier 1:** only board work. Wire the GPS TX to a chip pin and two chip pins through RC to
  earphones. Firmware: `uart_rx` on thread 0, the NCO and sigma-delta PE configurations, and
  the host code in `tier1/navfix.py` and `sonify.py` ported to C.
  - Nothing here depends on the tag lane except the audio's wrap and tag_out.
  - A cruder square-wave beeper needs only a sequencer thread toggling a pin.
- **Tier 2:**
  1. **The tag-lane extension in pe16:** RTL, lockstep against `pe_array.py`, then synthesis to
     replace the 510 µm² estimate.
  2. **The LFSR assist.**
  3. **Replay from the banks into the array** at one bit per clock, with a window across two
     banks for tracking.
  4. **The clock plan.** The chip clock must be exactly 4 × the front-end clock, or the pin
     sampler must sample on the front end's clock edges (its clocked mode) with a 1-of-5
     counter.
  5. **Check the front end's real IF, sample rate and filter** against the assumptions here.
  6. **Measure against real data:** a recorded IF file (above), then a live antenna.
  7. **Ephemeris decode:** subframes 1–3. The model assists the host with ephemerides, and
     decodes only TOW. Full decoding is the same bit-sync and parity machinery, over 18–30 s
     instead of 6 s.
  8. **Satellite clock, ionosphere and troposphere corrections.** The synthetic sky has none,
     so the fix error here is only the receiver's.

## Files

- `tier1/walk.py`: the synthetic walk and the NMEA stream, as the NEO-6M's default sentence
  set.
- `seq/uart_rx.ml`: the UART receiver programme; interpreter, RTL lockstep and baud sweep.
  `isa.ml`, `sequencer.ml` and `harness.ml` are symlinks to `../deadline-sequencer`.
- `tier1/navfix.py`: the integer parser and navigation.
- `tier1/check_nav.py`: the parser against pynmea2, the precision against geographiclib, and
  controls.
- `tier1/sonify.py`: the sound controller and the pin-level audio render.
- `tier1/analyse.py`: the audio checks, the plot and the clips.
- `tier2/gpsl1.py`: C/A codes, navigation words, orbits and the IF generator.
- `tier2/test_gpsl1.py`: 32/32 codes match the ICD's octal first-10-chips table; the Gold
  cross-correlation takes exactly the values {−65, −1, 63}; the parity round trip passes, and
  single-bit errors are caught 200/200. `results/tier2/test_gpsl1.txt`.
  - The parity equations are transcribed from IS-GPS-200. Generator and decoder share them, so
    a transcription error would not be caught here.
- `tier2/pe_array.py`: the PE row with the tag lane, clock by clock.
- `tier2/acq.py`: verify, loss, mc, timing.
- `tier2/fix.py`: the end-to-end sky → fix.

Reproduce with `uv run --with numpy --with scipy --with matplotlib --with numba --with pynmea2
--with geographiclib python <script>`, run from the script's directory. For the OCaml:
`cd seq && opam exec --switch=5.3.0 -- dune build` (Hardcaml v0.17).
