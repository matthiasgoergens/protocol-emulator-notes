# Four-phase output and input stage for the deadline sequencer

Placing pin edges between clock edges, and sampling pins between them, for the IHP SG13G2 Tiny
Tapeout chip. The sequencer's four threads each issue once every four clocks, so together they
issue once per clock. This stage puts the sub-clock offset into the pins:

- **Output.** Four clock phases (0, 90, 180 and 270 degrees). Every output pin has four toggle
  flip-flops ("lanes"), lane p clocked on phase p, and the pin is the XOR of its lanes. Each lane
  can make one edge per clock at quarter p, so a pin can have up to four edges per clock on a
  quarter-clock grid.
- **Input.** Four sampling flip-flops per pin, one on each phase: 4x oversampling.

Behind that is the programmable version: a calibrated delay line per lane, which places each edge
at any tap (a digital-to-time converter, DTC), and the same line on the inputs, which times
incoming edges (a time-to-digital converter, TDC). Both turn the chip into a timing debugger (the
shmoo demonstration below).

Everything here is a simulation. The four-phase stage is RTL, checked cycle-accurately and in an
event simulator. The DTC, TDC and target device are behavioural models whose assumptions are
stated where they are used.

## Contents

| File | What it is |
| --- | --- |
| `stage.ml` | The stage in Hardcaml, with two clockings of the same logic: four real clock inputs (for Verilog, iverilog and static timing), or one clock at four times the rate with enables (for Cyclesim) |
| `main.ml` | Stage against its reference model with planted faults; the sequencer RTL through the stage; emits `multiphase_stage.v` → `results/main.txt` |
| `iverilog/` | Event-driven check of the real four-clock Verilog, including phase skew → `results/iverilog.txt` |
| `nco.ml`, `fm.ml`, `fm_eval.py` | FM transmitter: an NCO computing four levels per clock drives the stage; the stage's pin is judged by `notes/fm-radio-2026-09-24/fm_sim.py`'s receiver → `results/fm.txt` |
| `eth_rxn.ml`, `rx_jitter.ml` | 10BASE-T receiver taking 1, 2 or 4 samples per clock; jitter sweep at the PAL clock → `results/rx-jitter.txt` |
| `shmoo.ml` | DTC/TDC timing-debugger demonstration on a behavioural SPI target → `results/shmoo.txt` |
| `isa_controls.sh` | Planted faults in the sequencer's new ISA logic → `results/isa-controls.txt` |
| `sta/` | Liberty delays, synthesis and static timing in the LibreLane container → `sta/*.txt` |

Build and run: `opam exec --switch=5.3.0 -- dune build`, then `dune exec` each of `./main.exe`,
`./rx_jitter.exe`, `./shmoo.exe`, and `./fm.exe <file>` followed by `uv run --with numpy python
fm_eval.py <file> results/fm.txt`; `iverilog/run.sh`; `sta/run.sh`.

## The design

### Output: lanes belong to phases, and the sub-slot comes with each write

The first idea was "thread i owns quarter i": thread i's lane clocked on phase i. That cannot place
edges freely. Thread t only issues on clocks c with c mod 4 = t, so a fixed thread-to-phase map
can only ever put an edge at quarter (c mod 4) of clock c. That is one fixed offset per clock, not
a grid. So lanes belong to phases, and each pin write carries its quarter:

- **ISA** (in `../deadline-sequencer`; unused bits, so every old programme is unchanged). SETP and
  SHO take a 2-bit sub-slot q: the new level starts at quarter q of the clock. The core exports
  `pin_sub`, four bits per pin: the level during each quarter. That costs 10 flip-flops.
- **Stage** (`stage.ml`). Per pin and clock:
  - a ph0 register turns the nibble into toggles (t_p = n_p XOR n_(p-1), with n_(-1) the last
    quarter of the previous clock);
  - lane p toggles on phase p. Lane 0 takes its toggle straight from the core's registers at the
    next ph0 edge; lanes 1 to 3 take it from the toggle register, a quarter, half or three quarters
    of a clock later;
  - the pin is the XOR of the lanes.
  Invariant: after core edge E(k+1) + p/4, the pin equals quarter p of the nibble held from E(k).
  The pin is one clock later than the sequencer's old pin output, a constant latency.
- **Throughput is unchanged.** There is at most one pin write per clock across all threads, and
  loops cost slots. The finer grid applies to edges the firmware could already make.
  `main.ml`'s edge train shows what the barrel adds: pin 1 toggles every 4.25 clocks (17 quarters),
  a period the clock grid cannot make. Each thread writes four consecutive edges with q = 0, 1, 2
  and 3 and idles for 13 slots. Measured: 141 spacings, all exactly 17 quarters.
- **FM needs a different source.** FM on the third harmonic of a clk/2 square wave needs an edge on
  nearly every clock, at a data-dependent quarter. Occasionally a clock needs two edges or none,
  because a 25 kHz deviation at a 1 kHz tone moves the edges ±25 carrier cycles against the grid.
  That is every slot of every thread. So FM uses an NCO (`nco.ml`). It evaluates its phase
  accumulator at four points per clock (three extra adders) and hands the stage a nibble per
  clock. A thread only has to write a frequency word per audio sample. The stage takes nibbles
  from any register source: the core, the NCO, or the pin streamer at width 4.

### Input: four samplers per pin, a synchroniser per phase

Each input pin has:

- a sampling flip-flop on each phase;
- a second flip-flop on the same phase, making a two-flop synchroniser per phase (the pad is
  asynchronous to every phase);
- a retiming flip-flop on ph0.

The core sees the four samples of clock j at clock j + 2, as `pin_in4`. Each first-stage flip-flop
has a full clock to resolve before the second samples it. The ph3 → ph0 retiming step is a
synchronous transfer with a quarter period, which is covered by STA. No MTBF was computed. SHI's new quad bit (bit 7)
shifts a pin's four samples into the accumulator in time order. A hardware receiver takes the
nibble directly (`eth_rxn.ml`).

## Checks

All numbers below are in `results/`.

| Check | Result |
| --- | --- |
| Stage (sub-step Cyclesim) against the reference model, 4 out + 4 in pins, 50,000 random clocks (`main.txt`) | 0 wrong output quarters, 0 wrong sample words |
| Planted faults: lane 2 on phase 3; no previous-quarter register; OR instead of XOR; sampler 1 on phase 2 | caught: 33,858 / 187,592 / 179,674 wrong quarters, 46,887 wrong sample words |
| Sequencer RTL → stage, 100 random programmes × 2,000 clocks, against the interpreter's `pin_sub` | 0 wrong quarters (1,152 of 1,668 pin changes off quarter 0) |
| ISA extension, lockstep interpreter against RTL, 300 × 2,000 cycles (`isa-controls.txt`) | 0 mismatches; three planted faults give 3,825 / 15,069 / 849 |
| Real four-clock Verilog in iverilog, independent reference in the testbench, at 16 and 15 ns, phases skewed by up to 1.5 ns (`iverilog.txt`) | 79,976 quarters and 19,992 sample words, 0 wrong; lane on the wrong phase: 15,020 wrong |
| Existing tests: deadline sequencer lockstep, UART, deadline, demo; sequencer-ethernet | all pass unchanged |

## Demonstrations

### (a) FM on the third harmonic (`results/fm.txt`)

The NCO RTL drives the stage RTL. The stage's pins are rendered and demodulated by
`notes/fm-radio-2026-09-24/fm_sim.py`'s own receiver: 99.75 MHz carrier from a 66.5 MHz clock,
25 kHz deviation at the fundamental, 1 kHz tone, 4 ms. One pin each for the clock grid, both clock
edges, and the four-phase stage.

The RTL's quarter-grid pin equals `fm_sim.py`'s ideal clk/4 quantisation in all but 2 of 1,064,000
quarters (inc rounding), at one fixed shift of 12 quarters (the pipeline latency) over the whole
run. Because the fm_sim wave is periodic over the window by construction, this also shows the RTL
wave is, which the circular metric below needs. So the note's "clk/4 is essentially ideal" row is now a property of the
real circuit.

fm_sim's SINAD saturates at 22 dB, an artefact the note documents. The window here holds whole
tone and carrier periods, so the same receiver made circular ("SINAD*") has no edge effects and a
far higher ceiling. That matters below, where the effects are small.

| Edges | SINAD (fm_sim) | tone rms (ideal 53 kHz) | SINAD* |
| --- | --- | --- | --- |
| clock grid (RTL) | −22.7 dB | 0.7 kHz: tone lost | −115 dB |
| both clock edges (RTL) | 19.2 dB | 17.7 kHz: distorted | 22.0 dB |
| **four-phase stage (RTL)** | **21.8 dB** | **53.2 kHz** | **31.5 dB** |
| DTC, exact edge times on 50 ps taps | 22.2 dB | 53.3 kHz | 91.3 dB |
| DTC, 50 ps taps, INL walk 5 ps/stage, 10 ps jitter, 2 % calibration error | 22.2 dB | 53.3 kHz | 47.9 dB |
| exact edges, no quantisation | 22.2 dB | 53.3 kHz | 126.9 dB |

**Tolerance of the four-phase stage (SINAD*, from 31.5 dB):**

- static lane offsets (phase-clock skew plus lane-to-pin mismatch):
  - lanes 1 and 3 late by 200 ps: 30.7 dB; by 800 ps: 28.5 dB;
  - random offsets within ±400 ps: 29.9 dB;
- rising edges 500 ps later than falling: no change;
- 100 ps rms edge jitter: no change.

Quantisation dominates. Anything the phase sources below deliver is good enough.

**DTC rows.** Pure tap quantisation is not monotonic in tap size (a 470 ps tap, commensurate with
the clock, scores better than 200 ps), because deterministic quantisation spurs land in or out of
the audio band. What limits a real delay line is INL and calibration error:

- a 5 ps per-stage random walk: 59 dB;
- a 2 % scale error: 50 dB;
- a 10 % scale error: 36 dB.

The last is still better than the four-phase stage.

### (b) 10BASE-T transmit through the stage (`results/main.txt`)

The sequencer-ethernet firmware runs unchanged on the sequencer RTL, through the stage. All 13,824
quarters of the frame match the Ethernet model's encoder. One flipped half-bit in the host stream
shows as 12 wrong quarters.

### (c) 4x oversampled receive with jitter (`results/rx-jitter.txt`)

The setup:

- 10BASE-T at the PAL clock (53.2 MHz, 2.66 clocks per half-bit), where `../pal-ethernet` found
  the one-sample receiver failing from ±4 ns;
- frames at ±100 ppm, uniform jitter on every edge;
- 20 random frames per cell, each intact with a good CRC to count.

`eth_rxn` is the existing receiver generalised to n samples per clock. At n = 1 it decodes
identically to `eth_rx` on all 240 lines (a differential check). The four-sample input goes through
the stage's samplers, which agree with direct sampling on every clock.

| Receiver | Last jitter with 20/20 | ±9 ns | ±10 ns | ±11 ns | ±12 ns |
| --- | --- | --- | --- | --- | --- |
| existing `eth_rx`, 1 sample | ±3 ns (8/20 at ±4) | 0 | 0 | 0 | 0 |
| 1 sample, threshold moved to 75 ns | ±3 ns (13/20 at ±4) | 0 | 0 | 0 | 0 |
| 2 samples (both clock edges) | ±6 ns | 12 | 4 | 1 | 0 |
| **4 samples (stage RTL)** | **±10 ns** | 20 | 20 | 19 | 4 |
| 4 samples, phases off by 0, +1, −1, +0.5 ns | ±10 ns | 20 | 20 | 13 | 0 |
| control: samples handed over reversed | never | 0 | 0 | 0 | 0 |

This matches a back-of-envelope bound. The receiver separates a 50 ns boundary interval from a
100 ns mid-bit interval with a threshold at about 75 ns, and loses one sample period to
quantisation:

- 1x: 18.8 ns quantisation leaves about ±3 ns of jitter;
- 2x: about ±8 ns;
- 4x: about ±10 ns (the boundary side limits: 70.5 ns versus 50 ns + 2J).

Moving the one-sample threshold barely helps, because quantisation consumes the margin. Twenty
frames per cell is coarse (no confidence bounds), and the jitter is uniform and independent per
edge; the agreement with the bound is what makes the ±10 ns figure credible, not the sample
size. Both clock
edges recover most of it, and four phases most of the rest. A ±1 ns phase error costs little.

### Shmoo: the chip as a timing debugger (`shmoo.ml`, `results/shmoo.txt`)

A behavioural demonstration of the programmable version (below), on a behavioural SPI mode 0
target.

**Chip side:**

- delay line of 63 ps taps (sg13g2_buf_1, fanout-of-one, typical corner);
- 3 % per-stage mismatch;
- calibrated by counting taps per 16.67 ns clock: 264 taps, 63.1 ps per tap, worst INL after
  calibration 41 ps.

**Target** (invented numbers of a plausible order):

- setup 1.5 ns and hold 1.0 ns at 1.2 V, each with 60 ps jitter per event;
- clock-to-output 7.00 ns for a 0 and 7.35 ns for a 1;
- minimum clock pulse 1.2 ns;
- delays scaling as (1.2/vdd)^1.3.

**Setup/hold shmoo.** MOSI's edge is swept against SCK's rising edge from −4 to +4 ns in 0.1 ns
steps, at nine supply points. At 1.2 V the failing window is −1.6 to +1.1 ns; the model's is −1.50
to +1.00. The measured window is wider by the per-event jitter tail and one tap. Across supply it
widens as the model does.

**Control.** A target with hold time 1.5 ns moves the measured hold boundary by +0.5 ns, as it
must. The map measures the target; it is not an artefact of the method.

**Response time.** 2,000 MISO edges were timed by the TDC. The histogram is bimodal, and the means
per data value are 7.000 and 7.347 ns: a 347 ps data-dependent delay, against the model's 350 ps.
This is the kind of thing reverse engineering looks for.

**Runt pulse.** A pulse of programmed width on SCK, made from two lanes (rise at t, fall at t + w).
The target starts accepting runts, and slipping a bit, at about 1.2 ns:

| Pulse | Bytes corrupted (of 200) |
| --- | --- |
| 0.9 ns | 0 |
| 1.1 ns | 13 |
| 1.2 ns | 98 |
| 1.4 ns | 188 |
| 1.6 ns | 200 |

Whether a real output pad passes a 1 ns pulse is unknown (see below).

**Connection to `../hwfuzz`.** The fuzzer's input is a byte string of records; its coverage
includes an application observer. Fine timing adds two input dimensions, per-edge offsets and
glitch widths or positions, and TDC-measured response times, bucketed, as observer features.
Coverage-guided search could then look for the offsets at which a target's state machine
misbehaves, not only the data that does. That is fault-injection fuzzing with the timing generator
on the same chip.

## Timing and implementation

### Liberty numbers (`sta/liberty_delays.txt`)

sg13g2, 1.2 V core; corners fast 1.32 V −40 °C, typ 1.20 V 25 °C, slow 1.08 V 125 °C. Fanout-of-one
chains with self-consistent slews and a 2 fF wire allowance:

| Cell | fast | typ | slow | Area |
| --- | --- | --- | --- | --- |
| buf_1, per stage | 42.6 ps | 63.2 ps | 101.0 ps | 7.3 um2 |
| inv_1, per stage | 22.3 ps | 32.6 ps | 52.1 ps | 5.4 um2 |
| dlygate4sd1_1 | 89.3 ps | 134.3 ps | 216.4 ps | 14.5 um2 |
| dlygate4sd3_1 | 252 ps | 371 ps | 592 ps | 16.3 um2 |
| dfrbpq_1 clock-to-Q | 0.11 ns | 0.17 ns | 0.27 ns | 49.0 um2 |
| xor2_1, A versus B arc mismatch | 3–6 ps | 5–9 ps | 8–12 ps | 14.5 um2 |

A tap therefore spans 2.4x between corners. That is why the delay line needs calibration, and why
its length is set by the fast corner.

### Synthesis and static timing (`sta/`)

**Synthesis.** Yosys, typical liberty, 2 output + 2 input pins: 101 cells, 2,633 um2, of which 42
flip-flops are 2,058 um2. Per pin that is 8 flip-flops out and 12 in, about 500 um2 and 750 um2.
For scale, `../deadline-sequencer`'s die (36,663 um2) is about 1.2 Tiny Tapeout tiles.

**SDC.** Four `create_clock`s on ph0 to ph3, with the same period and waveforms shifted by P/4, P/2
and 3P/4. They are related clocks, not asynchronous groups, because data crosses from ph0 into the
other phases. With generated phases on chip they become `create_generated_clock`s off the source,
plus uncertainty for the phase error.

**Results** (OpenSTA, ideal clocks, no CTS):

- every corner and period passes (15.0, 16.67 and 18.8 ns);
- worst setup slack +2.05 ns (slow, 15 ns), worst hold +0.10 ns (fast);
- the tightest real transfer is ph0 → ph1: a quarter period for clock-to-Q, one XOR and setup,
  about 0.6 ns at the slow corner (0.27 + 0.13 + 0.19) against 3.75 ns;
- the reported worst path starts at `clear` with a 1 ns input delay into a ph1 flip-flop: a
  quarter-period budget. The RTL has one synchronous clear shared by all four phase domains (yosys
  ties the flip-flops' asynchronous resets high). It meets timing here, but a silicon version
  should give each phase domain its own reset synchroniser, which is not built. Keep the pins'
  output enables low during reset, because the lanes leave reset on different phases.

**Lane-to-pin mismatch.** Clock-to-Q plus the XOR tree, the spread over the four lanes including
rise and fall: 18 ps fast, 35 ps typ, 48 ps slow. That is small against the ±400 ps the FM test
tolerates, so the XOR combiner's own skew does not matter. The unknowns are clock-tree skew between
the four phase trees (no CTS was run) and the pad.

### Glitches in the XOR combiner

- **One lane changes at a time.** A lane changes only at its own phase edge, and the four phases
  are a quarter period apart (3.75 to 4.7 ns). So the XOR never sees two inputs change within its
  own delay: there is no glitch from the combiner by construction. This is an argument from the
  structure and the STA numbers, not a simulation result: both simulations are zero-delay and only
  look at the pin between edges, so neither could see a glitch. The rule to keep: lanes of one
  pin must change at distinct phases, and the phase-to-phase skew must stay well under a quarter
  period, or edges reorder. A quarter pulse would then invert and become a runt of the skew's
  width.
- **The planted faults show the failure.** "Lane 2 on phase 3" puts two lanes on one edge; iverilog
  and Cyclesim both catch it (15,020 and 33,858 wrong quarters).
- **Tolerable skew.**
  - Function survives any skew below a quarter period minus the ph0 → ph_p transfer (clock-to-Q +
    XOR + setup, about 0.6 ns slow): about 3 ns at 66 MHz. iverilog passes at ±1.5 ns.
  - FM quality survives ±400 ps with 1.6 dB lost in SINAD*.
  - Receive survives ±1 ns to ±10 ns jitter.
- **Pulse width.** The shortest pulse the stage can make is a quarter clock: 3.75 ns at 66.5 MHz,
  or 4.2 ns at 60. Tiny Tapeout's published sky130 output figure is 33 MHz; no output-pad figure
  was found for IHP (`notes/tiny-tapeout-ihp-rules.md`). So quarter-width pulses and runts at the
  pad are unverified.
- **FM does not need short pulses.** Its edge rate is the clock-grid version's; only the placement
  changes.

### Phase sources: verdicts

| Source | Grid | Placement error | Cost | Verdict |
| --- | --- | --- | --- | --- |
| Both clock edges (negedge flip-flops) | half clock | the clock's duty-cycle error plus rise/fall asymmetry of the tree; unmeasured, likely a few hundred ps | nothing: 2 phases for free | Enough for receive (±6 to 8 ns instead of ±3). Not enough for FM (tone at a third of its amplitude). Do it first. |
| Quadrature pair from the RP2350's PIO on an input pin | quarter, exact in system-clock ticks | pad, board and the two clock trees' insertion delays differ: unknown, must be measured on chip | 1 input pin | Quadrature needs 4 PIO ticks per period, so the chip clock is at most sys/4: **37.5 MHz at the RP2350's rated 150 MHz**, 60 MHz only with a 240 MHz overclock. It costs the chip its clock speed. Tiny Tapeout's documented second-clock recipe assumes independent domains, which this is not (see below). |
| On-chip delay line, taps picked by calibration | quarter (or any) | half a tap plus INL: about ±30 to 50 ps typ, re-calibrated for temperature | a chain plus three tap muxes; calibration uses one sampling flip-flop | The best option: works at any clock, precision far beyond what FM or receive need. Taps must be placed as a fixed macro, since placement and routing make the taps uneven. |

**The Tiny Tapeout second-clock recipe.** It maps a clock onto a `ui_in` pin as an independent,
same-frequency domain with `set_clock_groups -asynchronous`. Our quadrature clock interacts with
ph0, so it needs the two clocks declared with a known phase plus uncertainty. The FAQ recipe was
also written against an older OpenLane (not checked on LibreLane 3). The delay line avoids both
problems.

### The programmable version: a DTC per lane, a TDC per input

**Structure.** Each lane's toggle flip-flop drives its own tapped delay line, and a multiplexer
picks the tap: the edge leaves at the clock edge plus k taps. With a line covering a quarter period
the four phases give the coarse part. With a line covering a whole period, a single clock suffices.
The input lanes use the same line two ways:

- a multiplexer on the delayed input gives a programmable sampling instant (eye scans);
- a flip-flop per tap gives a single-shot thermometer TDC.

**Size** (fast corner sets the tap count; `sta/dtc_area.txt`):

| Line | Taps at 60 MHz | Taps at 50 MHz | Chain | Mux tree (mux4) | TDC flip-flops |
| --- | --- | --- | --- | --- | --- |
| buf_1, whole period | 392 | 470 | 2,845 um2 | 4,991 um2 | 20,626 um2 |
| buf_1, quarter period | 98 | 118 | 711 um2 | 1,257 um2 | 5,157 um2 |
| dlygate4sd1, whole period | 187 | 224 | 2,714 um2 | 2,362 um2 | 9,839 um2 |
| dlygate4sd1, quarter period | 47 | 56 | 682 um2 | 610 um2 | 2,473 um2 |

**Resolution.** 42.6 / 63.2 / 101 ps per buf_1 tap at fast / typ / slow; twice that with dlygates.
The FM table shows that even 100 ps taps are far beyond the need (85 dB SINAD* before INL).

**The cheap point.** Four phases plus a quarter-period dlygate line per lane: about 1,300 um2 per
lane (chain and mux4 tree) plus a 6-bit select register (about 300 um2), so about 6,500 um2 per pin
with four lanes, at about 90 to 130 ps resolution. A full-period buf_1 line per lane costs about 7,800 um2 per lane, which is too much for
more than one or two pins.

**Shared clock line.** The alternative delays the clock instead of the data: one chain shared by
every lane, and a mux per lane selecting that lane's clock. It is cheaper, but clock muxing has the
stricter switching rule below.

**Calibration.**

- The TDC, or a single flip-flop sampling a swept tap, finds how many taps one clock period spans.
  The simulated line counted 264 at typ.
- A taps-per-clock register then scales the firmware's fine offsets, which are given in fractions
  of a clock (an 8 × 9-bit multiply per write, one write per clock). Firmware and compiler never
  see the corner.
- Code-density calibration fixes DNL: count TDC hits per tap under random input timing, then use a
  per-tap table.
- Re-calibrate periodically for temperature and voltage.

**Glitch-free tap switching** (data-tap variant). A lane's select may change only while its line is
quiet between the old and new taps: after the lane's last edge has passed both taps, and before its
next edge reaches either. Concrete rules:

- With four phases and a quarter-period line, update lane p's select on phase (p + 2) mod 4. Half a
  clock after its launch edge, the last edge has left the used taps (at most a quarter period), and
  the next launch is half a clock away.
- With a whole-period line, rotate a pin's edges over its four lanes, never use a lane in two
  consecutive clocks, and update its select in the idle clock.

For the shared-clock variant, the old and new tapped clocks must both be low (or both high)
throughout the switch. That limits a single step to under half a period.

**Per-edge offsets from the thread.** Only 2 bits are free in SETP. A FINE instruction (opcode E,
currently a NOP) would load a per-thread 8-bit offset, in 1/256 clock, applied to that thread's next
pin write. The FM NCO would compute each edge's exact fraction as (1 − acc_frac) × (1/inc), with
1/inc written by firmware together with inc (a 16 × 16 multiply). Neither is built. The DTC, TDC and
target here are behavioural.

**Nonlinearity and jitter.**

- **Random mismatch** makes INL a random walk. At 3 % per stage (an assumption, not a PDK Monte
  Carlo figure) the simulated line's worst INL over a clock was 41 ps.
- **Systematic INL** from placement and routing is likely larger and is why the line should be a
  placed macro.
- **Supply noise** modulates every tap and is probably the dominant jitter. It is unquantified
  here.
- **Effect on FM:** 5 ps per stage of INL gives 59 dB SINAD*, 20 ps rms jitter gives 85 dB, a 2 %
  scale error gives 50 dB.

## Evidence

| Claim | File |
| --- | --- |
| stage vs model, faults, sequencer through stage, 10BASE-T TX, 17-quarter train | `results/main.txt` |
| real-clock Verilog in iverilog, skews, fault | `results/iverilog.txt` |
| ISA lockstep and planted faults | `results/isa-controls.txt` |
| FM rows, skew and jitter tolerance, DTC rows | `results/fm.txt` |
| receive jitter table, differential check, sampler check | `results/rx-jitter.txt` |
| shmoo, control, response-time histogram, runt sweep | `results/shmoo.txt` |
| liberty delays, synthesis, STA, lane spread, delay-line area | `sta/liberty_delays.txt`, `sta/synth.log`, `sta/sta_summary.txt`, `sta/dtc_area.txt` |
| codex adversarial review and what was done about it | `results/codex-review.txt` |

## Open questions

- **Output pad.** How fast does IHP's output pad really toggle, and how does it distort a 1 to 4 ns
  pulse? This decides the runt and glitch uses, not FM placement.
- **Clock trees.** What is the skew between four phase clock trees after CTS? No layout was run. A
  delay-line phase source would need its taps placed as a macro, and LibreLane would have to leave
  the chain alone (ring oscillators need `keep` attributes).
- **Second clock on LibreLane.** Does Tiny Tapeout's second-clock recipe work on LibreLane with a
  related (not asynchronous) clock?
- **RP2350 HSTX.** Could the RP2350's HSTX peripheral (double-data-rate serial output, from
  memory of its datasheet: up to 150 MHz, so 300 Mbit/s per pin) give a quadrature pair at up to
  75 MHz, and are its pins wired to the chip's inputs on the demo board? Unverified; if so, the
  quadrature source would not cost clock speed.
- **Real 10BASE-T jitter.** What edge jitter do real 10BASE-T links deliver? That sets how much of
  the ±10 ns is needed.
- **Supply-induced jitter and mismatch.** Both need a SPICE or Monte Carlo view of the sg13g2
  cells.
