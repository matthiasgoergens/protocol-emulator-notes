# Backlog: everything we said we want to do (as of 2026-09-25)

Collected from the conversation of 23–25 September, so that nothing agreed is lost. Items marked
**running** had an agent working on them when this was written; their results land on branches
and are merged into master. The direction behind all of it is in `PLAN.md` ("Direction"): one
programmable chip, where every protocol and demo is a programme or configuration of a few
generic blocks, and the prototypes are the evidence for which blocks to have.

## Architecture (the centre of gravity)

- **running** `notes/architecture-v0.md`:
  - the generic block list;
  - the processing element defined so that every cell we need is a configuration of it: sprite,
    tile, FIR/CIC tap, NCO/mixer, correlator (sync words, GPS codes), min-plus, sorting, CRC;
  - a frequency table of which primitives the prototypes needed;
  - a table mapping every protocol and demo onto the blocks;
  - a gap list, the area budget against 6×4 tiles, a verification plan, and the open decisions.
- A GF(2) mode in the processing element (AND and XOR), so that these come from the array:
  - CRC, scramblers, whitening;
  - Gold codes;
  - 1-bit correlation.
- Whether CRC, bit stuffing and line coding are element modes or tiny assists is an empirical
  question. Settle it by synthesis plus workload mixes.
- **One partitionable systolic array.** A sparse set of cut or loop-back points, and feed and
  tap ports, joined to threads, pins and memory by a small crossbar. Cut points only where the
  workload mixes need them.
- **An inter-thread mailbox** with deadline-bounded send and receive, for bridges (**running**, as
  an ISA proposal).
- **One clock plan** for protocols and video: 17 × fsc NTSC = 60.85 MHz, against PAL 12 × fsc.
- **The SRAM safety net: decide.** A small macro for the sequencer's programmes, gain cells for
  bulk data. Recommended, but it runs against the "no safety net" aim.

## Protocols (Jane Street's list, and more)

- Done in simulation: UART, SPI, I2C, 10BASE-T transmit (firmware), the 10BASE-T receiver, and
  full-speed USB (a hardened block, to be re-expressed on the generic blocks).
- **running**:
  - JTAG and SWD (host side);
  - PS/2 and CAN, with wired-AND arbitration and clock offsets;
  - low-speed USB, ideally in pure firmware;
  - a complete 10BASE-T node: link pulses, TP_IDL, receive, and ARP and ping answered against
    an independent stack.
- **running** concurrency and bridges:
  - a capacity table of which protocols fit together;
  - Ethernet-to-TV (the headline), CAN-to-TV (a bus analyser on a television), UART↔I2C and
    I2C↔CAN;
  - proof that each protocol's timing is isolated from its neighbours.
- **running** fast Ethernet without a PHY:
  - IHP pad speed, simulated first; it gates everything below;
  - 100BASE-FX through an SFP fibre module;
  - 100BASE-TX straight onto copper. It may fail; a lossy link is acceptable (report frame loss
    against each limit, and errors must be detected).
- Parked: external-PHY interfaces (RMII and MII for 100 Mbit Ethernet, ULPI for high-speed USB).
  Keep them in mind; they are not a priority.
- Every protocol, each time: an independent oracle, planted bugs that must be caught,
  constrained random tests, interpreter and RTL cycle by cycle.

## Pins and timing

- Merged: the four-phase stage, with FM transmit, jittery 10BASE-T receive and the shmoo demo.
- To do:
  - a FINE instruction for per-edge programmable delay, and the exact-edge NCO;
  - the delay line as a placed macro, with a time-to-digital converter for calibration;
  - phase-clock skew after layout;
  - Tiny Tapeout's second-clock recipe on current LibreLane with a related clock;
  - whether the RP2350's HSTX can give a quadrature clock.
- Debugging uses, as demos:
  - margin (shmoo) tests on external targets;
  - glitch and runt injection;
  - timing fingerprints of devices;
  - timing offsets and glitch shapes as a hwfuzz mutation dimension.

## Memory

- **running**:
  - periphery for the thin cell's level-shifted data: a VLO supply, a strip voltage that tracks
    process and temperature, drivers and sense;
  - whether the pump's 2.3 V is safe on thin-oxide capacitors, with safe alternatives;
  - Monte Carlo of the thick-oxide cells, including oxide, junction and GIDL variation;
  - rule breaks under the SRAM marker, which the Tiny Tapeout precheck accepts: what they buy for
    our own cells.
- To do:
  - draw the metal finger capacitor (with WBL moved to Metal3), the row driver and the pump;
  - full LVS against a schematic, because the precheck has no LVS;
  - on-chip self-test: retention profiling per row, Berger checks, canary rows used as the
    thermometer;
  - an executable model of the memory's lifetime contract for the digital simulation;
  - an 8-word gain-cell bank per processing element;
  - a lower bound for the toy allocator;
  - modulo scheduling (Cydra 5) as the allocator's basis.
- Fun uses of expiring memory: a thermometer, a hand-touch detector, a physical unclonable
  function, self-erasing storage, a tile cache that evicts itself.

## Demos ("anything else your architecture makes possible")

- **running**:
  - FM receive to TV: 1-bit direct sampling, RDS text on screen, a spectrum or waterfall;
  - TV in, advert detection (compressed audio, black frames, a missing logo, the cut rate),
    output on CAN;
  - GPS hot or cold for geocaching: NMEA from a module, then raw signals with acquisition on the
    array;
  - a tile-based platformer on the generic blocks: looped tile cells, sprite multiplexing, a
    split screen.
- Retro console effects and video over Ethernet, re-expressed on the generic blocks.

## Verification (Jane Street's emphasis)

- **A programme verifier**, built before the showpieces: deadlines met, every read inside its
  row's lifetime at the chosen temperature bin, ports never double-booked.
- **A pessimising scheduler** as a test oracle (after Knuth's SHOAP).
- **A slow mode** that runs any programme correctly.
- **Bounded model checking** of the deadline guarantees with hardcaml_verify.
- **Mutation scores** for the whole suite.
- **The GDS round trip** with the extractor from the puzzle work.
- **Delay-annotated simulation** for the multi-phase logic.
- **ASCII waveform expect tests** in Jane Street's own idiom (**running**, see the taste study
  below).
- **FPGA bring-up on the ULX3S** (**running** readiness work: a top level, open toolchain, a host
  runner proven against Verilog simulation, a checklist). The board purchase is pending.

## Tools worth porting or bridging to Hardcaml

The ranking is **running** in `notes/jane-street-hardware-taste.md`. The candidates:
- **sigrok's protocol decoders** (over 100), as independent oracles for every protocol we
  implement: a bridge from Hardcaml simulation, or ports of the key ones. First pick.
- **Waveform export** to Surfer and GTKWave, if Hardcaml lacks it.
- **cocotb-style testbenches;** SymbiYosys- or riscv-formal-style property suites alongside
  hardcaml_verify.
- **RTL fuzzers:** ideas from RFUZZ and DifuzzRTL for hwfuzz, and coverage tooling.
- **Reference cores** for comparison: LiteX's LiteEth and LiteUSB, Amaranth libraries, the
  RP2040 PIO clone.

## hwfuzz and testing research

- Hardcaml assertions as oracles; automatic mutants and a mutation score.
- LLM-island experiments: the checksum ladder, including random networks.
- `~/prog/testing`: hill-climbing experiments on how to test, measured by mutation score.
- **An experiment that shows the thesis:** measure agents programming the chip, since agents
  plus simulators are what make "the demoscene tail as baseline" viable in 2026.

## Research threads

- Jane Street's hardware taste; tools to port (**running**).
- Public competitors and the winners of Jane Street's recent challenges (**running**).
- The codex brainstorm on everything since 23 September (**running**; triage it when it lands).
- Ideas from the Forth chips: slot-packed instructions, loops inside one word, blocking
  neighbour ports, executing code straight from a port.

## Questions to ask IHP or Jane Street

- Whether IHP's SRAM-marker relaxations are safe for geometry other than their own bit cell.
- Whether Metal4 and Metal5 over a custom array are fine in practice (Tiny Tapeout allows them).
- Whether the pads have an output toggle-rate figure.
- Whether 8×4 tiles will become available.

## Housekeeping

- Codex reviews run on `codex-luna` (the cheap model) unless a decision warrants more. DeepSeek
  runs off-peak, and MiMo Flash stands in for it.
- Every number keeps its raw run in the repository; every agent's claims are checked against its
  files before being relayed.
