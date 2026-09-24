# hwfuzz: coverage-guided fuzzing for any Hardcaml circuit

`hwfuzz.ml` is a library. `bench.ml` holds the benchmarks.

Give it a function that builds a `Circuit.t`, plus the names of the clock and clear inputs. It instruments the circuit by walking the signal graph. The comparison operands (see input-to-state below) are tapped the same way. Every multiplexer select and every comparison becomes a "decision" probe, and every register a state probe.

Hardware has no instruction pointer. These decisions are the closest thing to branches, which is also why RFUZZ (ICCAD 2018) used multiplexer selects as coverage for RTL.

**Coverage** comes in two kinds:

- Generic, from the circuit alone:
  - 4-grams of each decision signal, bucketed by relative frequency;
  - how often each register changes, and the values of registers up to 8 bits (state machines);
  - how often each output changes, and the period of its last 256 values.
- Application-specific: an optional observer sees the outputs every cycle and returns features.

**Input** is a byte string:

- byte 0 is a swarm mask: listed ports are held at 0 for the whole run;
- then records, each a hold byte followed by values for every data port;
- a hold byte gives 1 to 4 cycles (dense) or a power of two up to 32,768 cycles (sparse).

**Engine** (the Hypothesis ideas are marked):

- AFL-style queue, with a favoured entry per feature: the shortest input covering it;
- havoc stacks of record-aware mutations, including splicing;
- shrinking by halving block deletions (Hypothesis);
- swarm masks (Hypothesis);
- a dictionary and an input-to-state stage built from logged comparison operands (below);
- per-operator use and win counts, so heuristics can be judged by their yield.

The simulator is recreated for every execution, because `Cyclesim.reset` only restores registers that have an asynchronous reset. On small circuits it still runs thousands of executions per second. A snapshot-and-restore would be this tool's version of AFL's fork server.

## Design principle: hardware patience

Hypothesis declines some combinatorial searches, for example correlating edits position by position in `lower_duplicated_characters`, because it has to finish inside a CI run. hwfuzz's users are hardware teams, and as Dan Luu puts it in ["Given that we spend little on testing, how should we test software?"](https://danluu.com/testing/): "It's not unusual for a 'short' hardware test to take minutes, and for a long test to take hours or days." Hardware companies "dedicate thousands of machines to generating and running tests".

So hwfuzz should not inherit CI-sized trade-offs. It should offer two profiles, and the ledger should judge heuristics per profile:
- **quick**, for CI: yield per execution matters;
- **thorough**, for overnight and multi-day runs: what is reached by the end matters. That means exhaustive pairs and triples of logged replacements, deterministic stages, and several islands, possibly across machines.

The campaigns measured here (200,000 executions, about 20 minutes at 4 workers) are small by that standard. The limit on this machine is a shared host, not patience.

## Heuristics ledger

Each entry records what a heuristic was measured on and what it did. Hypothesis and AFL++ grew their heuristics by accumulating exactly this kind of experience.

1. **Buckets by relative frequency, not raw hit counts.** Crazy network, 64 cells: with AFL-style raw counts, 604 of 641 random programs counted as new, because noise differs slightly every run. With relative-frequency buckets, 84 of 641 did. AFL can use raw counts because control flow is sparse; hardware data is dense.

2. **Coverage on what the observer can perceive.** On the crazy network, most kept programs were fine periodic textures that a TV turns into colour noise. Coverage of pixel motifs on 4-pixel symbols helped only partly (see `../crazy-network/README.md`). Whatever the design, the observer's resolution should bound the coverage.

3. **Magic values need comparison logging.** On the combination lock (four strobed key bytes), measured as the deepest state reached, out of 4, on seeds 1 to 5 at 50,000 executions:

   | Version | Deepest state |
   |---|---|
   | Decision and register coverage alone | 1 |
   | + dictionary of logged comparison operands (AFL++'s CmpLog) | 2 |
   | + input-to-state: write the other operand into the record that drove the compared value | 3 |
   | + the "next pulse" variant | opened, all five seeds, after 711–1,387 executions |

   The "next pulse" variant shortens the record to one cycle and inserts a one-cycle record driving the logged value after it. Random inputs never opened the lock in 50,000 executions per seed on three seeds (odds about 1 in 256⁴).

   Operator yield on the lock, wins per use: input-to-state about 1 in 18, the dictionary as a havoc operator about 1 in 2,000.

4. **Held inputs hide one-cycle events.** A value held across several cycles, read by a level-sensitive strobe, advances a state machine and then resets it on the next cycle. Input-to-state on its own then oscillates. The pulse variants in 3 are the generic fix, since strobes and valids are common.

5. **The ladder at 10 seeds** (`sweep.sh`, commit 90c4795, results in `results/`). Each rung is a configuration switch.

   | Target | Configuration | Opened (of 10 seeds) | Median executions to open |
   |---|---|---|---|
   | 4-key lock, 50,000 per seed | random inputs | 0 | – |
   | | coverage only | 0 | – |
   | | + dictionary | 0 | – |
   | | + input-to-state | 0 | – |
   | | + one-cycle pulse | 0 | – |
   | | + next pulse (full) | 10 | 1,504 |
   | 8-key lock, 200,000 per seed | full | 10 | 1,991 |
   | | 4 independent restarts | 10 | 1,994 |
   | | 4 islands with sync | 10 | 1,994 |

   - The next-pulse variant is the whole difference on the lock.
   - Once input-to-state chains, each extra key costs a handful of executions, so twice the keys costs about a third more work.
   - The locks are too easy to separate restarts from islands; the packet benchmark has to answer that.

6. **The first violation tests the oracle.** The first long USB campaign reported a malformed transmission from the unmodified device. Reproduced and minimised to 19 bytes, it turned out to be an oracle bug. The input ended 51 cycles into the device's reply, and the observer judged the cut-off reply. With the reply allowed to finish, it is a correct STALL. An observation cut off by the end of a run must stay unjudged, and a transducer should leave time for the design to answer. Keep the reproducer: `results-usb/violation_usb_0.*`.

7. **Differential fuzzing with ground truth finds real disagreements, and the ranking matters.** Target: the 10BASE-T receiver against the prototype's own model decoder. The transducer sends a known frame through the model's encoder and adds timing faults; the fuzzer drives only the faults. Verdicts:
   - the RTL accepts wrong bytes (a false accept): never seen, in 9 campaigns of 20,000 executions;
   - the RTL drops a frame the model decodes;
   - the model drops a frame the RTL accepts.

   Both drop directions appear within about 1,000 executions, and each reproducer minimises to a single perturbation (`bench ethshow`).
   - **Fixed in the RTL.** A 2-cycle activity dropout mid-frame ended the frame, because one inactive cycle ended it. Now the frame ends after a full bit time of inactivity.
   - **Not fixed: a front-end question.** Other disagreements depend on what the comparator does while the squelch is off.
     - If it reads low: holding the last level fixes four cases and loses one.
     - If it keeps the polarity or has hysteresis: the RTL should not mask in-frame transitions with activity. But that change fails the prototype's own harness, which models a comparator without hysteresis.
     - Each design is robust under one front-end model. Which is right is a property of the board, so the transducer now models the comparator with hysteresis and the question is recorded in `../ethernet-10base-t/README.md`.
   - The lesson for the tool: a transducer's physical assumptions are part of the oracle, and a disagreement can indict them rather than either decoder.

8. **Speed is part of the method.** On the USB device, per-cycle coverage extraction initially made simulation 6 times slower than plain Hardcaml simulation. Three changes brought instrumented simulation from 17,000 to 99,000 cycles per second on one core:
   - reusing a simulator per worker when every register has a clear (checked against rebuilt simulators);
   - reading probes in 62-bit chunks;
   - logging comparison operands only when they change.

9. **How deep byte-level mutation gets into a protocol.** On the USB device (with checksum repair, 200,000 executions, 4 workers, `results-usb/long2.txt`), the milestones first reached were:

   | Milestone | Real device (executions) | Planted fault (executions) |
   |---|---|---|
   | Any response | 2,325 | 2,345 |
   | NAK | 5,247 | 5,318 |
   | ACK | 31,030 | 21,581 |
   | Descriptor data: a full SETUP, DATA0, IN control transfer assembled unaided | 108,773 | 107,751 |
   | SET_ADDRESS | – | – |

   Neither campaign reached SET_ADDRESS, so the planted fault behind it was not found. Without checksum repair, the device never answered at all in 5,000 executions (earlier short runs).

   The gap is sequence structure: SET_ADDRESS needs four packets in order, while mutation works on bytes and fixed-size records. Next experiment: packet-aware splicing and whole-packet dictionary entries, supplied by the target alongside its transducer.

10. **From one example transfer to a bug behind SET_ADDRESS, and the heuristics each step needed.** Target: the USB device with the planted fault (after an address is set, every transmission gets a stray SE0). The corpus was seeded with one GET_DESCRIPTOR control transfer, containing no SET_ADDRESS. Each run was 200,000 executions at 4 workers, seed 1, with packets as units (`results-usb/`, commits in the `*_commit.txt` files).

    | Configuration | SET_CONFIGURATION | SET_ADDRESS | Planted bug |
    |---|---|---|---|
    | Packet mutation + seed | 117,335 | – | – |
    | + multi-replacement, each logged value replaced with probability ½ | 73,984 | – | – |
    | + multi-replacement on 2–3 values per mutant | 8,257 | 26,407 | – |
    | + input-to-state on operands from 4 bits (not 8) | 54,452 | 24,482 | – |
    | + next-unit: append a copy of a unit with a logged operand substituted | 11,062 | 26,971 | **79,848** |

    **Correction (measured later, `bench usbstone`):** the diagnosis first recorded here was wrong. It said a request decodes only when two comparisons match at once, so a single replacement gives no new coverage. In fact each single edit gives new features even under plain coverage, measured against a background of 16 other invalid requests: 17 for bRequest `06` to `05` alone, 8 for bmRequestType `80` to `00` alone. So a stepping stone existed. Why the single-replacement runs stalled is open. With one seed per row, the improvement that coincided with multi-replacement may be luck; the seed sweep in entry 11 is meant to tell.

    Also measured: the token-address comparison is 7 bits wide, so byte-pattern input-to-state did not see it until operands from 4 bits were allowed. And after the address changes, only a *new* IN token can reach the device, which needs an insertion and a substitution together.

    The input the fuzzer built (`violation_usb-faulty-units_0.*`, 25 bytes) is:
    - SETUP to address 0;
    - DATA0 `00 05 08 ff 00 00 40 00`, which is SET_ADDRESS(8);
    - IN, for the status stage;
    - the host's ACK;
    - an IN to address 8.

    It was derived from the seed by changing four setup bytes and appending that last IN. Replayed on the real device it is clean: ACK, the empty DATA1, address 8, then NAK.

    Control: the real device under the full configuration reached SET_ADDRESS at 37,679 executions and ran all 200,000 without a violation (`results-usb/control.txt`).

    Caveat: one seed per row. Multi-replacement is therefore occasional by default (2 mutants per new entry); it is the `multi` configuration (`bench usbfuzz <target> multi ...`), uses 16, as these runs did; the default follows the sweep. The step-by-step ordering is suggestive, not a measured distribution.

## Next

- Seed sweeps for ledger entry 10, and the same heuristics against the lock and packet benchmarks.
- More differential targets: the deadline sequencer against its ISA model, the systolic matcher.
- A snapshot-and-restore for speed on large designs.
