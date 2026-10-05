# Backlog: everything we said we want to do (as of 2026-09-25)

Historical snapshot: every **running** tag below describes work in progress on
2026-09-25; it is not a current status report. `NEXT.md` is the current source
of truth for verified state and next actions.

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

- **Receiving beyond Nyquist** (the user's insight: real protocols suit compressed-sensing ideas).
  The framework is sampling at the finite rate of innovation (Vetterli, Marziliano, Blu 2002).
  The floor is the entropy rate of the unknown content, not twice a bandwidth. Uses:
  - once locked, one sample per bit at bit centres instead of 4× oversampling;
  - sampling only unpredictable fields;
  - telling which of a few candidate frames is present from a handful of samples (the matcher);
  - super-resolution of edge times;
  - protocols faster than our clock where their new content per second is low enough.

  Being modelled in the scope study.

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
  - reconcile `notes/gain-cell-compiler.md` with the mixed-direction failure
    model and shortened extended-Hamming checks now demonstrated in
    `prototypes/systolic-storage/`; quantify residual undetected errors
    (`notes/codex-brainstorm-triage.md`, §4);
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

- **Latency checking adopted (`latency-adopt`, merged 2026-10-05):** the HDMI pixel path is rewritten
  with `Delayed` and `align`, and is cycle-identical to the original; five prototypes fail
  `dune test` on a latency regression. The small 5-frame Cyclesim test
  now detects the end-to-end latency mutant too (555 of 1,375 cycles differ against the good design; `small-fixes`, 2026-10-05). Fourteen improvement proposals for hardcaml-latency are in
  `notes/latency-adoption.md`.
- **Formal checking landed (`symbolic-bmc`, merged 2026-10-05; `prototypes/formal/README.md`):**
  - **The interpreter:** ISA v2's interpreter is a functor over integers, SMT terms and Hardcaml
    signals.
  - **Incremental BMC with z3:** deadlines, pin ownership, isolation (proved at every depth by
    relational induction) and UART correctness.
  - **Kind 2** proves the deadline property for all depths.
  - **RTL equals the spec** for 23 clocks from reset for every instruction stream (Yosys
    SAT), and all 28 planted RTL bugs are caught at depth 15.
  - **Follow-ups:**
    - the functorised interpreter is 1.2–2.9× slower on integers (bridge A 9 s to 26 s): restore
      a fast integer path, or specialise;
    - the shared data bank, inboxes and ports have no ownership discipline like the pins;
    - isolation's two non-vacuity cover queries ran 22 minutes without an answer.

    The SPI period-8 compiler bug it found is fixed (period ≥ 10).
- **Open after the 2026-10-05 fixes (`fix-findings`, merged):**
  - (done on `small-fixes`: bridge B's SPI master now has the reply deadline; seqtrace uses symlinks and its check passes.)
  - the I2C fix changed the timing within one SCL low phase (SDA now moves 2 slots after SCL
    falls; low phases 28→36 and 44→40 clocks). It was accepted by the coordinator as within I2C's
    own timing rules, but rerun the FPGA I2C tests on the board;
  - the base-ISA 10BASE-T firmware cannot detect host underrun; only the v2 port has the fix.

- **Sign-off DRC must run IHP's maximal deck ourselves.** Tiny Tapeout's precheck runs only the
  deck's main table, which does not check the thick-oxide keep-outs (TGO.a–e), the poly end cap
  (Gat.c), n-well enclosures, pSD rules or contact-to-gate spacing (verified in the deck
  source; `prototypes/rule-breaks/deck/`). An accidental violation of those would pass the
  precheck unnoticed. Deliberate breaks (`prototypes/rule-breaks/README.md`) remain our own
  risk.

- **Determinism as a tracked design property, not an afterthought.** The sequencer is deterministic
  by construction; the chip is not at clock-domain crossings, the four-phase stage (metastability,
  phase skew), asynchronous external inputs, the analogue parts (pads, pump, delay line), and the
  expiring memory (retention varies with temperature and die). List every source of
  nondeterminism, model each in simulation as injected nondeterminism (metastability, skew and
  retention sweeps), and plan record-and-replay of silicon runs into simulation for debugging.
  Exploration testing (hwfuzz, and ideas from Antithesis) must cover both regimes.
- **Deliberate nondeterminism as design space** (the user's point: breaking determinism on purpose,
  knowing where and how to fence it, opens designs up). Candidates:
  - self-timed handshakes between elements, as in the GA144;
  - ring-oscillator or metastability randomness as a true random source;
  - the expiring memory as a physical unclonable function;
  - stochastic computing (numbers as random bit streams, multiplication as AND) for cheap,
    error-tolerant image and scoring maths;
  - equivalent-time sampling with the TDC, so the chip works as a debugging scope far beyond
    its clock;
  - dithering and randomised timing (FM spurs, glitch hardening, randomised refresh);
  - approximate storage (letting memory decay on purpose for lossy data);
  - chaotic and oscillator networks.

  Each needs its fence written down: which interfaces re-synchronise, what the verifier may
  assume, and how a run is still replayed.
- **In practice we reimplement, not copy** (Matthias, 2026-10-04): almost everything we borrow is
  written in another language (Clash/Haskell, Verilog, Python) and gets rewritten in
  OCaml/Hardcaml anyway. So unlicensed sources are fine as ideas. Credit the source of every
  idea we adopt; licences matter only for the rare verbatim copy.
  Code with vague or missing licences may still be run locally, for example as a test oracle
  or a reference to compare against (clash-chip8 as a reference emulator, fpga4fun's HDMI
  Verilog on the FPGA). It must not be committed to the public repository; keep it outside the
  repository, or gitignored.
- **Copying from other entries: the policy.** Ideas may be copied from anyone, with attribution.
  Code only under a compatible open-source licence, with attribution. Of the repositories studied
  on 2026-09-25, 11 are Apache-2.0 and 2 are MIT; 3 have no licence (fjpolo/ProtocolEmulatorr,
  LeEmperor/hardcaml_protemu, DanielMBouyou/protocol-emulator-asic), so they are ideas only.
  Apache-2.0 files keep their licence, notice and a record of our changes, with a per-file
  `SPDX-License-Identifier`. Our repository moved from MIT to Apache-2.0 on 2026-09-25 (see `NOTICE`),
  matching most of the code we may borrow and adding a patent grant.
- **Learn from other public entries' verification** (study of 15 repositories on 2026-09-25,
  private notes in `~/prog/janestreet/competitor-notes/`). Adopt, with credit:
  - **Mutation against formal proofs:** plant a broken deadline arm and require the BMC proof to
    reject it. At least six entries do some form of this; examples are MarcosAsh's SVA "teeth",
    WilliamZhang20's named RTL mutants, and fjpolo's equivalence-checking miter.
  - **A programme verifier by abstract interpretation:** MarcosAsh/protocol-emulator
    `src/analyser.ml` (OCaml, intervals over phase, period and cycles since an edge). It refuses
    firmware that could miss a deadline. Read it before building ours.
  - **A non-interference miter for pin and port arbitration between threads**, after
    umerimran-10xe's `protoemu_arb_miter.v`: assume equal inputs for the owner, assert equal
    outputs. It is the formal form of "ports never double-booked" and of the isolation proof in
    the bridges work.
  - **A verification-record format:** hash-pinned inputs, a "what this is NOT" section and honest
    non-closure reports (2AMLogic).
  - **A cocotb layer against the hardened netlist**, as Tiny Tapeout's own CI expects; several
    entries have one.
  - **An audit of our specification by formal methods,** as TejasDasa's `docs/formal.md`
    documents: five specification gaps found that 100 %-coverage random testing had missed.
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

- **`hardcaml-latency`: decided 2026-10-05.** It stays its own repository
  (`~/prog/janestreet/hardcaml-latency`, local only for now), because a standalone library is the
  likeliest upstream route and keeps it reusable outside this entry. The emulator uses it as a
  vendored or path dependency when the video pipelines adopt the wrapper. Publishing it is a
  later step, with any issue text to Jane Street reviewed by Matthias first. The decision is
  cheap to revisit.
  Adopted 2026-10-05 (branch `latency-adopt`): vendored at f59e57a, the HDMI pixel path
  rewritten with `Delayed`, the lint in `dune test` of five prototypes, and 14 proposed
  improvements: `notes/latency-adoption.md`.

- **Our own reverse-engineering tooling from the August puzzle**
  (`~/prog/janestreet/hardware-2026-08/`, `WRITEUP.md`). Reuse it on our own layout:
  - a GDS-to-netlist extractor (`work/extract.py`), with an OCaml port at
    `hardcaml_firing_squad/extract.ml` and `cells.ml`;
  - a gate-level simulator (`work/sim.py`, `sim.ml`);
  - a netlist checker (`netlist_check.ml`).

  Port them to IHP sg13g2 cells and use them for the post-layout round trip: extract our GDS,
  then run lockstep and fuzzing on the extracted netlist against the RTL. This is the
  independent check that Tiny Tapeout's precheck, with no LVS, does not give.
- **Lesson from that puzzle: check for undriven nets explicitly.** Jane Street's chip shipped
  with a floating input net that corrupts one message. A SAT solver treats an undriven wire as
  a free variable and picks a value that hides the bug, and our simulator read it as 0. So the
  round trip must report every net without exactly one driver, before any simulation or formal
  check. A cheap check, worth a line in the write-up.
- **A firing-squad puzzle chip already written in Hardcaml**
  (`hardware-2026-08/hardcaml_firing_squad/`): Hardcaml v0.17, Hegel property tests, a LibreLane
  SKY130 flow, DEF-to-GDS. It is a template for our own Hardcaml-to-GDS flow and property
  tests.

- **HDMI/DVI output on the ULX3S for the demos.** A Clash HDMI encoder for exactly this board
  exists (gergoerdi/clash-flappysquare, branch `ulx3s-hdmi`, `target/ulx3s`). Port its TMDS
  encoder and serialiser to Hardcaml, or bridge it, so FPGA bring-up can show the video demos on
  a monitor. On the chip itself, TMDS at 640×480 needs 250 Mbit/s per lane, beyond our pads.
  Read on 2026-10-04 (MIT licence, so code may be ported with attribution):
  - `TMDS.hs` is a 66-line DVI 8b/10b encoder: popcount, an XOR/XNOR chain and a 4-bit running
    disparity, as a Mealy machine.
  - On the ECP5, one PLL makes 25 MHz pixel and 250 MHz bit clocks (`src-hdl/clock.v`).
    `ClockToBit.hs` routes a clock onto a data pin.
  - A straight Hardcaml port is about a day's work.
- **Timed model checking of sequencer programmes.** Model each thread as a timed automaton and
  check deadlines with an established tool (UPPAAL, or nuXmv/Kind 2 on a discrete-time
  encoding). This would be an independent check of the programme verifier.
- **Refinement types for hardware:** Liquid Clash, LiquidHaskell applied to Clash, as prior art
  for static checking of widths, ranges and deadlines. Look for an OCaml/Hardcaml analogue.

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

- **Ideas from Antithesis**, which Jane Street uses and led a funding round for ("now leading their
  next funding round", blog.janestreet.com/getting-from-tested-to-battle-tested/, 2025-12-03).
  Research notes are in `/var/tmp/js-network/report.md`.
  - Snapshot and branch exploration: save simulator state at interesting moments and explore
    from there. hwfuzz currently rebuilds the simulator on every run.
  - "Sometimes" assertions and tuple coverage (SOMETIMES_EACH/ALL, EVER_SINCE) as observer
    features.
  - Metastability injection for clock-domain crossings, which already has hardware precedent
    (Kumar, Khan and Mittra, DVCon Europe 2023, arXiv:2406.06533). Apply it to the four-phase
    stage.
  - Fault injection of rare interleavings across sequencer threads and bridges.
  - Heat maps of explored state.

- Hardcaml assertions as oracles; automatic mutants and a mutation score.
- LLM-island experiments: the checksum ladder, including random networks.
- `~/prog/testing`: hill-climbing experiments on how to test, measured by mutation score.
- **An experiment that shows the thesis:** measure agents programming the chip, since agents
  plus simulators are what make "the demoscene tail as baseline" viable in 2026.

## Research threads

- **Framing for the write-up: "software-defined hardware".** The term is Groq's (their ISCA papers;
  see `notes/prior-art-systolic-uses.md`), and it fits Jane Street's ask ("reprogrammable enough to
  support new protocols after fabrication"). Our version: deterministic, compiler-scheduled
  hardware where protocols are programmes, and where hardware quirks (expiring memory,
  quarter-clock edges) are compiler constraints. Credit Groq for the phrase.
- **Lead the write-up with determinism.** Jane Street visibly values it: their taste notes,
  leading Antithesis's round, Hardcaml's cycle-exact expect tests, predictable latency in
  trading. Present:
  - timing exact by construction;
  - programmes whose timing a verifier can prove;
  - silicon runs that replay in simulation.

  The deliberate nondeterminism (random source, equivalent-time sampling, expiring memory) then
  appears as fenced and named, while everything else stays exactly reproducible.
- **...and with compilers.** Jane Street is an OCaml shop with its own compiler work (OxCaml
  and the OCaml compiler team), and Hardcaml is itself a compiler of sorts. Our design puts the
  compiler at the centre:
  - protocol compilers produce sequencer programmes;
  - the scheduler handles memory lifetimes, as rows with deadlines;
  - programmes are placed on array segments;
  - the verifier proves deadlines;
  - agents write code that the exact interpreter judges.

  Show the compiler stack as a first-class part of the entry, in OCaml.

- Jane Street's hardware taste; tools to port (**running**).
- Public competitors and the winners of Jane Street's recent challenges (**running**).
- The codex brainstorm on everything since 23 September (**triaged**; see
  `notes/codex-brainstorm-triage.md`).
- Ideas from the Forth chips: slot-packed instructions, loops inside one word, blocking
  neighbour ports, executing code straight from a port.

## Questions to ask IHP or Jane Street

- Whether IHP's SRAM-marker relaxations are safe for geometry other than their own bit cell.
- Whether Metal4 and Metal5 over a custom array are fine in practice (Tiny Tapeout allows them).
- Whether the pads have an output toggle-rate figure.
- Whether 8×4 tiles will become available.

## Housekeeping

- **Prefer OCaml** (Hardcaml for hardware) for new models, simulations and tools: Matthias,
  2026-09-25, "Let's do more OCaml." Python only where an existing Python tool is the point
  (independent references such as scapy or pynmea2, plotting). Port core Python models to OCaml
  when they are touched again.
  Each Python tool we lean on is also an impetus to write an OCaml equivalent: packet
  building and parsing like scapy, NMEA parsing, plotting to PNG and SVG, sigrok-style decoders.
  Keep the Python original as an independent cross-check. Two independent implementations
  agreeing is the point.

- Codex reviews run on `codex-luna` (the cheap model) unless a decision warrants more. DeepSeek
  runs off-peak, and MiMo Flash stands in for it.
- Every number keeps its raw run in the repository; every agent's claims are checked against its
  files before being relayed.
