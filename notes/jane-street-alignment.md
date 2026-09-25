# How the work lines up with what Jane Street asks for (note, 2026-09-25)

The source is the competition post of 10 September 2026, fetched on 25 September:
<https://blog.janestreet.com/protocol-emulator-asic-competition/>. Quotations are from it. The
rest is my reading, for our own planning.

## What they ask for, in their words

1. **Novelty, in two places.** "We're particularly interested in projects with unique
   functionality, as well as those that demonstrate novel approaches to design and
   verification methodologies!" They will "tape out the most novel designs".
2. **A general-purpose, reprogrammable protocol emulator.** It is "a tiny CPU with an
   instruction set designed for reading pins, writing pins, counting cycles, and hitting timing
   precisely". It should be "reprogrammable enough to support new protocols *after*
   fabrication". It should not be fixed blocks: "The goal isn't to put a UART block, an SPI
   block, and an I2C block on one die". For comparison they name the RP2040's PIO and TI's PRU,
   and ask "what you'd do differently".
3. **Protocols.** "Start with UART, SPI, and I2C." Stretch goals: "low-speed USB and 10Mbit
   Ethernet". Also worth considering: "JTAG, SWD, PS/2, CAN bus".
4. **Use.** "a useful tool for hardware debugging and reverse engineering, which is a good part
   of what we do."
5. **Open-ended.** "Show us anything else your architecture makes possible that we haven't
   thought of."
6. **Verification, emphasised.** "We are excited to see the languages and verification
   techniques you use, including formal methods, random constrained tests, AI-assisted
   verification, and more. As AI-assisted chip design becomes more common, we believe
   verification will be an extremely important aspect of the ASIC design flow going forwards."
   They use Hardcaml, and they suggest testing on an FPGA before the ASIC flow.
7. **Constraints.**
   - 6×4 tiles, about 0.7 mm², and "about 1K logic cells per tile".
   - The "CMOS5L Verilog template, which takes you from RTL to GDS".
   - "For instruction memory, SRAM can be more area-efficient than flip-flops."
   - Synthesise early, then place and route and check timing.
   - Open source. Deadline 18 January 2027, for the March 2027 shuttle.

## Where our work lands

| their point | what we have | fit |
|---|---|---|
| tiny CPU for pins, cycles, timing | deadline sequencer: four barrel threads, "wait with a deadline" as the primitive, 17,300 µm², closes 66 MHz | direct |
| reprogrammable, not fixed blocks | sequencer programmes from a protocol compiler; generic pin streamer and sampler; systolic matcher | direct |
| UART, SPI, I2C | compiled and checked against independent decoders and reference devices (pin sampler) | done in simulation |
| stretch: 10 Mbit Ethernet | transmit in pure firmware on the sequencer; receiver at the NTSC clock; display frames over raw Ethernet | strong |
| stretch: USB | full-speed device prototype, fuzzed with hwfuzz | strong (they asked for low speed; full speed is harder) |
| JTAG, SWD, PS/2, CAN | not yet addressed | gap: CAN's wired-AND arbitration and bit stuffing is a good test of the architecture |
| hardware debugging, reverse engineering | hwfuzz (coverage-guided Hardcaml fuzzer); four-phase stage with programmable edges and a TDC: margin (shmoo) tests, glitch injection, timing fingerprints | strong, and exactly their use |
| "anything else ... we haven't thought of" | PAL/NTSC generation chasing the beam, driven by Ethernet frames; FM on the third harmonic; systolic array effects; chaotic networks | strong |
| novel design methodology | gain-cell memory whose bits expire, with compiler-scheduled lifetimes; mixed cell rows; memory that doubles as thermometer, PUF and self-erasing storage; hand-drawn cells characterised by SPICE and Monte Carlo | very novel; also our biggest verification debt |
| novel verification | independent oracles; lockstep against executable specs; planted bugs and mutation scores; context-gated coverage in hwfuzz (no precedent found in nine RTL fuzzers); agents as programmers with an exact interpreter as judge | strong, and it matches their AI-assisted verification theme |
| Hardcaml | all RTL prototypes | direct |
| FPGA before ASIC | planned (`PLAN.md`); boards being bought | pending |
| area, about 24K cells | sequencer and matcher measured; processing element being synthesised | on track; memory area to be settled |

## Tensions, and what to do about them

**1. The riskiest novelty is the least verifiable by their methods.** Formal tools, constrained
random tests and AI-assisted verification all apply to RTL. They do not apply to a hand-drawn
gain cell, a charge pump, a delay line or level-shifted bit lines. If we go crazy there, and
we should, verification has to come in several layers:
- **SPICE and Monte Carlo** across corners, with every artefact recorded. We already have this
  for the cells.
- **Full LVS against a schematic.** The Tiny Tapeout precheck has no LVS step, so nobody else
  will catch a wiring error. So far we only extract netlists and read them.
- **An executable model of the memory's contract** (lifetime per row, and only 1s decay) that
  the Hardcaml simulation uses. The digital side is then verified against the contract, and the
  cells are verified against it separately.
- **On-chip self-test that measures the contract in silicon:** retention profiling per row,
  Berger checks, and canary rows.
- **A fallback.** The post recommends SRAM macros for instruction memory, and they come with
  their own built-in self-test variants (a published IHP Tiny Tapeout project uses one). A small
  macro holding the sequencer's programmes, with gain cells for bulk data, keeps the chip useful
  if our cells misbehave in silicon. This runs against the aim of no SRAM safety net, so the
  choice is ours. My view: a small safety net makes the crazy part easier to defend, not harder.

**2. "Hard to program" against "general-purpose and reprogrammable".** The protocols they list
must be easy on our chip. That means:
- a compiler and library that make UART, SPI and I2C one-liners;
- the crazy features used by choice, not required for the basics.

The demoscene framing holds for the showpieces, not for the baseline protocols. The sequencer's
deterministic schedule and exact interpreter already give the right shape: a programme is
accepted only if the interpreter proves its timing.

**3. Verifying the programmes, not just the hardware.** With expiring memory, a programme can be
silently wrong. Build the verifier before the showpieces:
- deadlines met;
- every read inside its row's lifetime, at the chosen temperature bin;
- ports never double-booked;
- the pessimising scheduler as a test oracle.

That is formal verification of a new kind, and exactly the "novel verification methodology"
they ask for.

**4. The template flow.** The post starts from the RTL-to-GDS template. Custom macros are
possible through LibreLane's macro mechanism (`notes/tiny-tapeout-ihp-rules.md`), but each one
adds integration risk:
- abutment;
- pins on the right metals;
- DRC with the whole chip;
- timing across the macro boundary.

Integrate one small macro early, not all of them late.

**5. Sub-clock timing is hostile to static timing analysis.** The four-phase stage, programmable
delays and the TDC need their own verification story:
- multi-clock constraints;
- simulation with delay annotation;
- calibration verified by the TDC in silicon;
- a mode that runs everything on the plain clock grid.

**6. Coverage of their protocol list.** CAN, JTAG, SWD and PS/2 should each get at least a
compiled programme and a decoder check, since they are cheap once the compiler exists. CAN is
the interesting one, because arbitration makes the pin bidirectional and wired-AND.

## Verification as a headline, not an appendix

Their closing emphasis ("verification will be an extremely important aspect") suggests
presenting the verification stack as part of the novelty:
- **Hardware:** executable specifications in OCaml, and lockstep against them.
- **Independent oracles:** reference devices and decoders that do not share the generator's
  assumptions. Lesson: lockstep against your own specification missed a bug the specification
  shared.
- **Planted bugs and mutation scores**, to test the tests.
- **hwfuzz,** with context-gated coverage.
- **Formal:** bounded model checking of deadline guarantees (still to do, in `PLAN.md`), and the
  programme verifier above.
- **The custom cells:** SPICE, Monte Carlo and LVS, with the silicon self-test.
- **Agents and simulators:** agents write programmes, and the exact interpreter and verifier
  decide. Honest records throughout: every number traceable to a run, and artefacts found and
  corrected in the open.

That last point, the record of our own mistakes caught by checking, is itself evidence of a
verification culture. Judges who care about verification will notice it.
