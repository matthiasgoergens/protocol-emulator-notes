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

## Next

- Differential fuzzing against models: the prototypes' lockstep checks become oracles.
- Fuzzing the USB and Ethernet receivers.
- A snapshot-and-restore for speed on large designs.
