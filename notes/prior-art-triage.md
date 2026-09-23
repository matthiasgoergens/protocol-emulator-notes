# Triage of the five prior-art surveys (2026-09-23)

This note covers five surveys:

- `prior-art-systolic-programming.md`
- `prior-art-looped-arrays.md`
- `prior-art-graphics-hardware.md`
- `prior-art-racing-the-beam.md`
- `prior-art-programming-chaotic-networks.md`

It sorts their contents into three groups: what we have been reinventing, what is worth borrowing, and what to build first. Citations are in the surveys themselves. Everything in them is reported, not measured, except the two chaotic-network experiments at the end of the last survey.

## What we have been reinventing

These already have names, and in several cases a theory that tells us what will happen before we build anything.

| Ours | Prior art | What the prior art adds |
|---|---|---|
| One packet per scanline configures generators | Amiga Copper, VIC-II raster interrupts, Atari TIA; closest overall is Gharachorloo & Pottle's Super Buffer (one line of cells, fed pre-sorted per-line data, no frame buffer) | Firmware tricks for free: sprite multiplexing, stretching, parallax, Kefrens bars, vector balls |
| Wave ring sharing one sine table | CAM-6 (one small shared lookup table visited by many cells); demo-scene plasma | Confirmation, not new mechanism |
| Running scan `x[i] = max(seed[i], x[i-1] - d)` (sketched in discussion, not built) | Forward pass of the Rosenfeld–Pfaltz / Borgefors chamfer distance transform | The reverse pass, and weights that approximate Euclidean distance |
| 16 cells × 10 passes | DSP *folding* (Parhi); the cell × pass index space is a Karp–Miller–Winograd uniform recurrence; AutoSA's split into space loops and time loops | A legality condition for schedules, checkable statically |
| Max-plus iteration to the Kleene star | Closed semirings: Carré, Gondran & Minoux, Aho–Hopcroft–Ullman; Mohri 2002 is the readable synthesis | One algorithm for min-plus, max-plus and Boolean closure |
| Many passes of a looped ring | Cuninghame-Green: powers of an irreducible max-plus matrix become eventually periodic, at a rate set by the max-plus eigenvalue | Predicts growth, decay or steady state, and the pass count needed to converge, from the wiring |
| Deep effect from a small repeated operator | Sternberg's Cytocomputer: a frame-buffer-free pipeline of identical morphology stages, where a big structuring element is a composition of small ones | Recipe: a big glow radius is N passes of a 3-tap operator |
| Per-pixel "loop again" bit | **No canonical ancestor found** by either survey; nearest are wavefront arrays and valid bits in dataflow machines | Possibly genuinely ours |

## What is worth borrowing

**The main observation.** Most of the good borrowings are the same cell: a register that is updated by `+`, `max` or `min` of its own value and an input from its left neighbour or a constant, with its sign or a comparison as the output.

- Forward differencing (Bresenham, Pixel-Planes 5) is a chain of adders. Degree n takes n adders, so a quadratic gives circles and ellipses, and a cubic gives wiggles.
- Pixel-Planes' half-plane tests are the sign bit of a degree-1 chain. AND and OR of several such signs give wedges, polygons and discs.
- Chamfer distance, max-plus glow and morphological dilation are the same chain with `max` or `min`, looped.
- Perlin-style lattice texture is an accumulator whose step is reloaded at lattice boundaries.

So the "plain systolic array, possibly looped" from the 23 September plan has an obvious cell. It is **one tropical-or-ordinary adder per cell, with {+, max, min} selected per cell by the host**. Each choice of operation comes with a known theory: finite differences for `+`, and max-plus and min-plus spectral theory for the other two. That gives us a way to program the array, which is exactly what the chaotic network lacked.

Other borrowings, grouped by cost:

- **Firmware only.** These need no hardware change and run on the existing console:
  - vector balls (the survey's closest one-to-one match);
  - flicker multiplexing past 16 objects;
  - sprite-row stretching for rubber logos;
  - band parallax.
- **Small extensions to the sprite cell:**
  - span or run cells (start-x, end-x, colour) in the Super Buffer style, which draw filled bars in one pass;
  - TIA-style horizontal replication (a repeat count and a pitch).
- **Texture instead of a fixed combining rule:** index a small host-loaded table with the high bits of the accumulators.
  - On a perspective floor the texture row is constant along a line, so the packet can carry it: 16 entries of 4 bits is 8 bytes per line, and needs no on-chip table.
  - Rotation needs a real 2-D table. Its area has to be measured, as flip-flops against an IHP SRAM macro, before we commit to it.
- **Compiler:**
  - Warp/W2's two-phase structure: first decide which cell does what on which pass, then schedule within each cell.
  - The folding legality condition as a static check.
  - Karp–Miller–Winograd dependence vectors, to decide whether the conditional back link is a small set of static schedules selected by a one- or two-bit tag.

## Chaotic networks: what the two measurements say

Both control ideas we measured failed, and for the same reason:

- the lambda-style pre-filter;
- Pyragas delayed feedback, which had no effect at any gain.

The CPU can only act once per line, which is 340 to 3,405 network steps, far beyond the instability horizon. Any further chaos-control idea, including the survey's top-ranked "control kernel" search by pinning cells, needs a hardware path that acts every few steps. A per-cell pin mask would be such a path. This supports keeping the network parked, and it names what would have to change to reopen it.

## What to build first

1. **A semiring-cell ring model.** Sixteen cells, each `r <- op(r, in)` with op in {+, max, min} and in from {left neighbour, constant}, a sign output, and an optional loop-back.
   - Show three programs on the same hardware:
     - a filled ellipse from second differences;
     - a glow halo around sprites using max-plus with decay, checking the pass count against the eigenvalue prediction;
     - a cubic wiggle.
   - Judge them through the TV decoder, and synthesise to compare area with the console background.
   - This one experiment covers the top items from the graphics-hardware survey (1, 2) and the looped-arrays survey (1, 2, 3, 4).
2. **Packet-carried texture row** for perspective floors. It is cheap, and it settles how much detail survives the roughly 1.3 MHz colour bandwidth.
3. **Dependence-vector write-up for the looped schedules**, once item 1 exists. It decides whether the compiler faces enumeration or real search.
4. **Firmware demos on the existing console** (vector balls, parallax). Nearly free, but they exercise nothing new, so they come last.
