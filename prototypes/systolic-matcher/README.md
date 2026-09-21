# Systolic pattern correlator: a prototype

A systolic computation for the protocol emulator: sixteen identical cells
in a line, each holding a template bit and a mask bit, correlating an
incoming bit stream against the template and raising a hit when the number
of matching positions reaches a programmable threshold. Sync-word and
preamble detection, majority-vote start-bit validation, Manchester
template decoding and logic-analyser triggering are all this computation.

Why systolic here: the measurements in `measurements/` showed that
configuration latches and switch matrices are where an eFPGA's area goes
and that long paths through them are where its timing goes. A systolic
array has neither. Every cell talks only to its neighbours, the
"programme" is two bits per cell plus a threshold, loaded through a
serial chain, and the schedule is fixed by the geometry, so timing is
exact by construction, which is the property the whole chip is meant to
have.

## Design

Weights-stationary form: samples move right one cell every two clocks
(two registers per cell), partial sums move right one cell per clock, so
each sum sweeps across the stored template. With `xa_i(n) = x(n-1-2i)` and
`y_i(n) = y_{i-1}(n-1) + m_i [xa_i(n-1) = t_i]`, the last cell's sum is

    y(n) = sum_j m_j [x(n - N - 1 - j) = t_j]

a correlation with latency N+1 and template bit 0 aligned with the newest
sample. `hit(n) = [y(n-1) >= threshold]`. This closed form is the
specification in `model.ml`, derived on paper, and the RTL in `matcher.ml`
is checked against it cycle by cycle.

## Results

- Lockstep: 300 random configurations, 500 random samples each, zero
  mismatches between RTL and closed form (`main.ml`).
- Directed: a planted 16-bit word is found exactly where the formula says,
  twice in 3000 random samples; with two corrupted bits it is still found
  at threshold 14. My first hand-computed expectation for the hit index
  was off by one; the model and the RTL agreed with each other and were
  right, the expectation was fixed.
- The first model version assumed the sum pipeline had run on zeros since
  forever; a reset leaves the partial-sum registers at zero instead, so
  terms that would have entered before time 0 are absent. The lockstep
  caught it on the first cycles.
- Area (Yosys, area-mode abc, sg13g2 typical liberty, flattened): 458
  cells, 10,015 um2, of which 139 flip-flops are 6,810 um2. Per cell about
  630 um2; the configuration is 32 bits plus a 5-bit threshold.
- Place and route (LibreLane 3.0.14 in its container, IHP sg13g2, 5 ns
  clock, 45 % target utilisation, `librelane.json`, metrics and flow log in
  `pnr-metrics/sys5ns_u45/`): die 31,488 um2, final utilisation 71 %,
  zero routing violations, setup slack +2.7 / +2.2 / +0.9 ns at the fast /
  typical / slow corners, hold slack positive everywhere. The array closes
  200 MHz at the slow corner, three times the competition clock. A first
  attempt at 65 % target failed in detailed placement because the resizer
  inserted 241 hold buffers on the short register-to-register paths after
  clock-tree synthesis and they did not fit; that is the one cost of an
  all-register design and it is why the floorplan needs slack.

Build and run: `opam exec --switch=5.3.0 -- dune build && dune exec ./main.exe`
(Hardcaml v0.17).

## Notes

The threshold compare is the only non-local path, one 5-bit compare at
the end. A wider template, several templates in parallel, or a
two-dimensional array for two-wire protocols would all keep the same
per-cell cost. The array as built does not decode; it flags. Feeding the
hit into the deadline sequencer's wait instruction as a pin is the
intended composition.
