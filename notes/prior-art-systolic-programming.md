# Prior art: how systolic arrays were designed and programmed

Context for this note: our chip's compute blocks are plain systolic pipelines
(nearest-neighbour links, identical cells) built for PAL composite video,
racing the beam with no frame buffer. We want to close a pipeline into a loop
with conditional back links, so a pixel can make several passes through the
same 16 cells (16 cells x 10 passes = 160 operation slots per pixel, 10 clocks
per pixel), scheduled offline by a host-side compiler. Below is what the
field already worked out about designing and programming such arrays, with a
"how we could use this" note for each item, and a ranked shortlist at the end.

## 1. Kung and Leiserson: the original systolic arrays (1978-82)

H. T. Kung and Charles Leiserson coined "systolic array" in a 1978 Carnegie
Mellon technical report, arguing that VLSI's real constraint is wire, not
gates: local, regular, nearest-neighbour communication with data pulsing
through a network of simple cells amortises one memory access over many
arithmetic operations. Kung's 1982 *Computer* survey "Why Systolic
Architectures?" generalised the pitch: simplicity and regularity of cells,
balance of computation and I/O, and multiple reuse of each input as it flows
through the pipeline.

**How we could use this.** This is the design argument for our per-scanline
packet interface: the RP2040 supplies one small packet per line and the
array reuses that state over many clocks and cells, instead of re-fetching
per pixel. The 1978 report's matrix-times-vector and convolution examples are
close cousins of our correlator and sprite pipeline — worth rereading for
how they counted cells vs. throughput, since we're making the same
area/latency trade at 130 nm instead of 1978's NMOS.

Citation: H. T. Kung and C. E. Leiserson, "Systolic Arrays for VLSI," CMU-CS
tech report, 1978 (also in *Sparse Matrix Proceedings 1978*, SIAM, 1979,
pp. 256-282). Open PDF: https://www.eecs.harvard.edu/htk/static/files/1978-cmu-cs-report-kung-leiserson.pdf .
H. T. Kung, "Why Systolic Architectures?," *IEEE Computer* 15(1):37-46, 1982,
DOI 10.1109/MC.1982.1653825 — paywalled; no free copy found via
Unpaywall/OpenAlex, flagging that. The 1978 report covers most of the same
ground and is open.

## 2. Space-time mapping / dependence-graph projection (Moldovan, Fortes; Quinton; Rao; Kuhn)

The design methodology that turns "why" into "how": write the algorithm as a
system of recurrence equations over an index space (an n-dimensional
dependence graph, one node per operation instance, edges are data
dependencies with constant offsets). Choose a linear **timing function**
(when each node fires) and a linear **allocation/projection** (which
processor each node lands on); projecting along a chosen direction collapses
the n-D index space onto a lower-dimensional array, and different projection
directions trade off array shape, latency and cell count. D. I. Moldovan and
J. A. B. Fortes formalised this "space-time mapping"; R. M. Kuhn's PhD work
and P. Quinton's automatic-synthesis papers made the projection mechanical
and gave sufficient conditions for legality (dependencies must stay uniform —
constant vector offsets — under the chosen transform).

**How we could use this.** This is the natural formal language for our host
compiler: represent each pixel's 160 slots as points in a 2-D index space
(cell 0-15, pass 0-9), with dependencies to the previous cell in the same
pass and to the same cell's state from the previous pass (the recirculation
edge). A timing function is "which of the 10 clocks a pixel spends at each
cell"; the projection is the constraint that cell 5 on pass 3 and cell 5 on
pass 7 both land on physical cell 5. The deliverable for us is the
*legality condition*: dependence vectors must stay uniform under a fixed
assignment, which tells us exactly when a back-link schedule is expressible
as a static per-cell program vs. needing a per-pixel runtime choice.

Citations: D. I. Moldovan, "On the Design of Algorithms for VLSI Systolic
Arrays," *Proc. IEEE* 71(1):113-120, 1983. J. A. B. Fortes and D. I. Moldovan,
"Parallelism Detection and Transformation Techniques Useful for VLSI
Algorithms," *J. Parallel and Distributed Computing* 2(3):277-301, 1985.
R. M. Kuhn, "Transforming Algorithms for Single-Stage and VLSI Architectures,"
PhD thesis/workshop paper, 1980. P. Quinton, "Automatic Synthesis of Systolic
Arrays from Uniform Recurrent Equations," *Proc. 11th ISCA*, 1984, pp.
208-214, DOI 10.1145/800015.808184 (ACM paywall; an earlier version is IRISA
Research Report No. 193, 1983 — I could not confirm a working open link this
session, flagging as unverified). Foundational theorem underneath all this:
R. M. Karp, R. E. Miller and S. Winograd, "The Organization of Computations
for Uniform Recurrence Equations," *JACM* 14(3):563-590, 1967, DOI
10.1145/321406.321418 — free PDF: https://www.cs.colostate.edu/~cs560/Spring2011/Notes/KMW-JACM1967.pdf .

## 3. S. Y. Kung's wavefront array processor and its language

S. Y. Kung (a different Kung — Sun-Yuan, not Hsiang-Tsung) proposed the
**wavefront array**: same nearest-neighbour mesh, but instead of a global
clock pulsing data through in lockstep, each cell fires as soon as its
operands are ready and tells its neighbours via handshake tokens ("data-driven,
self-timed" — control flows through the array alongside data). The
accompanying language (a matrix data-flow language, MDFL) let a programmer
describe algorithms as wavefronts propagating across the array rather than as
per-cycle schedules, closer to a dataflow/Occam style than to RTL.

**How we could use this.** Our design is deliberately clocked and
fixed-latency (10 clocks/pixel, video timing is the master clock), so full
asynchronous handshaking is probably the wrong fit — but the *idea* of a
per-neighbour "ready" flag, rather than assuming every slot's dependency is
always satisfied on schedule, is a cheap escape hatch if the compiler ever
needs a data-dependent stall (a back-link that sometimes takes an extra
pass). Even staying fully synchronous, the *language* idea — describe a
program as "this value's wavefront visits cells in this order" rather than
as a per-cycle netlist — is a good shape for the compiler's intermediate
representation.

Citation: S. Y. Kung, K. S. Arun, R. J. Gal-Ezer, D. V. Bhaskar Rao,
"Wavefront Array Processor: Language, Architecture, and Applications," *IEEE
Trans. Computers* C-31(11):1054-1066, 1982, DOI 10.1109/TC.1982.1675922.
Author's PDF (open): http://www.princeton.edu/~kung/papers_pdf/New%20Folder/Wavefront%20Array%20Procesor.pdf .

## 4. CMU Warp and iWarp, and the W2 compiler

Warp (1984-1990, H. T. Kung, CMU, with GE/Honeywell/Intel and DARPA funding)
was the step from fixed-function systolic arrays to *programmable* ones: a
linear array of 10+ VLIW floating-point cells, each capable of general
per-cycle instructions rather than one hard-wired function, so the same
hardware ran convolution, FFT, and vision kernels by loading different
per-cell programs. The **W2** language/compiler gave a machine abstraction
that separated "partition the algorithm across the linear array" from
"schedule each cell's VLIW instructions", i.e. exactly a two-level
space/time compilation problem, done by a real optimising compiler rather
than by hand. iWarp (1988-1990, with Intel) put a full computation + a
systolic-style communication agent on one chip per cell and generalised the
topology beyond a line, with the compiler front end (not W2, but a modified
pcc for C/Fortran) still doing array partitioning.

**How we could use this.** Warp is the closest historical analogue to "host
precomputes offline; array runs a fixed program per cell." Its two-level
structure — array-level partitioning, then per-cell VLIW scheduling — maps
onto our own two levels: first decide which of the 16 cells does which
operation on which of the 10 passes, then, within a cell, decide the
per-pass micro-schedule. Worth stealing: treating array-level partitioning
and per-cell scheduling as separable phases with a defined interface, rather
than one monolithic search over all 160 slots.

Citations: M. Annaratone et al., "The Warp Computer: Architecture,
Implementation, and Performance," *IEEE Trans. Computers* C-36(12):1523-1538,
1987 — open PDF: https://www.eecs.harvard.edu/~htk/publication/1987-ieee-toc-annaratone-arnould-gross-kung-lam-menzilcioglu-webb.pdf .
Monica Lam, "A Systolic Array Optimizing Compiler" (the W2 thesis), PhD
thesis, CMU, 1987/89, published by Kluwer
(https://link.springer.com/book/10.1007/978-1-4613-1705-0) — no free
full text found; CMU's tech-report archive may hold the original, unverified
this session. iWarp overview: T. Gross and D. O'Hallaron, *iWarp: Anatomy of
a Parallel Computing System*, MIT Press, 1998; TOC:
https://www.cs.cmu.edu/~droh/iwarpbook.toc.html .

## 5. Polyhedral scheduling: the modern descendant

The polyhedral model generalises Karp-Miller-Winograd/Moldovan-style
space-time mapping into a full compiler framework: represent a loop nest's
iteration domain as a polytope, express data reuse/dependencies as affine
relations, and search over affine schedules `theta(x) = T*x + Tp*p` for one
that is legal (preserves dependencies) and optimal by some cost model. Modern
tools (PolySA, and its more capable successor AutoSA, from UCLA) apply this
specifically to **generating systolic arrays for FPGAs from an ordinary
affine C loop nest**: they split the schedule into "space loops" (which map
to physical PEs, and require every dependency to have distance <=1 so
communication stays nearest-neighbour) and "time loops" (which run
sequentially inside a PE, e.g. a reduction/accumulation loop). This is a
direct, automated, current-day version of exactly the transformation we'd do
by hand.

**How we could use this.** AutoSA's space/time split names our own two axes
cleanly: "space" = physical cell (0-15), "time" = pass (0-9) plus clock
within a pass. Its legality rule — space-dimension dependencies must have
distance <=1 — is precisely our nearest-neighbour constraint, and its
reduction-loop-as-same-PE-time-loop pattern is the right model for a value
revisiting the *same* cell on consecutive passes (vs. a back-link that
revisits a cell after skipping others). We're unlikely to run AutoSA itself
(it targets HLS/FPGA C, and our array is hand-built RTL), but its published
cost model for choosing among legal space-time mappings (latency vs. PE
count vs. buffer size) is a good checklist for our compiler's search.

Citations: J. Cong et al./UCLA VAST group, "PolySA: Polyhedral-Based Systolic
Array Auto-Compilation," ICCAD 2018; A. Chi, J. Cong et al., "AutoSA: A
Polyhedral Compiler for High-Performance Systolic Arrays on FPGA," FPGA 2021.
Theory background doc (open):
https://autosa.readthedocs.io/en/latest/tutorials/theory_background.html and
source: https://github.com/UCLA-VAST/AutoSA .

## 6. Connection Machine and cellular-automata machines (CAM-6)

Two contemporaneous but different programmable-array traditions. The
**Connection Machine** (Danny Hillis, MIT/Thinking Machines, CM-1 1985,
CM-2 1987) was a SIMD machine with tens of thousands of 1-bit processors on a
hypercube network, programmed in Lisp-derived languages (CM Lisp, later C*
and CM Fortran) — "one instruction stream, broadcast to every cell, each
applying it to local data" — a very different contract from ours, but the
classic reference for programming a huge grid of identical cells. **CAM-6**
(Tommaso Toffoli and Norman Margolus, MIT Press 1987) is the concrete
counterpoint: a PC card with 256K bits of cell memory and eight 4Kbit
lookup tables acting as "processors," fast because every cell's update rule
was the same small table applied in parallel — "one shared rule, many
cells," structurally close to our "one sine table, one adder, ten
oscillators sharing it by rotation" ring.

**How we could use this.** CAM-6 is the more relevant of the two: it's
historical proof that a single small shared functional unit, visited by
many independent state records in rotation, is a legitimate way to build a
cellular machine — our wave-ring already does this, and CAM-6's write-up is
worth reading for how they handled "whose turn is it" (their update was
clocked and toroidal too). The Connection Machine is more a cautionary
contrast: it shows "one instruction, broadcast" sufficing for huge problems,
whereas we explicitly want per-cell/per-pass *different* micro-programs,
closer to Warp's VLIW-per-cell — useful mainly as the point we're
consciously not copying.

Citations: W. D. Hillis, *The Connection Machine*, MIT Press, 1985. T. Toffoli
and N. Margolus, *Cellular Automata Machines: A New Environment for
Modeling*, MIT Press, 1987 (https://mitpress.mit.edu/9780262526319/cellular-automata-machines/).
N. Margolus, "Cellular Automata Machines," *Complex Systems* 1(5), 1987 —
open PDF: https://content.wolfram.com/sites/13/2018/02/01-5-5.pdf . Neither
book itself found free (only the shorter Margolus article above, which is
open) — flagging as unverified whether a scan exists via archive.org.

## 7. Systolic arrays with feedback/recirculation, and run-time configuration

This is the closest match to our specific need — but it's a much thinner
literature than space-time mapping, and mostly framed as hardware *reuse*
rather than *program structure*. **Folding** is the standard name for
time-multiplexing a pipeline: use fewer physical cells than logical stages
and run each physical cell for several virtual stages over several clocks,
with a "folding set"/schedule deciding which virtual operation each
physical cell performs on which cycle — textbook DSP hardware design
(Parhi's *VLSI Digital Signal Processing Systems*), structurally identical
to our "16 cells x 10 passes" idea, usually applied to a fixed linear
pipeline folded onto fewer cells rather than a genuine loop-back topology.
Separately, **reconfigurable systolic arrays** ("polymorphic systolic
array," FPGA partial-reconfiguration accelerator papers) let node function
and interconnect be redefined at run time — but usually means "reprogram the
FPGA fabric between kernels," not "branch mid-array per item." I found no
literature specifically about **per-item data-dependent recirculation
counts** (an item deciding, from its own data, how many more passes it
needs) in a hardware systolic array — flagging this as the one item here I'd
treat as a possible gap rather than an established technique.

**How we could use this.** The folding literature gives vocabulary and a
correctness discipline directly transferable to the host compiler: a
"folding set" is exactly what our compiler must emit, and folding theory has
clean necessary-and-sufficient conditions for when a folded schedule is
realizable without extra buffering (the folding order must respect the
original dependency's iteration distance). Where our problem goes beyond
textbook folding is the *conditional* back link — a pixel that sometimes
shortcuts through fewer passes. That's closer to a small run-time-selected
schedule than a fixed fold, so it may be worth treating as a **static set of
legal schedules chosen at compile time, selected per-pixel by a cheap
data-side mux** (a 1-bit "skip pass" flag at a fixed point) rather than
dynamic reconfiguration — keeping us in the well-understood folding regime
instead of the far less charted runtime-reconfigurable-interconnect one.

Citations: K. K. Parhi, *VLSI Digital Signal Processing Systems: Design and
Implementation*, Wiley, 1999, folding chapter (standard textbook, no open PDF
found). On reconfigurable systolic accelerators, results were mostly
theses/patents rather than one canonical paper — e.g. a USU MS thesis,
"Dynamically Reconfigurable Systolic Array Accelerators" (open,
digitalcommons.usu.edu), gives a recent summary and further citations, but I
would not treat it as authoritative; flagging accordingly.

---

## Ranked shortlist: five ideas most worth trying first

1. **Treat the 160 slots as points in a 2-D index space (cell x pass) and
   write down the dependence vectors explicitly**, following
   Moldovan/Karp-Miller-Winograd. Experiment: for the sprite pipeline and
   correlator, write out one pixel's dependency graph by hand, check which
   dependence vectors are uniform, and see whether the conditional back
   link is a small finite set of uniform schedules selected by a 1-2 bit
   per-pixel tag. An afternoon's work that shows whether the compiler's
   search space is small and enumerable or needs real search.

2. **Borrow Warp/W2's two-phase compiler structure**: array-level
   partitioning (which cell does which operation, on which pass) followed
   by a separate per-cell micro-schedule phase. Experiment: build the host
   compiler as two passes with a fixed intermediate format between them
   ("cell 7, pass 3: op X, inputs from cell 6/pass 3 and cell 7/pass 2"),
   and check this decomposition alone suffices to hand-schedule one full
   test workload (the 10-oscillator wave ring) without reasoning about all
   160 slots jointly.

3. **Adopt DSP folding's legality condition as a compile-time check.**
   Experiment: a small checker that, given a proposed per-cell per-pass
   assignment, verifies the folding realizability condition (an operation's
   virtual-stage distance is consistent with the cell's fold factor) and
   flags illegal schedules before synthesis — turns "does this scheduling
   attempt work" from a simulation question into a static check.

4. **Prototype the conditional back-link as a static-schedule-set-plus-mux**
   rather than dynamic reconfiguration (item 7). Experiment: pick one
   candidate effect that plausibly needs a data-dependent early exit (e.g.
   a correlator that stops early on saturation), implement it as two or
   three pre-scheduled fixed-length paths selected by a per-pixel flag, and
   check whether that covers what we actually want before considering true
   per-item dynamic control.

5. **Read Moldovan/AutoSA's cost model for choosing among legal space-time
   mappings** (latency vs. cell count vs. buffer size) and adapt it as the
   host compiler's objective function rather than inventing an ad hoc one.
   Experiment: for the correlator, compute two or three legal schedules by
   hand under differing cell-count/latency trade-offs using the AutoSA cost
   framing, and check the ranking matches intuition before encoding a cost
   function into the real compiler.
