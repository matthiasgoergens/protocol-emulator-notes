# Verifier: static proof that a sequencer programme meets its edge deadlines and periods

An abstract-interpretation verifier for ISA v2 programmes (`../sequencer-v2/isa2.ml`). Given a
thread's 256-word page and a specification of its pins' timing, it either proves that every
execution, for every input, makes exactly the declared events with every gap inside its declared
interval and never misses a deadline, or rejects the programme with the offending event and the
path from pc 0 that reaches it. It also writes a per-image timing certificate (the predicted
slot of every pin write) and a ledger of image hashes.

Results are in `results/`, each file headed by its command, commit and date; `./run_all.sh`
regenerates them (niced, waiting while the load is above 20). Everything was run on 2026-10-05.

| check | what | result |
|---|---|---|
| sweep | every programme the compiler emits in the sweep's parameter ranges (UART, SPI, I2C, UART from the host), plus the formal suite's deadline and watchdog programmes | **530 of 530 proved** |
| interpreter cross-check | each image run on `Isa2.Spec`; every measured state and event must lie in the certificate | 9,299 runs, 2,674,218 instruction entries and 441,297 channel events measured: **none outside the certificate**, no proved image with a failing run |
| planted | 11 planted bugs, including SPI at period 8 (LDD wraps to 4095) and I2C without WAITP | **11 of 11 rejected**, each with a path |
| mutants | every single-word mutant of five programmes, judged against interpreter runs | 1,220 mutants: 275 rejected with a failing run, 943 proved with every run meeting the specification, **0 proved with a failing run**, 2 rejected with no failing run (both genuine, section 5) |
| precision | correct programmes rejected | **0** of 1,045 correct programmes (530 sweep, 514 deterministic mutants, the balanced branch); 1 before the relational `due` (the balanced branch) |
| random | random programmes against `Isa2.Spec` with random inputs | 3,000 programmes, 9,000 runs, 22,676,780 instruction entries: **0 outside the certificate** |
| controls | perturbed certificates and specifications the kernel must reject | **1,898 of 1,898 rejected** |
| kernel bugs | planted bugs in the kernel that some check must catch | **10 of 10 caught** |
| compose | demo composition (UART, SPI, I2C, watchdog on four threads) and pin ownership | proved; planted pin clash rejected |
| certificates | per-image certificates, ledger with SHA-256 of image and certificate | 530 images; `ledger-check` finds a matching certificate for every one |

## 1. What it proves

**Specification.** A specification names a *channel* (a set of pins one thread owns) and an
automaton over *events* on it (`spec.ml`). An event is one instruction doing something to channel
pins in one slot: a write (SETP, or SHO with its data), with the level each pin is left at; a
WAITP on a channel pin that proceeds (an observation) or times out (an expiry); a SHI sample.
Each transition names the event it accepts and the interval its *gap* (slots since the previous
channel event) must lie in. A state without transitions is final; in any other state the next
event must come within the largest upper bound of its transitions, its *deadline*. So one
automaton states periods (gap = P), deadlines (gap at most D), input-bounded waits (gap in
[1, D]) and the order of events.

**Claim.** For an image accepted by `check` (kernel.ml): in every execution of `Isa2.Spec` from
reset, under assumptions A1 to A5 below, every channel event the thread makes is one its
specification's current state accepts, with its gap inside the declared interval, and the thread
never spends more slots without a channel event than its current state's deadline. Slot s of
thread t is clock 4s + t, so a gap of g slots is 4g clocks.

**Assumptions** (also in kernel.ml's header):
- **A1, inputs.** Anything read from outside (pins, host, inboxes, ports, flags, the data bank)
  may take any value on any slot. **WAITP, WAITC and MBX are waits of input-dependent length,
  bounded by the deadline register:** with dl = d on their first issue they may proceed on any
  of the slots 0..d of the wait, or time out after slot d and jump to their fail target. IN has
  no bound. This is how I2C clock stretching is modelled: the slave may hold SCL for any time,
  and the programme must cope both with SCL seen high within its limit and with the timeout.
- **A2, host.** The host does not move the thread's pc through its control port.
- **A3, page.** The thread runs from pc 0 of a fixed 256-word page, which wraps as in Isa2.
- **A4, time.** Whole slots. The quarter-clock sub-slot q of SETP and SHO is printed in the
  certificate; FINE offsets are not bounded.
- **A5, output enables.** The enables are 0 at reset, and those of the thread's pins change only
  by its own writes. `compose` checks that no other thread's reachable code writes a channel's
  pins.

## 2. How (and what was adopted from whom)

The design follows **MarcosAsh's** verifier for his own ISA (github.com/MarcosAsh/protocol-emulator,
`src/analyser.ml` and `src/kernel.ml`, Apache-2.0, read at commit 3333f0c): an untrusted analyser
finds an invariant table by a worklist fixpoint with joins and widening; a small trusted kernel
re-checks the table one instruction at a time. His kernel is a circuit proved against his RTL by
SAT; ours is OCaml, checked against the interpreter (below). Ideas taken: the analyser/kernel
split; intervals with open ends and widening after a number of passes; a time-since-last-edge
quantity per row and the "gap" from each predecessor; the deadline kept as a point in time (his
phase `now - t`), which is our `due` beside the count-down register; reporting each missing
bound with what it rests on. Code taken: `interval.ml` is adapted from his `src/interval.ml`
(SPDX header and changes in the file; listed in `../../NOTICE`). Everything else is new code
for a different ISA.

**Domain** (kernel.ml). At the first issue of each instruction:
- a *key*, kept exactly: pc, the specification's state, cnt and acc (each a value or unknown),
  and the output enables;
- a *value*, as intervals: dl, since (slots since the last channel event), time (since the
  start), and due = since + dl.

Keeping cnt, acc and the specification state in the key unrolls counted loops (LDC 8 ... JNZ)
and separates the same pc at different points of a frame; the analyser falls back to unknown
cnt and acc after 512 keys at one (pc, state). Each instruction is one abstract step: a WAITD
with dl = d takes d + 1 slots; a WAITP proceeds after 1..d+1 slots or times out after exactly
d + 1 (A1); the two bounds on the next instruction's since (the plain sum, and `due + 1` for a
wait that runs to its deadline) are met.

**Kernel** (`Kernel.check`): the certificate is accepted when it contains the start state, is
closed under the abstract step, every event is accepted with its gap inside the declared
interval, and no entry's since exceeds its state's deadline. The trusted base is `kernel.ml`,
`spec.ml`, `interval.ml` and the specifications in `programmes.ml`; `analyser.ml` is not
trusted.

**Rejections** print the violation, the declared interval, and the abstract path from pc 0
(through the analyser's first-visit tree), e.g. for SPI at period 8:

```
PLANTED spi_p8 (LDD a wraps to 4095)         REJECTED  entries    71  events    28
    pc 8: 4098 slots may pass without an event in state byte 0 bit 1 mosi, whose deadline is 2
    path (9 instructions from pc 0):
        0  setp mask=06 val=0 oe=1 q=0  state start                              dl=0 since=0 due=0 time=0
        1  setp mask=08 val=1 oe=1 q=0  state sclk and mosi low                  dl=0 since=1 due=1 time=1
        2  lda 0xa5                     state cs idle                            dl=0 since=1 due=1 time=2
        3  setp mask=08 val=0 oe=1 q=0  state cs idle                            dl=0 since=2 due=2 time=3
        4  ldc 8                        state byte 0 cs asserted                 dl=0 since=1 due=1 time=4
        5  sho pin2 msb q=0             state byte 0 cs asserted                 dl=0 since=2 due=2 time=5
        6  ldd 4095                     state byte 0 bit 1 mosi                  dl=0 since=1 due=1 time=6
        7  waitd                        state byte 0 bit 1 mosi                  dl=4095 since=2 due=4097 time=7
        8  setp mask=02 val=1 oe=1 q=0  state byte 0 bit 1 mosi                  dl=0 since=4098 due=4098 time=4103
    pc 8: event p1:set=1 (byte 0 bit 1 sclk rise) has gap 4098 slots, declared 2
```

**Certificates** (TeslaCoilerOW's idea, github.com/TeslaCoilerOW/ttihp-protocol-emulator,
`docs/timing-certificates.md`): per image, the SHA-256 of its 256 words, the verdict, and one
line per pin event with its pc, instruction, specification transition, slot interval, gap and
declared gap. `results/ledger.txt` lists every sweep image's SHA-256 with its certificate's
SHA-256; `main.exe ledger-check results/ledger.txt` recomputes them and fails when an image has
no matching certificate. Five certificates are committed in `results/certs/`. Unlike
TeslaCoilerOW's, our certificates are **not proved on the RTL**: they are tied to the
interpreter by the cross-check, and the interpreter to the RTL by `../sequencer-v2`'s lockstep
test.

## 3. Specifications

Written in `programmes.ml` from the timing the compiler's comments document
(`../deadline-sequencer/compiler.ml`), as closed forms in the parameters, not from the emitted
words:
- **UART** (bit time B): start, 8 data bits and stop exactly B apart; idle level within B of the
  start; with `stretch = (k, d)` data bit k is B + d. From the host: a start bit any time after
  the idle level or a full stop bit.
- **SPI** (period P): SCLK high P/2 and low P/2, MOSI changes 2 slots after each fall, CS 2
  slots from its neighbours.
- **I2C** (quarter q, stretch limit L): each SCL release followed by SCL seen high within
  [1, L] slots or a timeout at exactly L, after which both lines are released one slot later;
  the high phase timed from the observation (2q - 1 to the fall; ack sample q - 1, fall q after
  it); STOP's release 2q - 1 after SDA falls.
- **Deadline programme** and **watchdog** (`../formal/programmes.ml`): the report pin within
  [2, ldd + 2] slots, or the timeout pin at exactly ldd + 2, one slot after the wait.

Writing the SPI specification from the source found one discrepancy: `spi_master` lists "cs
high" before "sclk and mosi low", but its item list is reversed as a whole, so the image sets
SCLK and MOSI first. Harmless (CS is high from reset either way, being released), but the
comment-level reading was wrong; the specification follows the image and says why.

## 4. Soundness evidence

Three kinds, each measured, none a proof (section 7):

**Interpreter cross-check** (`sim.ml`). Each image runs on `Isa2.Spec`, the semantics every other
test uses, at its thread's page with the other threads halted. At every first issue of an
instruction the measured (pc, specification state, cnt, acc, enables, dl, since, due, time) must
lie in a certificate entry, and every measured event must match an outcome of the kernel's step
from that entry with its measured gap and slot inside the predicted intervals. Environments:
pull-ups (UART, SPI: deterministic, one run is the whole truth); an I2C slave that stretches SCL
at random, never, by at most one slot, and, for stretch limits up to 16 slots, *targeted* runs
that stretch each release in turn by every whole number of slots up to the limit and past it;
random inputs on every clock (deadline programme, watchdog, UART from the host). The sweep:
`results/sweep.txt`.

**Mutants** (`results/mutants.txt`). Every single-word mutant (word to NOP, immediate and target
plus and minus one, swap with the next word, one random word) of a UART, an SPI, an I2C with a
7-slot stretch limit, the deadline programme and the watchdog: 1,220 programmes. Each is
verified and run. No mutant was proved while a run failed its specification, and no measured
state of any mutant left its certificate (up to the first event the specification does not
accept, where the analysis stops too).

**Random programmes** (`results/random.txt`): 3,000 random programmes of 4 to 43 words over all sixteen opcodes
(addresses kept mostly inside the programme, immediates mostly small so loops end), each with
the trivial specification (no channel), run three times on `Isa2.Spec` with random pins, host,
ports and flags on every clock (one run in four with the pins held low, so waits time out):
22,676,780 measured instruction entries, none outside the certificate. This checks the kernel's
step for every opcode against the interpreter, independently of any specification.

The checks found two kernel bugs while this was being built, both fixed: a push-pull SHO was
taken to drive its pin whatever the pin's output enable (found by the mutants' cross-check; the
key now keeps the enables, A5), and an open upper bound on `due` became `max_int` and overflowed
(found by the random programmes).

**Planted bugs** (`results/planted.txt`), each rejected, with the interpreter's verdict:

| planted bug | rejected because | interpreter |
|---|---|---|
| SPI at period 8: LDD a wraps to 4095 (`formal/README.md`, Findings 1) | 4098 slots without an event, deadline 2; SCLK rise gap 4098, declared 2 | fails |
| I2C with every WAITP removed (stretch-blind; same timing without stretching) | SCL low after a release with no observation of SCL high | fails |
| I2C, the ack's WAITP removed | ack sampled with no observation of SCL high | fails |
| I2C, the stretch limit's LDD removed before a release | timeout possible 1 slot after the release, declared 4095 | fails |
| I2C, a WAITP's timeout target is the next word | after a timeout, 2 slots without the release, deadline 1 | no run reaches it (needs a 4095-slot stretch) |
| UART, a data bit's LDD one short | data bit gap 15, declared 16 | fails |
| UART, HALT in place of the second stop bit | stop bit never comes | fails |
| UART, LDC 7 | stop bit where data bit 8 is declared | fails |
| SPI, CS released inside the bit loop | CS event where MOSI is declared | fails |
| deadline programme, LDD 30 against a declared 20 | observation gap 2..32, declared 2..22; timeout gap 32 | no run reaches it (random inputs see pin 1 high early) |
| UART, LDA replaced by IN | unbounded wait where the next start bit is due | fails |

Plus pin ownership (`results/compose.txt`): a watchdog whose timeout writes pin 0 (the UART's)
is rejected in the demo composition.

## 5. Precision

Precision here means: how often is a correct programme rejected?

- **Sweep:** 0 of 530 compiled programmes rejected; every interpreter run of each meets its
  specification.
- **Mutants:** of the 514 mutants that are deterministic (every reachable instruction has one
  outcome taking a known number of slots, so one interpreter run is the whole truth) and meet
  their specification, 0 rejected. Two non-deterministic mutants are rejected with no failing
  run; both are real violations under A1 that the runs' inputs did not make: a SEND to inbox 0
  that would time out (to a fail target past the programme) if another thread had filled the
  inbox, and a WAITP on pin 7 that would time out if the pin read low. With only random
  stretching, 79 mutants were in this class (the runs rarely got past the first byte's
  timeouts); adding runs without stretching and the targeted runs turned 77 of them into failing
  runs.
- **Hand-written, hard for the analysis** (`results/precision.txt`): a data-dependent branch
  whose two arms load different counts at different times for the same deadline. Every run
  meets its exact 11-slot gap. The analysis without `due` rejected it (gap 10..12); with `due`
  it is proved.

Known sources of imprecision, none reached by the compiler's output: an event between the join
of two such arms and their WAITD (after an event `due` restarts from dl alone); data-dependent
branches on an unknown accumulator whose arms make different events; more than 512 keys at one
(pc, state), after which cnt and acc become unknown; widening after four visits of a key.

## 6. "Accepts everything" detection

A verifier that accepts everything passes every test of correct programmes. Each of these fails
if that happens:
- `selftest` (run first by `run_all.sh`): every planted bug must be rejected, a correct UART
  proved, and a programme that never touches its channel rejected (no event checked is a
  rejection, never a vacuous proof).
- `planted`, `mutants`: the rejection counts are reported, and a mutant the interpreter shows
  failing must be rejected.
- `controls`: perturbed certificates (an entry removed, since/time/dl/due moved by a slot) and
  perturbed specifications (each exact declared gap moved by one slot) must be rejected by the
  kernel; this is what catches a kernel whose closure or gap check has gone missing.
- `kernel-bugs`: ten bugs planted in the kernel, each of which must make some check fail.

## 7. Open soundness gaps

- **The kernel is not proved.** Its step is checked against `Isa2.Spec` by runs (random
  programmes, mutants, the sweep), not by proof; MarcosAsh's kernel is proved against his RTL by
  SAT. A transfer bug on an instruction or input pattern the runs never make would go unseen.
  The ten planted kernel bugs show the runs catch bugs of the kinds planted, not all.
- **The specifications are trusted.** They are written from the compiler's comments; a
  specification that declares the wrong gap proves the wrong thing. Data levels are not
  checked: a data event accepts any level, so the verifier proves when bits change, not which.
- **Events are writes, not edges.** A write that leaves the level unchanged counts as an event;
  the claim is that pins change only at declared events, at declared times.
- **No link to the RTL.** Certificates are not proved on the RTL (TeslaCoilerOW proves his per
  segment); the interpreter is tied to the RTL by `../sequencer-v2`'s lockstep test only.
- **Assumptions.** A2 (host control), A3 (fixed page), A4 (sub-slot q and FINE) and A5
  (enables) are not checked by the kernel; `compose` checks the part of A5 about other threads'
  writes, using the same analysis. Inter-thread mailbox protocols are treated as arbitrary
  inputs (A1), so a thread that waits on another is only bounded by its own deadline register.
- **The cross-check's own logic** (when an issue is the first of an instruction, how a WAITP's
  outcome is read off the run) is a second implementation of parts of the ISA, in `sim.ml`.
- **Base ISA.** The verifier analyses the compiler's output after `../sequencer-v2/compat.ml`'s
  translation to ISA v2, not the base ISA on the original core.
- **Codex review** (gpt-6-luna, once, read-only): reported one soundness gap, that SHO with
  capture keeps a known accumulator. Refuted by measurement: `main.exe step 7910 0` shows the
  accumulator becomes unknown (`kernel.ml`, `if cap then Any`). It found no other gap in the
  opcode cases, the `due` rules or the deadline check, at medium confidence by its own account.

## Files

`kernel.ml` (trusted step and check), `analyser.ml` (fixpoint), `spec.ml` (specifications),
`interval.ml` (intervals, adapted from MarcosAsh), `programmes.ml` (images, specifications,
planted bugs, precision cases), `sim.ml` (interpreter cross-check), `sha256.ml`, `main.ml`
(commands), `run_all.sh`. `isa2.ml`, `compat.ml`, `isa.ml` and `compiler.ml` are links to the
prototypes' own files.
