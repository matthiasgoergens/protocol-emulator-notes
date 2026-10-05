# 100 Mbit/s Ethernet without a PHY chip, on the IHP Tiny Tapeout chip

Two routes to 100 Mbit/s Ethernet straight from the chip's pins, IHP SG13G2 (1.2 V core, sg13g2_io
pads at 3.3 V), with a core clock of 62.5 MHz:

1. **100BASE-FX through an SFP fibre module**: 125 Mbaud NRZI with 4B5B coding.
2. **100BASE-TX straight onto copper**: 125 Mbaud MLT-3 after 4B5B and a scrambler.

**Verdict in one paragraph.**
- **The pads are not the limit.** The 30 mA output pads that Tiny Tapeout wires to `uo_out` and `uio` switch cleanly to 250 Mtoggles/s into 10 pF in every corner.
- **100BASE-FX is feasible.** Transmit needs both clock edges. Receive needs a front end that samples at least 3 times per UI to be robust. At 2 samples per UI, which the four-phase stage gives at 62.5 MHz, it works without frequency offset or without jitter, but frames are lost when both are present.
- **The receive input needs gain.** The CMOS input pad cannot slice an SFP's LVPECL output directly in slow silicon, because it needs ±300 mV of overdrive at 62.5 MHz. One small part fixes that: a 1:2 transformer or a differential receiver.
- **100BASE-TX transmit works from two pins and three resistors.** The simulated waveform is close to the TP-PMD template. The rise time is slightly too fast and is fixed with a capacitor.
- **100BASE-TX receive works over a few metres of cable at 3–4 samples per UI**, with two CMOS input pads as slicers biased from the transformer centre tap. It fails on long cables, where the lack of adaptive equalisation shows, and in slow silicon unless the pads get more signal.

The pieces are reusable: a line-code unit, an LFSR scrambler, a 4B5B block code, a delimiter
aligner, and an oversampling CDR (see "Reusable units").

Everything below points to a file. Raw simulation data is in `/var/tmp/fast-eth/` (scratch, not
committed); the summaries are in `results/`.

## Step 1: the IHP I/O pads

**Which pads.** From Tiny Tapeout's own TTIHP 26a chip netlist, `release/v.1.0.0/netlist/tt_ihp_wrapper.v` in `tinytapeout-ihp-26a-foundry-submission` (fetched 2026-09-25, copy in `/var/tmp/fast-eth/tt_ihp_wrapper_26a.v`):
- `uo_out` uses `sg13g2_IOPadOut30mA`;
- `uio` uses `sg13g2_IOPadInOut30mA`;
- `ui_in` and the other digital inputs use `sg13g2_IOPadIn`;
- IOVDD is 3.3 V and the core 1.2 V (its `doc/Datasheet.md`).

The early ttihp 0p1 chip used the 4 mA pads instead.

**How.** The runs are `spice/padsim.py` and `spice/run_all.sh`, analysed by `spice/analyse.py`, with all numbers in `results/pads.txt`.
- **Tools:** ngspice 44.2 with PSP103 and R3_CMC (compiled with openvaf-r in the container), using the PDK's own `sg13g2_io.spi`.
- **Corners:** tt (1.2 V / 3.3 V), ss (1.08 V / 3.0 V) and ff (1.32 V / 3.6 V), each at 27 °C and 85 °C.
- **Package and board:** a 2 nH bond wire plus a lumped capacitance.
- **Not modelled:** supply inductance, so ground bounce from simultaneous switching is not in these numbers.

Two changes to the PDK netlist were needed to simulate at all. Both are reproduced in isolation (`/var/tmp/fast-eth/pads/dbg-*`) and documented in `padsim.py`:
- **The clamp-gate antenna diodes are removed.** These are 0.3 µm² `dantenna` junctions. With them, every transient that switches the driver stops with "timestep too small": level shifter plus clamps fails, the same circuit without them runs.
- **The pad ESD diodes use simplified model cards.** The same `dantenna` / `dpantenna` models fail when the pad passes through 0 V, so I kept saturation current, series resistance and capacitance, and dropped the breakdown, recombination and high-injection terms, which only act far outside 0 to IOVDD.

**Output pads, toggle test into 10 pF.** The table gives swing as a percentage of IOVDD (`results/pads.txt`):

| pad | 125 Mt/s | 250 Mt/s | 333 Mt/s |
|---|---|---|---|
| 30 mA (TT's uo_out, uio) | 100 % every corner | 98-100 % | 89-100 % |
| 16 mA | 100 % | 84-99 % | 67-94 % |
| 4 mA (ttihp 0p1) | 56-84 % | 30-48 % | 24-36 % |

**30 mA pad, PRBS7 NRZI at 125 Mbaud.**
- **10-90 % edges:** 0.8-1.6 ns into 5 pF and 1.3-2.2 ns into 10 pF.
- **Delay from the core to the pin:** 1.7-3.5 ns.
- **Data-dependent jitter:** at most 0.44 ns peak to peak.
- **Eye:** fully open in every corner, both temperatures.

The maximum clean toggle rate is above 250 Mt/s for the 30 mA pad, and about 100 Mt/s for the 4 mA pad in slow corners.

**Input pad `sg13g2_IOPadIn`.**
- **Switching point: 0.55-0.63 V.** From `in_dc` over the corners. It is not mid-rail: the input stage is a thick-oxide inverter supplied from the 1.2 V core. It has no hysteresis. That is below LVTTL's V_IL of 0.8 V, so a 0.7 V "low" from a 3.3 V part reads as a 1.
- **Small signals at 62.5 MHz**, a sine centred on its own threshold through 50 Ω, 3 pF and 2 nH:
  - ±300 mV toggles in every corner, with the output duty cycle at 53-60 % and a delay of 1.2-3.7 ns;
  - ±150 mV fails at ss (no output swing);
  - ±75 mV fails at ss and at tt 27 °C.

  **So a slicer built from this pad needs about ±0.3 V of overdrive to cover slow silicon**, and about ±0.1 V at typical.
- **A full-swing 0-3.3 V clock at 62.5 MHz comes out at 56-58 % duty cycle**, because the threshold is low. Every digital input on TTIHP 26a is this pad (I did not trace which gpio carries `clk`), so the core clock probably arrives with a 7 % duty-cycle error, about 1.1 ns at 62.5 MHz. That matters for any both-edges output: see the transmit notes below.

### Pad speed for HDMI / DVI and faster links (2026-10-05)

These runs are in `results/pads_hdmi.txt` (`spice/run_hdmi.sh`). The core-side drive is an ideal PRBS7 into the pad's `c2p` at the bit rate, so they say what the pads can do, not how the core makes 250 Mbit/s. That needs the four-phase stage, or a 10-to-4 gearbox at 60-62.5 MHz.

**Drive-strength options in sg13g2_io:** `IOPadOut` / `TriOut` / `InOut` at 4, 16 and 30 mA, plus `IOPadAnalog`. On TTIHP 26a the choice is already made: the 30 mA cells. The 4 mA cell would not do these rates (toggle table above).

**Into 2 nH plus 10 pF** (30 mA pad, PRBS7 NRZ):

| rate | eye opening above 50 % of IOVDD, worst (ss 85 °C) to best (ff 27 °C) |
|---|---|
| 120 Mbit/s | 0.86-0.91 UI |
| 240 Mbit/s | 0.67-0.81 UI |
| 250 Mbit/s | 0.68-0.81 UI (5 pF: 0.76-0.88 UI) |

The full swing is reached in every case (97-100 %), with 10-90 % edges of 1.3-2.2 ns.

**HDMI / DVI pair, driven pseudo-differentially.** The arrangement:
- two 30 mA pads in antiphase per pair, each through a series resistor Rs at the chip;
- 10 cm of board plus 1 m of cable, modelled as 50 Ω per conductor, lossless;
- the sink's 50 Ω to AVcc = 3.3 V on each conductor, plus 1.5 pF.

With a pin low, the line sits at 3.3 V × (Rs + Ron) / (Rs + Ron + 50), so the pad acts as the current switch a real TMDS source has.

| Rs | rate | diff swing p-p | eye height | eye open ≥ 150 mV | common mode |
|---|---|---|---|---|---|
| 270 Ω | 120 Mbit/s | 0.87-1.13 V | 0.82-1.03 V | 0.96-0.97 UI | 3.06-3.09 V |
| 270 Ω | 240 Mbit/s | 0.87-1.14 V | 0.80-1.03 V | 0.88-0.94 UI | 3.07-3.08 V |
| 270 Ω | 250 Mbit/s | 0.87-1.14 V | 0.81-1.03 V | 0.86-0.93 UI | 3.07-3.08 V |
| 120 Ω | 250 Mbit/s | 1.37-1.93 V | 1.26-1.80 V | 0.91-0.95 UI | 2.91-2.95 V |

**Verdict: HDMI / DVI at 240-250 Mbit/s per lane is electrically plausible from these pads**, with 8 resistors and an HDMI connector: four pairs (three data and the clock) use all 8 `uo_out` pins.
- **Use about 270 Ω.** It gives TMDS-like levels: the line low at 2.8 V (about 10 mA per pin), about 1 V p-p differential, and a common mode of 3.07 V.
- **Avoid 120 Ω.** It gives a bigger swing, but 1.4-1.9 V p-p exceeds the 1.2 V maximum I remember, and its 2.9 V common mode is below the window.
- **The TMDS limits used here are from memory and NOT checked against the DVI or HDMI text:** a receiver needs at least 150 mV differential; the common mode must lie between AVcc − 300 mV and AVcc − 37.5 mV; the swing must stay under 1.2 V p-p.

**Ground bounce, simulated** (`results/pads_hdmi.txt`; one corner, tt 27 °C). All 8 pads switch together, with IOVDD and IOVSS each through 1 nH and an assumed 100 pF of on-die IO decoupling:
- **the IO rails bounce by 0.37-0.41 V p-p;**
- **the pair's differential eye barely changes:** open over 0.86-0.90 UI against 0.93 without bounce, with the same swing and height. A pseudo-differential pair rejects bounce common to both pins.
- **The real casualty would be single-ended inputs on the same ring:** 0.4 V of IOVSS bounce against a 0.59 V input threshold. Keep fast inputs (Ethernet receive) away from the HDMI pins, or do not run both at once.

**Not modelled:**
- cable loss: 1 m at 125 MHz is small, but longer cables matter;
- skew between the pads of a pair, which shows up as common-mode noise;
- whether a given monitor accepts a 24 MHz pixel clock.

The edges (0.8-1.3 ns, 20-80 %) are fast for the rate, so ringing at the connector is the board's job.

**Input pad at 125 MHz:**
- **A full-swing square** comes through in every corner, at 58-63 % duty cycle with 0.35-0.85 ns delay.
- **±600 mV** comes through in every corner (51-54 % duty).
- **±300 mV** fails at ss 27 °C (works at 62.5 MHz).

So the pads can also *receive* 250 Mbit/s if the signal is large.

## Step 2: 100BASE-FX via an SFP module

### Design

Transmit (`pcs.ml`, `tx ~media:Fx`), at 2 code bits per clock:
- a byte interface, one byte per 5 clocks;
- /J/K/ replaces the first preamble octet, then 6 × 0x55, the SFD, data, a CRC-32 FCS computed on the fly, /T/R/, and 12 octets of /I/ before the next frame;
- 4B5B, then a 10-bit gearbox that shifts out 2 bits per clock;
- NRZI, 2 levels per clock.

The two levels go out on one clock's rising and falling edges. **Assumption:** a both-edges output stage. That is the four-phase stage with 2 of its 4 lanes, or the classic XOR of a rising-edge and a falling-edge flop. The line has 8 ns resolution, so a finer stage is not needed.

**SFP transmit interface.** Two 30 mA pads in antiphase, each through 150 Ω, into the SFP's internally AC-coupled 100 Ω differential input (the SFP MSA puts the coupling capacitors and termination inside the module):
- simulated 1.18-1.58 V peak-to-peak differential, with 1.1-1.5 V of eye in every corner (`results/pads.txt`, "SFP transmit input");
- that is inside the usual 0.5-2.4 V SFP input range (from memory of SFP datasheets, not checked against the MSA text);
- the crossing spread of 0.75 ns includes the coupling capacitors still settling in a 1 µs run, so it is an upper bound.

Receive (`pcs.ml`, `rx ~media:Fx`, plus `cdr.ml`):
- the sampler delivers n samples per clock;
- the CDR turns them into 0-3 UIs per clock;
- NRZI decode;
- the delimiter aligner finds /J/K/ at any bit position and emits 5-bit groups;
- 4B5B decode;
- the frame state machine strips the preamble at the SFD, checks the CRC-32 residual (0xDEBB20E3), and requires /T/R/ at an even nibble.

Any other symbol ends the frame as bad. Bad frames are signalled, never passed as good.

The CDR (`cdr.ml`) is a precise fixed-point model written the way the hardware would be: integer arithmetic, bounded work per clock, and one clock of look-ahead. It has two parts.
- **At 3 or more samples per UI:** a second-order digital PLL on edge positions, with 16 fractional bits (so the frequency integrator resolves about 8 ppm; with 8 bits it pinned at ±2000 ppm, found by trace). It decides each UI from edges, not by picking samples: each edge is assigned to its nearest UI boundary.
- **At exactly 2 samples per UI:** a separate slot tracker. There, the PLL has a false lock. I showed at source, and measured, that when edges straddle a sample, the edge positions alone cannot tell which of the two samples is the eye centre. The tracker follows the jitter cluster between two sample slots, and learns the direction of the frequency offset in idle, where every run is one UI, so that the sum of (run − 2) is exactly the drift in samples.

**This CDR is not yet in Hardcaml.** The rest of the receive path is.

**Front-end assumptions (someone else's block, modelled behaviourally in `line.ml`):**
- n = 2 samples per clock is both edges of the 62.5 MHz clock (1 sample per UI);
- n = 4 is the four-phase stage (2 per UI);
- n = 6 or 8 would need 6 or 8 phases, or a delay-line / TDC sampler (3 or 4 per UI).

A per-tap phase error models multi-phase mismatch.

**SFP receive interface.** The SFP's receive output is LVPECL/CML, typically 0.6-1.2 V peak to peak differential (again from memory of datasheets), so about ±150-300 mV per leg. The input pad needs ±300 mV at ss, so **a single leg into a biased pad works at tt and ff and fails in slow silicon.** Options, in order of robustness:
1. **A small differential receiver** (an LVPECL/LVDS-to-LVCMOS translator). One part, and it always works. It is the fallback, not the fun answer.
2. **A 1:2 RF transformer (balun), e.g. Mini-Circuits ADT4-1WT (1:4 impedance, 2-775 MHz).** It turns the differential signal into a single-ended one of twice the voltage, centred by a divider on the pad threshold. Its 2 MHz low corner is acceptable for FX, whose NRZI runs are at most 4 UI, but not for scrambled 100BASE-TX.
3. **Resistors only**: AC-couple one leg, and bias it at the pad threshold with a divider, or better with a threshold servo. In a servo, the chip drives a PWM pin into an RC and adjusts the duty until the sliced idle pattern (/I/ is a 62.5 MHz square wave) is 50/50, which cancels the 0.55-0.63 V spread of the threshold. **Margin in slow silicon is too small.**

### Verification

**Checks** (`opam exec --switch=5.3.0 -- dune build`, then `./_build/default/main.exe`; each prints its pass lines):
- **Reference model** `ref_model.ml`, written independently from the code tables as list-level OCaml: bit-serial CRC-32 (checked on "123456789" = 0xCBF43926), 4B5B, NRZI, MLT-3, the x^11+x^9+1 keystream (checked to be maximal length, 2047), and a stream decoder. The 4B5B table was checked against Wikipedia's on 2026-09-25.
- **The RTL transmitter's code stream decodes to the same frames** as the reference.
- **Every frame is delimited and its FCS is correct.**
- **The NRZI line decodes back to the code stream.**
- **At most 3 zeros in a row** anywhere in the coded stream.
- **The RTL receiver recovers every frame** from the reference line, on an ideal input.

**Loss sweep.** Frame loss rate against oversampling, random jitter and frequency offset:
- **Setup:** `results/fx_sweep.txt`, summarised in `results/fx_summary.txt`; 400 frames per cell, rotating 64 / 128 / 512 / 1518 bytes, after 20 000 UI of link-up idle; one command per cell, `main.exe fxcell OSR PPM RJ DCD DDR TAP NF`. Loss means frames not received intact. **The CRC let no bad frame through: 0 false accepts in 120 cells × 400 frames.**
- **The table:** all sizes, with 64 B / 1518 B in brackets. Columns are the random jitter on every edge, in ns RMS.

| samples per UI | offset | 0 | 0.25 | 0.5 | 0.75 | 1.0 |
|---|---|---|---|---|---|---|
| 1 (both edges) | 0 | 0 % | 100 % | 100 % | 100 % | 100 % |
| 1 | ±200 ppm | 60 % (12 / 100) | 67 % | 75 % | 84 % | 94 % |
| 2 (four-phase) | 0 | 0 % | 6 % | 0 % | 0 % | 34 % |
| 2 | +100 ppm | 0 % | 45 % (10 / 89) | 55 % | 60 % | 81 % |
| 2 | ±200 ppm | 0 % | 16-32 % (3-6 / 43-75) | 42-60 % | 59-68 % | 84-86 % |
| 3 | ±200 ppm | 0 % | 0 % | 0 % | 16-20 % (3 / 37-48) | 78-80 % |
| 4 | ±200 ppm | 0 % | 0 % | 0 % | 4-6 % (0-2 / 13-17) | 64-68 % |

Budget cells at +200 ppm and 0.3 ns RMS:
- **Other error sources:** plus 0.5-2 ns of duty-cycle distortion at the receiver, 0.5-1 ns of both-edges skew from the transmitter, and ±0.3-0.6 ns of tap mismatch.
- **3 or 4 samples per UI: 0 % loss**, except the harshest cell (1.5 ns DCD, 1 ns skew and ±0.5 ns mismatch): 40 % at 3 samples, 2 % at 4.
- **2 samples per UI: 54-70 % loss**, 12-35 % for 64-byte frames.

**Reading.**
- **Both clock edges alone (1 sample per UI) cannot receive.** It works only at exactly 0 ppm with no jitter. With an offset, the sampling point sweeps through the edges, and a 1518-byte frame always contains a slip.
- **With 3-4 samples per UI there is a wide margin.** The knee is at 0.75 ns RMS random jitter, against a 100BASE-FX receive budget whose random part is, from memory of the FDDI PMD numbers, about 2.3 ns p-p (about 0.16 ns RMS).
- **The four-phase stage's 2 samples per UI is the borderline case.** It is error-free without frequency offset, or without jitter, but with both it loses about a third of the frames at 0.25 ns RMS. That is usable for a ping demo with 64-byte frames (3-16 % loss). The remaining loss is my tracker, which falls behind when jitter and drift coincide, not a demonstrated limit: the edges carry the information. A better 2× tracker, or a third sampling phase from a delay-line tap, is the next step.

**Frequency offset.** 100BASE-FX allows ±100 ppm at each end, ±200 ppm together (802.3 clause 24). Our transmit clock must be 62.5 MHz within 100 ppm:
- the RP2040/RP2350 makes exactly 62.5 MHz from 125 MHz, and 12 MHz crystals are typically ±30 ppm;
- the 56-58 % duty cycle through the clock pad means about 1.1 ns of both-edges skew at our transmitter, the `ddr` column above;
- it is within what our own receiver tolerates, but the media converter's receiver tolerance is not known.

Three ways to remove the skew:
- feed 125 MHz and divide by two on chip;
- bias the clock input at the pad threshold;
- let the four-phase stage's calibrated fine delay trim the falling-edge lane.

### Module choice and demo path

- **Module:** a 100BASE-FX SFP, 1310 nm multimode, LC, 2 km class, e.g. an "SFP-FE-FX"-type part from FS.com, or Cisco GLC-FE-100FX-compatible modules.
- **Why not 1000BASE-X SFPs:**
  - 1000BASE-SX is 850 nm, which a 1310 nm 100BASE-FX partner cannot receive;
  - some 1G modules have a clock-and-data recovery unit, or receive filtering, specified only near 1.25 Gb/s;
  - copper 1000BASE-T SFPs contain a PHY speaking SGMII / 1000BASE-X and will not pass 125 Mbaud NRZI at all.

  Multi-rate modules specified from 125 Mb/s to 1.25 Gb/s exist, but "works at 125 Mbaud" has to be read from the datasheet, not assumed. None of this is from a datasheet I checked today: treat it as the question to ask the vendor.
- **Demo path:** chip → SFP → multimode duplex patch cord (LC to SC) → TP-Link MC100CM media converter → RJ45 → any PC or switch. The MC100CM is 802.3u 100BASE-FX, 1310 nm, multimode, SC, 2 km, with a 10/100 RJ45 port (TP-Link product page, fetched 2026-09-25).

## Step 3: 100BASE-TX straight onto copper

### Transmit

MLT-3 on a pin pair (`units.ml`, `Line_code.mlt3_pins`):
- **The line level is A − B.** A 1 toggles A when the line is at ±1, and B when it is at 0.
- **So exactly one pin moves per step**, and each pin moves at most every second UI.
- **The zero level alternates** between (0,0) after +1 and (1,1) after −1.
- **Each pin is a 62.5 Mt/s signal with 8 ns edge resolution**, the same both-edges output as FX.

The pins drive the MagJack primary. The first values (82 Ω, 250 Ω) assumed ideal 3.3 V pins and gave only 0.77 V: the pads measure about 36 Ω output resistance under this load.
- **Series resistor per pin:** 47 Ω.
- **Across the primary:** 249 Ω.
- **Result:** a 100 Ω differential source and about 1 V into 100 Ω.

The scrambler is the generic additive LFSR (x^11 + x^9 + 1). Checked against the reference: the RTL scrambler output equals reference keystream XOR code, and A − B equals the reference MLT-3 of the scrambled stream.

Simulated with the pads, 1:1 magnetics (350 µH, 0.3 µH leakage) and 1 m of line into 100 Ω (`results/pads.txt`, "100BASE-TX"). The TP-PMD template numbers are from memory and NOT checked against the standard's text.

| | tt 27 °C | ss 85 °C | ff 85 °C | template |
|---|---|---|---|---|
| peak ±(mV) | 969 / 980 | 761 / 771 | 1062 / 1075 | 950-1050 |
| symmetry | 98.9 % | 98.6 % | 98.8 % | 98-102 % |
| overshoot | 1.3 % | 2.6 % | 1.4 % | ≤ 5 % |
| rise / fall 10-90 | 2.9 / 2.9 ns | 3.0 / 2.9 ns | 2.9 / 2.8 ns | 3-5 ns |
| jitter p-p | 0.53 ns | 0.82 ns | 0.48 ns | ≤ 1.4 ns |

**It is close.**
- **The rise time is just under the template's minimum, and a capacitor across the primary fixes it:**
  - 15 pF gives 3.5-4.1 ns, with overshoot 5.4-6.5 %, just over the limit because the capacitor rings with the leakage inductance. A small series resistor on the capacitor should damp that (untested).
  - 33 pF overshoots the rise time, to 4.8-5.4 ns.
- **The amplitude tracks IOVDD and the pad resistance.** The ss and ff corners also move IOVDD to 3.0 and 3.6 V; on a board with a regulated 3.3 V the spread is smaller.
- **Marginal symbols reach the partner as CRC failures, not a link drop.** The scrambled idle keeps the partner's descrambler locked. The partner drops the link only if its receiver loses lock, and the pin-pair waveform's timing is fixed by our clock.

### Receive: why it is hard, and what survives

Why a real PHY is complicated:
- the cable's loss rises with √f (skin effect): about 17 dB at 62.5 MHz over 100 m, so it needs an adaptive equaliser;
- MLT-3 after a scrambler still has low-frequency content, so the transformer's high-pass causes baseline wander, which PHYs correct;
- the three levels need two thresholds that track the amplitude;
- clock recovery runs at 125 Mbaud.

On a short cable almost all of that goes away: 2 m of Cat5e loses about 0.3 dB at 62.5 MHz.

**The proposed receiver** is two IOPadIn pins on the two legs of the MagJack's receive winding, with the centre tap biased Δ = TH/2 below the pad threshold by a divider. Pad P then fires when the line is above +TH, and pad N when it is below −TH, with TH = 0.5 V. After that come the same CDR, MLT-3 decode, a descrambler that locks on idle (plaintext all ones, 40 correct predictions in a row) and the same 4B5B / framing / CRC RTL.

**The channel model** is `tx_channel.py`, with the sweep in `tx_sweep.sh` → `results/tx_sweep.txt`:
- **Transmit side:** the RTL transmitter's real scrambled line (`main.exe txgen 200`), from the partner's point of view, at 0.97 V and 2.9 ns rise;
- **Magnetics:** two transformer high-passes;
- **Cable:** the Cat5e loss formula, with the skin term made causal;
- **Equaliser:** an optional passive RC shelf;
- **Pads:** each modelled as a slicer with a dead zone taken from Step 1. ±0.1 V at tt, ±0.2 V at ss, ±0.05 V at ff, with the pad threshold shifted by the corner against a fixed bias;
- **Sampling:** +200 ppm and 0.2 ns RMS jitter;
- **Scoring:** decoded by the CDR and the RTL receiver.

Results (`results/tx_summary.txt`, from `results/tx_sweep.txt`). **The sweep was cut short by a host restart: 127 of 144 cells.** Frame loss, all sizes, with 64 B / 1518 B in brackets; 200 frames per cell; 0 false accepts in all cells.
- **"Eye":** the analogue eye at the slicer input, upper / lower.
- **g:** the receive transformer ratio (1 is a normal MagJack, 2 an extra 1:2 step-up).
- **Corners:** pad dead zone and threshold shift per corner, against a fixed bias divider.

| cable | eye (mV) | 4/UI, g=1, tt / ss / ff | 4/UI, g=2, tt / ss / ff | 2/UI, g=1, tt |
|---|---|---|---|---|
| 1-10 m | 726-584 | 0 % / **100 %** / 0 % | 0 % / 0 % / 0 % | 46-52 % |
| 20 m | 427 / 409 | 94 % / 100 % / 53 % | 0 % / 19 % / 0 % | 100 % |
| 30 m | 266 / 248 | 100 % everywhere | 92-100 % | 100 % |
| 50 m and longer | closed | 100 % | 100 % | 100 % |

**Verdict for copper receive.**

**At 4 samples per UI it works to about 10 m with a normal MagJack, at typical and fast silicon.** The knee is at about 20 m, where the cable's loss brings the levels close to the fixed ±0.5 V thresholds.

**Slow silicon fails even at 1 m**, for a different reason. The pad needs about ±0.2 V of overdrive, and its threshold sits 44 mV below what a fixed divider assumes, which leaves almost no margin. Two fixes:
- a 1:2 step-up (with Ethernet-class inductance, since an RF balun's 2 MHz corner would add baseline wander);
- a threshold servo through a PWM pin, which moves the bias with the pad.

The step-up also takes typical silicon to 20 m.

**At 2 samples per UI it loses about half the frames even at 1 m**, the same tracker weakness as for FX.

**Past 30 m the eye is closed**, and a receiver needs what a PHY has: an equaliser that adapts to the cable and thresholds that track the amplitude. My fixed passive shelf equaliser cells (20-50 m) all came out with a closed eye, worse than no equaliser. That is a defect in how I scaled the equaliser in `tx_channel.py` (it re-normalises the gain at 30 MHz), not a measurement of what a shelf can do; those cells are excluded.

## Reusable units

All are in `units.ml`, as Hardcaml, parameterised, with bit 0 first in time and a `count` input for streams carrying 0..k valid bits per clock.

| unit | here | also serves |
|---|---|---|
| `Lfsr.additive` (taps, width, bits per clock, load for sync) | 100BASE-TX scrambler | PCIe 1/2 and USB 3 (x^16+x^5+x^4+x^3+1), SONET (x^7+x^6+1), 802.11 (x^7+x^4+1), PRBS generators and checkers |
| `Lfsr.multiplicative` | - | 64b/66b (x^58+x^39+1), DVB, ATM (self-synchronising) |
| `Line_code.nrzi_encode/decode` (invert option) | 100BASE-FX | USB full / low speed (a 0 toggles), FDDI |
| `Line_code.mlt3_pins`, `mlt3_decode` | 100BASE-TX | FDDI over copper (TP-PMD) |
| `Line_code.manchester` | (the 10BASE-T prototype) | 10BASE-T, DALI, and differential Manchester / BMC (manchester of NRZI) for USB Power Delivery and AES3 |
| `Block_4b5b` | 100BASE-X | FDDI, USB Power Delivery (4b5b + BMC) |
| `Aligner` (delimiter, group width) | /J/K/ | 8b10b comma (K28.5), USB SYNC, HDLC flag |
| `Cdr` (model: n samples per clock, osr, any sample alphabet) | FX and TX | anything NRZ-like: USB full speed (12 Mb/s at 5 samples per bit from 60 MHz), UART at high rates, CAN bit timing (resynchronisation on edges is the same loop), 10BASE-T |

Synthesis, flattened, Yosys against the SG13G2 typical library (`synth/synth.sh`, `synth/*.stat.txt`), without the CDR:

| block | area | sequential share |
|---|---|---|
| FX transmit | 6 354 µm² | 43 % |
| FX receive | 7 270 µm² | 38 % |
| TX-copper transmit | 7 135 µm² | 47 % |
| TX-copper receive | 12 549 µm² | 37 % |

One TT tile is about 31 300 µm². Timing at 62.5 MHz is not checked.

## Parts list for a demo

| part | for | notes |
|---|---|---|
| 100BASE-FX SFP, 1310 nm multimode, LC, 2 km | FX | check "125 Mb/s" in its datasheet |
| SFP cage and connector, 20-pin | FX | or an SFP breakout board |
| multimode duplex patch cord, LC to SC, OM1 or OM2 (62.5 or 50 µm) | FX | |
| TP-Link MC100CM media converter | FX demo to copper | 100BASE-FX, 1310 nm MM, SC |
| 2 × 150 Ω, 0603 | FX transmit | series, at the chip |
| receive gain: an LVPECL/LVDS-to-LVCMOS receiver, or a Mini-Circuits ADT4-1WT (1:4 impedance) | FX receive | plus a divider or PWM + RC bias at about 0.59 V |
| RJ45 with integrated 10/100 magnetics (1:1, 350 µH), e.g. HanRun HR911105A or Würth 7499010211A | TX | part numbers from memory, check the pinout |
| 2 × 47 Ω, 1 × 249 Ω, 15 pF C0G across the primary | TX transmit | |
| divider for the receive centre tap (to about 0.34 V), or a PWM pin + 10 kΩ / 100 nF | TX receive | a 1:2 step-up with Ethernet-class inductance helps the slow corner |
| a PC or switch with a 10/100 port, and a short Cat5e cable (1-2 m) | both | |

Buying in Singapore: FS.com ships SFPs and patch cords, and Lazada or Shopee carry the MC100CM. Availability was not checked today.

## Reproduce

```
opam exec --switch=5.3.0 -- dune build
./_build/default/main.exe                           # all checks
./_build/default/main.exe fxcell 4 200 0.5 0 0 0 400  # one FX cell
./_build/default/main.exe txgen 200 /var/tmp/fast-eth/tx/stream
./tx_sweep.sh                                        # TX receive sweep (needs the stream)
./_build/default/main.exe verilog /var/tmp/fast-eth/rtl && synth/synth.sh
spice/run_all.sh && uv run --with numpy python3 spice/analyse.py   # pads (podman, spice-retention)
```

## Open questions

- **The 802.3 bit order of 4B5B code groups** (I assumed leftmost first) and the exact TP-PMD template numbers. Both are from memory, and both matter only against a real partner. The first test with the media converter settles the bit order.
- **The CDR in Hardcaml.** The model is written to be ported (fixed width, bounded work per clock), but its area and timing are unknown.
- **A better tracker at 2 samples per UI**, or one extra phase. This decides whether the four-phase stage alone is enough for 100BASE-FX receive.
- **Ground bounce.** Two or more 30 mA pads switching together with real supply inductance is not simulated. It adds jitter at the transmitter and a threshold shift at the inputs.
- **The receive limits of the media converter and PC** (jitter tolerance, amplitude), which decide how much of the transmit skew matters.
- **The input pad's small-signal behaviour** is from a sine at one frequency. The copper receive model reduces it to a dead zone, which is crude.
