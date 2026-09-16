# Brainstorm: novel designs for the Jane Street protocol-emulator ASIC competition

Source: <https://blog.janestreet.com/protocol-emulator-asic-competition/>
Deadline: 2027-01-18. Target: IHP 130nm CMOS5L via Tiny Tapeout, 6x4 tiles
(~24 tiles, ~24K logic cells, plus SRAM — the post explicitly hints SRAM for
instruction memory; possibly 8x4 if the larger allocation materializes).

The post rewards two things: **unique functionality** and **novel
design/verification methodology**. A well-executed RP2040 PIO clone wins
neither — it exists. Budget roughly "2–4 PIO-class state machines + a few KB
SRAM + one clever block".

## Architecture ideas (functional novelty)

1. **Timed-automata engine instead of a CPU.**
   Replace fetch-decode-execute with a table of states in SRAM: each state =
   (pin drive mask, wait condition {edge / level / timeout / pattern-match},
   next state, timeout escape). No ALU, no pipeline — a protocol *is* a timed
   finite automaton anyway, so the hardware runs the natural model directly.
   Much smaller per state machine than a PIO-style CPU, so 4–8 of them are
   affordable, and the semantics are trivially amenable to formal proof (see
   methodology). Nobody has taped out a "timed automaton as ISA" protocol
   engine.

2. **Emulator + analyzer closed loop.**
   Everyone will build transmit/receive; few will close the loop. Timestamped
   capture of pin transitions into a ring buffer, and let programs *branch on
   measured timing* (auto-baud, adaptive clock-stretch tolerance, measuring an
   unknown device's bit period before speaking to it). Turns the chip from
   "protocol peripheral" into "reverse-engineering instrument" — exactly how
   the post frames Jane Street's interest. Top pick for a headline feature.

3. **Naughty mode / fault injection.**
   A protocol emulator that deliberately *violates* the protocol: programmable
   timing jitter, early/late data, NAK injection, clock-stretching attacks,
   arbitration-loss tests on I2C/CAN. For testing the robustness of other
   people's hardware — genuinely useful, on-theme for hardware RE, and nearly
   free in gates once a programmable timing engine exists.

4. **Sub-cycle resolution via delay lines.**
   Standard cells only: a tunable inverter-chain delay on output edges and a
   simple TDC on input edges give pin timing finer than the clock period. This
   is what makes the stretch goals (low-speed USB, 10BASE-T Manchester)
   plausible at TT-class clock speeds; ring-oscillator/delay-line blocks have
   precedent on Tiny Tapeout. Higher risk (PVT variation), but very "novel
   design" flavoured.

5. **Programmable CRC/LFSR assist.**
   A small CRC engine with the polynomial in a register (plus scrambler mode)
   is a few hundred cells and unlocks CAN, USB, Ethernet, SDI-12 etc. in
   firmware. Cheap "assist hardware" that distinguishes an architecture from a
   bit-banger.

6. **The meta move: firing-squad fabric.**
   A 1-D array of tiny identical cells, one per pin, that self-synchronize to
   emit precisely aligned waveforms — a cellular-automaton protocol engine, in
   homage to my firing-squad puzzle submission (itself inspired by their
   reverse-engineering puzzle). Probably not the most practical architecture,
   but as a *story* it's the kind of thing that gets a design remembered.
   Could be a secondary block rather than the main engine.

### Killer apps to demo (firmware, not gates)

- SWD/JTAG — the chip becomes a debug probe (the single most compelling demo
  for the RE audience)
- SPI-flash / I2C-EEPROM dumper
- 1-Wire, WS2812, PS/2, MIDI, DMX512, NEC IR, Wiegand, ISO 7816 smartcard
- One-line pitch: "an open-source Bus Pirate in silicon"

## Methodology ideas (verification novelty)

7. **Mechanized ISA/timing semantics in Lean 4.**
   The state machine of idea #1 has a tiny, clean semantics. Prove (a) the RTL
   refines the ISA-level timed-automaton semantics, and (b) properties of
   *firmware*: e.g. "the UART program meets its timing spec for all baud
   divisors in range". Aristotle is well-suited to the firmware-side proofs.
   "First tapeout with a formally verified pin-timing ISA" is exactly the
   "novel verification methodology" they're asking for.

8. **GDS round-trip verification.**
   The previous puzzle produced a GDS→gate-level-netlist extractor and
   simulator (`hardware-2026-08/work/extract.py`, `work/sim.py`). Point it at
   *our own* post-P&R GDS and run the full firmware test suite against the
   extracted netlist. Almost nobody does post-layout functional
   re-verification on a Tiny Tapeout budget; the tooling already exists.
   Great write-up material.

9. **Hardcaml end-to-end, with the puzzle's tricks.**
   Model in Hardcaml, `verdict_property_test.ml`-style property testing, and
   generate protocol firmware from a high-level OCaml description (a tiny
   "protocol DSL" that compiles to the ISA, with the compiler itself tested by
   random program generation + differential testing: Hardcaml sim vs.
   synthesized netlist vs. Yosys-level sim).

10. **On-chip fuzzer.**
    LFSR-based constrained-random traffic generator + protocol-violation
    checker in hardware: the chip fuzzes the DUT and reports violations.
    Small in gates, doubles as BIST, and directly echoes the post's "random
    constrained tests" language.

11. **AI-assisted firmware + formal backstop.**
    Use an LLM to write new protocol implementations from datasheets, but gate
    acceptance on the timing proof / differential tests. A concrete, honest
    answer to their "AI-assisted design and verification" theme rather than a
    hand-wave.

## Suggested headline combination

A **timed-automata protocol fabric** (#1) with **closed-loop measurement**
(#2) and **naughty mode** (#3), SRAM program store, **CRC assist** (#5),
**verified in Lean 4** (#7), with **post-GDS netlist re-verification** reusing
the existing extractor (#8) — demoed as an SWD probe and an auto-bauding
UART/SPI/I2C analyzer. Every element is either a functionality novelty or a
methodology novelty, it fits ~24 tiles, and it reuses real assets that
already exist.

## Open questions / feasibility checks

- Cell-count estimate for the automata engine (states × entry width in SRAM,
  sequencer in std cells).
- What SRAM macros the CMOS5L Tiny Tapeout template exposes.
- Whether a delay-line TDC survives P&R usefully (PVT spread on SG13G2).
- Clock speed realistically achievable → which stretch goals (USB LS,
  10BASE-T) are in reach with/without sub-cycle timing.
