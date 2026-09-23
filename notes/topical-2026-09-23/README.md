# Does a one-unit nudge spread? Operation mixes, saturating against wrapping bytes (2026-09-23)

`sens.py` (run with `uv run --with numpy python sens.py`; output in `sens.txt`) measures how a nudge spreads. The set-up:

- 64 cells, each reading its left neighbour and one random partner;
- each cell computes op(a, b) + k with k in [−8, 8];
- 200 random networks per row, run for 400 steps;
- a +1 nudge to cell 0 at the start.

It measures how far that nudge spreads in the last 50 steps, how many cells are still moving, and how many are stuck at 0 or 255.

- **Saturating max/min:** the difference never exceeds 1 in any network. This is the theorem that monotone, homogeneous ("topical") maps are non-expansive in the sup norm: interfering while the network settles has a bounded, predictable effect.
  - But with random constants only 12 % of cells are still moving at the end, and 27 % are stuck at a rail. Such a network settles and stops unless the host keeps feeding it.
- **Adding sub or add between two cells, with saturation:** a nudge can grow (worst 64 and 255), but it rarely does, because most cells die on the rails.
- **Wrapping bytes:** even with max/min alone, 4 % of cells differ and the worst difference is 128. Wraparound breaks monotonicity. With sub or add as well, the nudge reaches 56 % to 98 % of cells, and it spreads to nearly all of them with sub/add alone. This is the crazy network's regime, and it is why per-line seeding could not steer it.

Conclusion: steer-while-settling needs saturating monotone cells (max, min, adding a constant). Chaos comes back as soon as the operations stop being monotone or the values wrap. The fraction of such cells is a knob between order and chaos. The semiring ring (`prototypes/semiring-ring/`) uses saturation.
