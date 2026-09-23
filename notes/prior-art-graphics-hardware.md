# Prior art: historical graphics hardware for a beam-racing PAL chip

Context: a Tiny Tapeout ASIC (IHP 130 nm, ~0.7 mm2) generating PAL composite
video by racing the beam — no frame buffer, 256x240 pixels, 10 clocks/pixel
at 53.2 MHz. An RP2040 sends a ~50-70 byte packet per scanline. Existing
blocks: a 16-cell systolic sprite pipeline, a rotozoomer background from two
16-bit phase accumulators (per-line start, per-pixel step, XORed), and a
wave engine summing up to ten plane waves via a rotating ring with one sine
table and one adder. No multipliers. Composite colour bandwidth is
~1.3 MHz, so coarse shapes and smooth gradients read better than fine
detail. A host PC can precompute anything offline.

Each item below: what the idea is, how it maps onto our blocks, and a
citation with an open-access link where one exists.

## 1. Pixel-Planes: linear expression evaluator, Ax+By+C per pixel

Pixel-Planes (1981-85) gave every pixel of a small processor array a one-bit
adder; loading coefficients A, B, C and running the adder tree evaluates
Ax+By+C at every pixel in parallel — a half-plane edge test, the core
primitive for polygon fill without any per-pixel multiply. Fuchs, Poulton,
Eyles et al., "Fast spheres, shadows, textures, transparencies, and image
enhancements in pixel-planes," ACM SIGGRAPH Computer Graphics 19(3), 1985,
DOI: 10.1145/325165.325205. Follow-on architecture (open PDF):
https://techreports.cs.unc.edu/papers/88-014.pdf.

*Use:* our two phase accumulators already compute linear functions of
screen position incrementally, XORed for the rotozoomer. Running three or
four such accumulators per line and combining with AND/OR instead of XOR
gives filled half-planes and wedges directly — no multiplier, since A and B
arrive as the per-pixel step from the CPU. Cost: one comparator per extra
accumulator.

## 2. Pixel-Planes 4/5: quadratic expressions for circles and spheres

Pixel-Planes 5 evaluated Ax²+Bxy+Cy²+Dx+Ey+F per pixel — the implicit form
of a circle or sphere — incrementally, with the increments precomputed
off-chip. Fuchs, Poulton, Eyles, Greer et al., "Pixel-Planes 5," SIGGRAPH
1989, DOI: 10.1145/74333.74341. Open short-version PDF:
https://faculty.cc.gatech.edu/~turk/my_papers/pxpl5_short.pdf.

*Use:* a quadratic's second difference is constant, so it needs only two
chained adders (value Q, first-difference D, constant second-difference):
each pixel does Q += D, D += const, and Q's sign is a circle/ellipse
boundary test. Rounder than the XOR checkerboard, and composable as a mask
ANDed with the existing background. Host computes D and the constant from
the desired centre/radius.

## 3. Jim Clark's Geometry Engine: a fixed pipeline of identical stages

The Geometry Engine (1981-82) was one VLSI stage of the transform/clip
pipeline (a 4-component float vector unit); chaining identical chips built
the whole pipeline, each doing one fixed operation on a vertex stream.
Clark, "The Geometry Engine," SIGGRAPH 1982 / ACM SIGGRAPH Computer
Graphics 16(3), DOI: 10.1145/965145.801272. Open PDF:
https://graphics.stanford.edu/courses/cs148-10-summer/docs/1982--clark--geometry_engine.pdf.

*Use:* this is architecturally what the 16-cell systolic sprite pipeline
already is. The transferable discipline: keep every cell doing the *same*
small operation regardless of the data flowing through it, letting the
per-line packet carry per-cell parameters rather than per-cell code paths.
Worth auditing whether any cell currently branches on sprite/mode and could
be made uniform instead.

## 4. Forward differencing for polynomials and conics

Bresenham's trick — track an integer error term, update it by a small
increment, avoid division and multiplication — generalises: an n-th degree
polynomial's n-th finite difference is constant, so it evaluates along a
scanline with n adders and no multiplies. Bresenham, "Algorithm for
computer control of a digital plotter," IBM Systems Journal 4(1):25-30,
1965, DOI: 10.1147/sj.41.0025. Open copy:
https://ohiostate.pressbooks.pub/app/uploads/sites/45/2017/09/bresenham.pdf.
The midpoint circle/conics extension is surveyed in van Aken & Novak,
"Curve-drawing algorithms for raster displays," ACM TOG 4(2), 1985, DOI:
10.1145/357337.357341 — no open copy found; flagged as likely paywalled.

*Use:* the general mechanism behind #2 — chain one more adder (third
difference) to get a cubic wiggle instead of just a parabola, for
negligible extra gates. Could run as a second "phase engine" alongside the
rotozoomer, feeding the background or a sprite-cell offset (e.g. a
parabolic bounce trajectory).

## 5. Watkins' scanline algorithm and hardware span buffers

Watkins' 1970 thesis reformulated visibility as an ordered scanline sweep
over coherent x-intervals ("spans") rather than per-pixel polygon tests;
Evans & Sutherland built hardware from it, the Shaded Picture System
(1973). Watkins, "A Real-Time Visible Surface Algorithm," PhD thesis,
University of Utah, UTEC-CSc-70-101, June 1970. Open, full scan:
https://archive.org/details/utech-csc-70-101_watkins_dissertation_jun70.

*Use:* our per-line packet is already span-buffer-shaped. Extending it to
carry a short list of (start-x, end-x, layer-id) spans, rather than only
accumulator seeds, gives a cheap span-based background mode — solid bars,
horizon lines, sprite-masking regions — costing one comparator pair per
span.

## 6. NES PPU: tile fetch pipelined into shift registers

The NES PPU fetches the next tile's bitplanes while the current tile is
still shifting out of small shift registers, fully hiding fetch latency
behind display — a two-stage pipeline with no stall. Overview: nesdev.org,
"PPU rendering," https://www.nesdev.org/wiki/PPU_rendering (community wiki,
not a primary source; cross-checked against
https://famicom.party/book/09-theppu/).

*Use:* applicable if sprite-cell parameters ever come from on-chip table
memory rather than arriving pre-formed in the packet — prefetch the next
cell's data while the current cell's shift register drains, the way the
PPU double-buffers pattern bytes. Relevant once per-line sprite variation
is wanted without spending packet bytes every row.

## 7. Atari TIA: register-driven objects, no framebuffer

The TIA has no framebuffer; a handful of registers per scanline (player/
missile position and graphics byte, playfield bits) are read out by
beam-synchronised counters, and the CPU rewrites them every line — the
origin of "racing the beam." Overview: Wikipedia, "Television Interface
Adaptor," https://en.wikipedia.org/wiki/Television_Interface_Adaptor;
primary description: https://www.atariarchives.org/dev/tia/description.php.
(Montfort & Bogost, *Racing the Beam*, MIT Press 2009, is the standard
secondary source; no open full text found — flagged as likely paywalled.)

*Use:* close to our own architecture already, so the useful transfer is
TIA's register economy: one "player" gets up to three horizontal copies
from a size/copy register, essentially free. Add a repeat-count/pitch field
to a sprite cell's packet fields so one cell's shape replicates N times
across the line at a fixed pitch (e.g. a starfield row) instead of costing
N cells.

## 8. C64 VIC-II: raster interrupts and mid-frame reconfiguration

The VIC-II lets the CPU interrupt at a chosen scanline and rewrite chip
registers before the beam arrives, so different "modes" can coexist within
one frame — sprite multiplexing (reassigning 8 hardware sprites' positions
mid-frame to show far more than 8) is the best-known result. Overview:
https://www.c64-wiki.com/wiki/VIC; register reference:
https://ist.uwaterloo.ca/~schepers/MJK/vic2.html.

*Use:* this is exactly what our per-line packet already permits — the
actionable point is firmware, not hardware: since a fresh packet arrives
every line, the same 16 sprite cells can represent more than 16 logical
sprites across a frame by reassigning a cell's (x, pattern, colour) on
different lines, as long as no single line needs more than 16 live cells.

## 9. Amiga Denise/Agnus and the Copper: a tiny register-writing coprocessor

The Copper does one thing — wait for a beam position, write a value into a
chip register — letting a short instruction list change colours or
scroll/sprite positions at exact raster points without CPU intervention
(copper bars, per-line palettes). Amiga Hardware Reference Manual, "About
the Copper,"
http://amigadev.elowar.com/read/ADCD_2.1/Hardware_Manual_guide/node0048.html.

*Use:* the RP2040 already plays this role once per line; the Copper's
finer trick is multiple writes *within* one line. A future packet format
could carry two or three (x-position, new step-value) pairs, letting a
single scanline change the rotozoomer's step mid-line for cheap horizontal
banding — a firmware/packet change, costing only a compare-and-reload in
the existing accumulator logic.

## 10. TMS34010: a general CPU with graphics instructions

The TMS34010 (1986), the first fully programmable graphics processor, was a
bit-addressable 32-bit CPU whose instruction set added pixel-block-transfer
and line-draw opcodes — "acceleration" as a few graphics-shaped
instructions on a general core, not fixed-function blocks. Overview:
https://en.wikipedia.org/wiki/TMS34010; datasheet PDF:
https://www.farnell.com/datasheets/84292.pdf.

*Use:* mainly a cautionary contrast — that generality costs silicon we
cannot afford at ~0.7 mm2. Its narrower, transferable idea (PixBlt: copy a
small pattern with a boolean combine op) is already what the 16-cell sprite
pipeline does at fixed size; not worth generalising further.

## 11. Systolic rasterisers: Super Buffer and the Pixel Machine

Gharachorloo & Pottle's Super Buffer (1985) replaced a framebuffer with one
scanline's worth of pixel processors: polygons pre-sorted by starting
scanline feed in as spans, each cell passing state to its neighbour every
clock in a wavefront. Gharachorloo & Pottle, "Super Buffer: A Systolic VLSI
Graphics Engine for Real-Time Raster Image Generation," 1985 Chapel Hill
Conference on VLSI; cited via OSTI record
https://www.osti.gov/biblio/5790960 — no open full text found, flagged as
likely paywalled/proceedings-only. Related, coarser-grained: Potmesil &
Hoffert, "The Pixel Machine," SIGGRAPH 1989, DOI: 10.1145/74333.74340 (a
MIMD array with distributed framebuffer — software-programmable nodes, less
directly transferable).

*Use:* Super Buffer is our closest historical relative — one line's worth
of cells, fed pre-sorted per-scanline data, no framebuffer, describes both
systems. Concrete transfer: feed the systolic sprite pipeline runs
(start-x, end-x, colour) rather than only point sprites, so one pass can
also render solid or striped horizontal bars without a cell per bar.

## 12. Vectrex: analog integration for smooth motion

The Vectrex drives beam-deflection integrators directly: the DAC output is
a *slope*, and an op-amp integrator turns a held slope into a smooth
position ramp, so diagonal motion costs one held constant, not many steps.
https://vectrex.com/understanding-the-vector-display-of-the-vectrex/.

*Use:* conceptual only (we're raster, not vector), but reinforces the
existing design direction — the phase accumulators already integrate a
held constant over pixel-clocks. Worth continuing to push new effects into
"constant held, integrated by an adder already in the loop" rather than
recomputing per pixel.

## 13. Procedural texture cheap in hardware

**Perlin noise** interpolates gradients defined only at integer lattice
points, so arbitrary-resolution detail comes from a small fixed table, not
a stored image. Perlin, "An Image Synthesizer," Computer Graphics
(SIGGRAPH 85) 19(3):287-296, DOI: 10.1145/325334.325247. Open PDF:
https://www.cs.drexel.edu/~deb39/Classes/Papers/p287-perlin.pdf.

**Plasma** (demoscene folklore, no primary citation; e.g.
https://lodev.org/cgtutor/plasma.html) sums a few sine-table lookups
(offset by position and time) and maps the sum through a colour palette —
essentially what our wave engine already does.

**Palette cycling** animates a static pattern purely by rotating the
colour lookup table. Well covered in Mark Ferrari's GDC talk on 8/16-bit
colour cycling (widely available on video, no durable open citation —
flagged as folklore-with-good-secondary-coverage).

*Use:* the missing piece beyond our existing plasma-like wave engine is
Perlin's lattice trick, which gives *non-periodic*-looking texture from a
tiny table instead of the visibly periodic look of pure sine sums. Host
precomputes an 8-16 entry gradient table once; the chip linearly
interpolates between adjacent entries while sweeping x — again just an
accumulator (value += step, step reloaded at lattice boundaries), no
multiplier. Palette cycling is nearly free to bolt onto any layer already
driven from a small colour table — cycling the read offset once a frame
costs one counter.

## Ranked: five ideas most worth trying first

1. **Forward-differenced quadratic circle/ellipse mask (#2/#4).** Two
   chained adders per pixel give a genuinely round shape, which nothing on
   chip does today. Experiment: add a value/delta/second-delta accumulator
   beside the background engine; sign of value gates a fill; host computes
   delta/second-delta from a centre and radius; confirm a resizable filled
   disc.

2. **Linear half-plane testers as a background mode (#1).** Reuses existing
   accumulator hardware with AND/OR instead of XOR. Experiment: run two
   independent linear accumulators per line, display (acc1>0) AND (acc2>0)
   as a wedge, sweep coefficients to rotate it, and check for clean edges
   versus the XOR checkerboard's diagonal aliasing.

3. **Span-based sprite runs (Super Buffer style, #5/#11).** Lets the
   systolic pipeline draw filled bars in one pass. Experiment: extend one
   cell's packet fields to (start-x, end-x, colour); confirm it paints a
   bar spanning many pixels while the other 15 cells still handle point
   sprites on the same line.

4. **TIA-style horizontal replication for sprite cells (#7).** A
   repeat-count/pitch field multiplies apparent sprite count for free.
   Experiment: add a 3-bit repeat count and 8-bit pitch to one cell's
   fields; confirm N evenly-spaced copies render from one cell's pipeline
   state.

5. **Perlin-style small-lattice interpolated texture (#13).** Directly
   attacks the composite-bandwidth constraint better than pure sine sums,
   and is a pure accumulator. Experiment: host precomputes an 8-entry
   per-line gradient table; chip interpolates it as an extra layer; compare
   visually against the wave engine for whether the non-periodic look
   survives PAL bandwidth limiting.

## Flags / uncertainties

- Van Aken & Novak (#4) and Gharachorloo & Pottle's Super Buffer (#11): no
  open-access full text found; content above is reconstructed from
  secondary sources, not the primary text.
- Montfort & Bogost's *Racing the Beam* (#7): likely paywalled; used the
  open TIA hardware description directly instead.
- Mark Ferrari's colour-cycling talk and the demoscene plasma technique
  (#13) have no durable primary citation — treated as folklore with good
  secondary coverage, flagged rather than dressed up.
- NES PPU description (#6) relies on community wiki sources, not a
  manufacturer datasheet — cross-checked across two independent write-ups
  but not a primary source.
