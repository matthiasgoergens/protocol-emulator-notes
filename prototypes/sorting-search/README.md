# Sorting on a fixed wiring: a benchmark for program search (2026-09-23)

Parked, after a first round. The question: given a fixed set of links (the "tapeout"), how well can a program be found that makes some links compare-and-exchange in each layer, so that the network sorts? The host may read the outputs in any fixed order. Sorting was picked as a benchmark with published optima, not as a demo.

**Checker.** `failures` in `search.py` requires that all inputs with the same number of ones give the same output, checked exhaustively over every 0/1 input. By the 0-1 principle that means the network sorts. It accepts the textbook bitonic network on the hypercube and rejects it with one comparator flipped (1,016 failures) or removed (1,178). See `controls.py`.

**SAT with counterexample refinement** (`search.py`, CaDiCaL through pysat): solve on a small set of inputs, check exhaustively, add the failing inputs and repeat.

- With every pair wired, it reproduces the known optimal depths: 3 for 4 inputs and 5 for 6 inputs, each with one less proved impossible. For 8 inputs it finds the optimal depth 6, but proving 5 impossible did not finish within 120 s.
- 8 inputs on the hypercube (12 links instead of 28): depth 6, the same as with every pair wired. Depth 5 proved impossible in 140 s.
- 16 inputs on a line: depth 16 found in 512 s, and 15 proved impossible in 122 s. This matches the known result that sorting on a line takes n rounds, even with the output order free.
- 16 inputs on every other wiring: no solution within 600 s per depth. That includes the hypercube at depth 12, where the bitonic network gives 10. The ring, random matchings and ring plus chords all timed out from depths 12 to 20.
- Conclusion: this encoding does not scale to 16 inputs without the symmetry breaking the published optimality proofs rely on.

**Beam search on the set of reachable 0/1 vectors** (`greedy.py`): weak. It got 18 layers on the hypercube (bitonic: 10) and 11 with every pair wired (optimum: 9), and did not finish on the line.

**Maps.** `viz.py` draws the value-against-value comparison map in the style of static-sorting-visualisation. It also checks that rank-adjacent pairs are compared on every input, which any correct sort must do.
