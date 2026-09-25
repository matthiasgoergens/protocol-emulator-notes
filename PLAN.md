# Plan, as of 22 September 2026

What the measurements and prototypes in this repository add up to, and what
comes next. Numbers are in `datapoints.md` with their runs.

## Direction (decided 2026-09-25)

Converge on ONE programmable chip. Every protocol and every demo (the retro console and
platformer, video over Ethernet, radio, GPS, the debugging tools) must be a programme or a
configuration of a small set of generic blocks: the sequencer threads; the pin stage (streamer,
sampler, quarter-clock timing); generic protocol assists (programmable CRC, bit stuffing, line
coding, oversampling with resynchronisation, the matcher); a systolic array of one programmable
processing element; and the memory. The special-purpose prototypes built so far (the retro
console's sprite pipeline, the USB block, the Ethernet receiver) are feasibility studies to be
re-expressed on those blocks, not parts of the chip. Where a generic block falls short, extend it
minimally and name the other uses that benefit. Why: it is what Jane Street asks for ("The goal
isn't to put a UART block, an SPI block, and an I2C block on one die"), and it makes the area
budget add up. The unified architecture is being written up as `notes/architecture-v0.md`.

## The shape of the chip

Fix the schedule in hardware, compute everything else offline. Every
measured block that follows this rule closed timing with margin on IHP
sg13g2; the reconfigurable fabric, which does not, did not.

- **A deterministic sequencer** (`prototypes/deadline-sequencer/`): four
  hardware threads round-robin, one instruction per slot, "wait for an
  event with a deadline" as the primitive. 17,300 um2 synthesised, a
  third of one RP2040-PIO-style state machine, and it closes the board's
  66 MHz at every corner with 7 ns to spare. Its programmes are produced
  by a compiler and proven by exact simulation; its instruction memory is
  an SRAM macro, not yet attached.
- **Systolic arrays for the fast paths** (`prototypes/systolic-matcher/`):
  nearest-neighbour wires only, a few configuration bits per cell, timing
  fixed by geometry. The sixteen-cell correlator is 10,000 um2 and closes
  200 MHz at the slow corner. The same shape serves sync-word detection,
  majority-vote sampling, Manchester decoding, CRC as a fixed XOR network,
  and waveform playback at one sample per cycle.
- **Hardened serialisers** for anything faster than the sequencer's slot
  rate, since 10 Mbit Ethernet needs a 20 MHz toggle and the sequencer
  changes a pin at most every four cycles.
- **A small reconfigurable fabric only as glue, if at all**: measured at
  about 90 LUT4s for the whole allocation, with worst paths of 32 ns
  typical and 45 ns at the slow corner, 78 % of its tile being routing.
- **Sub-cycle timing as the bolt-on that only silicon can grade**: a
  calibrated delay line to place output edges between clocks and a
  delay-line time-to-digital converter to timestamp input edges, both
  calibrated by search from the host after fabrication. This is what
  makes the fractional 3.3 samples per half-bit of Ethernet exact and what
  a full-speed USB receiver at 5.5 samples per bit benefits from.

## The shape of the software

The compiler carries the burden, because the machines have no arbitration
and no stalls, so a programme's timing is a property of the programme.

- Today: a macro assembler in OCaml (`compiler.ml`) whose protocol
  generators derive every edge from the one-slot rule, checked by the
  interpreter's exact simulation, by independent decoders and by
  closed-form edge spacings. UART, SPI and I2C run on three threads at
  once; a stretched bit and a baud sweep show a receiver's tolerance edge
  exactly.
- Next: a timing macro ("the next edge is at slot T") so a programme is a
  declaration of edges and the padding is mechanical; then the schedule
  as an integer programme, one integer per event, ordering and spacing
  constraints from the ISA, equalities from the protocol, deadlines as
  inequalities, thread interleaving as disjunctions, with programme
  length as the objective. Branching is handled as time (both arms of a
  deadline wait are scheduled), as select (evaluate every alternative,
  choose late), as padding (deadlines turn variable latency into
  constant), or as a thread.
- An LLM agent writing programmes from a spec is an acceptable front end
  on one condition: the acceptance test stays the exact simulation plus
  decoders that do not know the generator. The agent writes, the
  interpreter proves, the decoders check.

## Verification

- Every block has an executable specification in OCaml and a lockstep
  differential test on random programmes or configurations; every test
  has been shown to catch a planted bug before being trusted.
- Place and route in the LibreLane container for every block, with all
  three corners read, and full DRC on the stock tile.
- Still to do: bounded model checking with hardcaml_verify for "every arm
  of every deadline wait meets its deadline"; the GDS round trip with the
  extractor from the earlier puzzle work, ported to the IHP cell library;
  mutation scores for the whole suite.

## Test bench before silicon

An FPGA board takes over as the test bench for everything digital: the
sequencer and correlator against real UART, SPI flash and I2C parts, a
Linux host enumerating a full-speed USB device built from these blocks,
and two boards chained for a synchronisation demo. The Hardcaml sources go
through the same Yosys and nextpnr already used here. A Raspberry Pi is
the master-side counterpart and USB host; RP2040 boards are the slaves,
the jitter-free stimulus, and the same family as the Tiny Tapeout demo
board, so test scripts transfer to the chip unchanged. What the FPGA
cannot grade is left for silicon: sg13g2 timing, which OpenROAD already
gives, anything analogue, and the chip's own variation, which is what the
calibration-by-search and portability experiments are for.

## Stretch, in order of price

1. Full-speed USB device on the standard pads: all existing pieces apply.
2. Ethernet 10BASE-T: hardened Manchester serialiser plus the delay line.
3. High-speed USB at 480 Mbit: the digital packet engine at 60 MHz on
   eight-bit words is buildable now with the same blocks and can be
   costed before anyone commits to the analogue half, which needs a
   custom differential front end on analogue pins, an eight-phase
   delay-line clock, and a carrier board. That half is a mixed-signal
   project in its own right.

## Rejected, with the measurement that rejected it

- Table-driven pin cells: a small per-pin table is a thousand
  configuration latches at 31 um2 each.
- A straight PIO clone: four machines fit but take 16 to 18 of 24 tiles.
- The reconfigurable fabric as the engine: 78 % routing by area, 45 ns
  worst path at the slow corner, about 90 LUT4s in the whole allocation.

## Decision, 23 September 2026: plain systolic arrays; the chaotic network is parked

Direction: a plain systolic array (a pipeline of identical cells with
nearest-neighbour links, as in the sprite pipeline, the correlator and the
wave ring), optionally closed into a loop with conditional back links, so a
value can take another pass through the cells when a condition holds.

Reason: these structures have exact reference models, lockstep tests,
working PAL output, and a programming model a compiler can target: each
pass through the cells is a stage of a program, and the loop count and back
links are scheduled offline.

Parked: the "crazy network" (random sparse links, byte cells, add/XOR/sub/max).
Its search produced a few good finds, but we have no good handle on how to
program it deliberately: most programs are chaotic, objectives get gamed,
and GF(2) linearity gives little useful structure. Revisit only when there
is an algebra to design with (max-plus with a Kleene closure, composable
blocks with contracts), not by more random search. The prototype and its
findings stay in `prototypes/crazy-network/`.
