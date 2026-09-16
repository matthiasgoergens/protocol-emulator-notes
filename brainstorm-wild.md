# Wild pass: ideas without the consensus filter

Written 16 September 2026, after [synthesis.md](synthesis.md). Each idea says
why it might win and why it might die.

## Reinvent what a programme is

1. **Timed session types as the ISA.** A protocol is a session type. Timed
   multiparty session types (Bocchi, Yang, Yoshida 2014) project one global
   description into one local automaton per role with timing constraints on
   each message. Nobody has built a runtime for them in silicon. Might die
   because the theory assumes reliable message passing and pins are not that.
2. **Timed regular expressions, both directions.** Asarin, Caspi and Maler
   describe a protocol as a language over time. A matcher decodes, a sampler
   from the same language emits. The chip is timed grep. Might die because
   the automata blow up.
3. **Timing tables, not programmes.** DRAM controllers run from a table of
   constraints and a scheduler that never violates them. The programme is a
   Petri net with timed transitions plus minimum and maximum separations
   between events; the hardware is a scheduler.
4. **A binarised neural network as the engine.** Weights in SRAM, inputs the
   last N pin samples, output the next pin state. Train on a capture. Worse
   than a state machine, but "the first ASIC that learns a protocol from a
   waveform" is a sentence the judges will repeat.
5. **The ISA is VCD.** Native input and output is a value-change stream with
   branches. Simulator and silicon share a file format.
6. **A tiny eFPGA beside the sequencer.** Sixty-four 4-input lookup tables
   with configuration in latches, about two tiles, giving wire-speed glue for
   whatever nobody thought of. This is what makes "new protocols after
   fabrication" true at USB and Ethernet rates. PSoC universal digital blocks
   did it; no open-source Tiny Tapeout design has.

## Reinvent what a pin is

7. **Sub-nanosecond timestamps on every edge.** An inverter delay on this
   process is tens of picoseconds, so a delay-line time-to-digital converter
   beats any USB logic analyser on resolution. The bottleneck becomes
   getting timestamps to the host.
8. **Pins that measure the outside world.** Charge a pin, release it, time
   the decay. That measures the I2C pull-up, detects a missing termination,
   and reports wire capacitance before the chip speaks.
9. **Protocol identification.** Sample an unknown header, compute edge
   statistics, report "clock on pin 3, UART at 115200 on pin 5". The prior
   work reverse-engineered their chip; this chip reverse-engineers yours.
10. **A programmable digital PLL as the universal receiver.** USB, Ethernet,
    CAN, PS/2, MIDI, infrared and 125 kHz RFID are all "recover the clock,
    then sample". One NCO and phase detector covers them. With a coil the
    chip emulates an RFID tag by load modulation.
11. **Time-of-day as a first-class input.** A pulse-per-second pin
    disciplines a 64-bit counter and every event is stamped in absolute
    time. Two boards then agree on time to a cycle.

## Reinvent what one chip is

12. **Chips that chain.** Winners get several chips. Reserve a pin pair as a
    deterministic link and the design scales across dies. Demo: light a fuse
    at one end of a rack of boards and every LED fires on the same tick with
    the rack length unknown. That is the firing squad synchronisation
    problem, for real, across boards, and it is how test equipment triggers.
13. **Runtime verification on the die.** A second instance of the engine in
    monitor role watches the same pins against a loaded property automaton
    and raises a pin on violation. The chip carries its own oracle after
    tapeout, when simulation has stopped.
14. **An internal crossbar with programmable wire delay and jitter.** Master
    and slave on one die, looped back through a simulated bad cable, so
    conformance tests need no wiring.
15. **The chip debugs itself over its own JTAG.** JTAG master as an emulated
    protocol, JTAG TAP as the chip's debug port, loop closed with two jumpers.
16. **Identity and true randomness from the silicon.** Ring oscillators
    across the die give a physically unclonable identity; metastability gives
    a true random source for an on-chip fuzzer. Both only mean anything on
    real silicon, which is the prize.
17. **A clockless core.** Bundled-data asynchronous engine reacting in gate
    delays with no clock jitter, the theoretical floor for reaction time.
    OpenROAD will fight every step. Highest novelty, highest chance of a
    dead die.

## Reinvent the methodology

18. **Active automata learning with the chip as the query engine.**
    Angluin's L* learns a state machine from membership queries; Vaandrager's
    group learned TLS and SSH implementations this way. Queries are the
    bottleneck and a deterministic chip fires them faster than any software
    harness. On brand for the company that posed the puzzle.
19. **The RP2040 PIO as the oracle.** Compile every protocol to PIO and to
    our chip, run both on the same board, compare cycle by cycle.
20. **Differential fuzzing of silicon against simulation after fabrication.**
    Every discrepancy is a real process, voltage or timing finding.
21. **Publish the agent transcript as the methodology.** A measured record of
    which adversarial lens found which bug, refutation passes included. The
    honest version of AI-assisted design is the novel one.
22. **A schedulability check in the loader.** Liu and Layland's
    rate-monotonic bound is one line; the loader refuses an unschedulable
    programme set. A chip that says no.

## Bets

Crazy block beside a safe core: 12 with 11. Chained chips with a shared
timebase turn the prize itself into the demo and the firing-squad story is
already written. Second: 18, the only idea here that is a research result
rather than a feature. Third: 6, the one that makes the reprogrammability
claim true rather than aspirational. Avoid 17.
