# Formal: bounded model checking of sequencer programmes, and RTL against specification

The deadline sequencer's executable specification (`../sequencer-v2/isa2.ml`, ISA v2) is now
written once over an abstract domain of values. This directory runs that *same* code on three
domains:
- OCaml integers: the specification every existing test already used;
- SMT-LIB bit-vector terms: bounded model checking of programmes;
- Hardcaml signals: the specification as a circuit, compared with the hand-written RTL by Yosys.

There is one semantics. Nothing here is a second model of the ISA that could drift from the
first. Results are in `results/`, each file headed by its command, commit and tool versions.
Everything was run on 2026-10-05.

| task | what | result |
|---|---|---|
| 1 | interpreter generic over values | lockstep and all ported suites unchanged; integer speed restored (bridge A 31.7 s → 10.2 s, 9.4 s before the functor) |
| 2a | deadline waits | `main.ml`'s deadline programme: no violation to 160 clocks, with the other three threads unconstrained; planted bug found at clock 89 |
| 2a | every WAITD of UART + SPI + I2C | 15 contracts, 720 clocks; **found a latent SPI compiler bug** (Findings) |
| 2a | the same after the I2C clock-stretching fix (`results/a-protocols.txt`) | UART + SPI: 5 contracts, 720 clocks beside the real I2C master, 0.17 s; I2C: its 8 WAITD contracts (and at stretch limit 7 its 3 WAITP contracts) **for every state at their anchor, at every depth**, 0.1 s; planted off-by-one LDD found (Findings 4) |
| 2b | pin ownership | four programmes, 720 clocks; planted bug found at clock 95 |
| 2c | isolation (2-copy miter) | BMC: planted bug found at clock 28; induction: holds at **every depth** for the UART; both covers now reachable by concrete witness (0.9 s, was unanswered after 22 min) |
| 2e | ownership of bank, inboxes, ports | bridge A: no violation to 300 clocks; planted violations found; with bank ownership the bank-reading UART is isolated at **every depth**; rules on the declaration itself (one writer per bank address, inbox i received only by thread i, one sender unless shared), shared with the hazard checker, 4 of 4 planted declarations rejected |
| 2d | UART frame, every byte | 2 frames (440 clocks); planted bug found at clock 98 (byte 0x04) |
| 3 | Kind 2 (k-induction, IC3) | deadline property **proved for all depths** in 0.2 s; UART times out at 15 min |
| 4 | RTL against specification (Yosys) | equal for 23 clocks after reset, for every instruction stream and input; **28 of 28** planted RTL bugs found |
| 5 | power-up determinism (SymbiYosys) | two copies from arbitrary register contents agree on every output after a one-clock reset, **unbounded** (abc pdr); **found a fetch bug in the RTL** (Findings 5), now fixed; 2 of 2 planted un-reset registers that reach an output are caught, 3 that cannot are correctly passed |
| 6 | per-property report | every property PROVED, VACUOUS, FAILED or UNDECIDED, every cover REACHABLE or UNREACHABLE, across all engines (`results/summary.txt`); a planted vacuous property is reported VACUOUS |
| 7 | our UART against Jane Street's `Uart.Tx` (SymbiYosys) | pin-equivalent for 4 frames and every 4 byte values, with an offset that shrinks by exactly one clock per back-to-back frame (3, 2, 1, 0), and **why no constant offset can hold** |

## 1. One interpreter, several value domains

`Isa2.Make (V : VALUE)` is the interpreter. `V` supplies:
- bit-vector constants and operations (`add`, `logand`, `shl`, `extract`, `zext`, `eq`, `ult`,
  `ite`, ...);
- truth values;
- the data bank (`mem_read`, `mem_write`).

Every value has a fixed width. The integer instance does not track widths, so each operation
that could leave its width is told the width (`~w`) and wraps there. `Isa2.Spec = Make
(Int_value)` is the specification. The old public API (`state`, `io`, `effects`, `init`, `step`,
`step_f`, `sub_of`, ...) is re-exported with the same types, so no caller changed.

To make that possible, the interpreter is now written as dataflow. Every next-state value is
computed from the state at the start of the clock, with conditionals as `ite` on values, and
written at the end. It gained one effect, `pins_written` (the pins a SETP or SHO writes), which
the ownership check needs and the integer wrapper drops. The executing thread stays an OCaml
`int`: the schedule is fixed (thread = clock mod 4), so it never needs to be symbolic.

Evidence that the rewrite changed nothing:
- `lockstep2.exe 1000 5000` gives output byte-identical to the recorded
  `../sequencer-v2/results/lockstep.txt`: both generators, the coverage table and all 28
  planted-bug controls.
- The seven ported suites of `../sequencer-v2/run_all.sh` give output identical to their
  recorded results: the UART/SPI/I2C demo, 10BASE-T, JTAG and SWD, low-speed USB, PS/2, CAN TX
  and multi-proto bridge A. The one exception is bridge A's own "elapsed" line.

**Speed** (restored 2026-10-05, branch formal-followups). Through the functor, without flambda,
every value operation was an indirect call and every opcode's result was computed on every
clock: bridge A of the multi-proto port went from 10.1 s to 31.7 s. Three changes, none of
which forks the semantics:
- `Isa2.Spec` is `Make`'s body written out over `Int_value`, between two markers, so that
  ocamlopt sees the integer operations as known functions and inlines them (`[@inline]`). The
  build fails unless the copy is verbatim (`../sequencer-v2/specialise.awk`, run from its `dune`);
  `../sequencer-v2/specialise.sh` rewrites the copy after an edit of `Make`.
- `VALUE.known_false` guards each opcode's group: a value used only where its opcode holds is
  not computed when the opcode is known not to hold. On integers that is every other opcode; on
  SMT terms it skips terms that would fold away; on Hardcaml signals it is never taken, so the
  circuit is the whole instruction set as before.
- the `cases` lists became `ite` chains, the field and opcode helpers became top-level, and
  `sub_of` spreads the old and new pins once instead of four times.

The record types (`state_of`, `io_of`, `effects_of`) moved out of the functor, parameterised, so
that `Spec.state` is the same type as `Make (Int_value).state`.

Measured on this machine, each run back to back (`/var/tmp/formal-followups/runs/`):

| run | before the functor | functor | now |
|---|---|---|---|
| bridge A, `bridge_a.exe all`, 3 runs each, alternating | 10.1 s | 31.7 s | 11.3 s |
| the same at the end of the work (with the ownership effects) | 9.4 s | | 10.2 s |
| interpreter alone, 20 M random clocks | 1.0 s | 8.9 s (generic instance) | 1.6 s |
| lockstep 1000 × 5000 (RTL simulation dominates) | 133 s | 152 s | 143 s |

The lockstep output and all nine ported suites are byte-identical to the recorded results, and
the interpreter benchmark's final state hashes agree for all three. The remaining gap on the
interpreter alone is the dataflow form itself (every common field is computed every clock).

## 2. Incremental bounded model checking, ScottCheck style

**Terms** (`smt.ml`). SMT-LIB terms are hash-consed and folded as they are built: operations on
constants are evaluated, and the usual identities are applied. One rule matters most: comparing
an ite tree of constants with a constant is pushed into the tree. z3 runs over a pipe
(`z3 -in -smt2`).

**The machine** (`machine.ml`) steps `Isa2.Make (Smt.Value)`. Each thread runs either:
- the concrete programme in the store; or
- an unconstrained instruction word every slot ("Havoc": whatever another thread might do).

For a concrete thread, the clock is split by fetch address. The interpreter runs once per
address the thread can be at, on a constant instruction word, where nearly everything folds. The
results are merged under "address = a". A programme whose timing does not depend on inputs
therefore folds to constants entirely, and the solver sees only the data.

**The loop** (`bmc.ml`) is Gergo Erdi's ScottCheck pattern (credits below): unroll one clock at
a time in a single solver session. At each depth, `push`, assert the goal (a property violation
at exactly this clock), `check-sat`, `pop`. The unrolled clocks stay asserted. Two additions:
- a goal that folded to `false` is not sent at all;
- environment assumptions are asserted at the top level as they appear.

After the last depth, **covers** check that the outcomes the property speaks about are
reachable, so a pass cannot be vacuous.

**Monitors** (`props.ml`) are written once over the value domain too. Every counterexample is
replayed on `Isa2.Spec` through the same monitors, and the run checks that the violation
reproduces at the same clock. All of them did ("counterexample CONFIRMED" in `results/bmc.txt`).

The programmes are the real compiler's output (`../deadline-sequencer/compiler.ml`), translated
to v2 by `../sequencer-v2/compat.ml`, as the v2 ports run them. Planted bugs are edits of
compiled words, as a compiler bug would produce.

### Results (`results/bmc.txt`)

Times are wall-clock for the whole run; "goals" counts the depths whose goal reached the solver.

| property | programme | depth (clocks) | goals | result | time |
|---|---|---|---|---|---|
| (a) deadline | `main.ml`'s deadline programme on thread 1, threads 0, 2, 3 unconstrained | 160 | 38 | no violation; both outcomes reachable | 0.05 s |
| (a) planted | same, LDD 21 for a 21-slot window | 90 | 21 | violated at clock 89 | 0.05 s |
| (a) every WAITD | UART, SPI (period 10), I2C on threads 0–2 | 720 | 0 (all folded) | no violation; all 15 reachable | 0.03 s |
| (b) ownership | UART pin 0, SPI 1–3, I2C 4–5, watchdog 7 | 720 | 625 | no violation; every thread writes | 0.12 s |
| (b) planted | watchdog's timeout writes mask 0x01 | 96 | 1 | violated at clock 95 | 0.02 s |
| (c) isolation, BMC | UART on thread 0; threads 1–3 unconstrained in each copy | 36 | 35 | no violation; covers stopped unanswered after 22 min | 919 s |
| (c) planted | UART reads its bytes from the shared bank (LDB) | 29 | 28 | violated at clock 28 | 72 s |
| (c) isolation, induction | as (c) | all | 1 query | inductive | 0.08 s |
| (d) UART, every byte | 2 bytes from the host, always ready | 440 | 248 | no violation; 2 frames reachable | 0.18 s |
| (d) any arrival | 1 byte, host ready at any clock | 208 | 198 | no violation; 1 frame reachable | 21.5 min |
| (d) planted | data bit 3 of byte 1 stretched by 3 slots | 99 | 4 | violated at clock 98 | 0.01 s |

What each property says:

**(a) Deadline waits.** A contract names:
- a wait instruction;
- its anchor, the instruction that opens the window (the LDD);
- the window's length in the thread's own slots.

The monitor counts the thread's slots since the anchor, independently of `dl`. Each time the
wait executes, only three outcomes are allowed:
- the event is on this slot's pin input: proceed;
- no event and this is the last slot of the window: take the fail branch;
- no event, earlier in the window: stay.

Anything else is a violation, including staying after the window. For a WAITD the fail branch is
the next instruction. For `main.ml`'s programme the window is 21 slots (84 clocks), the timing its
own test exercises. For the WAITD of the three compiled protocols, the contract is the ISA's rule
"LDD n then WAITD occupies n + 1 slots". That checks the ISA's timing along every path, with the
other threads running, not the compiler's intent.

The planted bug is an off-by-one LDD (21 instead of 20). The counterexample is the obvious one:
pin 1 never rises, and at slot 21 of the window the WAIT stays with dl = 1 instead of failing.

**(b) Pin ownership.** Each thread's set of pins written so far (SETP's mask, SHO's pin and pair
partner); bad when two sets meet. The planted bug is a watchdog whose timeout writes the UART's
pin. The counterexample needs the solver to withhold pin 6 for the whole 21-slot window, and it
does: the watchdog's timeout SETP writes pin 0 at clock 95.

**(c) Isolation, as a two-copy miter** (after umerimran-10xe's arbitration miter, credits). Two
copies of the machine get the same environment inputs. Thread 0 runs the UART in both. In each
copy, threads 1–3 execute independent unconstrained instruction words every slot. The other
threads are assumed to obey ownership: they never write pin 0. The property is that pin 0 (level,
output enable, and all four quarter-clock levels) is the same in both copies at every clock.

The planted bug is realistic. The transmitter takes its bytes from the shared data bank (LDB),
which nothing protects. In the counterexample, another thread STBs a 0 into the byte in one copy
before thread 0 reads it, and the first data bit differs at clock 28.

The BMC of the miter is expensive: z3 must reason through three threads of arbitrary
instructions per copy. In the planted run, the solver's cumulative time was 5 s by clock 20 and
72 s by clock 29.

The unbounded version is cheap: a one-round **relational induction step** (`c-induction`). The
relation R says the copies agree on everything thread 0 owns or reads:
- its registers;
- pin 0;
- the round latch.

Everything else is a separate free variable in each copy: the other threads' registers, the other
pins, the inboxes and the bank. Thread 0's pc may be any address it can reach. One query shows
that R before a round implies pin 0 equal after every clock of the round and R after it. The
reset state satisfies R, so isolation holds **at every depth**. The query is checked to be
non-vacuous (its assumptions are satisfiable). Two controls fail as they should: the LDB variant,
and the clean UART without the ownership assumption.

**(d) UART transmitter, every byte.** The receiver monitor knows nothing of the compiler, like
`../deadline-sequencer/decoders.ml`. It watches the line (the pin when driven, 1 when released),
starts at a falling edge, and samples mid-bit at 10 + 20k clocks (bit period 5 slots). It expects
0, the byte lsb first, then 1, where the byte is the one the thread took from the host. The
programme is the compiler's UART with each `LDA byte` replaced by `IN`, so the byte is an input.

The planted bug is the compiler's own fault injector (data bit 3 of the first byte stretched by 3
slots). The solver picks byte 0x04, whose bit 2 is 1 and bit 3 is 0, so the stretched bit is
sampled where bit 3 should be.

**(e) Ownership of the bank, the inboxes and the ports** (2026-10-05, `results/ownership.txt`).
The declaration is `../sequencer-v2/ownership.ml`: per thread, the bank address ranges it may
read and write, the inboxes it may send to and receive from, the ports it may use. The same
declaration is checked statically by the hazard checker (`../verif-oracles`, with bank addresses
from a data-flow analysis of the bank pointer) and here as a property. The interpreter reports
what each clock touches: `bank_read`, `bank_write`, and four new 4-bit effects naming the inboxes
and ports an instruction uses, whether or not it succeeds. `Props.disobeys` is bad when a touch
is outside the executing thread's declaration; `Props.obeys` is the same as an assumption.

| scenario | what | result |
|---|---|---|
| e | bridge A (T0 UART RX → inbox 1 → T1 I2C master → inbox 2 → T2 UART TX, T3 SPI), every input free | no violation to 300 clocks (175 goals, solver 267 s) |
| e-planted-steal | T3's first word becomes RECV inbox 2 | violated at clock 3, confirmed on `Isa2.Spec` |
| e-bank | the UART reading its two bytes from bank 0 and 1 (LDB), declared to read 0..1 | no violation to 440 clocks (2 frames), both addresses read |
| e-bank-planted | the same, declared to read 0 only | violated at clock 204 (the second LDB, address 0.13), confirmed |
| c-induction-ldb-owned | isolation of that UART, every thread assumed to keep to its declaration (the others may write 2..1023), R also equates bank 0..1 | **inductive**: pin 0 cannot depend on the other threads, at any depth |
| c-induction-ldb-owned-overlap | the same, with the others allowed to write address 1 | not inductive (counterexample with thread 0 at pc 14) |

The last two answer finding 2: with the bank under ownership, the UART that reads the bank is
isolated without a bound, as the immediate-only UART was. Each assumption is a property
checked on its own: the UART's own reads by e-bank and by the hazard checker (which accepts 0..1
and rejects 0 only, at the same LDB); the other threads' by checking their programmes when
there are any.

**Rules on the declaration itself** (`Ownership.conflicts`, added 2026-10-05). A declaration
can be wrong before any code runs, and a havoc thread in a proof is assumed to keep its
declaration, so the declaration needs rules of its own. The same function is the hazard
checker's OWNERSHIP rule (`../verif-oracles/README.md`), and `resources` refuses to run on a
declaration that breaks it:
- no bank address written by two threads; one thread per port and direction;
- inbox i belongs to thread i, and only thread i may receive from it (WAITC 10 polls the
  executing thread's own inbox, so another receiver could not wait for it);
- at most one declared sender per inbox, unless declared shared;
- an inbox some thread sends to must be received by its owner.

Scenario `e-declarations` (`results/bmc.txt`) applies them to bridge A's declaration (keeps the
rules) and to four planted variants, all rejected: T3 also declared to receive from inbox 2; T3
also declared to send to inbox 1; T2 no longer declared to receive from inbox 2; T0 and T3
declared to write overlapping bank ranges. The isolation inductions keep their own "anything
else" declaration for the havoc threads (every inbox, the whole bank), which is deliberately
looser than these rules: it is an over-approximation, not a design.

Covers for e use one concrete witness: the host sends 0x10 (ACK) on the UART line from clock 8.
Replayed on `Isa2.Spec`, T1 and T2 start receiving at clocks 5 and 6, T0 passes the byte to
inbox 1 at clock 620 and T1 answers into inbox 2 at 785. The two later ones lie beyond the
300-clock bound and are reported as such.

**Cost, and the cut.** Bridge A's UART receiver follows its input, so without help the unrolled
terms nest: the term graph more than doubled every 20 clocks (31,000 definitions at 120). After
each clock `Machine.cut` replaces every non-constant register by a fresh variable with its
defining equation, and keeps a thread's pc split over the addresses it can be at. The graph then
grows linearly (about 525 definitions a clock), but the solver's time does not: the goals at the
UART's WAITC 11 (whose target comes from `lsend`) need z3 to reason back through the unrolling,
267 s in all at 300 clocks, and an earlier run had not reached 400 clocks 10 minutes later. 1,000
clocks, which would include a whole frame, was out of reach. The static check covers every
reachable instruction without a bound; the BMC's value here is the semantic cross-check and the
counterexamples. The cut is not used for the isolation miter, where it undoes the sharing
between the two copies (16 clocks: 5.9 s with it, 0.3 s without).

### Limits of the checks
- Bounded, except where stated: the isolation induction step, and Kind 2's proof of (a).
- Inputs are free and independent on every clock. In particular, the four quarter-clock samples
  are not tied to the pin input. This over-approximates the environment, so passes are
  conservative. No counterexample here depends on it.
- The deadline monitor reads the raw pin input, so it does not cover programmes that set the
  round latch (cfg bit 7).
- (d) covers 2 frames with the host always ready, and 1 frame with arbitrary arrival times.
  With free arrival the solver's time per clock grows quickly (over 200 s per clock at 224 in an
  earlier run), so 208 clocks, just enough for one frame, is the depth used.
- The clean isolation miter ran to 36 clocks (cumulative solver time 4.9 s at 24 clocks, 60 s
  at 32, 1019 s at 36, `results/isolation-covers.txt`). Its two cover queries had run 22
  minutes unanswered as plain satisfiability questions. They are now decided by concrete
  witnesses (below), in 0.92 s and 0.03 s. The induction step remains the real result.
- The isolation result is for one protocol (the UART). A protocol that reads the inbox, the
  bank or a port is isolated only under the ownership assumption of (e), as the induction with
  bank ownership shows for the bank.

**Covers by concrete witness** (`bmc.ml`, `witnesses`). A cover asks whether an outcome is
reachable, and a satisfying assignment is all that needs. A witness gives a value to every
input and unconstrained instruction word. It is first replayed on `Isa2.Spec` through the same
condition (in OCaml), then asserted in the solver with the cover, inside the push, so that z3
only evaluates. Unsatisfiable means the witness is wrong and is reported as "WITNESS FAILED",
never as unreachable. For the isolation miter: every input 0 and every unconstrained word a
NOP, except copy a's thread 1 setting pin 1 at clock 1 ("the copies' other pins differ", from
clock 1), and the same with no exception ("the transmitter drives pin 0 low", from clock 8, its
start bit). A first version emitted the witness's equations inside the push, so the first
cover's pop deleted definitions the second cover then used; z3 answered with an error, which was
read as unsatisfiable. Definitions are now written before the push, and a solver error fails
loudly.

## 3. Timed model checking for comparison: Kind 2

**Which checker.** UPPAAL needs a licence key, obtained by registering, so it was not used.
nuXmv's binary downloads without registration, but its licence restricts commercial use, so it
was not used either. The checker used is **Kind 2** v3.0.0 (Apache-2.0, release binary).
It runs k-induction, IC3 and BMC over a Lustre model with machine integers, with z3 as its
solver. It ran with three engines (BMC, k-induction, IC3) to keep the load near four cores.

**The model is generated, not hand-written** (`lustre.ml`):
- the machine's state becomes Lustre state variables;
- one round (four clocks) of `Isa2.Make (Smt.Value)` and of the property monitor runs on them;
- every term in the property's cone of influence becomes an equation.

A thread whose pc is a state variable has no constant leaves to split on. It is split over the
addresses its control-flow closure can reach, and the property includes "pc is in that set", so
a gap would show as a violation. For the deadline programme, the cone is 5 state variables (`pc`,
`page`, `dl`, `cfg` of thread 1, and the monitor's counter), 2 inputs and 69 equations. The other
threads are unconstrained and outside the cone. The files are in `kind2/`.

| model | Kind 2 (`results/kind2.txt`) | our BMC |
|---|---|---|
| (a) deadline, correct | **valid for every depth**, by k-induction at k = 22–24 rounds (0.2 s) | no violation to 160 clocks (0.12 s) |
| (a) planted LDD 21 | invalid at k = 22 rounds (clocks 88–91) (0.2 s) | violated at clock 89 (0.04 s) |
| (d) UART, byte always ready | timeout, 15 min | 2 frames, no violation (0.14 s) |
| (d) UART, any arrival | timeout, 15 min | 208 clocks, no violation (21.5 min) |
| (d) planted stretch | invalid at k = 24 rounds (2.2 s) | violated at clock 98 (0.01 s) |

**Verdict.** Worth having for small, deadline-shaped properties, because it turns "no violation
to depth N" into "no violation". The window of 21 slots is exactly the k it needs, so a
deadline contract is naturally k-inductive. It costs little once the exporter exists, and the
exporter reuses the one semantics.

It is not a replacement for our BMC. Our loop gives counterexamples in the programme's own terms,
replayed on the specification. On the UART, whose frame is about 50 rounds long, k-induction and
IC3 found no proof in 15 minutes, while the BMC checks two whole frames in under a second.

A dense-time timed automaton (UPPAAL) would add nothing for this machine: time is a slot counter
by construction, and a discrete model is exact.

## 4. RTL against specification, Yosys

`hardcaml_verify` is not installed in switch 5.3.0, so Yosys's SAT-based BMC was used, in the
LibreLane container of `../deadline-sequencer/pnr/run_pnr.sh` (Yosys 0.62).

**The specification as a circuit** (`equiv/`). `Isa2.Make (Hw_value)` is the interpreter with
Hardcaml signals as values. `spec_core.ml` wraps it in registers with the RTL core's port timing:
- four copies of the interpreter, one per thread, selected by the thread register;
- host control applied after the clock. This is the only line of semantics written there rather
  than taken from `Isa2`, because the hardware's thread index is a signal and `Isa2`'s is an
  `int`.

**The miter** (`miter.ml`) instantiates `sequencer2.ml` (optionally with one of its 28 planted
bugs) and the specification circuit. Every input is free on every clock:
- the instruction word, so every programme is covered, even one that changes under the core;
- the pins, host, ports, flags and host control;
- the bank's read data. The RTL gets that byte a clock later, as from its SRAM; equivalence for
  every read value implies equivalence for every memory.

`mismatch` compares every output and every architectural register, as `lockstep2.ml` does: data
outputs only while their strobe is set, and the in-flight LDB byte stands in for the
accumulator. Before Yosys, the miter itself was smoke-tested in Cyclesim with 20,000 random
clocks: no mismatch on the real RTL, and a mismatch for 25 of the 28 planted bugs. Random
simulation missed the host-pc bypass, RECV at dl = 0 and SKEQ.

**Depth.** Yosys counts time steps, and step 1 is the clearing clock, so depth N checks N − 1
clocks. `run_equiv.sh` prints both; `results/equiv-bugs-depth16.txt`, recorded before that
change, prints N only.

| | result | time (wall, with container start) |
|---|---|---|
| real RTL, depth 8, 16, 24 (`results/equiv-clean.txt`) | no mismatch, i.e. equal for **23 clocks** (5 to 6 instructions per thread) from reset, for every instruction stream and input | 55, 96, 264 s; 1.4 M variables at depth 24 (an earlier run also passed depths 12 and 20) |
| 28 planted bugs, depth 16 | **28 of 28** counterexamples, including the three random simulation missed | 41–96 s each |

`results/equiv-bug-*.txt` decode a counterexample into a programme trace. Two examples:
- "SKEQ skip lands on pc+1": the solver makes thread 1 load its accumulator by LDB, with the
  bank's read data chosen equal to the SKEQ immediate. Thread 1's pc diverges after its SKEQ.
- "RECV on an empty inbox stays at dl = 0": thread 2 executes `recv ch0` on an empty inbox with
  dl = 0. The specification takes the fail branch; the faulty RTL stays.

Not tried: `sat -tempinduct`. RTL-internal registers that the comparison cannot see (pending LDB,
the previous pins) would probably need strengthening invariants first.

## 5. Power-up determinism (SymbiYosys)

After MarcosAsh's `formal/powerup.sby` (credits). `powerup/powerup.sv` instantiates two copies
of the v2 core as it is synthesised (`powerup/emit_core.ml`: the Verilog of `tt/src`, no debug
ports). No register of the core has an initial value, so each copy starts from its own arbitrary
contents. Both copies get the same inputs on every clock, including clear. Clear is forced high
for the first `RESET_CLOCKS` clocks, and free (but shared) afterwards. From then on every output
must agree, one assertion per group: pins (level, output enable, quarter-clock levels), the
fetch address, host, ports, bank, FINE, cfg. Data buses are compared only while their strobe is
set. The memories are outside the core, as on the chip. Each copy's programme word is the
store's output for the address that copy presented on the previous clock. Both copies get the
same word when they presented the same address, and independent words otherwise. The bank's
read data is modelled the same way. This is exactly "every register that can reach an output
is reset": a register left out of the clear may differ, and the proof fails only if the
difference reaches a pin.

`Sequencer2.create ?unreset` builds named register groups without the clear, as planted faults;
without it the generated Verilog is byte-identical to the build without the option.

Results (`results/powerup.txt`; `powerup/run_powerup.sh`, SymbiYosys and Yosys 0.62 in the
LibreLane container; abc pdr for the proofs, smtbmc with z3 for the bounded run and covers):

| task | what | result |
|---|---|---|
| r1 | real core, one-clock reset | **PASS, unbounded** (abc pdr; 45 s, 333 s with the vacuity control added) |
| r2 | real core, two-clock reset | PASS, unbounded (abc pdr, 27 to 171 s across runs) |
| r1_bmc | as r1, bounded, 12 clocks | PASS |
| u_cfg | `cfg` registers without the clear | **FAIL** at step 1 (`cfg_out` differs) |
| u_dl | `dl` registers without the clear | **FAIL** at step 4: a wait in thread 0 ends at a different clock, so the fetch addresses part |
| u_inbox | inbox data without the clear | PASS: read only while `full`, which is reset |
| u_prev_pins | `prev_pins` without the clear | PASS: selected only after a SETP with q > 0, by which time it holds a reset value |
| u_host_tag | `host_tag` without the clear | PASS: compared only with `host_out_valid`, and OUT writes it first |

The three passing planted faults are the point of comparing outputs rather than demanding a
reset on every register: those registers really cannot reach a pin before they are written.

**What the first run found** (`results/powerup-before-fetch-fix.txt`, commit d0d3f3e). With a
one-clock reset, r1 failed at step 1. During the clear clock the core presented a fetch address
computed from the power-up contents of `thread`, `pc` and `page`. The store latched that word,
and thread 0 executed it as its first instruction (copy a ran `f500`, copy b `c000`, an IN,
whose ready strobe differed). With a longer reset the proof passed, but a simulation (iverilog,
boot pcs 10, 20, 30, 40) showed thread 0 then executing the word at **thread 1's** boot address:
`thread` is 0 during clear, so the core presented the address for thread 0 + 1. The lockstep test
missed both because `harness2.ml` did not model this: after clear it set the store's address to
thread 0's boot address itself. The TT harness boots every thread at 0, which hides it too.

The fix (`../sequencer-v2/sequencer2.ml`): while clear is high the core presents thread 0's boot
address. `harness2.ml` now latches whatever address the core presents during clear, as an SRAM
does. With the honest harness and the old RTL, the lockstep test fails at clock 0 in every
programme (`lockstep2.exe 20 200`: 1297 and 856 mismatching clocks); with the fix, `lockstep2.exe
1000 5000` gives output identical to `../sequencer-v2/results/lockstep.txt`.

Limits: the inputs `boot_pc` and `boot_page` are free on every clock (on the chip they are a
configuration register); the stores are modelled per address, not as a whole memory, which only
adds behaviours. The proof is of the core alone; the TT wrapper's own registers (its loader) are
outside it.

## 6. Per-property report

After smprather's per-property PROVED / REACHABLE / VACUOUS summary (credits). Every assertion
names a cover for its **antecedent**: the condition under which it can fail at all. A property is
PROVED only when the engine finds no violation **and** its antecedent is reachable within the
same bound; if the antecedent is unreachable the verdict is VACUOUS, never a pass. The format is
the same for every engine:

    PROPERTY <name>: PROVED <scope>; antecedent <cover> reachable
    PROPERTY <name>: VACUOUS <scope>; antecedent <cover> unreachable
    PROPERTY <name>: FAILED at clock <k>
    PROPERTY <name>: UNDECIDED (...)
    COVER <name>: REACHABLE | UNREACHABLE within <n> clocks | UNDECIDED

- **Our BMC** (`bmc.ml`): `Bmc.run` takes a mandatory `~antecedent`, the name of one of its
  covers, and fails if the cover is missing. The antecedents: (a) every contract's wait executes;
  (b) two threads write pins; (c) the other threads make the copies' other pins differ; (d) a
  frame is sampled; (e) some thread touches an inbox; e-bank: thread 0 reads the bank. For an
  induction step the antecedent is its hypotheses: unsatisfiable hypotheses make it VACUOUS.
- **SymbiYosys** (`sby_report.py`): each `label: assert` needs a `label_ante: cover`; the script
  combines the proof's log with the cover task's log. Where smtbmc's covers are too slow (the
  UART miter, 840 clocks), the antecedent is asserted negated as `label_ante_reach` and checked
  by abc bmc3: a failure at step n means reachable at step n.
- `report.sh` collects every PROPERTY and COVER line into `results/summary.txt` and marks the
  planted faults and controls, where FAILED or VACUOUS is the expected answer.

Controls for the report itself: `a-vacuous-planted` places a deadline contract on an address the
programme never reaches; it has no violation, and is reported **VACUOUS**, not PROVED. In
`powerup.sv`, `vacuity_control` asserts an implication whose antecedent (the output enables
differ) the other assertions rule out; it must be reported VACUOUS too.

Two things this caught while it was being built. sby's summary listed only 5 of the 7 reached
covers in one run, so a report read from the summary called two reachable antecedents undecided;
`sby_report.py` reads the engine's own "Reached cover statement" lines. And the first antecedent
written for the UART miter counted falling edges on the lines, which data bits produce too: it
was reached at step 606, before the last frame had started, and so certified less than it
claimed. It now requires every byte taken by both transmitters and our last frame finished.

Not in the report: Kind 2 (section 3) and the RTL-against-specification runs (section 4), whose
non-vacuity evidence is the 28 of 28 planted bugs.

## 7. Our UART against Jane Street's `Uart.Tx`

After MarcosAsh's `fsm_miter` (credits). The reference is `Uart.Tx` from
github.com/janestreet/hardcaml_hobby_boards (MIT), `src/uart.ml`, commit 9e6aeca (2025-10-30). It
is not vendored: `uart-miter/build_hobby_tx.sh` compiles the unmodified upstream files from a
checkout in `/var/tmp` next to our `emit_hobby_tx.ml`, which fixes the configuration (8 data bits,
no parity, one stop bit, 20 clocks per bit) and writes Verilog. The upstream source needs Hardcaml
v0.18 and `ppx_hardcaml`, which the shared switch 5.3.0 lacks (v0.17, no ppx), so it builds in a
project-local opam switch, `/var/tmp/formal-hygiene/hobby-switch`, with v0.18~preview.130.106+341
from Jane Street's opam repository.

Our side is the v2 core (the Verilog of `tt/src`) running the compiler's UART programme on
thread 0, pin 0, 5 slots (20 clocks) per bit, taking each byte from the host with IN: the
programme of property (d). `uart_rom.exe` writes it as the store's contents; the store reads
in one clock, as on the chip. `uart-miter/uart_pair.v` runs both on the same bytes.

**Measured first, in simulation** (`results/uart-miter.txt`, iverilog, 4 bytes). Our core takes
byte k when its IN executes. The Tx takes a byte in its Start state while `data_in_valid` is high.

| feeding the Tx | Tx frame starts | our frame starts | offset |
|---|---|---|---|
| each byte valid one clock after our core takes it ("locked") | 7, 208, 409, 610 | 10, 210, 410, 610 | 3, 2, 1, 0 |
| every byte valid as soon as the Tx can take it | 2, 203, 404, 605 | 10, 210, 410, 610 | 8, 7, 6, 5 |

**Why no constant offset holds.** Back to back, the Tx needs 10 × 20 + 1 = 201 clocks per frame:
after the stop bit's last enable it spends one more bit period in Complete, then one clock in
Start to take the next byte, so its stop bit is 21 clocks. Our frame is exactly 200 clocks: the
next byte's IN sits inside the stop bit's 5 slots. In general the Tx's back-to-back period is
10 × clocks_per_bit + 1, always odd, and ours is a whole number of 4-clock slots, so no
clocks_per_bit makes them equal; the offset changes by one clock per frame whichever way the Tx
is fed. Within a frame the waveforms are identical: start and data bits are 20 clocks on both.

**The proof** (`uart-miter/uart_miter.sv`, SymbiYosys, abc bmc3): the bytes are free constants
(every value of all four), the Tx is fed locked, and every clock from reset to 840 our line at t
equals the Tx's line at t − d, with d = 3, 2, 1, 0 in our frames 1 to 4 (before the first, 3).
The Tx's line before its reset has taken effect counts as idle.

| task | what | result |
|---|---|---|
| bmc | 4 frames, every 4 byte values, offsets 3, 2, 1, 0 | **PASS to 840 clocks** (0.11 s) |
| ante | antecedent: all four bytes taken by both, our last frame finished | reachable at clock 810 (our last frame started at 610) |
| constant | the same with one constant offset, 3 | **FAIL** at clock 210, our second start bit |
| flip | the Tx given each byte XOR 0x80 | **FAIL** at clock 170, bit 7 of the first byte |
| stretch | our programme with the compiler's fault injector (data bit 3 of byte 1 three slots longer), 2 bytes | **FAIL** at clock 90 |

abc decides the 840 clocks in a tenth of a second because, with the timing locked, everything
but the byte values is deterministic; the three controls show the property is not vacuous
(and the antecedent shows the whole horizon is compared).

Limits: four frames, back to back, host always ready; a fifth would need the Tx to be behind
ours (d = −1). The Tx's `data_in_ready` is high exactly in its Start state, which the feeding
logic uses as its accept signal; that is read from the upstream source, not from a spec.

## Findings

1. **Latent bug in the SPI compiler** (`../deadline-sequencer/compiler.ml`, not fixed here).
   `spi_master` asserts `period >= 8`, and the README says "any even period of at least eight
   slots". At 8 it computes `a = P - 8 - (P/2 - 3) = -1` and emits `LDD 4095`. A simulation on the
   base interpreter measures SCLK edges 16,416 clocks apart instead of 32; period 10 gives the
   expected 40. The shortest valid period is 10. This was found by a cover (two WAITD of the
   SPI thread never finish within 720 clocks), not by a property violation.
2. The isolation counterexample is a design point, not just a test. Pins have an ownership
   discipline; the data bank, the inboxes and the ports have none. A protocol thread that reads
   any of them can be disturbed by another thread. **Addressed** by (e): an ownership
   declaration for the bank, inboxes and ports, checked statically and by BMC, under which the
   bank-reading UART is isolated at every depth.
3. The bounded equivalence finds all 28 planted RTL bugs at 15 clocks. That includes three that
   uniform random simulation of the same miter misses in 20,000 clocks; the lockstep needed a
   biased generator for those.
4. **(a) on the three protocols stopped finishing, and finishes again** (`results/a-protocols-after-i2c-fix.txt`,
   `results/a-protocols.txt`). `results/bmc.txt` was recorded before the merge with the I2C
   clock-stretching fix (5be80cf). The I2C master now waits on SCL, so its timing follows an
   input, the goals no longer fold to constants (0 goals before), and the run did not finish in
   30 minutes (69 goals sent), nor in 15 minutes with the state cut. Scenario b (pin ownership,
   the same I2C programme) still passes, but sends 646 goals instead of 625 and takes 55 s
   instead of 0.12 s; unmodified HEAD gives the same numbers, so this comes from the merge.

   **What replaces it** (2026-10-06). Bounding the stretch was tried first and does not help:
   the I2C master's contracts from reset with a stretch limit of 2 slots (every input still
   free) did not finish in 30 minutes, with or without the cut. Splitting does:
   - `a-protocols-uart-spi`: the UART's and SPI's 5 WAITD contracts, exactly as before (every
     input free, 720 clocks, all four threads running their programmes), now beside the real
     I2C master (stretch limit 4095). Their goals fold again: **no violation, 0.17 s**.
   - `a-protocols-i2c-local`: each of the I2C master's 8 WAITD contracts from **every state at
     its anchor**: every register of every thread, the pins, the latch and the bank free, every
     input free, the other threads executing unconstrained words; the run lasts the window plus
     two slots. A static check (`entered_only_at_anchor`) shows each wait is entered only
     through its anchor's straight line. Together these cover every execution of the wait at
     every depth from reset (the argument is in `main.ml`, above `predecessors`); the
     antecedent (the wait executes) is shown reachable from reset on `Isa2.Spec` with every pin
     read high. **8 of 8 PROVED, 0.1 s.**
   - `a-protocols-i2c-local-l7`: the same with the stretch limit 7 and the 3 WAITP contracts
     added (window: limit + 1 slots from the LDD two words before the WAITP; both the event and
     the timeout covers reached in each window). **11 of 11 PROVED.** The WAITP contracts at the
     real limit, 4095, would need a 4,097-slot window and are not run.
   - `a-protocols-i2c-local-planted`: the first WAITD's LDD one larger: **FAILED at clock 8.**

   What changes, exactly. Before the fix, a-protocols checked the I2C master's WAITD contracts
   along its one path from reset, to 720 clocks. Now they are checked from every state at their
   anchor, which includes every state reachable from reset, at any depth, and every input; the
   price is one assumption on the free state, that the thread's cfg is 0 (bit 7 would make the
   wait read the round latch where the monitor reads the pin), which holds because cfg is 0 at
   reset and the programme has no CFG instruction (checked). The UART and SPI part is unchanged.
   The whole-system, from-reset run of the I2C master is what no longer finishes; a-spi8 (the
   latent SPI bug, Findings 1) uses the same whole-system run and stays behind
   `SLOW_A_PROTOCOLS=1`.
5. **Thread 0's first fetch after reset came from the wrong address** (section 5). Found by the
   power-up determinism proof; fixed in `../sequencer-v2/sequencer2.ml`, and the harness that hid
   it now models the store's latch during clear.

## Credits and prior art

- **Gergo Erdi, ScottCheck** (github.com/gergoerdi/scottcheck, MIT; "ScottCheck: An Adventure
  in Symbolic Execution", IFL 2020). The incremental BMC loop (`bmc.ml`) and the idea of running
  the interpreter on symbolic values come from it (`../../notes/prior-art-erdi-kmett.md`,
  item 6). No code was copied; ScottCheck is Haskell/SBV.
- Prior art recorded in `../../notes/backlog.md` from public competition entries:
  - umerimran-10xe's arbitration miter (assume equal inputs for the owner, assert equal outputs)
    is the shape of (c);
  - mutation against proofs, as several entries do it (MarcosAsh's SVA "teeth", WilliamZhang20's
    named RTL mutants, fjpolo's equivalence miter), is the planted bugs here;
  - MarcosAsh's abstract-interpretation programme verifier (intervals over phase, period and
    cycles since an edge) is the unbounded alternative to (a). **It has not been read yet**; the
    backlog's advice to read it before building ours still stands for the programme verifier.
- **MarcosAsh**, github.com/MarcosAsh/protocol-emulator (Apache-2.0): power-up determinism as
  a two-copy proof from arbitrary flop contents (`formal/powerup.sby`), and a miter of firmware
  against `hardcaml_hobby_boards`' `Uart.Tx` (`make -C formal fsm_miter`). Ideas only; sections
  5 and 7 are our own.
- **smprather**, github.com/smprather/janestreet-blog-serial-protocol-emulator (MIT): every
  property reported as PROVED, REACHABLE or VACUOUS, vacuous never counting as a pass
  (`formal/run_formal.sh`). Idea only; section 6 is our own.
- **Jane Street**, github.com/janestreet/hardcaml_hobby_boards (MIT, Copyright (c) 2025 Jane
  Street Group, LLC): `Uart.Tx` (`src/uart.ml`, `src/uart_types.ml`), the reference circuit of
  section 7. Used unmodified from a checkout outside this repository; no code copied.
- Tools: z3 (MIT, from the `z3-solver` wheel), Kind 2 (Apache-2.0), Yosys (ISC, in the
  LibreLane image), Hardcaml.

## Running it

```
opam exec --switch=5.3.0 -- dune build          # main.exe and equiv/miter.exe
# z3 without root or a shared environment:
uv venv /var/tmp/symbolic-bmc/z3env && uv pip install --python /var/tmp/symbolic-bmc/z3env/bin/python z3-solver
export PATH=/var/tmp/symbolic-bmc/z3env/bin:$PATH
./_build/default/main.exe a a-planted      # one or more scenarios; no argument: all
./_build/default/main.exe e e-bank e-bank-planted e-planted-steal c-induction-ldb-owned
                                           # ownership (results/ownership.txt)
./run_all.sh bmc | kind2                   # regenerates results/bmc.txt, results/kind2.txt
equiv/run_equiv.sh clean 8 16 24           # Yosys, in the LibreLane container
equiv/run_equiv.sh bugs 16
equiv/run_equiv.sh bug 12 "SKEQ skip lands on pc+1"
./_build/default/equiv/miter.exe --sim 20000 ["BUG"]   # the miter in Cyclesim, a smoke test
```

Per-property report (section 6): `./report.sh` (reads the result files, runs nothing).

UART miter (section 7): `uart-miter/run_uart_miter.sh [TASK...]`, after making the project-local
switch as `uart-miter/build_hobby_tx.sh` describes.

Power-up determinism (section 5): `powerup/run_powerup.sh [TASK...]`. It needs the LibreLane
image and the z3 venv above (`Z3ENV`); the container has no `/lib64`, so the script runs the
host's z3 through the host's dynamic loader, mounted read-only.

Kind 2: the v3.0.0 release binary (github.com/kind2-mc/kind2/releases), on `PATH` or in
`KIND2`. `BMC_SMT_LOG=DIR` saves the SMT-LIB of each BMC run, replayable with `z3 FILE`.
