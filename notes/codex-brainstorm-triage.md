# Codex brainstorm triage (2026-09-26)

This triage treats `notes/codex-brainstorm-2026-09-25.md` as proposals, not
evidence. The controlling goal is the one programmable chip in `NEXT.md`:
protocols and demos should be programmes or configurations of a few generic
blocks. The useful ideas below are gated by the existing evidence and gaps in
`notes/backlog.md` and `notes/architecture-v0.md`.

## Decision summary

- Keep the SRAM programme-store safety net, but use the architectural plan of
  record, 512×16, unless a measured image-capacity experiment proves that a
  reduced 256×16 profile is sufficient. The proposed 256×16 store is not
  sufficient for the broader protocol programme.
- Run the agents-programming-the-chip claim as a controlled eight-task
  experiment. Test the narrow claim that agents make expert scheduling
  repeatable when hazards are enumerable and an independent judge exists.
- Make the learn–break–emulate “silicon laboratory” a staged demonstration
  built from the generic blocks, not a replacement architecture or the first
  integration target.
- Keep gain cells as data memory and an isolated self-characterisation
  experiment. Do not put them on the programme fetch or protocol-critical path.
- Do not demote the general PE to a test structure. It is central to the
  one-programmable-chip direction; if area fails, reduce the PE count before
  removing generality.

## Worthwhile near-term actions

### 1. Freeze the SRAM-backed baseline and measure the real integration

**Owner:** hardware integration and physical design.

**Experiment.** Integrate the sequencer/ISA v2, exact 512×16 SRAM macro, host
load/readback, synchronised GPIO, streamer/sampler and matcher. Run UART, SPI
and I²C with every custom analogue block disabled. Lock interpreter against
RTL, then run the first whole-chip place-and-route probe with the exact macro
and report the measured placement factor, timing and macro interface.

**Success criteria.**

- UART, SPI and I²C pass independent oracle and cycle-by-cycle suites with no
  gain-cell, pump or TDC dependency.
- Programme load/readback is deterministic and complete over the chosen page
  map.
- The exact macro meets the 60 MHz interface contract, or the failure is
  recorded with usable timing and floor-area numbers.
- Every workload image has a recorded word count and page placement. A 256×16
  reduction is accepted only if all required images fit without hidden host
  execution or live patching.

**Evidence and correction.** `notes/architecture-v0.md` D4 recommends 512×16
and reports measured firmware sizes beyond 256 words; the macro is 45,309
µm², with an estimated 10 % halo in the area budget. The brainstorm’s roughly
28,000 µm² figure is
plausible for 256×16 but does not answer the capacity evidence. Its roughly
80,000 µm² baseline sum is not a substitute for G13 whole-chip place and
route. At the pessimistic placement factor, even the full 16-PE design is 11 %
over budget, so integration must measure rather than assume routability.

### 2. Run the eight-task agents experiment

**Owner:** OCaml toolchain/verifier; benchmark and statistical design; FPGA
test harness.

**Experiment.** Freeze the ISA, interpreter, compiler interface, simulator,
verifier and agent version before selecting hidden tasks. Use eight held-out
tasks, for example:

1. a JTAG boundary-scan/debug transaction;
2. an SWD line-recovery and transfer sequence;
3. a bidirectional PS/2 keyboard exchange;
4. 1-Wire reset, ROM search and timed read/write;
5. CAN arbitration with bit stuffing and error recovery;
6. difficult I²C with wired-AND arbitration and clock stretching;
7. a timed glitch search around a declared setup/hold window; and
8. a matcher-triggered response with a deadline.

These are variants of demonstrated workload classes, not copies of the
existing solutions. Hide implementations, decoders and test vectors from the
agent context. Compare two randomised arms: simulator plus verifier, and
compiler errors only. Use fresh sessions, the same fixed model and prompt
policy, balanced order within task, and no human code edits. Five sessions per
task and arm is a pilot floor; choose the final repetition count from a
predeclared power calculation for a 30-percentage-point effect before
unblinding.

**Primary endpoint.** Independently accepted output without human code edits:
the hidden decoder, cycle-exact reference and FPGA/loopback replay must all
accept the submitted programme.

**Secondary measures.** Success rate, wall-clock time, attempts, token or
compute cost, human interventions, programme words, verifier iterations and
worst timing margin. Preserve every failed attempt and counterexample.

**Success criteria.** The narrower thesis is supported only if the
task-stratified acceptance improvement reaches the predeclared 30-point
practical margin and its interval excludes zero. Report all eight tasks
separately. Sessions are nested within tasks and are not eight independent
protocol populations; an interval that includes zero is inconclusive, not
evidence of equivalence. Any task accepted only in simulation is a negative
result for the physical chip claim.

**Why this is useful.** It directly tests `notes/backlog.md`’s proposed
agents-plus-simulators experiment while avoiding the brainstorm’s unsupported
claim that agents can discover information absent from their observations.

### 3. Build the timing debugger in gates

**Owner:** timing/FPGA systems; hardware-security host tools.

**Experiment and gates.**

1. Reproduce the claimed PAL-clock 10BASE-T failure at ±4–5 ns on fresh runs.
2. Plant a setup/hold defect in an FPGA target and test differential phase,
   pulse-width and jitter search against a golden target.
3. Calibrate the TDC and four-phase output by internal and external loopback,
   reporting monotonicity, DNL/INL, jitter and PVT shmoos.
4. Only then build the undocumented “sensor”, timed state-machine learner and
   emulator substitution.

**Success criteria.** The planted defect is found and minimised in a
predeclared majority of fresh randomised campaigns, while the golden target
produces no false failure. The minimised witness replays on a fresh process.
For learn–break–emulate, a hidden controller test set must accept the emulator
over legal commands, boundary timings and calibrated glitches; report query
budget and counterexamples rather than claiming formal equivalence from a
passing demo.

This is a strong demonstration if the early gates pass. It is too integrated
to be the first baseline because it depends on the TDC, analogue timing,
matcher, `hwfuzz` oracle and host learner at once.

### 4. Isolate and repair the gain-cell memory programme

**Owner:** memory model/compiler; physical verification.

**Experiment.** First replace the one-way decay abstraction with the observed
0→1 and 1→0 failures. Quantify residual undetected-error probability for a
replacement code, then test thin, thick and pumped rows in an isolated array
with programmable wait/sense times and adversarial neighbour patterns. Have an
independent final-binary checker recompute every read/refresh deadline and
mutate lifetime bins, stale entries and port conflicts.

**Success criteria.** A schedule just inside the declared contract passes and
one just outside is rejected; the checker catches every planted off-by-one and
stale-bin mutant; raw row/lifetime maps are retained. Keep this structure
outside the protocol-critical path until post-layout PVT, LVS/PEX and the
thin-oxide pump question are resolved.

## Ideas that conflict with the architecture or current evidence

- **256×16 as the general programme store:** conflicts with D4 and the recorded
  image sizes. Keep it only as a reduced, explicitly scoped baseline profile.
- **Demoting the general PE:** conflicts with the mapping table and D2/D15.
  Shrink 16 PEs to 12 or 8 under G13 pressure; do not turn the central
  programmable block into a test structure.
- **“Silicon laboratory” as the strongest entry by assertion:** this is a
  framing preference. Its learn–break–emulate loop is useful only as a staged
  generic-block demonstration after the baseline and timing gates.
- **Age-selective forensic recorder:** speculative and weakly supported. Run
  the proposed Monte Carlo, and cut it unless elapsed-time classification
  beats a counter or SRAM ring buffer by a predeclared margin.
- **Self-tuning receiver claim:** the ±4–5 ns failure is not established in the
  cited backlog or architecture evidence. Reproduce it before scheduling the
  feature.
- **`hwfuzz` novelty and the broad demoscene thesis:** three-seed trends and
  one curated programme are insufficient. Judge `hwfuzz` by mutation score,
  restored historical bugs and fresh multi-seed campaigns; judge agents with
  hidden judges and physical replay.
- **Using SRAM for code and gain cells for bulk data:** this is consistent with
  D5. The brainstorm’s “no-SRAM mode” is a useful experiment, not a reason to
  make gain-cell programme fetch a tapeout dependency.

## Open questions

- Which exact SRAM macro and page map fit the real compiled images, and what
  does G13 measure for the baseline and the 16-PE candidate?
- Can the eight tasks be held out from the public implementations and model
  context without changing the task difficulty?
- What repetitions are needed for the 30-point effect once task clustering is
  accounted for, and is five sessions per cell merely a pilot?
- Are the FPGA target, TDC calibration, hidden decoder and physical replay
  available for every task before the experiment starts?
- Does the unknown peripheral have a reproducible oracle, or would a planted
  vulnerability mainly measure the benchmark author?
- What error distribution and temperature bin should define the gain-cell
  lifetime contract, and what residual undetected probability is acceptable?
- Does the TDC/phase debugger retain a plain-clock fallback if the analogue
  calibration fails PVT or pad-speed checks?

## Recommendation

Sequence the work as: SRAM baseline and G13 measurement → verifier and
eight-task agent benchmark → differential timing fuzzer with a planted FPGA
defect → staged learn–break–emulate demo → isolated gain-cell
self-characterisation. This preserves the competition goal, turns the
brainstorm’s best ideas into falsifiable experiments, and keeps every risky
analogue or storage novelty off the protocol-critical path.
