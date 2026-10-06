# One programmable chip for protocols: a protocol-emulator ASIC

This is the working repository for an entry to Jane Street's
[protocol-emulator ASIC competition](https://blog.janestreet.com/protocol-emulator-asic-competition/):
a small chip, fabricated on IHP's 130 nm process through a Tiny Tapeout shuttle, that speaks
protocols such as UART, SPI and I2C on behalf of a host. Entries are due on 18 January 2027, for
the March 2027 shuttle, in at most 6x4 tiles.

The design takes the competition's hint literally: "The goal isn't to put a UART block, an SPI
block, and an I2C block on one die and call it done." There are no protocol blocks. The chip is a handful of generic
programmable blocks, and every protocol and every demo is a programme or a configuration of them.
Timing is exact by construction, so a compiler can check before anything runs that a programme
meets its deadlines.

Everything here is design, simulation and measurement. Nothing has been fabricated, and the FPGA
bring-up is prepared but not yet run on a board.

## The intended chip

This is the target design; the blocks exist as separate prototypes and are not yet integrated
into one top level.

```
            host (the RP2040/RP2350 on Tiny Tapeout's demo board)
                                 | programme and configuration loading, data streams
   +-----------------------------+------------------------------------------------+
   | sequencer: 4 hardware threads, deadline waits ------------ programme memory    |
   |    | push/pull bus                  | pin writes and reads           | mailbox |
   |    v                                v                                          |
   | PE array: 16 processing elements, pin stage: four-phase output and input,      |
   | split into segments, with         open drain, complementary pairs, streamer,  |
   | loop-backs and feeds   <------->  sampler, phase accumulator (pin NCO)        |
   |    ^                               ^  bit-path assists: edge-tracking sampler, |
   |    |                               |  bit-stuff tracker, line coder, CRC,      |
   | gain-cell memory banks             |  sync-word matcher                        |
   +--------------------------------------------------------------------------------+
          one 60 MHz clock, four phases derived on chip
```

- **Deadline sequencer.** Four hardware threads issue round-robin, one instruction per clock in
  total, so every instruction takes exactly one slot. Its central instruction is "wait for this
  pin level, but no longer than this deadline". Threads pass data through small mailboxes. The executable specification is an OCaml
  interpreter (`prototypes/sequencer-v2/isa2.ml`); the hardware is written in
  [Hardcaml](https://github.com/janestreet/hardcaml).
- **Four-phase pin stage.** Four clock phases let a pin change, or be sampled, on a quarter-clock
  grid: four edges per clock out, 4x oversampling in (`prototypes/multiphase`).
- **Pin stage helpers.** A streamer and a sampler move words between the host and the pins at a
  fixed rate without the sequencer; a phase accumulator (NCO) makes carriers and PWM; small assists
  handle bit recovery, bit stuffing, line coding, CRCs and sync-word matching.
- **Processing-element array.** Sixteen identical elements in a line (a systolic array), which can
  be split into independent segments, for the work a sequencer is too slow for: CRCs, correlation,
  phase accumulators, pixel generation, audio noise shaping (`prototypes/unified-pe`). Its RTL is
  checked in lockstep against a model (`prototypes/unified-pe/verify`).
- **Gain-cell memory.** Dynamic memory cells denser than the process's SRAM, which forget within
  microseconds to milliseconds; the compiler schedules every read before its value expires
  (`prototypes/gain-cell`, `notes/gain-cell-compiler.md`). So far these are SPICE simulations on
  the process models and drawn layouts with DRC and LVS runs, not part of any hardened design.

The design rationale, including how the blocks were chosen by counting the primitives the earlier
special-purpose prototypes needed, is in `notes/architecture-v0.md`. Some earlier prototypes ran
at other clock rates (53.2 MHz for PAL video, for instance); the note explains the choice of
60 MHz. The running list of open
work is `notes/backlog.md`.

## What runs on it (in simulation)

| Area | Protocols and demos | Where |
| --- | --- | --- |
| Competition list | UART, SPI, I2C | `prototypes/deadline-sequencer`, `prototypes/sequencer-v2` |
| Further protocols | JTAG, SWD, PS/2, CAN, S/PDIF | `prototypes/proto-jtag-swd`, `prototypes/sequencer-ps2-can`, `prototypes/spdif` |
| Stretch goals | low-speed USB as firmware; 10BASE-T Ethernet answering ARP and ping | `prototypes/usb-ls`, `prototypes/eth10-node` |
| Several at once | several protocols on one sequencer, with bridges between them (Ethernet to TV, a CAN bus analyser) | `prototypes/multi-proto` |
| Video | PAL and NTSC composite colour, a retro console, a platformer game, a wave-interference game | `prototypes/retro-console`, `prototypes/platformer`, `prototypes/wave-engine`, `prototypes/video-nco` |
| Audio and radio | one-bit audio output with noise shaping, IMA ADPCM and SBC decoding, FM transmit | `prototypes/onebit-dac`, `prototypes/multiphase` |
| Gadgets | a GPS finder that tells you by sound whether you are getting closer, the chip as a logic analyser and oscilloscope | `prototypes/gps-hotcold`, `prototypes/scope` |
| FPGA test bench | ULX3S top level, host runner and checker; DVI output to a monitor | `prototypes/fpga-ulx3s`, `prototypes/hdmi-ulx3s` |

Each directory's README states what was checked, how, and what was not.

## How it is checked

The aim is that no claim rests on one implementation agreeing with itself, and that every check is
shown to be able to fail.

- **Lockstep.** The RTL runs clock by clock against the OCaml specification and every output is
  compared. Each test suite comes with deliberately planted bugs that it must catch.
- **Independent oracles.** Protocol traffic is judged by code written separately from the design:
  host models, [sigrok](https://sigrok.org/)'s protocol decoders run as an external program
  (`tools/sigrok-judge`), and unmodified third-party HDL such as alexforencich's `verilog-uart`
  (`tools/peers`). Every judge also gets a deliberately faulty trace, to show it can fail.
- **A static programme verifier.** Abstract interpretation proves that a programme makes its pin
  events within the declared timing windows for every input, or rejects it with the path to the
  violation (`prototypes/verifier`). It proves all 530 programmes the compiler emits across the
  swept parameter ranges, and its trusted kernel is tested with planted kernel bugs.
- **Formal proofs.** Bounded model checking of the specification with z3; SymbiYosys and Yosys
  proofs on the RTL, including that the chip behaves identically after reset whatever its
  registers held at power-up; an equivalence check of our UART against the transmitter in Jane
  Street's [`hardcaml_hobby_boards`](https://github.com/janestreet/hardcaml_hobby_boards). Every property is reported as proved, reachable or vacuous
  (`prototypes/formal`).
- **Layout back to behaviour.** A netlist extracted from the final GDS alone, independently of the
  place-and-route tools, is compared with the place-and-route record per cell and per net, and run
  cycle by cycle against the RTL (`prototypes/postlayout-roundtrip`).
- **Coverage-guided fuzzing** of Hardcaml designs (`prototypes/hwfuzz`), stall injection, and
  checks that every pin and memory bank has one declared owner (`prototypes/verif-oracles`).

## Tiny Tapeout

`tt/` is the submission harness, laid out as in Tiny Tapeout's IHP template. Its Verilog is
generated from Hardcaml at build time and never committed. `tt/scripts/harden.sh` runs Tiny
Tapeout's own hardening steps in a pinned copy of their LibreLane environment
(`tools/librelane-tt`). The first run, on a 6x4-tile placeholder top level around the sequencer,
finished with no DRC, LVS or antenna errors, setup slack +10.39 ns and hold slack +0.12 ns at a
20 ns clock (`tools/librelane-tt/results/tt-harden/`). It has not been through Tiny Tapeout's
precheck yet, and the real top level, with all the blocks above, is not integrated yet.

## Repository map

| Path | Contents |
| --- | --- |
| `prototypes/` | one directory per block, protocol, demo or study, each with a README and a `results/` directory |
| `tools/` | the sigrok judge, third-party peers, the pinned LibreLane environment, latency checks |
| `tt/` | the Tiny Tapeout harness |
| `notes/` | architecture, backlog, prior-art surveys, and what we learnt from other entrants and from the solvers of Jane Street's earlier [ASIC puzzle](https://blog.janestreet.com/asic-puzzle-results/) |
| `measurements/` | early area studies: an RP2040 PIO clone and a FABulous embedded-FPGA tile on the same process |
| `brainstorm-*.md`, `synthesis.md`, `second-layer/` | the opening brainstorm: independent idea lists from the same prompt, compared in `synthesis.md` |
| `datapoints.md`, `PLAN.md`, `techniques.md` | early measured facts, the first plan, and ways a large host can do the work a tiny chip cannot |

## Reproducing

Most prototypes are OCaml: install Hardcaml v0.17 in an opam switch with OCaml 5.3, then
`dune build` in the prototype's directory; its README lists the commands, and each `results/`
file names the command and commit that produced it. Synthesis and place and route use Yosys and
LibreLane in containers; the Python tools run through [uv](https://docs.astral.sh/uv/). The IHP
process design kit and third-party sources are not vendored unless stated; the notes name the
commits used.

## Credits

Ideas and code from other people's public work are credited where they are used, by repository,
and listed with their licences in `notes/learned-from-others.md`,
`notes/learned-from-puzzle-solvers.md` and `NOTICE`. Prior-art surveys are in `notes/prior-art-*.md`.

## Licence

Apache-2.0 (see `LICENSE`); the repository was relicensed from MIT on 2026-09-25. Third-party files keep their
own licences, listed in `NOTICE`.
