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
| 1 | interpreter generic over values | lockstep and all seven ported suites unchanged; interpreter slower (below) |
| 2a | deadline waits | `main.ml`'s deadline programme: no violation to 160 clocks, with the other three threads unconstrained; planted bug found at clock 89 |
| 2a | every WAITD of UART + SPI + I2C | 15 contracts, 720 clocks; **found a latent SPI compiler bug** (Findings) |
| 2b | pin ownership | four programmes, 720 clocks; planted bug found at clock 95 |
| 2c | isolation (2-copy miter) | BMC: planted bug found at clock 28; induction: holds at **every depth** for the UART |
| 2d | UART frame, every byte | 2 frames (440 clocks); planted bug found at clock 98 (byte 0x04) |
| 3 | Kind 2 (k-induction, IC3) | deadline property **proved for all depths** in 0.2 s; UART times out at 15 min |
| 4 | RTL against specification (Yosys) | equal for 23 clocks after reset, for every instruction stream and input; **28 of 28** planted RTL bugs found |

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

The cost is speed. Without flambda, every value operation is an indirect call through the
functor, and every opcode's result is computed on every clock. Measured on this machine:
- lockstep: 2 min 02 s before, 2 min 23 s after (the RTL simulation dominates);
- bridge A, mostly interpreter: 9 s before, 26 s after (an A/B run of both builds).

`perf` puts `caml_apply2`/`caml_apply3` and the value operations at the top. Not tried: an
flambda switch, or a lazy `ite` for the per-opcode groups.

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
- The clean isolation miter ran to 36 clocks only (cumulative solver time 22 s at 24 clocks,
  329 s at 32, 919 s at 36); its two cover queries were stopped unanswered after 22 minutes.
  The non-vacuity of the unconstrained threads is shown instead by the planted run, where one
  of them does reach pin 0 through the bank. The induction step is the real result.
- The isolation result is for one protocol (the UART). Any protocol that reads the inbox, the
  bank or a port is not isolated by construction, and the induction step says so.

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

## Findings

1. **Latent bug in the SPI compiler** (`../deadline-sequencer/compiler.ml`, not fixed here).
   `spi_master` asserts `period >= 8`, and the README says "any even period of at least eight
   slots". At 8 it computes `a = P - 8 - (P/2 - 3) = -1` and emits `LDD 4095`. A simulation on the
   base interpreter measures SCLK edges 16,416 clocks apart instead of 32; period 10 gives the
   expected 40. The shortest valid period is 10. This was found by a cover (two WAITD of the
   SPI thread never finish within 720 clocks), not by a property violation.
2. The isolation counterexample is a design point, not just a test. Pins have an ownership
   discipline; the data bank, the inboxes and the ports have none. A protocol thread that reads
   any of them can be disturbed by another thread. Bank and inbox ownership need the same
   treatment as pins; `props.ml`'s ownership monitor could be extended to them the same way.
3. The bounded equivalence finds all 28 planted RTL bugs at 15 clocks. That includes three that
   uniform random simulation of the same miter misses in 20,000 clocks; the lockstep needed a
   biased generator for those.

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
- Tools: z3 (MIT, from the `z3-solver` wheel), Kind 2 (Apache-2.0), Yosys (ISC, in the
  LibreLane image), Hardcaml.

## Running it

```
opam exec --switch=5.3.0 -- dune build          # main.exe and equiv/miter.exe
# z3 without root or a shared environment:
uv venv /var/tmp/symbolic-bmc/z3env && uv pip install --python /var/tmp/symbolic-bmc/z3env/bin/python z3-solver
export PATH=/var/tmp/symbolic-bmc/z3env/bin:$PATH
./_build/default/main.exe a a-planted      # one or more scenarios; no argument: all
./run_all.sh bmc | kind2                   # regenerates results/bmc.txt, results/kind2.txt
equiv/run_equiv.sh clean 8 16 24           # Yosys, in the LibreLane container
equiv/run_equiv.sh bugs 16
equiv/run_equiv.sh bug 12 "SKEQ skip lands on pc+1"
./_build/default/equiv/miter.exe --sim 20000 ["BUG"]   # the miter in Cyclesim, a smoke test
```

Kind 2: the v3.0.0 release binary (github.com/kind2-mc/kind2/releases), on `PATH` or in
`KIND2`. `BMC_SMT_LOG=DIR` saves the SMT-LIB of each BMC run, replayable with `z3 FILE`.
