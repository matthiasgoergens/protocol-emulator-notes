# Synthesis of the three brainstorms

Inputs: [brainstorm-kimi.md](brainstorm-kimi.md),
[brainstorm-codex.md](brainstorm-codex.md),
[brainstorm-claude.md](brainstorm-claude.md). Written 16 September 2026.

The three were produced independently, so agreement between them is
evidence and disagreement is a question to settle by measurement. Both are
listed below, then a merged proposal, then the experiments that decide the
open points.

## 1. Where all three agree

1. **The primitive is "wait for an event with a deadline", not an ALU op.**
   Kimi calls it a timed-automata engine, codex calls it programmes with
   timing contracts, Claude calls it a time-triggered ISA. All three reject
   a general CPU with a fast loop as the core, because timing must be exact
   by construction rather than by counting instructions.
2. **The loop must close.** Capture and timestamp the other side's edges,
   and let programmes react to measured timing: auto-baud (kimi), reactive
   replay of a recorded device (codex), programme-as-waveform (Claude).
3. **Misbehaving on purpose is a feature.** Fault injection (kimi), timing
   envelope sweeps (codex's "timing microscope"), protocol tester (Claude).
   It is cheap once a programmable timing engine exists and it is the kind
   of "novel functionality" the judges asked for.
4. **A firing-squad-style spatial fabric is the memorable idea and the
   risky one.** Kimi: "probably not the most practical". Codex: "most
   adventurous, synthesis experiment first". Claude recommended it as the
   engine and is the outlier. The decisive datum is in
   `hardware-2026-08/hardcaml_firing_squad/BUILDING.md`: the full
   rule store mapped to roughly 99,000 SKY130 instances, about four times
   the whole 24K-cell budget. Full neighbourhood tables are out; only
   sparse rules or small per-cell programmes could survive.
5. **Verification is half the submission.** All three want a differential
   test of an executable reference model against the RTL with random
   programmes, all three want AI-written firmware gated by tests, and two
   (kimi, Claude) want the GDS-to-netlist extractor from the puzzle turned
   on our own layout. Nobody else entering will have that tool.

## 2. Where they disagree

| Question | Kimi | Codex | Claude |
| --- | --- | --- | --- |
| Where the timing guarantee lives | Lean proof that RTL refines the automaton semantics | Host compiler checks deadlines; chip stays simple | Hardware structure (barrel threads, one-clock cells) makes timing trivial |
| Engine | Timed-automaton table in SRAM | Small sequencer, decide by experiment | Table cells under a barrel-threaded scheduler |
| Novelty bar | Feature list | Must beat XMOS timestamped ports and NXP FlexIO; novelty is the composition | Feature list plus prior-art reading list |
| Headline demo | SWD debug probe, auto-bauding analyser | Recorded sensor replaced by the chip, still working when the controller's timing changes | Bridge between two protocols |
| Sub-cycle delay lines | Yes, high risk | Not mentioned; warns digital proofs say nothing about analogue pins | Bolt-on, calibrate at run time |
| Memory | Open question | Warns CMOS5L macros may differ from the SG13G2 tables | Cites SG13G2 macro sizes as if final |

The three positions on the first row are layers, not rivals: deterministic
hardware makes the host compiler's timing analysis tractable, and a formal
semantics is what both are checked against. The engine question is a
measurement, see section 4. Codex is right about the novelty bar and about
memory: the SG13G2 numbers in the Claude file must be re-confirmed for the
CMOS5L branch before any memory-heavy design is chosen.

## 3. Merged proposal

**Thesis, in codex's framing:** a protocol is a timed conversation. Describe
it once. The chip runs either endpoint, monitors the exchange, or replaces a
recorded device. The host proves the timing before the chip runs.

**Hardware, smallest thing that carries the thesis:**

- A deterministic sequencer whose instructions are: wait for edge, level,
  pattern or deadline; atomic pin write with output enable; shift; count;
  bounded branch. Missed deadlines are reported, never silent.
- Two to four hardware threads, round-robin, so concurrent protocols have
  zero mutual jitter (Claude). Each thread owns pins statically; the
  compiler rejects conflicting ownership (codex).
- Assist blocks everyone agrees on: shift registers with programmable
  dividers, without which low-speed USB and 10 Mbit Ethernet are
  unreachable at 66 MHz; a CRC/LFSR unit with a loadable polynomial (kimi);
  a timestamped edge-capture buffer sharing the SRAM with programme store.
- Fault-injection hooks on the pin path: jitter, delayed or early edges,
  bit flips into the CRC unit (kimi, codex, Claude).
- Optional, only if it closes timing: a calibrated delay line for sub-cycle
  output placement. Never in the critical path of the main design.
- A ROM "hello" programme and a serial loader that needs two pins, so first
  silicon is testable from the RP2040 within minutes.
- The spatial fabric survives only as a demo block if measured area allows,
  or as a nod in the write-up.

**Software:** a small protocol language with roles (codex). One description
compiles to controller, peripheral and monitor programmes, and to an OCaml
reference interpreter. Keep independently written reference models for
UART, SPI and I2C so a bug in the shared description cannot certify itself
(codex's warning).

**Verification stack, cheapest first:**

1. Hardcaml property tests in the style of the firing-squad testbench.
2. Lockstep differential test: interpreter versus RTL, random programmes,
   fixed seed, compare pins every cycle.
3. `hardcaml_verify` bounded proofs of the per-instruction timing claims.
4. Lean semantics of the ISA if time allows (kimi); the interpreter is the
   fallback specification.
5. RP2040-side MicroPython tests against Verilator through a socket, then
   unchanged against silicon (Claude).
6. Mutation score of the suite, reported as a number (Claude).
7. GDS round trip on the final layout with the puzzle extractor ported to
   the IHP cell library (kimi, Claude).
8. AI-written firmware for a protocol nobody on the team wrote, accepted only
   if it passes 2 and 5, with the failure points reported (kimi, Claude).

**Demos, in order of persuasiveness for this audience:** the recorded-sensor
replacement (codex), the SWD probe (kimi), the timing-envelope sweep of a
real peripheral (codex, kimi), and a post-fabrication protocol none of the
three brainstorms named, to prove reprogrammability.

## 4. Experiments that settle the open points

Run these before writing the design document, and fix the acceptance
criteria before looking at results.

1. **Memory.** Read the CMOS5L template and the Tiny Tapeout memory page for
   what macros exist on that branch. This gates everything.
2. **Engine bake-off** (codex's discriminating experiment). Implement a
   programmable UART transmitter, then SPI and I2C, on a compact sequencer
   and on a sparse rule engine. Compare mapped cells, programme bytes and
   worst-case reaction latency under the same synthesis constraints. The
   blog's own advice is to start with the UART transmitter, so this is not
   extra work.
3. **Clock closure.** Place and route the sequencer with an SRAM in the path
   and record the achieved frequency; that number decides whether 10 Mbit
   Ethernet is in scope.
4. **Extractor port.** Run the puzzle's GDS extractor on the template's own
   example design in the IHP library, so the tool is validated before it is
   needed (the puzzle work's first rule: never point an unvalidated tool at
   the real thing).

## 5. Gaps none of the three covered

- **The host interface.** All three assume the RP2040 loads programmes and
  reads results, none designs the path. A bridge or an analyser produces
  data faster than a serial loader can drain it. Decide early whether the
  8 dedicated inputs and 8 outputs form a parallel host bus, and what that
  costs the protocol pin budget.
- **Input synchronisers.** Two flip-flops of metastability protection add
  two cycles of latency and one cycle of uncertainty to every measured
  edge. Codex mentions the uncertainty; nobody states the resulting timing
  resolution, which every guarantee and every "timing microscope" number
  depends on.
- **Team and split.** The post strongly recommends a team. The proposal
  splits cleanly into hardware, language and compiler, and verification
  tooling, and the deadline is 18 January 2027.
