# Second-layer proposals: stranger protocol machines

16 September 2026.

These proposals use the first round of brainstorming as a jumping-off point
for more unusual designs. They explore what might be worth turning into
silicon, with protocol emulation as its first application. Agreement between
the earlier write-ups is not the selection criterion here.

The earlier material remains useful context:

- [Claude's brainstorm](../brainstorm-claude.md)
- [Codex's brainstorm](../brainstorm-codex.md)
- [Kimi's brainstorm](../brainstorm-kimi.md)
- [First synthesis](../synthesis.md)

The timing-contract engine remains a good contender. The alternatives below
ask more unusual questions about what a programme, a peripheral or an
execution state could be.

These are conceptual proposals. Their novelty, area, timing and suitability
for the shuttle have not been established. Each needs a small worked example
that demonstrates why its unusual machinery is useful.

## 1. Schrödinger's peripheral

### Central idea

A chip that keeps several interpretations of an interaction alive.

Instead of committing immediately to one protocol state, the machine
maintains a set of possible states. An incoming edge might be a start bit, a
clock transition or part of a pulse-width encoding. Different hypotheses
interpret it differently; subsequent observations eliminate inconsistent
hypotheses.

The chip can respond when the surviving interpretations agree on an output,
or report that the conversation remains ambiguous. This could operate at
several levels: uncertain baud rate, uncertain framing, or alternative paths
through one known protocol.

### Why it is interesting

The architectural object is a programmable machine operating on sets of
states. Protocol recognition and emulation become two uses of the same
machinery. Uncertainty becomes an observable part of execution.

This extends the earlier ideas of adaptive timing, monitoring and executable
protocol descriptions into a different execution model.

### Memorable demonstration

Connect an unfamiliar serial source and display the competing
interpretations as they disappear. Once sufficient information has arrived,
let the chip participate in the conversation.

The initial implementation should use a bounded, explicitly supplied family
of hypotheses. It need not discover arbitrary protocols from scratch.

### Hard questions

- Some interpretations cannot be distinguished passively. The machine must
  be able to say that several explanations remain possible.
- Agreement must cover output timing and drive enable, as well as value.
- The representation of alternative states must avoid uncontrolled growth.
- Observation-to-participation needs a defined handover point, especially if
  the conversation is already in progress.

### First worked example

Use a short serial trace compatible with several candidate framings at its
start. Show which observations eliminate which candidates, and what the chip
does when the trace remains ambiguous.

## 2. A pinball machine for protocols

### Central idea

Program a graph of components through which tokens travel. Components wait,
delay, split, join, count, sample pins or emit values. A token carries a
little data.

A UART receiver becomes a start-edge token that launches a sequence of
sampling events. An I2C interaction involves tokens representing observed
clock edges, permission to drive a line and completion of a byte. A join
waits for several conditions before allowing the next action.

This is related to timed Petri nets and dataflow. The proposal is to make
such a graph the chip's reprogrammable execution model.

### Why it is interesting

This is a possible descendant of the firing-squad work: small local rules
produce coordinated behaviour, while the programme makes causality visible.

It could be clocked internally. The programming model need not expose
instruction scheduling, but it must expose the timing guarantees of token
processing and communication.

### Memorable demonstration

Display the executing graph on the host while the fabricated chip runs
several interacting protocols. Watch where a conversation is waiting and
which event allows it to proceed.

The display is a view of the execution, not a requirement to stream every
internal event at full operating speed.

### Hard questions

- Token storage, routing and simultaneous transitions need precise, bounded
  semantics.
- Joins need rules for matching tokens from the same transaction.
- Full queues, missing tokens and competing transitions must have defined
  behaviour.
- A graph implementation must earn its area and complexity through useful
  composition or timing properties.

### First worked example

Draw a small receiver graph and extend it with an independent timeout path
and a response path. Work through simultaneous arrival and timeout events,
showing exactly which transition wins and what happens to the other tokens.

## 3. An entire imaginary circuit board inside one chip

### Central idea

Make the primitive a virtual device, with local state, timers, message
queues and connections to virtual wires. Several virtual devices share the
external pins through a resolver.

The chip could impersonate a small ecosystem: sensors, an EEPROM, a GPIO
expander and other companion devices expected by a controller. Their
behaviour could be connected internally: changing one virtual sensor alters
another device's status register.

### Why it is interesting

Scheduling, shared buses and device identity become architectural concepts.
The aim is to express interacting personalities, including their timing and
shared state.

For an open-drain interface, each virtual participant could contribute
"pull low" or "release", and the resolver would produce the combined
result. This is a digital behavioural model; external electrical properties
still need separate treatment.

### Memorable demonstration

An actual controller believes it is talking to a populated board. Substitute
this chip for the companion devices, then change the imagined board by
loading another programme.

### Hard questions

- Device state, programme storage and scheduling all consume resources.
- Virtual participants must meet the timing visible to the real controller.
- The resolver needs interface-specific rules; arbitrary outputs cannot all
  be combined as if they were open-drain signals.
- The design needs a useful abstraction beyond independent address-response
  tables.

### First worked example

Model two devices on one bus whose responses depend on shared internal
state. Show that the same programme preserves their individual identities
and their interaction when the controller changes transaction order.

## 4. A peripheral with save states

### Central idea

Give the emulator a complete, deliberately small architectural state that
can be checkpointed and restored: programme position, registers, timers,
queued events and protocol state.

An interaction becomes an experiment that can be repeated from a known
point. Restore the virtual peripheral, change one parameter, and continue.

### Why it is interesting

This combines a silicon debugger, an emulator and a language for
reproducible experiments. It pairs particularly well with the imaginary
circuit board: a whole virtual ecosystem could have a reproducible starting
state.

### Memorable demonstration

Save a peripheral immediately before a transaction, then repeat that
transaction with different response delays or data values. Each run starts
from exactly the same emulated internal state.

### Hard questions

- Restoring the chip cannot undo signals already observed by another device.
  Repetition needs a coordinated counterpart reset, a legal pause point, or
  a wholly virtual interaction.
- A checkpoint must include all relevant state, including pending events and
  any input history used by edge detectors.
- Timers need a defined relationship to restored logical time and continuing
  physical time.
- The programming system could identify externally restartable checkpoints,
  but that requires explicit assumptions about the counterpart.

### First worked example

Specify a transaction boundary at which the peripheral can be restored.
List the state that must be saved and the action required of the counterpart
before the transaction can be repeated faithfully.

## 5. A protocol that changes its own wiring

### Central idea

Build a small programmable fabric whose configuration can change atomically
during execution.

During one phase, resources form a receiver. Once a command has been
recognised, those same resources become a response generator, a parallel
sampler or several independent channels. The programme describes successive
circuit configurations and the conditions for moving between them.

### Why it is interesting

The question is whether a small amount of hardware can implement a much
larger sequence of specialised machines by reusing resources over time.
Conventional protocols would supply the initial personalities.

### Memorable demonstration

Invent an interface that changes encoding, direction or lane count between
phases. The chip follows those changes from one loaded programme.

### Hard questions

- Configuration changes must preserve selected state and leave outputs
  well-defined.
- Transition latency must be predictable and compatible with the protocol.
- Configuration storage and distribution can consume the area saved by
  resource reuse.
- There must be a concrete advantage over expressing the same behaviour
  with ordinary instructions and configurable shifters.

### First worked example

Describe a two-phase interaction and map both phases onto the same small
resource set. Account for configuration transfer, state preservation and the
observable behaviour during the transition.

## Which directions deserve exploration?

The pinball machine and Schrödinger's peripheral are the strongest
conceptual contenders. Both offer an unusual answer to "what is a
programme?", which could shape the silicon, tools and demonstration.

The imaginary circuit board has the clearest immediate use. Save states
could make it particularly distinctive. Dynamic wiring is the largest
architectural gamble.

Two deliberately different exploration tracks would be worthwhile:

- **The strange machine:** a programmable token graph, with UART, SPI and
  I2C as examples of its expressive power.
- **The strange instrument:** a peripheral that tracks alternative
  interpretations and exposes uncertainty, eventually turning an observed
  interaction into an executable personality.

For each, begin with one small, worked programme showing something awkward
to express on a conventional sequencer. That establishes whether the unusual
execution model produces a useful capability before committing to RTL or a
particular memory organisation.

These are alternatives to explore, not a proposal to combine all five into
one chip.
