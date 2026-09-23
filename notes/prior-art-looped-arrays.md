# Prior art: looped, recirculating and iterative array hardware

Context: our chip is a beam-racing video processor with no frame buffer.
Compute happens in systolic pipelines — identical cells, nearest-neighbour
links, one clock per cell per pixel-time. We want to close such a pipeline
into a ring with conditional back-links, so a datum can take several passes
through the same cells (e.g. 16 cells x 10 passes = 160 slots per pixel),
and possibly run to a fixed point, such as the max-plus Bellman-Ford
iteration `x <- max(b, A x)` whose fixed point is the Kleene star `A* b`
(glow / distance-field effects). A host compiler produces the per-cell
programs offline. This note surveys prior art on looped/iterative array
hardware and the algebra behind it, with a "how we could use this" for
each item and a ranked shortlist of experiments at the end.

## 1. Recirculating pipelines and loop-back in stream processors

**Wavefront arrays (S. Y. Kung).** A systolic array is clocked globally;
a *wavefront* array replaces the global clock with local handshaking
(data-driven, self-timed), so a value only advances when the receiving
cell is ready. Kung, "VLSI Array Processors" (Prentice-Hall, 1988; survey
chapter PDF: https://www.ece.ucdavis.edu/~bbaas/281/papers/KungVlsiArrayProcs.pdf)
and Kung et al., "Wavefront Array Processor: Architecture, Language and
Applications" (MIT VLSI Conf., 1982) — also see "VLSI Wavefront Arrays
for Image Processing" (Springer, 1985 chapter). *How we could use this*:
our loop-back is the same idea in miniature — instead of asynchronous
handshaking (too expensive for a small video chip), a single "still
looping" flag per packet tells the ring whether to re-inject or drain,
which is a synchronous, one-bit-of-control approximation to wavefront
control flow.

**Recirculating delay-line memory (video/analogue prior art).** Before
frame buffers were affordable, CRT scan converters and time-to-digital
electronics used *recirculating delay lines*: a shift register or
acoustic/analogue delay line whose output feeds back to its own input
through an OR/adder, refreshing or accumulating a signal every cycle
without ever landing in RAM. See e.g. US4149252A (rho-theta to XY scan
converter using a "reiteration memory") and general recirculating
delay-line descriptions in scan-converter patents. *How we could use
this*: this is the closest ancestor of "no frame buffer, loop the pixel
stream through itself" — it confirms the pattern is old and was solved
with shift-register rings, exactly our cell-ring topology, rather than
addressable memory. It is reassuring prior art for the *architecture*,
though it carries no algebra — the payload here is just delay/average,
not Bellman-Ford.

## 2. Cellular logic image processors (CLIP, MPP, Golay)

**CLIP4 (M. J. B. Duff, UCL).** A 96x96 mesh of 1-bit SIMD cells, each
talking to its 8 nearest neighbours, running the same instruction at
every cell every cycle — cellular-automaton-style local logic for binary
image processing. Duff, "CLIP4: A Large Scale Integrated Circuit Array
Parallel Processor," IJCAI 1973 / later surveys, e.g. "Architectures of
SIMD Cellular Logic Image Processing Arrays" (Springer, 1983,
https://link.springer.com/chapter/10.1007/978-3-642-82150-9_2); overview
also in "Comparison of the CLIP4, DAP and MPP processor-array
implementations" (https://www.osti.gov/etdeweb/biblio/5363001). *How we
could use this*: CLIP4's whole trick is running the **same local rule for
many iterations** to get global effects (region growing, skeletonisation)
out of purely local, nearest-neighbour hardware. Our loop is CLIP4
collapsed from a 2-D mesh to a 1-D ring of cells reused over time instead
of over space — each "pass" through our 16-cell ring is one CLIP4
"generation." Worth mining CLIP's iterative binary operators (shrink,
expand, propagate-until-stable) as candidate cell rules.

**Goodyear MPP.** A 128x128 1-bit SIMD mesh built for NASA satellite
image processing (1983). Batcher, "Architecture of a Massively Parallel
Processor" (https://dl.acm.org/doi/pdf/10.1145/285930.285977); Wikipedia
overview: https://en.wikipedia.org/wiki/Goodyear_MPP. *How we could use
this*: same lesson as CLIP4 — MPP's applications (image thresholding,
convolution, connected-component work) were all done as repeated local
sweeps, not one-shot global computation, which is exactly the deal our
looped ring makes with the host compiler (trade passes for area).

**Golay hexagonal logic.** M. Golay proposed a hexagonal neighbourhood
(7 pixels: 1 centre + 6 neighbours) and a small instruction set ("Glol")
of local pattern-transform rules, implemented as small dedicated logic
per cell; hardware realisations followed as 16x12-cell hexagonal cellular
arrays. Golay, "Hexagonal Parallel Pattern Transformations," IEEE Trans.
Computers C-18(8), 1969, pp. 733-740 (paywalled on IEEE Xplore, no open
copy found — flagged below); secondary description in "Feature
Extraction by Golay Hexagonal Pattern Transforms," IEEE Trans. Computers,
and "A cellular logic array for image processing" (1973,
https://www.sciencedirect.com/science/article/abs/pii/0031320373900459).
*How we could use this*: Golay's neighbourhood definition and small
"transform table" per cell is a good model for how small our per-cell
instruction set can afford to be — a handful of boolean/ordinal ops
selected by a few bits — which matters because our host compiler has to
fit a program into very few control bits per cell per pass.

## 3. Mathematical morphology hardware

**Serra's morphology, and Sternberg's cytocomputer.** J. Serra formalised
erosion/dilation/opening/closing algebraically (structuring elements,
lattice operations) in "Image Analysis and Mathematical Morphology"
(Academic Press, 1982; borrowable scan at
https://archive.org/details/imageanalysismat0000serr). S. Sternberg (ERIM)
built this into a real pipeline machine, the **Cytocomputer**: a linear
pipeline of identical stages, each doing one erosion/dilation with a
small structuring element, so a k-stage pipeline realises k successive
morphological operations at one pixel per clock, with no frame buffer
(it can sit directly behind a sensor). Lougheed & McCubbrey, "The
Cytocomputer: A Practical Pipelined Image Processor," 7th Int'l Symp. on
Computer Architecture (ISCA), La Baule, 1980; survey "Pipeline
Architectures for Morphologic Image Analysis," Machine Vision and
Applications 1(1), 1987 (https://link.springer.com/article/10.1007/BF01212310).
*How we could use this*: this is closest in spirit to us of everything
surveyed — a beam-synchronous, frame-buffer-free pipeline of identical
programmable stages. The difference is that the Cytocomputer gets its
depth by laying down more physical stages (one structuring element per
stage), where we get depth by looping the *same* stages several times.
Their morphological chain rule — dilation by a large structuring element
= composition of dilations by small ones — is a direct recipe for
programming our ring: express a big morphological operator (e.g. a large
glow radius) as N passes of a small 3-cell operator, and let the host
compiler pick N.

## 4. Distance transforms and two-pass chamfer algorithms

Rosenfeld & Pfaltz showed that a *global* distance-to-nearest-set-pixel
map can be computed by two local, sequential raster sweeps (forward
top-left-to-bottom-right, then backward), each sweep only touching
already-visited neighbours — no global data structure needed. Rosenfeld
& Pfaltz, "Sequential Operations in Digital Picture Processing," J. ACM
13(4), 1966, pp. 471-494 (open PDF, author's own copy:
https://www.cs.virginia.edu/~jlp/66.sequential.op.pdf). Borgefors
generalised the local mask weights to approximate true Euclidean distance
much better ("chamfer" distances) and formalised the double-scan
(forward + reverse lexicographic) recipe. Borgefors, "Distance
Transformations in Digital Images," Computer Vision, Graphics, and Image
Processing 34(3), 1986, pp. 344-371; readable modern treatment: "Optimum
Design of Chamfer Distance Transforms,"
http://cvsp.cs.ntua.gr/publications/jpubl+bchap/ButtMaragos_ChamfDistTransf_ieeetIP1998.pdf.
*How we could use this*: this is essentially our "distance-field / glow"
use case already solved for the 2-D raster case with exactly two
passes over the frame. Our situation is one dimension short (a 1-D pixel
stream, no vertical neighbour without a line buffer) and unbounded in
passes rather than fixed at two — so the natural bridge is: use one pass
per scanline for the horizontal (chamfer-style) sweep, feed a per-column
running minimum/maximum forward across scanlines through a small
line-delay buffer (this is exactly what our "running scan"
`x[i] = max(seed[i], x[i-1] - d)` already does), and use the *looped
ring* to do the chamfer's second (reverse) pass, or extra passes for
larger radii, without needing a full frame buffer. The forward/backward
two-pass structure also motivates giving our ring a "direction" bit.

## 5. Path algebras and semiring frameworks

**Carré, and Gondran & Minoux.** B. Carré showed that Bellman-Ford,
Dijkstra, Floyd-Warshall and matrix-inversion-style path algorithms are
all instances of one abstract "path algebra" (a semiring), differing only
in which (+, x)-like pair of operations you plug in. Carré, "Graphs and
Networks," Clarendon Press/Oxford, 1979. Gondran & Minoux generalised
this to "dioids" (idempotent semirings) with a full algebraic and
spectral theory: Gondran & Minoux, "Graphs, Dioids and Semirings: New
Models and Algorithms," Springer, 2008 (https://link.springer.com/book/10.1007/978-0-387-75450-5).
**Aho, Hopcroft & Ullman's closed semirings.** AHU generalised Kleene's
and McNaughton-Yamada's regular-expression construction to any *closed
semiring* (one where infinite sums converge), giving one algorithm that
computes all-pairs path costs for shortest paths, regular-language
recognition, or matrix inversion depending on the semiring chosen: Aho,
Hopcroft & Ullman, "The Design and Analysis of Computer Algorithms,"
Addison-Wesley, 1974; journal form: Aho & Ullman, "A more general
algorithm for computing closed semiring costs between vertices of a
directed graph," CACM 18(2), 1975 (https://dl.acm.org/doi/pdf/10.1145/358876.358884,
appears openly fetchable). A readable synthesis of all three (Carré,
Gondran-Minoux, AHU), with the max-plus / Kleene-star connection made
explicit, is Mohri, "Semiring Frameworks and Algorithms for
Shortest-Distance Problems," J. Automata, Languages and Combinatorics
7(3), 2002, open PDF at https://cs.nyu.edu/~mohri/pub/jalc.pdf. *How we
could use this*: this is the theoretical backbone for exactly the thing
we want to do — `x <- max(b, A x)` converging to `A* b` is a Kleene-star
computation in the max-plus semiring, one member of a family that also
covers ordinary shortest paths (min-plus) and reachability (boolean
OR-AND). Our host compiler can treat "what does this looped ring
compute" as "pick a semiring, pick a sparse matrix A from the cell
wiring, run enough Kleene-star iterations to converge" — a principled
stopping rule (bounded by the wiring graph's diameter, in passes)
instead of a guessed pass count.

## 6. Systolic arrays for the algebraic path problem and transitive closure

**Guibas, Kung & Thompson (1979).** The founding systolic-array paper
for path problems: a 2-D systolic mesh that computes the reflexive-
transitive closure (and, by choice of semiring, all-pairs shortest paths)
of an n-node graph in O(n) time using O(n^2) simple cells, each doing one
`(+,x)`-style update per cycle and passing data to its neighbours.
Guibas, Kung & Thompson, "Direct VLSI Implementation of Combinatorial
Algorithms," Caltech Conf. on VLSI, 1979, pp. 509-525 (persistent copy:
https://resolver.caltech.edu/CaltechCONF:20120504-162659203; also on
ResearchGate). **Günter Rote (1985)** built on this with a *hexagonal*
systolic array performing closed-semiring Gauss-Jordan elimination — one
general algorithm that specialises to Floyd-Warshall (transitive
closure/shortest paths) or to real matrix inversion depending on the
semiring — using O(n^2) cells in 7n-2 steps; later "orthogonal" variants
reduced this to 5n-2. Rote, "A Systolic Array Algorithm for the Algebraic
Path Problem (Shortest Paths; Matrix Inversion)," Computing 34(3), 1985,
pp. 191-219, open author's PDF:
https://page.mi.fu-berlin.de/rote/Papers/pdf/A+systolic+array+algorithm+for+the+algebraic+path+problem+(shortest+paths;+matrix+inversion).pdf
(see also H.-W. Lang's worked-example page:
https://hwlang.de/papers/trans/transcl.htm). *How we could use this*:
these are 2-D O(n^2)-cell arrays computing a full all-pairs closure in
one shot — too big for our per-pixel budget — but the *recurrence* they
systolise (repeatedly folding in one more pivot row/column) is exactly
a Kleene-star computation done incrementally. Our ring is the other end
of the same trade-off: small state, many sequential passes, instead of
GKT/Rote's large state in few steps — worth naming explicitly when
sizing cells-x-passes in the compiler.

## 7. Max-plus algebra, eigenvalues and periodicity

R. Cuninghame-Green founded "minimax algebra" (max-plus / max-times
linear algebra) and proved that every irreducible matrix has a unique
max-plus eigenvalue, with the matrix powers becoming eventually periodic
("ultimately linear") once the associated cyclic structure kicks in.
Cuninghame-Green, "Minimax Algebra," Lecture Notes in Economics and
Mathematical Systems 166, Springer, 1979; survey "Generalised
Eigenproblem in Max-Algebra," https://web.mat.bham.ac.uk/P.Butkovic/My%20grant%20papers/WODES%20published.pdf.
Baccelli, Cohen, Olsder & Quadrat gave the full linear-systems theory
(max-plus analogues of eigenvectors, spectral radius, periodic regimes,
stability) with an emphasis on discrete-event/queueing systems.
Baccelli et al., "Synchronization and Linearity: An Algebra for Discrete
Event Systems," Wiley, 1992 (no full open PDF found in this search — the
maxplus.org project site is the usual pointer, flagged below as unverified
open-access status). *How we could use this*: this directly predicts the
*qualitative behaviour* of our looped ring under many passes, before we
build anything. If the wiring matrix A (which cell feeds which, plus
weights/decays) is irreducible, `A^k x` does **not** keep changing
forever — it converges to (or cycles around) the max-plus eigenvector,
with the eigenvalue controlling whether the pattern grows, shrinks or
holds steady per pass. That is a ready-made design rule for the host
compiler: choose the weights on the back-links so the eigenvalue is
exactly 0 (steady glow, no growth or decay pass-to-pass) or slightly
negative (glow that fades over passes, like our `-d` term in the running
scan) — and predict *how many passes to convergence* from the matrix's
cyclicity/period instead of tuning pass counts by eye.

## 8. Conditional iteration / data-dependent loop counts in systolic arrays

Classical systolic array synthesis (uniform recurrence equations mapped
to space-time) does not have run-time-varying loop counts by default;
a data-dependent conditional is normally handled by deriving a control
signal from the recurrence's index set at compile time ("multistage
pipelining" — see the general survey area "Efficient control generation
for mapping nested loop programs onto processor arrays,"
https://www.sciencedirect.com/science/article/abs/pii/S1383762106001287),
or by running all branches and selecting the result at runtime. Kung's
wavefront model (section 1) gives a more dynamic answer: let local
handshaking, not a global schedule, decide how many times data
recirculates. This is a thinner area of the literature than the others
— flagged as the least-settled topic — a single "keep looping" flag
riding with the datum, checked at the loop-back junction, has no one
canonical named ancestor in what I found; it is closest to wavefront
self-timed control and to "valid" bits in modern streaming dataflow
accelerators. *How we could use this*: treat the per-packet "loop
again?" bit as our whole conditional-iteration mechanism — the systolic
analogue of a wavefront control token — enough to implement "iterate
until a per-pixel counter hits zero" or "until a magnitude drops below
threshold" without per-cell general-purpose control flow.

## Uncertainties flagged

- Golay's original 1969 IEEE TC paper: no open-access copy found (IEEE
  Xplore only); details above rely on secondary descriptions.
- Baccelli et al.'s 1992 book: no open PDF located in this search; likely
  available via maxplus.org or an author's page, not verified here.
- The Cytocomputer citation year (1980, ISCA) is well attested by
  secondary sources but I did not open the primary proceedings text
  directly.
- "Conditional iteration in systolic arrays" turned up mostly adjacent
  material (control-signal synthesis for static nested loops) rather
  than papers specifically about *data-dependent* loop trip counts; treat
  section 8 as thin coverage, not a settled area.

## Five ideas most worth trying first

1. **Max-plus Kleene-star glow via the loop-back ring** (section 5/7).
   Wire a small ring (e.g. 8 cells) so each cell computes
   `x <- max(b_i, x_left - w)` with a fixed decay weight `w` per pass, and
   loop for a fixed small pass count. Experiment: point-source seeds
   (`b_i` spikes) on a scanline, sweep the decay weight and pass count
   live, and look for the fade-out radius converging (or not) to the
   eigenvalue-predicted plateau — a visible, tunable "glow halo" on the
   TV screen.
2. **Two-pass chamfer distance field re-used as our looped ring**
   (section 4). Do one forward pass per scanline (already our running
   scan) then route the ring for a *second*, reverse-direction pass over
   the same scanline before it's displayed. Experiment: draw a few
   sprites/edges per line and check whether the reverse pass visibly
   sharpens/symmetrises the distance falloff versus the current one-pass
   version.
3. **Cytocomputer-style "big operator via N small passes"** (section 3).
   Take one small morphological/blur kernel (3-tap max or average) and
   run it for a variable pass count N chosen by the host compiler per
   object. Experiment: same sprite rendered with N=1,4,16 to show a
   visibly growing halo/blur radius purely from pass count, with no
   change to the per-cell logic.
4. **Eigenvalue-tuned steady glow (no growth or decay)** (section 7).
   Pick back-link weights so the wiring matrix's max-plus eigenvalue is
   exactly 0, and check empirically that the pattern stabilises after a
   pass count matching the matrix's predicted cycle length, rather than
   growing or shrinking. Experiment: log/display the per-pass max value
   at a probe pixel across passes and confirm it flatlines at the
   predicted step, rather than only fine-tuning by eye.
5. **Wavefront-style "loop again?" flag as the whole conditional-loop
   mechanism** (section 8/1). Implement the simplest possible
   data-dependent stopping rule — one bit per packet, cleared when a
   per-pixel counter hits zero or a magnitude threshold is crossed — and
   verify it can end distance-field growth early for near pixels while
   letting far pixels use the full pass budget. Experiment: a scene with
   both a nearby and a very distant edge on the same scanline, showing
   different effective glow radii from the *same* hardware pass budget
   because near pixels stop looping early.
