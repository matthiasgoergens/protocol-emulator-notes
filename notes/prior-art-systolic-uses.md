# Prior art: where systolic/dataflow arrays actually paid off, and when interleaved storage helps

> Coordinator's note (2026-09-25): written by a research agent. Claims are marked [V] (read
> in the primary source by that agent), [S] (secondary) or [L] (lower confidence). I did not
> re-verify the [V] quotes myself: Groq's site did not serve the ISCA 2020 PDF to a plain fetch.
> The phrase "software-defined" is at least Groq's own; it is in the title of their ISCA 2022 paper.

Draft literature survey for the Tiny Tapeout chip (IHP 130nm, ~0.7mm², 60MHz, 16-element
generic-PE systolic array segmented 2|2|4|8, 4-thread deterministic protocol sequencer,
gain-cell memory with expiring bits). Written 2026-09-25. Sources fetched and read where
practical; confidence flagged per claim as **[V]** (verified against a fetched primary
source — paper text/figures I or a research sub-agent actually read), **[S]** (secondary —
press, blog, search-engine synthesis of a primary source I could not fetch cleanly), or
**[L]** (low confidence — plausible but unverified, or a single uncorroborated secondary
source). Numbers with no flag are direct arithmetic on flagged inputs.

Research for this note was farmed out to four parallel sub-agents (Groq; TPU/Eyeriss/energy;
Cerebras/Graphcore/Dojo/SambaNova; Kung history and small-array wins), each told to fetch
primary sources where cheap and flag confidence explicitly. Their findings are folded in
below with the flags they reported.

---

## Summary table

| System | What the array/tile does | Why it won (stated or inferred) | Memory arrangement & ratio | Confidence |
|---|---|---|---|---|
| **Groq TSP/LPU** | 4× 320×320 systolic MACC planes (MXM) + 5,120 vector ALUs (VXM), streaming East-West across 20 "superlanes" | Fully static, compiler-scheduled datapath — *no* arbiters, caches or branch prediction anywhere on chip; "software-defined hardware" (term coined in the paper itself) | 220 MiB SRAM split into 88 MEM slices, physically interleaved **between** MXM/SXM and VXM on each superlane row; ≈556 bytes of SRAM per arithmetic unit | **[V]** — both ISCA papers read directly |
| **Google TPUv1** | 256×256 (65,536) 8-bit MAC systolic array, weight-stationary, activations stream through | Systolic execution chosen explicitly "to save energy by reducing reads and writes of the Unified Buffer" — an SRAM-access-energy argument, not primarily an area one | 24 MiB Unified Buffer + 4 MiB accumulators = 28 MiB total, **sized to match the MXU's physical pitch**; ≈448 bytes/MAC | **[V]** — paper read directly |
| **Eyeriss (v1)** | 168 PEs, row-stationary dataflow: weights, activations *and* partial sums each get a place to stay local | Directly minimises data-movement energy; silicon-measured RF:rest energy ratio ≈4:1 for CONV layers confirms the design goal in real chips, not just simulation | 0.5 kB dedicated RF/PE + 108 kB shared global buffer (≈643 B/PE); DRAM access costs ≈200× an RF access in their own 65nm-calibrated model | **[V]** — ISCA 2016 paper read directly, including the energy table and die photo |
| **Cerebras WSE-2/3** | 850k–900k cores, each with dedicated local SRAM, no shared cache | "Two types of memory... memory that stores a lot but is slow, and memory that's fast but can't store much" (Feldman) — avoids the HBM/DRAM memory wall by making the die itself huge enough to hold everything in SRAM | 40–44 GB total SRAM, 48 KB/core, 21 PB/s aggregate on-chip bandwidth; escape valve is off-chip "MemoryX" weight streaming when a model exceeds on-die capacity | **[S]** — Hot Chips PDFs unreadable via fetch tool; numbers triangulated across ≥3 independent secondary sources plus a Feldman quote |
| **Graphcore IPU MK2** | 1,472 tiles × 624 KiB local SRAM = 900 MB, Bulk-Synchronous-Parallel (compute → barrier → exchange) | All-SRAM tiles avoid "expensive, capacity-limited" HBM; BSP removes the programmer's synchronisation burden | 624 KiB/tile dedicated, no shared cache; DRAM fallback ("Streaming Memory") only when models exceed 900 MB | **[S]** — two independent technical sources (ServeTheHome, an academic microbenchmark paper) agree exactly on the 624 KiB × 1,472 = 900 MB figure |
| **Tesla Dojo D1** | 354 training nodes/die, 1.25 MB SRAM/node (~440 MB/die) | Standard co-location argument (memory next to compute to cut data-movement energy); no verbatim Tesla quote recovered | ~11 GB SRAM per 25-die training tile (one source says ~22 GB/tile — **unresolved discrepancy**) + up to 160 GB DRAM via DIP cards | **[S]**, with a flagged internal disagreement between sources |
| **SambaNova RDU / Plasticine** | 1:1 grid of Pattern Compute Units (PCU) and Pattern Memory Units (PMU), finely interleaved (not clustered) | Address-generation arithmetic moved into PMUs specifically so it doesn't consume PCU pipeline stages/output links — an interleaving-for-utilisation argument, distinct from Eyeriss/TPU's interleaving-for-energy argument | Plasticine: 16×8 grid, 76.9× perf/W over FPGA (academic). Shipped SN40L: 1,040 PCU+PMU pairs, 520 MiB SRAM + 64 GiB HBM + 1.5 TiB DRAM — a three-tier hierarchy Plasticine itself never needed | **[S]** for Plasticine (PDF unreadable, reconstructed from a lecture-note summary); **[V]**-ish for SN40L (SambaNova's own arXiv paper, fetched as clean HTML) |
| **H.T. Kung systolic arrays (1978–82)** | Matrix ops, convolution/FIR, (DFT, sorting, DP — lower confidence attributions), GCD | Regular, purely-local-communication design matched to a VLSI era where wires/pins were the scarce resource relative to gates; high compute-per-I/O-pin ratio | N/A (this is the founding rationale, not a specific memory ratio) | **[L]**–**[S]** — the founding papers themselves could not be fetched cleanly this session; rationale reconstructed from citing literature |
| **Warp/iWarp (CMU/Intel, 1984–93)** | Systolic array for vision/DSP, later loosened toward general MIMD nodes | Real shipped hardware (~20 PC-Warp units, ~39 iWarp systems sold) but the *systolic purity* was progressively diluted for programmability as scope broadened | N/A | **[S]** — Wikipedia + CMU sources, well corroborated |
| **GP2021 12-channel GPS correlator** | 12 independent, individually power-gateable correlator channels | Named, datasheet-documented, real shipped product in the 8–32-element band the survey asked about | N/A | **[S]** — multiple datasheet mirrors agree |
| **Viterbi ACS arrays** | Small systolic add-compare-select array, size = number of trellis states (16–128 depending on code) | Patented (US 5,027,374), NASA-documented (deep-space telemetry), ~1 Gb/s @ 83 MHz in <30k gates (1μm CMOS) | N/A | **[S]** — patent + NASA NTRS citation, not full text read |

---

## 1. Groq TSP/LPU — the closest analogue to our own bet on determinism

Two papers were fetched and read directly: Abts et al., **"Think Fast: A Tensor Streaming
Processor (TSP) for Accelerating Deep Learning Workloads,"** ISCA 2020
(groq.com/groq-isca-paper-2020), and Abts et al., **"A Software-defined Tensor Streaming
Multiprocessor for Large-scale Machine Learning,"** ISCA 2022 (groq.com/isca-2022-paper).
Also read: Dennis Abts's ISC2020 slide deck (mlhardware.github.io/2020/groq.pdf). All **[V]**
below unless flagged.

**Floorplan and interleaving.** The TSP reorganises a conventional 2D mesh of general-purpose
cores into a "functionally sliced" microarchitecture: each *row* of the mesh implements one
function, stacked as a slice. Reading outward-in across one die hemisphere: `MXM MXM | SXM |
MEM (44 slices) | VXM | MEM (44 slices) | SXM | MXM MXM`, repeated across 20 vertically-stacked
"superlanes." **MEM is interleaved directly between the matrix unit (MXM) and the vector unit
(VXM)** — confirmed from the paper's own floorplan figures and die photo, not inferred. Data
flows East-West between functional slices; instructions flow North-South from instruction
control units down through each slice.

**Deterministic execution — the actual "why."** This is stated repeatedly and explicitly, not
just implied by marketing:

> "guaranteeing determinism by eliminating all reactive elements in the hardware (*e.g.*
> arbiters, and caches)." — abstract
>
> "while microarchitectural enhancements such as caches, branch predictors, and prefetchers
> help tremendously in improving performance, they do not bound worst-case performance." —
> introduction
>
> "The TSP programming model relies on two critical elements: (1) deterministic data paths in
> hardware, and (2) exposing temporal information about an instruction's execution latency
> through the ISA... Exposing this additional temporal information across the static-dynamic
> interface gives rise to 'software-defined hardware.'" — §III

The phrase **"software-defined hardware" is coined in the ISCA 2020 paper itself**, worth
citing the paper rather than later marketing copy for it. The ISC2020 slide deck states the
motivation even more bluntly (Abts, Groq Chief Architect): out-of-order execution and cache
hierarchies "increases tail latency... not energy or silicon efficient," contrasted with "a
large, single-level scratchpad SRAM — fixed, deterministic latency." 144 independent
instruction-control units issue strictly in program order; there are no condition codes or
status flags anywhere in the vector datapath — everything is stateless and scheduled entirely
by the compiler ahead of time.

**Numbers.** 220 MiB on-chip SRAM (88 MEM slices × 2.5 MiB), 409,600 MACC units + 5,120 vector
ALUs = 414,720 arithmetic units → **≈556 bytes of SRAM per arithmetic unit**. Peak throughput:
820 TOPS at an idealised 1 GHz (the paper's own exposition clock) or ≈737–750 TOPS at the real
nominal 900 MHz — these are the *same* number at two different assumed clocks, not a
discrepancy, once you redo the arithmetic. Off-chip bandwidth: 480 GB/s via chip-to-chip links
(confirmed independently in both the paper and the slide deck). The widely-repeated **"80
TB/s SRAM vs ~8 TB/s HBM" comparison could not be traced to either paper [S/unverified]** —
the papers give 55 TiB/s idealised total on-chip bandwidth and no explicit HBM comparison at
all; flag this specific number as unconfirmed if citing it elsewhere.

**Scaling to 10,440 chips (ISCA 2022).** The multi-chip system extends single-chip determinism
without any hardware arbitration at all: **Software-Scheduled Networking (SSN)** resolves all
contention in the compiler, "the hardware is disallowed from asserting back pressure which
would disrupt deterministic operation of the network." Chips are kept in a shared logical time
base not via a literal shared clock but via a **Hardware Aligned Counter (HAC)** protocol —
periodic resynchronisation measured (not just claimed) to ~216 cycles mean latency with 2.6–2.9
cycle standard deviation across real links. This is the direct, measured answer to "how do you
get determinism across chip boundaries without a global clock": you don't assume lockstep, you
continuously re-derive a shared time reference and schedule everything against it at compile
time.

**Relevance to us:** our 4-thread deterministic protocol sequencer plus a compiler that
schedules gain-cell reads within their expiry lifetime is the same bet at a vastly smaller
scale — remove reactive hardware, push all scheduling into the compiler, and buy back the
energy/predictability that would otherwise go to arbitration logic. Groq is direct evidence
that this bet pays off when taken seriously (not just as an optimisation, but as *the*
organising principle of the whole chip).

---

## 2. TPU, Eyeriss, and the energy-of-data-movement evidence

**Google TPUv1** (Jouppi et al., ISCA 2017, arxiv.org/abs/1704.04760 — fetched and read
directly, including figures). The systolic Matrix Multiply Unit is 256×256 8-bit MACs (65,536
total), weight-stationary (weights load top-down and stay resident; activations stream in from
the left as a diagonal wavefront). The paper is explicit about *why* systolic execution was
chosen:

> "As reading a large SRAM uses much more power than arithmetic, the matrix unit uses systolic
> execution to save energy by reducing reads and writes of the Unified Buffer."

This is an **energy argument specifically about SRAM access, not primarily an area or
throughput one**. The die floorplan (Figure 2) shows the 24 MiB Unified Buffer at 29% of die
area and the MXU at 24%, together ~two-thirds of the die, and states explicitly: **"The 24 MiB
size was picked in part to match the pitch of the Matrix Unit on the die."** I.e. the memory
was sized and placed to physically feed the array, not chosen independently. Total on-chip SRAM
(24 MiB buffer + 4 MiB accumulators = 28 MiB) over 65,536 MACs ≈ **448 bytes/MAC**.

**Eyeriss** (Chen, Emer, Sze, ISCA 2016 — fetched and read directly, including the energy table
and die photo). Row-stationary dataflow gives weights, activations, *and* partial sums each a
place to stay local, explicitly to minimise data movement. The paper's energy-cost table
(Table IV, 65nm process, normalised to one MAC operation):

| Storage level | Energy relative to 1 MAC |
|---|---|
| RF (0.5 kB) | 1× |
| Array / inter-PE (1–2 mm) | 2× |
| Global buffer (>100 kB) | 6× |
| DRAM | 200× |

Crucially, this isn't just a simulated design goal: **"This distribution is verified by our
Eyeriss chip measurement results where the ratio of energy consumed in the RF to the rest
(except DRAM) is roughly 4:1"** for convolutional layers — a real, silicon-measured
confirmation, not just an architectural intention. Row-stationary measured 1.4–2.5× more
energy-efficient than weight-stationary/output-stationary/no-local-reuse dataflows at equal
hardware area. The fabricated chip: 168 PEs, 0.5 kB dedicated RF/PE, 108 kB shared global
buffer (≈643 B/PE), 65nm, 16 mm² die. Eyeriss v2 (secondary/medium confidence — fetched-summary
only): 192 PEs, ~410 B/PE scratchpad, 192 kB global buffer.

**Horowitz's "Computing's Energy Problem"** (ISSCC 2014 plenary keynote — the actual PDF was
fetched and read directly, including Figure 1.1.9's pJ table, 45nm/0.9V):

| Operation | Energy |
|---|---|
| 8-bit int add | 0.03 pJ |
| 32-bit int add | 0.1 pJ |
| 8-bit int mult | 0.2 pJ |
| 32-bit int mult | 3.1 pJ |
| 16-bit FP add | 0.4 pJ |
| 32-bit FP add | 0.9 pJ |
| 16-bit FP mult | 1.1 pJ |
| 32-bit FP mult | 3.7 pJ |
| 8 KB cache access | 10 pJ |
| 1 MB cache access | 100 pJ |
| DRAM access | 1.3–2.6 nJ |

The ubiquitous **"DRAM ≈ 200× SRAM" folklore number is not stated as a single figure anywhere
in Horowitz's slide** — it has to be constructed by comparing DRAM against the *smallest*
on-chip SRAM row (8 KB: 130–260× DRAM/SRAM). Eyeriss's own, independently-derived 200×
(different process, different methodology) lands in the same place, which is a real and
interesting cross-check — but the ratio for a *large* on-chip SRAM (1 MB, 100 pJ) vs DRAM is
only ~13–26×, an order of magnitude smaller. **Lesson: always state which SRAM size you're
comparing against — the "200×" number is only valid for small, near-compute SRAM, not for a
big shared buffer.**

**Processing-in-memory** (secondary sources only). UPMEM's PIM-DRAM: each DPU core has
exclusive access to a 64 MB DRAM bank, 24 KB instruction memory, 64 KB scratchpad; reported
23× average / 93× peak speedup vs a Xeon on streaming benchmarks **[S, not independently
verified]**. Samsung HBM-PIM (Aquabolt-XL): 16-wide SIMD per bank, vendor-claimed >2× system
performance and >70% energy reduction **[S — press/vendor claims, not peer-reviewed]**. General
PIM failure modes found in the literature (Mutlu et al., arxiv.org/abs/1802.00320, not fetched
directly): compute logic competes with memory density for the same silicon, limited/bespoke
instruction sets, and severe sensitivity to arithmetic intensity — PIM units sit idle exactly
on the low-reuse workloads they're supposed to help with.

**Cross-chip per-PE storage comparison** (all derived from the [V] numbers above):

| Chip | Dedicated local storage per PE/MAC | Shared buffer per PE/MAC |
|---|---|---|
| TPUv1 | ~64 B/MAC (accumulator) | 448 B/MAC total |
| Eyeriss v1 | 512 B/PE (RF) | 643 B/PE (shared) |
| Eyeriss v2 | ~410 B/PE (scratchpad) | ~1 kB/PE (shared) |
| Groq TSP | — (streaming, no per-unit RF) | ~556 B/unit |

Despite very different dataflows, three independent designs converge on **a few hundred bytes
of local storage per compute element**, backed by a shared buffer of a similar order of
magnitude. None of the published, successful designs provision kilobytes of *dedicated*
storage per single MAC/PE.

---

## 3. Cerebras, Graphcore, Dojo, SambaNova — how far to push "no DRAM at all"

All four converge on the same underlying justification — SRAM is faster and lower-power per
bit moved but far less dense than DRAM/HBM, so put compute next to small local SRAM tiles
rather than centralising memory — but diverge sharply on how far they push it.

**Cerebras** (WSE-2/3, [S] — Hot Chips PDFs would not extract cleanly; numbers triangulated
across ≥3 independent secondary sources). WSE-2: 850k cores, 40 GB total SRAM, 48 KB/core.
WSE-3: 900k active cores (of ~970k physical — implying ~7% redundancy margin), 44 GB SRAM, 21
PB/s aggregate on-chip bandwidth. Andrew Feldman (co-founder/CEO), quoted directly from a
public post: "There are two types of memory. Memory that can store a lot, but is slow. And
memory that is fast, but can't store much per square millimeter... GPUs use HBM [the slow-dense
kind]." Escape valve for models too big for on-die SRAM: weights stream in from off-chip
"MemoryX" layer-by-layer while activations stay resident. **Documented downsides**, from an
independent technical comparison (arxiv.org/pdf/2503.11698, not independently re-derived by
me): claimed >20× worse FLOPS-per-dollar than an Nvidia GB200 system; and from a wafer-scale
survey (arxiv.org/pdf/2310.09568): SRAM density scaling has essentially stalled since 5nm while
HBM capacity keeps growing — i.e. the all-SRAM approach is fighting an increasingly unfavourable
scaling trend, not a settled advantage.

**Graphcore IPU MK2** ([S], but well-corroborated: an independent academic microbenchmarking
paper, arxiv.org/pdf/2311.04417, independently derives the *exact* same 624 KiB × 1,472 tiles =
900 MB figure Graphcore's own materials give — a genuine cross-check, not just repeating a spec
sheet). Bulk-Synchronous-Parallel execution: local compute → global barrier → structured
exchange. Graphcore's stated rationale (via Hot Chips coverage): HBM is "expensive and
capacity-limited," so use many small SRAM tiles plus commodity DDR4 only as overflow.
**This is the strongest documented failure mode found anywhere in this survey**: multiple
independent academic papers (including a 2025 ACM ICS paper specifically proposing
"barrier-aware" scheduling to fix it) treat BSP straggler/load-imbalance stalls on tile-based
accelerators as an active, unsolved research problem — the mechanism is that any load
imbalance between tiles stalls the *entire* barrier, and Graphcore's own materials do not
volunteer this; it comes entirely from independent literature.

**Tesla Dojo** ([S], with an unresolved discrepancy between two independent secondary sources
on tile-level SRAM: ~11 GB vs ~22 GB per 25-die training tile — reported honestly rather than
picking one). 1.25 MB SRAM per training node × 354 nodes/die ≈ 440 MB/die. No verbatim Tesla
quote on the design rationale could be recovered this session (the "no packaging gaps" phrase
from the task brief was not found in any reachable source — likely exists only in a talk
video/slide deck not accessible via the fetch tools used). Independent (SemiAnalysis) criticism:
power density above Nvidia A100-class GPUs, and a custom (non-RISC-V) ISA flagged as added
toolchain risk.

**SambaNova RDU / Plasticine.** Plasticine (Prabhakar et al., ISCA 2017 — PDF would not render
via the fetch tool; reconstructed from a lecture-note summary, [S]) interleaves Pattern Compute
Units and Pattern Memory Units 1:1 in a 16×8 checkerboard, specifically because **routing
address-generation arithmetic from a PCU to a PMU, rather than doing it inline, keeps the PCU's
pipeline stages and output links free for actual data computation** — a distinct rationale from
Eyeriss/TPU's "minimise SRAM energy," closer to "don't let addressing arithmetic steal compute
throughput." Claimed 76.9× perf/W over FPGA. The shipped SN40L (SambaNova's own arXiv paper,
2405.07518, fetched and read as clean HTML — closer to **[V]** than most secondary sources
here) generalises this into a three-tier hierarchy (520 MiB on-chip SRAM + 64 GiB co-packaged
HBM + 1.5 TiB off-package DRAM), explicitly because "compute FLOPs [are] scaling faster than
both memory bandwidth AND capacity" — i.e. Plasticine's pure-SRAM academic assumption did not
survive contact with real model sizes. The paper itself names the tradeoff this creates: a
"static bandwidth model in the compiler" now has to do the scheduling work a GPU's cache
hierarchy would otherwise do at runtime.

---

## 4. H.T. Kung's original systolic proposals, and what actually shipped

**The founding rationale** (Kung & Leiserson, CMU tech report, 1978/79; Kung, "Why Systolic
Architectures?", IEEE Computer, 1982 — **neither full text could be fetched cleanly this
session**; rationale below is reconstructed from citing literature, [S]/[L]). The recurring,
well-corroborated argument: identical, purely-locally-connected processing elements minimise
design/verification cost and avoid long wires/global bus contention — framed as *the* VLSI-era
constraint, where wires and I/O pins are disproportionately expensive relative to gates. The
payoff is a **high compute-to-I/O ratio**: because each datum is reused by many PEs as it flows
through the array, the same pin bandwidth supports far more computation than a conventional
load/store architecture — closer to the inverse of the usual memory-bound bottleneck.

Original proposed applications, confidence-flagged individually: matrix/matrix-vector
multiplication and banded-matrix linear algebra **[S]**; convolution/FIR filtering, confirmed
via a specific 1982 Kung & Song 2-D convolution chip **[S]**; GCD of integers and polynomials,
explicitly confirmed via Wikipedia's history section quoting the original work **[S]**; DFT,
sorting networks, priority queues, dynamic programming/string matching — all widely cited as
part of the "Kung school" canon but **not pinned to a specific primary citation this session**
**[L]**; error-correcting codes (Reed-Solomon) — **not confirmed as Kung's own 1978–82 proposal**
(the systolic RS-decoder literature found is mid-1980s, building on the paradigm rather than
being Kung's own work) **[L]**.

**What actually shipped:**

- **CMU Warp / Intel iWarp** (1984–93, [S], well corroborated via CMU/Wikipedia sources). Warp
  started 1984 for low-level computer vision and neural-net simulation; production PC-Warp
  units (~$350,000 each) sold ~20 units 1987–89. iWarp (Intel/CMU, 1988) tried to put a whole
  parallel-computing node on one chip; ~39 machines sold 1992–93. Documented trajectory: each
  generation *loosened* the strict systolic coupling ("increasing memory capacity and loosening
  the coupling between processors") to gain programmability, and Intel eventually absorbed
  iWarp into a broader product line rather than actively marketing it — i.e. the systolic
  purity was a liability for general-purpose use, and the products that survived did so by
  becoming less systolic, not more.
- **Systolic Reed-Solomon/BCH decoders**: solidly documented in mid-1980s IEEE/NASA papers,
  explicitly in a **NASA deep-space/satellite telemetry context** (e.g.
  ntrs.nasa.gov/api/citations/19880003318) — real, working systolic RS decoder silicon existed
  for exactly the kind of communication-protocol error-correction our chip targets. **No named
  consumer product (CD player, HDD controller) with a confirmed systolic architecture was
  found** — RS decoding is universal in that hardware, but whether the shipped silicon was
  specifically systolic is unconfirmed **[L]**.
- **Viterbi add-compare-select (ACS) arrays**: the strongest, most concretely "real and shipped"
  item found for small-array communications hardware. US Patent 5,027,374 explicitly titles a
  "bit serial Viterbi decoder add/compare/select array"; a Springer paper reports a fully
  systolic ACS architecture at ~1 Gb/s @ 83 MHz in <30,000 gates (1μm CMOS); array size equals
  the code's trellis-state count (16–128 depending on constraint length — constraint-length-4/5
  codes with 16–32 states fit squarely in an 8–32-element band) **[S]**.
- **Systolic motion estimation in video codecs**: well-attested as a technique in the VLSI/MPEG
  encoder literature (e.g. Liang-Gee Chen's NTU group, a real fabricating lab) but **no single
  confidently-named shipped commercial chip** was confirmed this session; the general claim
  that motion estimation is systolic-array-friendly and consumes up to 80% of MPEG-2 encoder
  computation is solid **[S]**.
- **Smith-Waterman sequence alignment**: TimeLogic's **DeCypher** is a real, named, commercially
  shipped FPGA product (deployed as late as 2014, University of Ghent) claiming ~379× speedup
  over one CPU core; whether its internal FPGA core is specifically systolic is *inferred* from
  general FPGA-Smith-Waterman literature, not TimeLogic's own disclosure **[L]** on that
  specific point. UC Santa Cruz's **Kestrel** chip is a genuinely fabricated, well-documented
  research systolic array for sequence analysis, but targets 512 PEs — too large for our
  8–32-element comparison band.
- **Systolic BLAS on FPGA**: gemm_hls (ETH Zürich, open source) reports 462/301/132 GFLOP/s
  (fp16/fp32/fp64) on a Xilinx VCU1525 — real, citable, but no PE-count was confirmed this
  session **[S]**.

**Small (8–32 element) non-ML wins outside the Kung lineage, with an honest negative:**

- **GP2021** — a real, named, widely-deployed 12-channel GPS baseband correlator chip
  (Plessey/GEC → Mitel → Zarlink lineage), squarely in the 8–32 band, well documented via
  multiple datasheet mirrors **[S]**.
- **Amiga blitter — genuinely NOT an array.** Checked and reported honestly: it is a single
  pipelined DMA/raster-op engine, not multiple PEs. **Do not cite it as a systolic-array
  example** — that would be misuse of the term.
- **Logic-analyser CAM-based trigger matching** — the concept (parallel comparison of an input
  word against many stored trigger patterns) is real and generically documented, but **no named
  historical HP/Tektronix product with confirmed CAM-array internals was found**; flagged as an
  open gap rather than asserted **[L]**.

---

## 5. Lessons for our chip

1. **Determinism-as-the-organising-principle is validated at scale, not just plausible.** Groq's
   entire architecture is the same bet our 4-thread sequencer plus lifetime-scheduled gain-cell
   reads is making: eliminate reactive hardware, push all scheduling to the compiler, and the
   energy/predictability you buy back is worth more than the flexibility you give up. This is
   the single strongest piece of evidence in this survey and it transfers directly, independent
   of scale.

2. **Successful designs put a *small* amount of storage very close, backed by a modestly larger
   shared pool — not deep hierarchies, and not huge dedicated register files.** TPU (~64 B/MAC
   dedicated), Eyeriss v1/v2 (~410–512 B/PE dedicated), and Groq (~556 B/unit, no dedicated RF
   at all) converge on a few hundred bytes per compute element despite wildly different
   dataflows. Our own per-PE gain-cell bank (~2.3k μm² for 8 words) and latch RF (~46 μm²/bit)
   are far smaller in absolute bytes, which is expected given our PE and process scale, but the
   *ratio* argument is the transferable part: check each candidate problem (below) against
   "does one PE's working set for several cycles fit in its local bank," not against an absolute
   byte target borrowed from ML accelerators.

3. **Interleaving memory with compute pays off for two distinct reasons, not one** — worth
   keeping separate when we justify our own memory placement: (a) an *energy* argument (TPU,
   Eyeriss: avoid the cost of a bigger/further SRAM access) and (b) a *utilisation* argument
   (Plasticine: don't let addressing arithmetic consume the compute pipeline's own stages). Our
   segmentation (2|2|4|8) is closer to (b)'s concern than (a)'s — the risk to watch for is
   scheduling/addressing overhead eating into the array's own throughput, not raw SRAM energy,
   since our banks are already tiny.

4. **"DRAM/far-SRAM is ~200× a local access" is real but SRAM-size-dependent, not universal** —
   Horowitz's own numbers show the ratio drops to ~13–26× once the comparison SRAM is 1 MB
   rather than 8 KB. Any energy argument we make for keeping gain-cell banks local should state
   the size being compared against.

5. **Small (8–32-element) arrays have solid historical precedent doing exactly the things our
   own scoping already flagged** — GPS correlation (GP2021, 12 channels), Viterbi/ACS decoding
   (16–128 states, our size band fits the lower end), FIR filtering (Kung & Song's lineage), and
   video motion estimation — which corroborates, rather than merely inspires, our finding that
   the array helps DSP-on-pins, GPS correlation, video and pattern matching but not protocol
   logic itself.

6. **The Kung lineage's own trajectory is a warning, not just an inspiration.** Warp/iWarp
   survived commercially only by progressively *loosening* systolic coupling for
   programmability — i.e. rigid systolic purity was a liability outside a narrow set of
   regular, high-reuse computations. This matches our own finding that "no protocol needs the
   array": systolic/dataflow arrays are a good fit for a deliberately narrow slice of problems,
   and trying to stretch ours to cover general control flow would be repeating a documented
   failure mode, not a novel risk.

7. **Watch for the two most concretely documented failure modes**: Graphcore's BSP
   straggler/load-imbalance stall (still an open research problem in 2025 papers) and
   Cerebras/Graphcore's capacity-ceiling-forcing-DRAM-fallback. Our analogue of both is the
   gain-cell lifetime constraint: if the compiler's static schedule ever has to *wait* on a
   stalled read across segments, that's our BSP-barrier-equivalent, and it's worth explicitly
   checking the scheduler never introduces a reactive wait of that kind.

---

## 6. Concrete problems worth prototyping on our array

Ordered roughly by strength of historical precedent found in this survey:

1. **GPS/CDMA-style parallel code correlation**, mapped onto the 2|2|4|8 segments as independent
   correlator channels — direct precedent in the GP2021 12-channel correlator, and already
   flagged in our own scoping.
2. **Viterbi decoding (ACS array)** for a small convolutional code sized to one of our segments
   (16 or 32 states) — the single strongest small-array precedent found, patented and
   NASA-documented, and a natural fit for the condition-gated operand mode (branch-metric
   compare-select).
3. **FIR/IIR filtering and general "DSP on pins"** using saturating-add and the window/merge
   mode — direct lineage from Kung & Song's 1982 systolic convolution chip and the standard
   VLSI-DSP-textbook treatment of systolic FIR arrays.
4. **Reed-Solomon or BCH error-correction decoding** for a communication protocol carried on the
   pins — solid NASA/satellite-telemetry precedent for systolic RS/BCH decoders, and a good use
   of GF(2) mode for syndrome computation.
5. **Sprite/tile blitting and simple block-matching motion estimation** for a small video
   pipeline — matches the well-documented (if not individually-named-product-confirmed) use of
   small-to-medium systolic PE arrays for MPEG-style motion estimation, and our own
   already-flagged video/sprite strength.
6. **Approximate pattern/string matching** using a dynamic-programming-style systolic recurrence
   (a scaled-down Smith-Waterman/Kestrel-style structure) — direct lineage from Kung's original
   DP/string-matching proposals, scaled from Kestrel's 512 PEs down to our 16.
7. **Sorting network or median filter** using the array's max/min operations — direct lineage
   from Kung's original sorting-network proposal; a median filter for sensor/pin denoising is a
   concrete, small, testable instance.
8. **CRC/checksum computation pipelined across the array**, tying into the architecture's
   existing CRC-32 unit finding — general lineage from the systolic error-correcting-code
   literature, lower-risk than full RS/BCH decoding.
9. **A small systolic GEMV/dot-product demo**, explicitly to bound the *low* end of the design
   space given our own finding that "no protocol needs the array" — precedent is the
   TPU/gemm_hls lineage scaled down to 16 elements; useful mainly as a negative/comparison data
   point rather than a target application.
10. **Parallel pattern/trigger matching using GF(2) mode across segments**, logic-analyser-style
    — the weakest-sourced item in this survey (no confirmed historical named product), included
    because the mechanism (CAM-style parallel comparison) is real and cheap to prototype even
    without a strong historical precedent behind it.

---

## Gaps and follow-ups if higher confidence is needed

- Kung's 1978/79 and 1982 original papers: two independent PDF mirrors both failed to yield
  clean text this session. Library/IEEE Xplore access would let someone quote the original
  application list and "why systolic" rationale directly rather than via secondary paraphrase.
- Hot Chips slide decks for Cerebras (HC2022, HC2024), Graphcore (HC33), SambaNova (SN10, SN40L)
  and Tesla Dojo (HC2022) all exist at known URLs but returned garbled binary through the
  WebFetch tool used here — a dedicated PDF-to-text extraction pass would upgrade several
  **[S]** items above to **[V]**, particularly the disputed Dojo per-tile SRAM figure.
  Confirmed-to-exist URLs are given inline above.
- No individually-attributed Jonathan Ross quote (podcast/interview) was recoverable this
  session — transcripts on Masters of Scale/Acquired were not fetchable from this sandbox.
- The Amiga-blitter negative result should probably be checked against arcade sprite hardware
  (Namco/Williams-style) and SNES/Genesis PPUs specifically, which were not investigated this
  session; my working expectation (unverified) is the same negative result holds.
