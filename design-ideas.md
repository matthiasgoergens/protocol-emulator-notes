# Protocol-emulator ASIC: design ideas

Brainstorming notes, 16 September 2026.

The strongest candidate is a small protocol emulator with explicit timing
contracts: describe what should happen on the wires, when it must happen,
and how the device should react when it does not. The same description could
drive an emulator, a monitor, and a verification model.

The [competition announcement][competition] explicitly welcomes novel
functionality and novel design or verification methods. These proposals are
potentially distinctive submissions, not claims of first invention or
verified area and performance estimates.

## Inspiration from the existing Hardcaml work

Two aspects of the earlier work are particularly useful:

- The firing-squad project's idea of loading rules into a general engine.
  Its [model][squad-model] provides a conceptual starting point.
- Independent models, generated tests, waveform replay, and comparisons
  against extracted circuitry, as used in the [Star Battle testbench][tests]
  and the [firing-squad verification flow][squad-build].

The existing runner evaluates cellular-automaton cells serially using a
32,768-by-5-bit rule table. Its build notes report roughly 99,000 mapped
instances in an earlier implementation, dominated by the rule store and
lookup logic. Borrowing the programming idea does not require retaining
that representation.

Timestamped I/O already exists in [XMOS][xmos], and programmable combinations
of timers, shifters and state machines already exist in [FlexIO][flexio]. A
strong novelty argument needs to go beyond those ingredients.

## 1. Programmes that come with timing guarantees

Give the instruction set concepts such as waiting for an edge, sampling at
an offset, changing several pins together, and branching on deadline expiry.

An illustrative programme might say:

```text
await falling_edge(RX) with timeout
sample eight bits at specified offsets
check stop bit
emit decoded byte or timing violation
```

A compiler checks whether every relevant execution path can meet its
deadlines. It could reject conflicting pin ownership, unbounded work before
a scheduled output, or insufficient buffering under stated traffic
assumptions.

Most checking happens on the host. The chip needs a small deterministic
execution engine and explicit reporting of missed deadlines.

**Demonstration:** run UART reception and an SPI transaction concurrently,
showing the timing guarantees for both. Modify a programme so that it cannot
meet them and show the compiler's counterexample.

**Novelty angle:** verification becomes visible functionality through a
timing-aware programming model.

**Main difficulty:** guarantees need explicit assumptions about external
input timing, synchroniser uncertainty, and host servicing. A proof about
clocked digital behaviour does not establish analogue pin behaviour.

## 2. One protocol description, several roles

Describe an interaction between participants, then compile projections that
act as the controller, act as the peripheral, or passively monitor the
exchange.

For I2C, the description includes START, address, acknowledgement, data,
stretching and STOP. Selecting a role determines which events the chip
generates and which it observes.

Failures could be explanatory: "expected acknowledgement in this interval;
observed release", accompanied by a short trace.

**Demonstration:** load an EEPROM-like peripheral personality and communicate
with it. Reload the same chip as a monitor of that interaction. Add a small
custom protocol after fabrication to demonstrate generality.

**Novelty angle:** a compact executable protocol language with role selection
and timing semantics.

**Main difficulty:** a shared specification can spread one mistake into the
emulator, monitor and tests. Keep independently written reference models for
the baseline protocols. Role projection and branching also need limits to
prevent state explosion.

## 3. A protocol time machine that responds to live events

Replay the structure of an interaction while responding to the other
endpoint's actual behaviour. Capture an exchange, annotate it on the host,
and turn it into a small programme:

```text
recognise request
capture selected fields
await handshake
respond after recorded relative delay
substitute payload fields
```

This preserves a device's peculiar behaviour without assuming the controller
always runs at exactly the same speed.

**Demonstration:** record a sensor transaction, replace the sensor with the
chip, and have the controller continue working when its inter-byte delays
change. Change the emulated reading while preserving the sensor's observed
response timing.

**Novelty angle:** capture becomes editable, reactive firmware. This could
be a useful instrument beyond the competition.

**Main difficulty:** a trace does not establish which events caused which
responses. Start with explicit host-side annotation. Use short, triggered
captures because trace memory could otherwise dominate the design.

## 4. A small spatial protocol fabric

Build a handful of programmable actors, each with local state, a timer, pin
access and communication with neighbouring actors. A protocol becomes
cooperating machines: one recognises edges, one shifts bits, one counts
fields, and another schedules responses.

Unlike the existing serial cellular-automaton runner, actual parallel
execution would be the point. Independent protocol activities progress
together, with defined communication latency and coordinated output
changes.

**Demonstration:** configure the fabric for UART and SPI simultaneously, then
reconfigure it into a streaming protocol bridge. A visible synchronisation
demonstration could nod to the firing-squad project.

**Novelty angle:** a protocol-oriented spatial machine, with a compiler that
exposes and checks its timing.

**Main difficulty:** establishing that the organisation earns its complexity.
Explore small local programmes or sparse transition rules instead of the
full neighbourhood table. Bridging also needs explicit buffering and
backpressure assumptions.

This is the most adventurous architectural option. An early synthesis
experiment should precede a commitment to it.

## 5. A programmable timing microscope

Make the emulator especially good at measuring another device's timing
behaviour. A programme systematically varies response delay, inter-byte gaps
or sample phase, recording whether exchanges complete correctly. The host
turns the observations into a map of the device's operating envelope.

**Demonstration:** emulate a peripheral and measure how long its controller
tolerates a delayed response. Alternatively, sweep a receiver's sampling
position across a transmitted bit. Report observations and clock-cycle
resolution.

**Novelty angle:** a protocol emulator that also produces reproducible timing
experiments.

**Main difficulty:** distinguishing the other device's behaviour from the
emulator's sampling uncertainty and I/O delays. This measures digital timing
at a stated resolution; it is not automatically a precision analogue
instrument.

This is a strong flagship application for one of the other architectures.

## Recommended combination

Combine idea 1 with a restricted version of idea 2, and use idea 3 as the
memorable demonstration:

> Describe a timed conversation once; run either endpoint, observe it, or
> turn a recorded interaction into a responsive replacement device.

Keep the initial language small: edge and level waits, deadlines, shifts,
counters, bounded branches, and atomic changes to pin values and output
enables. UART, SPI and I2C provide the baseline examples.

This gives the project a coherent functional story, room for Hardcaml
craftsmanship, and a verification argument that can be demonstrated.

## Feasibility and first experiment

Plan around the currently stated 6-by-4-tile allocation, rather than the
possible expansion. The competition deadline is 18 January 2027, with the
March 2027 CMOS5L shuttle targeted subject to the foundry schedule.

Memory deserves an early experiment. [Tiny Tapeout's memory guidance][memory]
documents working IHP SRAM, but its current macro tables are labelled
SG13G2 and warn that integration is changing. Confirm exact CMOS5L support
before choosing a memory-heavy architecture.

The first discriminating experiment would implement the same UART, SPI and
I2C examples on a compact sequencer and a small rule engine. Compare programme
storage, mapped area, and worst-case reaction latency under matched
functional requirements and synthesis constraints. Define the required
protocol rates and resource limits before inspecting the results. Retain
individual results, tool versions, configurations and generated artefacts.

No implementation, synthesis, timing closure or area validation has been
performed for these proposals. The existing tests are useful methodology
examples; sampled trace agreement is not a universal equivalence proof.

[competition]: https://blog.janestreet.com/protocol-emulator-asic-competition/
[xmos]: https://www.xmos.com/documentation/XM-002509-PC/html/
[flexio]: https://www.nxp.com/docs/en/application-note/AN5239.pdf
[memory]: https://www.tinytapeout.com/specs/memory/
[squad-model]: ../hardware-2026-08/hardcaml_firing_squad/model.ml
[squad-build]: ../hardware-2026-08/hardcaml_firing_squad/BUILDING.md
[tests]: ../hardware-2026-08/hardcaml/main.ml
