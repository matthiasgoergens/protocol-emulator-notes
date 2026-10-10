# Architecture overview

The chip speaks protocols on behalf of a host, and it has no protocol blocks: it is a handful of
generic programmable blocks, and every protocol is a programme or a configuration of them. This
page describes the blocks as `prototypes/chip-top` integrates them, the timing model that makes
every programme's timing exact, and where the chip is and is not deterministic. The design
rationale and the measurements behind each block are in `notes/architecture-v0.md`; what each
block does is specified by its executable model, which chip-top's specification
(`prototypes/chip-top/src/chip_spec.ml`) composes and its RTL is checked against, clock for
clock.

## The blocks

```
            host (RP2040 or RP2350 on Tiny Tapeout's demo board)
                 | host link: 4 data lines, a strobe, a read request
   +-------------+------------------------------------------------------------+
   | sequencer: 4 hardware threads ---------------- programme store, 1,024 x 16 |
   |    | SEND/RECV ports 4-7     | pins 0-7, flags          | inboxes 0-3      |
   |    v                          v                                            |
   | PE array: 4 segments    pin map and pad selects, four-phase pin stage,     |
   |   (4 PEs on the          streamer, sampler, pin NCO; edge-tracking         |
   |   hardened chip)         sampler, CRC unit, matcher on the recovered bits  |
   |    ^                                                                        |
   | data bank, 1,024 x 8 (LDB, STB)                                             |
   +----------------------------------------------------------------------------+
          one clock (60 MHz on the demo board)
```

- **The sequencer** ([isa.md](isa.md)): four hardware threads issuing round-robin, one
  instruction per clock, from one programme store addressed {page, pc}. It owns eight logical
  pins, four one-byte inboxes for passing data between threads, a 1,024-byte data bank, the
  host's IN and OUT, and four ports into the PE array.
- **The pin stage** ([configuration.md](configuration.md)): a host-configured map from the
  sequencer's logical pins (and the other sources: streamer, NCO, segment taps, the recovered
  bit) to the pads, and from the pads to the logical pins' inputs; four-phase output and input,
  so a pin can change on a quarter-clock grid (the `q` of SETP and SHO) and be sampled four times
  a clock (SHI `quad`); open-drain pads.
- **The helpers on the pins**: a streamer and a sampler that move words between the host and
  the pins at a fixed rate without the sequencer, a pin NCO (a phase accumulator for carriers and
  PWM), and on the recovered-bit path an edge-tracking sampler (Manchester, biphase mark, NRZ),
  a CRC unit and a sync-word matcher, whose results reach the threads as flag inputs.
- **The PE array** ([configuration.md](configuration.md)): identical processing elements in a
  line, cut into four segments, each fed by a thread's SENDs on its port and read by RECVs, for
  the work a sequencer is too slow for (CRCs, correlators, noise shapers: `examples/dac.s` is a
  sigma-delta modulator on four PEs).
- **The host link** ([host-link.md](host-link.md)): the only way in; it loads programmes and
  configuration while the sequencer is stopped, and streams data to and from the threads while it
  runs.

## Timing: threads, slots, clocks

The sequencer executes one instruction per clock, taking the threads in turn: thread *t* on the
clocks congruent to *t* mod 4. One instruction of one thread is a **slot**, 4 clocks. Every
instruction takes exactly one slot, and an instruction that waits (for a pin, a deadline, a
mailbox, the host) executes again in its next slot instead of stalling. Nothing a thread does can
delay another thread, so a thread's timing is a function of its own programme and its inputs
only, and every pin edge it makes is at a slot that can be counted from the source. The
deadline register (LDD) bounds every wait: "wait for this pin, but no longer than this".

That is what the toolchain's `--verify` relies on: the static verifier
(`prototypes/verifier`) follows a thread's programme slot by slot over all inputs and proves that
its pin events come at the declared slots, or shows the path that breaks them
([tutorial.md](tutorial.md)).

## From the core to the pins and back

On prototypes/chip-top, a pin level the core sets in clock *k* is on the pad during clock *k* + 1
(the output stage registers it), and the core sees in clock *k* + 2 what a pad's input sampler
took in clock *k*: two synchroniser stages (`prototypes/chip-top/README.md`, "Phases").
`tools/asm`'s runner builds the same pipeline around the ISA interpreter, and checks on every
example that the interpreter and the chip then put the same levels on every pin on every clock
of the run.

A level written with sub-slot `q` starts at quarter *q* of its clock on the four-phase output
stage. The hardened chip runs the stage on both clock edges, so a quarter-1 or quarter-3 edge
appears a quarter late there (`prototypes/chip-top/README.md`, "Phases").

## Determinism

The sequencer, the PE array and the helpers are synchronous logic stepped by one clock: given the
same inputs on the same clocks, they do the same thing. The chip as a whole is not deterministic
where the outside world enters: asynchronous pin inputs (resolved by the synchronisers, an edge
seen within a known window), the host's timing (FIFOs with valid flags; IN, RECV and the feeds
wait, with deadlines where the programme gives one), and analogue effects at the pads.
`notes/architecture-v0.md` section 7 lists each source, its fence, and what the verifier may
assume about it. The verifier's own assumptions are stated in its kernel
(`prototypes/verifier/kernel.ml`, A1 to A5): every input may take any value on any slot, the host
does not move the thread, and so on.

## What is built and what is not

prototypes/chip-top integrates all of the above with the PE array at 4 PEs (one per segment)
for the hardened chip and up to 16 in simulation; the programme store and the data bank are
SRAM macros. Not yet in the chip: the fine-delay lines (so FINE has no effect), the bit stuffer
and line coder, a second recovered-bit chain, and the gain-cell data banks. Its README's
"Open issues" is the current list.
