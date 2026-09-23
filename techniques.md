# Getting more out of a tiny chip with a big host

Techniques that move work off the chip to a computer with time to spare,
before the chip runs (compilation, precomputation, search) or after it
runs (decoding, analysis). Each entry says what leaves the chip, what
stays, and what it would do in this project. The organising rule, shared
with systolic arrays: fix the schedule in hardware, compute everything
else offline. Every measured block that follows it closed timing with
margin on IHP sg13g2; the reconfigurable fabric, which does not, did not.

## Move the decision to compile time

- **Static scheduling.** The compiler decides the cycle of every operation,
  so the hardware needs no arbitration, interlocks, handshakes or queues.
  Groq's processor is the extreme; the deadline sequencer is the small
  version. Cost on chip: negative, it removes logic.
- **Time-multiplexed hardware.** One datapath serving several logical
  machines in fixed slots (the sequencer's barrel threads). The radical
  form is the time-multiplexed FPGA of the 1990s and later Tabula:
  configuration streamed from memory every cycle, so the fabric is one
  context of logic and the memory holds many. With an SRAM macro at 6 to
  8 um2 per bit against 31 for a latch, streaming configuration from SRAM
  is how a table-driven design would come back to life here.
- **Proof-checked loading** (not proof-carrying: the chip cannot check a
  proof). The loader on the host consumes the compiler's proof and the
  chip trusts what it is handed, so bounds, ownership and timing checks
  are software. Nothing needs to reach the chip, not even provenance:
  the host knows what it loaded, and if it is ever unsure, reloading is
  cheaper and more certain than reading anything back. Corruption after
  loading is handled the same way, by reloading at every session start
  and whenever in doubt.
- **Health checks off the chip too.** An on-chip pin-ownership check
  costs about a tenth of the sequencer and prevents a drive fight that,
  on chip, warms a spot rather than killing the die; the fatal case is an
  external device driving a pad the chip also drives, which no on-chip
  check can see and a series resistor on the breakout board absorbs for
  free. Move the watchdog to the RP2040 on the demo board and accept the
  residual risk.

## Move the function into data

- **Waveforms as programmes.** The host precomputes exact sample streams
  (NRZI with bit stuffing, Manchester, CRC appended), run-length coded;
  the chip plays them at one sample per cycle. Decompression is a
  counter. Cheapest transmitter for the fast protocols; the time-triggered
  ISA in disguise.
- **Templates instead of decoders.** The correlator's templates,
  precomputed per fractional phase, replace a clock-recovery circuit. Any
  classifier over a window of samples reduces to templates and thresholds
  computed offline.
- **Linear functions as taps.** CRC, scramblers and syndromes are linear
  over GF(2), so each is a shift register with programmable taps and the
  tap matrix is computed offline. One array serves every polynomial.
- **Tables in SRAM.** Any function of about ten bits is a lookup: state
  machines, packet-field decision trees, address matching, perfect hashes.
  The offline work is state minimisation and encoding.

## Move the numerics

- **Rational timing by accumulator.** Any bit period, fractional included,
  is a phase accumulator with compile-time constants (Bresenham).
- **Noise-shaped timing.** Where an edge cannot land on the right cycle, an
  offline-computed dither pattern makes the average edge exact and pushes
  the error spectrum where the receiver's filter rejects it: sigma-delta
  applied to time. With a delay line it gives sub-cycle placement without
  a PLL.
- **Fractional oversampling.** Sample at whatever the clock gives and
  decode at that ratio with offline-designed filters, rather than building
  a clock at the line rate.

## Move the learning

- **Calibration by search.** Delay lines, oscillators and thresholds are
  characterised after fabrication by the host; the chip stores the result
  and carries no calibration hardware.
- **Reservoir computing.** The disciplined form of Thompson's evolved
  circuit: a fixed nonlinear dynamic system on chip (coupled delay lines
  or oscillators), and only a linear readout trained offline. Used to
  decode real signals in the literature. The wild card: the spare chips
  would let us measure whether a readout trained on one die transfers.
- **Identity from variation.** A physically unclonable function is the
  same move; enrolment and error correction live off-chip.

## Move the decoding

- **Sample and ship.** The chip is a sampler, a buffer and a link; every
  protocol is decoded on the host. The limit is the link to the RP2040,
  tens of megabits, which is why the systolic front end matters: it
  compresses samples into edge timestamps or hits, and the host decodes
  those. The analyser mode and the emulator mode are the same hardware
  with the decoding moved in opposite directions.
- **Superoptimisation.** With a 64-word programme memory, the shortest
  programme meeting the timing constraints is worth an exhaustive or
  solver-driven search, run once per protocol on the host.

## Where to pull first

The waveform player and SRAM tables are cheap and immediately useful for
the fast protocols; sample-and-ship with edge compression gives the
analyser mode almost for free; noise-shaped timing plus the delay line is
the exact answer to Ethernet's fractional ratio; reservoir computing is
the one that would make a judge sit up, with a real risk of not working,
which the spare chips are for.

## The principle underneath: specialised hardware, general software

Build hardware that does not look general purpose: sparse links, a ring
here, a few random shortcuts there, fixed tables. Then spend the smarts
offline, in search and compilation, to make it do what is wanted anyway.
Precedents: compressed sensing (random measurements, clever recovery),
reservoir computing (random network, trained readout), superoptimisation
(fixed instruction set, exhaustive search for the program), and the
drum-memory programmers who placed each instruction to arrive just in
time.

Interconnect options, cheapest to most general:
- **Sparse shortcuts.** A few long links turn a ring's n-hop paths into
  about log n (the small-world effect); because routes are computed
  offline, any sparse set works, including random ones, with no need for
  the special distributions that on-the-fly routing requires.
- **Designed link sets for specific algorithms.** Coprime lengths for
  prime-factor FFTs (a GPS C/A code is 1023 = 3 x 11 x 31 chips); prime
  lengths with a closed ring for Rader's transform; Golomb rulers and
  difference sets so that every lag appears exactly once, as in
  minimum-redundancy antenna arrays.
- **Random, then chosen.** Draw many random sparse link sets, compile and
  simulate the target programs on each, keep the best, and compare
  against structured baselines rather than assuming randomness wins.
- **A Benes network** where arbitrary rearrangement is needed: every
  permutation in about 2 log n stages, with switch settings computed
  offline.
- **Links between levels** (pixel, line, frame, and delayed links across
  time): stencils and shadows from a skip link to the background stage,
  frame-rate automata driving per-pixel operations.

Two disciplines keep this honest. Measure expressiveness: for each target
program the compiler either finds a schedule on the sparse hardware or
says it cannot, and the success rate is counted against a dense baseline.
And treat failure as information: a failed search points at the link or
table entry that would have made it possible, which is how the hardware
should grow. Keep long wires few and visible to the router early; they
are what made an eFPGA tile 78 % routing.
