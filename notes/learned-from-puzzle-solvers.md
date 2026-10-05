# What the ASIC-puzzle solvers' tooling can teach our entry

Written 2026-10-05 (SGT). Scope: the public write-ups and repositories from Jane Street's August
2026 ASIC reverse-engineering puzzle, mined for **tooling and verification technique** (not for
the answer), plus what Jane Street says it values. Companion to `notes/asic-puzzle-results-hints.md`
(what Jane Street praised; not repeated here) and `notes/learned-from-others.md` (other competition
entries; its rows V30, V31 and V32 touch the same ground and are extended, not repeated, below).

## How to read this note

**Evidence labels** on every claim about someone else's work:

- **[R]** I read the page, PDF or file myself on 2026-10-05. Raw copies are in
  `/var/tmp/learn-from-puzzle/` (`pages/`, `txt/`, `repos/`); that directory is on disk, not tmpfs.
- **[S]** From a search snippet, a listing, or the results post only; not read.
- A number in somebody's README or paper is **their** claim. Nothing here was reproduced by running
  their code, except where the text says so (nothing did).

**Licences** were checked with `gh api repos/OWNER/REPO --jq .license.spdx_id`; raw output and the
commit read are in `notes/learned-from-puzzle-solvers-licences.txt`. No licence means ideas only
(code may be run locally as a reference, never committed here). A paper or web page without a
repository is also ideas only. Credit is by GitHub handle or the name the author published under.

**Read in full or in large part [R]:** Soto Franco (PDF), Shapovalov (PDF), Shi, van Driel and
Post, Ravishankar (HackMD), Aravapalli (first half), Taboada (blog), Vargas (first two thirds),
Stapleton (page), Garner (PDF), Smallwood (PDF, extraction half), Wójcik (page), Ebert (PDF, first
five sections), and the two Jane Street posts plus the 2020 ASCII-waveform post. **Repositories
cloned and read at README/doc level, with code only sampled:** elementalcollision/retrace,
FigureZig/asicrev, umutdinceryananer/asic-reverse-engineering, JGalil/gds2netlist-asic-puzzle,
zaidharis7/asic-reverse-eng, 4wirtc (SPICE runner), stephenebert, ArkAung/silicon-atlas,
shaikhmubin02, NotCleo. **Only listed [S]:** Kaniyeri's Minecraft recording (a 34 MB mp4 was
downloaded, not watched), Gulawani's playable page (hosted at notcleo.github.io; its fetched text was a 1 kB shell), the other 15 or so clones.

## What we already have, so it is not a lesson

From `prototypes/postlayout-roundtrip/README.md` and `hardware-2026-08/SOLVING.md` [R]: a from-scratch
GDSII parser; union-find extraction with pins from the cells' own labels; the PDK's own Verilog
models interpreted as gate primitives and checked against the liberty functions over every cell's
full truth table (the same cross-check Soto Franco made); the structural check that every net has
exactly one driver and every input has metal under it (the floating-net lesson); lockstep against
the Hardcaml RTL; planted cuts, shorts and crossed wires, with a rule that a plant must change the
connectivity to count; calibration on the warm-up (54 vectors) before touching the puzzle; replay of
the supplied VCD; and a field guide with the dead ends left in. Anything below is a gap against that.

## 1. The solvers' tooling, by stage

Credit is by name as published. "Same as ours" means we already do it.

### GDS parsing and layer handling

- **Libraries.** gdstk: Aravapalli, Stapleton, Ebert, JGalil, retrace, zaidharis7 [R]. KLayout's
  Python module: Soto Franco; KLayout macros: Smallwood [R]. Magic `ext2spice` to SPICE then a script
  to Verilog: Ravishankar, 4wirtc [R]. Cadence PVS in LVS "extraction only" mode: Garner [R].
- **Own parser.** Shapovalov's `asicrev`: C++20, 7.1 kLOC, no EDA dependency, 42 tests, 1,618
  placements and 130,137 polygons in 60 ms [R paper]. Ours is OCaml (same as Shapovalov's role).
- **Layers that bite.** Leave device layers (`licon`, `diff`) out of connectivity, or every cell shorts
  its own pins through its transistors (Soto Franco §2.2; ours: Cont is mapped but not followed) [R].
  A pin label means something only on its own layer (probing a li1 label against met1 ties the pin to
  a rail, silently) [R]. Layer 200/0 and the `INTERNAL_3/7` placeholder cells are inert; Garner had to
  edit the layer-map table to see them at all [R].
- **Geometry traps** (all fail silently): rotation units: gdstk converts degrees to radians before
  you see them, and Aravapalli converted twice [R]; path outlines with 8 vertices, so a
  `len(points) == 4` test dropped 90% of the routing in `puzzle.gds` (JGalil) [R]; bounding boxes
  instead of exact rectangle decomposition merge wires across the empty part of L-shapes (Shapovalov,
  with a lemma) [R]; **vias must overlap, same-layer metal may merely abut** (Shapovalov §II-C and
  JGalil, independently) [R]; via cell names can misreport their layer (`VIA_via2_3_*` holds via1
  cuts: derive the layer from the cut inside, JGalil) [R]; flatten before extracting, or clock
  buffers' internal nets are shared by every instance (Soto Franco) [R].
- **Placement convention.** A routed database gives the lower-left of the *oriented abutment box*; a
  layout gives the cell's own origin; for flipped rows they differ by the row height. Shapovalov's
  check scored 96/230 until he compared transformed abutment boxes, 230/230 after [R]. retrace needed
  all eight LEF/DEF orientations once an SRAM macro placed at `E` appeared; sky130's N/S/FN/FS were
  not enough [R].

### Netlist extraction and connectivity

- Union-find over rectangles per layer joined by cuts: nearly everyone. KLayout `LayoutToNetlist`:
  Taboada (plus a custom pin-attach step), Soto Franco ("KLayout's connectivity engine"), and as a
  *second* extractor by Ebert, JGalil and retrace [R].
- Ravishankar and 4wirtc took Magic's `ext2spice` and converted; Smallwood wrote KLayout macros that
  walk `Region` interactions from each pin [R].
- **Structural lint of the result** (Smallwood): count no-driver nets, output-only nets, clock-related
  nets, multiple-driver nets; five no-driver nets turned out to be the top-level inputs [R]. (Ours does
  a stricter version.) Wójcik's lesson, which we credit already: 26 undriven pins left to the SAT
  solver as free variables gave a "winning" trace that printed garbage; his extractor had also left all
  84 reset pins off `rst_n` [R].

### Standard-cell recognition

- **Cell names left in the GDS: a table lookup** (all but Vargas and umut): the problem becomes
  connectivity only (Soto Franco §2.1; Shapovalov §II-A "Read the file before writing code. Thirty
  seconds decided whether this was a geometry problem or a device-recognition problem") [R].
- **Vargas** recognised cells from geometry: poly ∩ diff gives transistor gates, inside nwell means
  PMOS; diffusion minus gates gives DN_i/DP_i source/drain nodes; a net that touches only a gate is an
  input, one that touches a diffusion node is an output; the result simulated twice (PySpice and Z3)
  and compared per cell [R]. He then "decompiled" clusters to Verilog with a script. This is overkill
  for us (our cells keep their names) but is the only independent check of a cell's *function* against
  its *layout*.
- **umut** fingerprints every placement geometrically (stage 1) and has 99 synthetic circuits with
  known answers to score the recogniser [R README]. **retrace `cellcheck`** compares every cell master
  embedded in a GDS against the PDK's own cell GDS, layer by layer (PDK fingerprinting) [R].
- Soto Franco found the library's two descriptions of each cell function disagree (`definition.json`
  equations name inverted inputs by their uninverted form; the timing data uses real pin names) and
  generated both, then compared all 62 combinational cells exhaustively [R]. We do the same against
  liberty.

### Netlist to graph, and simplification

- **Ravishankar:** Yosys to strip physical-only cells and techmap clock buffers (9,876 cells down to
  696), `show` to a Graphviz `.dot`, positions copied in from a Magic-extracted DEF, then a script
  that excises every cell inside a hand-drawn bounding box into its own submodule (via Yosys JSON),
  checked by looking at connectivity between boxes: 11 modules, most matching the floorplan islands
  [R]. His repo (`sanrav2016/asic-puzzle-2026`, no licence) has `solution/bounding_box.py`,
  `combine_modules.py`, `annotate_dot_with_coords.py` [S, filenames only].
- **van Driel and Post:** the islands as regions R1..R11; regions drawn as a graph and ordered by
  "trophic level" (ecology: prey to predator) to pick a reading order; inside a region, the connected
  components of the *internal* wires split a 96-cell box into eleven independent copies of one small
  machine, so only one had to be understood [R].
- **Taboada:** no floorplan reading; MST/single-linkage clustering at 10 µm on cell positions, plus
  the drawn output box, gave 12 blobs from 695 logic cells; small blobs brute-forced [R]. The "cut
  honesty" check: he drove the cut-out printer with the exact bus the rest of the chip fed it and got
  the same output as the whole chip. Cutting the printer out and asking SAT for `success` went UNSAT,
  because an AND gate that success needs sits inside the hatched box [R].
- **Shi:** cones: of 728 cells, 484 reach `success`, 244 do not (the output generator); the success
  cone is 47 cells over 57 flops; pushing `success = 1` backwards through 47 AND/NOR/inverter gates
  fixes every flop uniquely (`required_state.json`, 56 flops) [R]. Later, an impulse sweep (one input
  bit, diff every flop against the all-zero run) built the same 56 bits *forwards*; 56 of 56 agreed
  [R]. Two derivations in opposite directions is the strongest form of "it is not a coincidence".
- **Shapovalov:** symbolic expansion of every flop's next-state function over other flops and inputs;
  where the expression became unreadable (the eleven region counters), he switched to 121 one-bit
  experiments on a netlist compiled to straight-line Python (about a microsecond per run) [R].
  "Stop reading when reading becomes expensive."
- **Stapleton:** intervention instead of reading: `signature(i) = Q(one-hot i) XOR Q(empty)`, cluster
  identical responses, interpret afterwards; backward dependency slice shows the output generator
  cannot affect `success` (79 of 92 flops can) [R].

### Simulating the extracted netlist

- **Icarus + the PDK's Verilog models:** Ravishankar, Shi (cocotb on the extracted netlist), Soto
  Franco, Stapleton [R]. **Own cycle simulators:** Soto Franco (Python expression trees, also what
  the solver unrolls), Shapovalov (compiled straight-line Python), Ebert and Stapleton (functions from
  liberty), JGalil (3-valued) [R]. **Xcelium:** Garner [R].
- **Vendor-model hazards:** Garner could not use the behavioural models. `sky130_fd_sc_hd__dlxbn`
  contains an invalid line (`wire 1 ;`), flip-flop models declare delayed nets that nothing drives (so
  `X` everywhere), some physical cells have no model; he switched to the functional models with
  `UNIT_DELAY=#0` [R]. zaidharis7 found Yosys cannot read sky130's behavioural models (UDP and
  `specify`), so its Yosys cross-check was skipped on that machine [R]. Our IHP models include UDP
  primitives (`sg13cmos5l_udp.v` exists [R]), so the same trap is waiting for gate-level Yosys use.
- **Unknowns.** Four flops in the puzzle have no reset. Soto Franco ran both simulators over all
  sixteen power-up states and showed verdict and reply identical (§5.4), and **the same refuted
  hypothesis** (that power-up state explained a disagreement) hid a real bug until the unknowns were
  assigned definite values [R]. Ebert and JGalil carry a third value `X` [R]. Ours is two-valued.
- **Formal/BMC:** Yosys `sat` with `async2sync` (Ravishankar: 150 cycles, 1,085,946 variables; a silent
  bug in his first setup sent him to the layout-based route instead), Z3 unrolling (Aravapalli, Stapleton, Soto Franco, Ebert),
  SymbiYosys (retrace, asicrev), BMC from *arbitrary* start states over all 2^92 (umut's claim, 13 solver
  calls) [R].
- **Beyond logic:** Garner ran the full transistor netlist in Spectre on five top-and-tail vectors and
  found large glitches on `O[7:0]`, because the outputs are driven straight from combinational gates; he
  notes they are harmless if sampled on the falling edge [R]. 4wirtc wrote a black-box ngspice runner:
  the recovered netlist is "design-only" (no stimulus, no `.tran`, no `.lib`, fixed ports) and the
  runner measures nothing but the declared ports [R]. Smallwood synthesised the netlist for a Basys 3
  (Vivado turned 728 cells into 106 FPGA cells), wrapped it with a UART front end, and found his own
  UART receiver counted 124 characters instead of 121 [R].

### Waveform comparison

- Every solver replayed `example_inputs.vcd`: Soto Franco 623 samples of `O` and `success`;
  Shapovalov 312 edges; van Driel 730 output-bit values; JGalil 5,616 comparisons with the nine `t = 0`
  samples excluded because the VCD records `x` there (the reverse case, simulator `x` where the VCD has
  a value, counts as failure) [R].
- **Sampling convention is a bug class.** Shapovalov scored 292/312 until he fixed two conventions
  (the stimulus seen at an edge is the value from before that timestamp's updates; a combinational
  output must be re-evaluated from post-edge state) [R]. Both are in his §VII list. Garner noticed that
  `I` changes on falling edges and `O` on rising edges [R].
- A single trace has coverage limits (Soto Franco §3.2): his passed 623/623 while every tie-high cell
  read 0, because the trace never exercises a tie path [R].
- retrace's `vcdtb.py` turns a VCD into a self-checking testbench (V31) [R README].

### Visualisation

- Interactive animated walkthrough (van Driel): scrollytelling page, trophic ordering, Fabio
  Crameri's perceptually uniform "batlow" and "oslo" colour maps, cited with DOIs [R].
- Netlist and layout side by side, **one shared instance ID** across both panes, hover in either
  highlights the other (Stapleton) [R]. A playable board that serialises through the recovered
  protocol and runs on the gate-level netlist (Stapleton [R]; Gulawani, hosted at notcleo.github.io [S]).
- Shi: `make image` draws which cells lit up, colour by first cycle touched; the key move in his
  own words ("visual aids really do help a lot") [R]. Shapovalov: one recovered net drawn on the die
  "is the cheapest sanity check available, since a net that looks like scattered confetti rather than
  a tree means the merge is wrong" [R]. Ravishankar: Graphviz with real coordinates [R].
- Silicon Atlas (ArkAung): a local browser tool that shows Verilog, netlist, placed layout and GDS
  geometry of the same register side by side, with a board editor that replays a changed input [R README].
- Aravapalli rebuilt eleven-cycle resets and ≥2 counters in CircuitVerse to watch them run [R].

### How they verified their extractors

This is the stage Jane Street's "Takeaways" cares about most. In order of strength:

1. **A known answer first** (warm-up), at every level of detail it ships: placements vs the DEF,
   connectivity vs the DEF net by net, the netlist as a graph isomorphism, an external SAT equivalence
   check, then function vs the published description (Shapovalov Table I, with a "What it would have
   caught" column) [R]. Shapovalov, Soto Franco, JGalil, Ebert and retrace all did some of this.
2. **Name-free isomorphism by colour refinement** (Weisfeiler-Leman), seeded from the ports, with pin
   names folded into edge labels and a *shared* signature table across both graphs. A discrete
   refinement (79 cells in 79 classes, 84 nets in 84) is a unique correspondence, a proof and not a
   count (Soto Franco §3.1; JGalil: 163 colours for 163 nodes; Shapovalov) [R]. Shapovalov's first two
   attempts failed in the *checker* (an edge comparison that assumed the two orderings were comparable;
   refinement run separately on each graph) [R].
3. **Net-partition comparison across extractors**, never names: compare which `(instance, pin)` sets
   share a net (Ebert 739 canonical endpoint partitions; JGalil 2,777/2,777 terminals, 0 merged, 0
   split; retrace V4) [R].
4. **Constructed inputs**: JGalil's `test_hierarchy.py` pushes every flattened cell's polygons, paths and
   labels into a new child cell referenced with a mirror and translation, pre-compensated so the
   composition is the identity, then requires byte-identical statistics, because neither shipped GDS is
   nested and the recursive walk would otherwise be untested [R]. Shapovalov's `ring.size() < 4` guard
   was caught by a unit test written before the extractor saw real data [R]. zaidharis7's
   `equiv-selftest` mutates the golden netlist and requires `NOT EQUIVALENT` with a counterexample [R].
5. **Two independent simulators required to agree on every verdict** (Soto Franco: 216 inputs; the
   disagreement located the tie-high defect) [R].
6. **Property-shaped unit tests** (Shapovalov: each cell's function re-derived as a truth table and
   compared with the PDK's model; the rectangle decomposer checked for area conservation and
   disjointness; the whole warm-up flow as one `ctest` case) [R].
7. **Auditing the harness itself** (Shapovalov: "A verification harness is code, and deserves the same
   suspicion as the thing it checks"; 96/230 was a harness bug) [R].
8. **Statement of what was not proved**: Wójcik's ZK proof binds a witness to a hash of the model but
   "does not prove that N was faithfully derived from the public GDS" [R]. That is exactly the gap our
   post-layout round trip fills.

### How their write-ups are structured (so the next person can follow)

- Soto Franco: a boxed "Standard of evidence" paragraph on page 1; "Corrected hypotheses" (§7.2) with
  the evidence that eliminated each; a reproduction table with one command per claim; `make all` ending
  on `tools/verify.py`, which "exits non-zero if any claim fails" [R].
- Shapovalov: an explicit ladder of five checks with "what it would have caught"; §VII "Errors made
  along the way" (each "produced plausible output"); Limitations that name what cell identity as a
  lookup cannot do; three conclusions in the order they mattered [R].
- asicrev README: every section tagged `[warm-up]`, `[target]` or `[both]` after a table of "the two
  layouts"; "Verification A" (what the warm-up establishes about the *tool*) separated from "Verification
  B" (what is established about the *target*) [R].
- umut: `docs/problems.md`, 57 entries, each with symptom, root cause, and a verdict from a closed
  vocabulary (**understood**, **worked around**, **retracted**); a README section "Why you should not
  believe any of that"; `tools/review_packet.py` runs 40 gates and one report and writes an evidence file
  stamped with the commit, refusing to write if it cannot substantiate its own tables; the CI badge covers
  a stated subset and the workflow says why (Docker, a 40-minute corpus, one gate red on purpose) [R].
- Stapleton: "Each stage produced a checkable artifact, listed here" and four named levels of abstraction
  [R]. Shi and Taboada open with an AI-use disclosure; Wójcik closes with one [R].

## 2. What Jane Street says it values: additions to the existing note

Nothing here duplicates `notes/asic-puzzle-results-hints.md` (checked by grep for the key phrases).
Quotes are verbatim except that typographic apostrophes are normalised. [R] throughout.

**Results post** (<https://blog.janestreet.com/asic-puzzle-results/>, 2026-10-02):

- On AI as tool-maker: "AI is going to be part of challenges like this, and it is a game changer for
  building analysis, netlist viewing, and debugging tools. Some entrants described using it for small
  scripts; others gave agents the whole puzzle."
- On AI as solver, with a value judgement: "When we first came up with the puzzle we also saw that the
  latest models could be given a single prompt and, in 30 minutes or less, come up with the final
  solution. Although this takes away a lot of the fun and learning from working through the puzzle!"
- On the tools: "Most solvers used KLayout, Yosys and Z3 alongside custom tools (many AI-written)
  implemented in Python, Rust, C++, OCaml, Haskell and even Odin." (Icarus, cocotb and Surfer are not in
  this sentence; they come from individual write-ups and the puzzle README.)
- On writing your own extractor: "Some folks, however, took on the extra challenge of writing their own
  netlist extraction tool." And of Shapovalov: "He then did a process of trial-and-error with the warm-up
  design to debug his pipeline before using it to extract the main puzzle GDS."
- On SAT-only answers: "The downside, however, of using a SAT solver for such a challenge is that it
  doesn't reveal much about the inner workings of the chip, just the necessary inputs to reach a desired
  output state." Aravapalli "found the best of both worlds".
- On visualisation as a window onto method: "One of the best ways to see how different people
  approached the challenge is via the visualizations they built!"
- On coverage of the field: "There were so many great write-ups that we didn't get to feature all of
  them". (So being featured is not a given, and the ranking by novelty of *method* is visible: SPICE,
  Minecraft, FPGA, zero-knowledge, impulse response, a hand-built C++ extractor.)

**Puzzle post** (<https://blog.janestreet.com/can-you-reverse-engineer-an-asic/>, August 2026):

- The AI rule, which the existing note does not carry: "Please don't feed the puzzle files directly
  into an AI tool, nor use it to generate your writeups. Feel free to use AI for writing any scripts or
  code you may need as part of solving the puzzle, though! It's also fair game to use AI to work through
  the warm-up puzzle, see below."
- Selection and reward: "We'll feature the most interesting writeups and techniques in a follow-up post,
  and send swag for our favorite solutions." Submission asked for "a brief description of how you did it".
- Embargo, which the competition post reverses: "please refrain from posting spoilers (or a full writeup)
  online until the submissions are closed." Competition: "there's no need to keep your work hidden until
  the deadline, so feel free to build in public!" (<https://blog.janestreet.com/protocol-emulator-asic-competition/>).
- The warm-up as a stated feature: "most people haven't [opened a GDS file]. To help you get started,
  we're providing a small worked example ... You can use it ... to test any tools you build before pointing
  them at the real puzzle." The winning solvers' method is exactly that advice.
- The sequel, flagged a month early: "Consider this puzzle a warm-up of its own. Later this year we'll
  be launching a competition where, instead of reverse engineering our chip, we'll challenge you to design
  your own - and the most interesting entries will actually get fabricated".

**Reading across the two posts.** Jane Street rewards (1) method over answer (SAT-only is marked as
the weaker route), (2) tooling you built *and checked*, (3) a visual a stranger can poke at, and (4)
human-written explanation: AI-written code is welcome, AI-written write-ups were asked against in the
puzzle post. The competition post has no equivalent sentence, so treat that as a taste signal and not a
rule (see section 4).

## 3. Adopt-next list

Size: S under a day, M a few days, L a week or more. "Value" is my judgement for the competition
entry, not a measured quantity. "Ours" says what exists today (read at
`prototypes/postlayout-roundtrip/` as of commit 7c3433b).

| id | Source [label] | Licence | Concretely adopt | Ours | Where | Size | Value |
| --- | --- | --- | --- | --- | --- | --- | --- |
| P1 | elementalcollision/retrace `tools/retrace/tech.py` (`IHP_SG13CMOS5L`) and `docs/TEMPO_LVS.md` §1-§3 [R doc]; IHP-GmbH/IHP-Open-PDK `ihp-sg13cmos5l/libs.tech/klayout/tech/sg13cmos5l.map` (dev branch) and `libs.ref/sg13cmos5l_stdcell/verilog/` [R] | Apache-2.0 both | Port the round trip to **the PDK the competition uses**. The map says "M1-M4-TM1 stack" and "Via4, Metal5, TopVia2, TopMetal2 not available in SG13CMOS5L PDK"; cells are `sg13cmos5l_*` (84 modules, same names as sg13g2; bodies differ and I did not diff them); models need `sg13cmos5l_udp.v`. From retrace's IHP findings: tie cells need no resistor cut; the antenna diode `antennanp` has a signal pin `A` and a real `VSS` tap; supplies are `VDD`/`VSS` on std cells and `VDD!`/`VSS!`/`VDDARRAY!` on the SRAM; macro pins live in the macro's top cell labels as `A_ADDR<9>` (193 pins, matching the LEF); power nets and single-pin CTS dummy-load nets are excluded from net comparisons and counted. | `extract.ml`, `cells.ml`, `roundtrip.sh`, `run_pnr.sh` all target `sg13g2` and list Metal5/TopMetal2 (`Via4` 66, `TopVia2` 133). The 202-second block run was `ihp-sg13g2`. | `prototypes/postlayout-roundtrip/` | M | very high: every number in its README is for a variant the shuttle does not use |
| P2 | Shapovalov (paper §II-B, II-D, Table I) [R]; asicrev MIT; retrace `tools/tempo/lvs.py` checks (a)-(c) [R doc]; JGalil `verify_warmup.py` [R README]; Soto Franco `compare.py` [R paper, no repo found] | asicrev MIT, retrace Apache-2.0, JGalil MIT, Soto Franco ideas only | Compare the extraction with the P&R run's own record, not only cell-type counts: (a) restore instance names by exact `(master, x, y, orientation)` against the DEF (mind the abutment-box offset and all eight orientations); (b) net pin-set partition against the DEF and `nl.v`; (c) optionally Weisfeiler-Leman refinement with pin names in edge labels and one shared signature table. | Per-cell-type counts equal LibreLane's (all 30 types); no per-net or per-placement comparison | `postlayout-roundtrip/check.ml` or a new `compare_def.ml` | M | high: a false merge or split that preserves cell counts passes today |
| P3 | Shapovalov §II-C(b) [R]; JGalil README "Implementation notes" [R] | MIT (JGalil) | Test the touch-versus-overlap rule: our `poly_intersect` (closed, boundary counts) is used for **both** same-layer joins and via-to-metal joins (`extract.ml` line 295). Both sources say vias need strictly positive overlap. Cheap experiment first: re-extract with strict overlap for vias and diff the net partition on our hardened GDS. If identical, record that and keep it as a regression; if not, find out why before anything else. | untested; I did not run it | `extract.ml` | S | medium-high (could be nothing, could be a silent false short) |
| P4 | retrace `tools/retrace/cellcheck.py` [R listing/doc; code not read] | Apache-2.0 | Compare every cell master embedded in the hardened GDS with the PDK's `sg13cmos5l_stdcell.gds`, layer by layer. In retrace's campaign the `cell_internal_tamper` mutants were killed by `cellcheck` and by simulation, and `cellcheck` flagged 26 of 91 non-equivalent mutants. | "Anything below Metal1" is explicitly trusted (README, "What it does not check") | new `cellcheck.ml` | S | high: closes a stated gap cheaply |
| P5 | Soto Franco §5.4 and §7.2(3) [R]; Ebert §4 three-valued simulator [R]; JGalil `simulate.py` [R README] | ideas only (Soto Franco, Ebert); JGalil MIT | Add an `X` value to `sim.ml`; for every flop without a reset, run both simulators over all 2^k power-up states (k was 4 in the puzzle) or prove the reset sequence covers it; report in the results. Run the gate-level netlist with the PDK's own model in Icarus as well, with the `UDP` file, `UNIT_DELAY=#0`, and watch for `X` from undriven delayed nets (Garner). | two-valued simulator; the tie-high plant exists | `sim.ml`, `test_cells.ml` | S-M | medium-high: power-up state is arbitrary in silicon |
| P6 | retrace `tools/retrace/mutate.py`, `test/mutation/campaign.py`, `docs/MUTATION.md`, `tools/tempo/faults.py` [R]; umut `--selftest` and "null models printed beside every score" [R README] | Apache-2.0; umut MIT text | Widen the planted faults and change what is reported. Operators: via delete, path widen to short, **cell flip (mirror in place)**, **master swap at identical footprint**, pin-label swap, **supply short inside one fill cell**, **rail open (every via stack removed from one VDD rail)**, near-miss shift (expected equivalent), path end type. Classify each mutant killed / equivalent (same partition and same `(master, x, y, orientation)` multiset) / survived, with a per-layer kill table. Choose sites by rule from the base extraction, record the seed, and make the neighbourhoods disjoint so each check must report **its own** fault and nothing else. Their survivor (`nor2_2` to `nand2_2`, same footprint) is invisible to every extraction-level check and only a behavioural oracle sees it; add that case and say so. | cuts, shorts, one crossed-wire class, a foreign-layer route; no master swap, mirror, supply or rail faults; no kill table | `mutate.ml`, `roundtrip_check.ml` | M | high: it is the single most reusable evidence in the whole field, and ours is already half-built |
| P7 | retrace `tools/l2n/` [R listing]; JGalil `klayout_check.py` [R README]; Ebert §3.4 [R]; IHP `ihp-sg13cmos5l/libs.tech/klayout/tech/lvs/{sg13cmos5l.lvs, run_lvs.py}` [R listing; contents not read] | Apache-2.0; MIT; ideas only; Apache-2.0 | A second, independent extraction (KLayout `LayoutToNetlist`, handed a flattened layout so it redoes placement and mirroring) compared as net **partitions** over `(instance@origin, pin)`, never names. This is V30 in `learned-from-others.md`; three solvers did it independently, and retrace's mutation data show it adds little on its own (19 of 91 mutants) but catches near-miss and flip classes the others miss. IHP ships its own LVS deck; try it on the hardened GDS against `nl.v` as a third opinion. | none | `postlayout-roundtrip/` | M | medium-high |
| P8 | asicrev `scripts/prove_rtl.sh` [R]; retrace `tools/analysis/e2e.py`, `formal/recovered_miter.sv` [R doc/listing]; Ebert §5 (Z3: circuit and rules agree for all 2^121 boards) [R] | MIT; Apache-2.0; ideas only | Formal equivalence of the extracted netlist and the hardened RTL on **one small block first** (the deadline sequencer): emit the extracted netlist as plain Verilog with primitive-only cell models (our `cells.ml` already reduces the PDK models to gates, which also avoids the Yosys-cannot-read-UDP problem), map flops to RTL by DEF name, `async2sync` then a miter (`sat -seq N`) or SymbiYosys `abc pdr`. Write down why the bound is complete (Shapovalov: all behaviour is reached within 121 cycles, so depth 128 is a proof) and keep a negative control (the planted master swap must fail it). COMP names formal methods first. | random lockstep only | new `formal/` beside the prototype | L | high; cost is the hours of solver time (Shapovalov: 332 minutes for 1.2 million variables) |
| P9 | umut `docs/problems.md`, `tools/review_packet.py`, `.github/workflows/gates.yml` [R]; retrace `docs/STATUS.md`, `ci.sh` and pinned image digest [R workflow] | umut MIT text (GitHub: NOASSERTION); retrace Apache-2.0 | Evidence discipline as artefacts: a problems register with a closed verdict vocabulary (**understood**, **worked around**, **retracted**); one command that runs every check and writes an evidence file stamped with the commit, refusing to write if a table cannot be substantiated; a CI that runs a declared subset and says why the rest is excluded; one gate deliberately red when a question is open; pin tool versions (LibreLane image digest, PDK commit, oss-cad-suite date) as retrace's workflow does. | results logs with commands and commit exist; no register, no single evidence run | `notes/` plus a make target | M | high: this is the "followable process" Jane Street thanked solvers for |
| P10 | Soto Franco, Shapovalov, asicrev README structure (section 1 above) [R] | structure only, no code | Write-up skeleton: boxed "standard of evidence" (what each claim was tested against, by something independent of the implementation, on RTL or gate-level or post-layout); "Corrected hypotheses" with the evidence that killed each; "Errors made along the way"; section tags by what a claim is about; a reproduction table with one command per claim; Limitations that name what is not covered. Disclose AI use per artefact with the check that constrains it (Shi, Taboada, Wójcik did this and Wójcik was featured). Write the prose by hand (see section 2). | notes are strong on this; the public write-up does not exist yet | the eventual submission write-up | S | high |
| P11 | van Driel and Post; Stapleton; ArkAung `docs/` [R] | none for any; Crameri colour maps are cited by van Driel (their licence not checked) | One page a stranger can poke at: (a) the sequencer stepped cycle by cycle (matches the existing note's rec. 5); (b) a layout/netlist/RTL viewer with **one shared ID** across panes, built on our own extraction (instances, nets and coordinates already exist in memory), so hovering a net in the layout shows the RTL signal and its waveform; (c) perceptually uniform colour for counts and time. | no viewer | `site/` or similar | M-L | high: Jane Street's stated favourite category |
| P12 | Taboada [R] | none (repo has no licence; the idea is in the blog) | Boundary-trace replay for block-level lockstep: record the signals at a block's boundary in the whole-chip run, replay them into the block, require identical outputs, so a block verified alone is verified on the stimulus it will actually see; and note that a hint box is not a clean cut (an AND inside the printer's box fed `success`). | block harnesses with their own stimulus; the README already says coherent stimulus reaches more | `generic_lockstep.ml` | S-M | medium |
| P13 | Garner §Analog simulation [R]; 4wirtc `sim/spice/` README [R] | none for both | Only if time allows: ngspice on the **delay chain** (our most distinctive feature), black-box: design-only handoff, ports only, forbidden directives list. Separately, check that every output pin is registered; Garner's SPICE run showed glitching on outputs driven straight from combinational gates. | none | `prototypes/delay-line/` | L | low-medium |

**Considered and not adopted:** Vargas's transistor-level recognition (our cells keep their names; keep
the idea of SPICE-versus-model per cell only if P4 finds a mismatch); Wójcik's zero-knowledge proof; the
Minecraft build; Cadence-flow specifics (Garner).

## 4. Top ten lessons, ranked

Ranking is by what would most improve the credibility of our entry per unit of work, not by how clever
the source was.

1. **Port the round trip to `sg13cmos5l` before quoting any round-trip number.** The IHP PDK repo says
   the CMOS5L stack is "M1-M4-TM1" and that Via4, Metal5, TopVia2 and TopMetal2 are "not available";
   retrace's IHP port was done on real `sg13cmos5l_*` masters. Our prototype was built and run on
   `sg13g2`. Sources: IHP-Open-PDK `sg13cmos5l.map` [R]; retrace `docs/TEMPO_LVS.md` §2 [R]; our
   `extract.ml`, `roundtrip.sh` [R]. (P1)
2. **Compare the extraction with the P&R run's own record per placement and per net, not by cell-type
   counts.** Shapovalov's ladder (placements, connectivity net by net, isomorphism, external SAT
   equivalence, function) and retrace's V1/V3 are the standard. Include the origin-versus-abutment-box
   trap and all eight orientations. Sources: Shapovalov Table I [R]; retrace [R]; JGalil [R]. (P2, P3)
3. **Close the "below Metal1 is trusted" gap with a cell-master comparison against the PDK's cell
   GDS.** Small, and it killed a mutant class nothing else did. Source: retrace `cellcheck`. (P4)
4. **Make the simulator three-valued and enumerate power-up states of unreset flops.** Soto Franco's
   refuted hypothesis hid a real bug until unknowns were given definite values. Sources: Soto Franco §5.4,
   §7.2 [R]; Ebert §4 [R]; JGalil [R]. (P5)
5. **Turn planted faults into a campaign with a kill table, "equivalent" mutants explained, a survivor
   admitted, and each check required to find its own fault.** retrace's result (130 mutants, 90 killed,
   39 equivalent, 1 survivor that only behaviour can see) is the template. Sources: retrace
   `docs/MUTATION.md`, `faults.py` [R]; umut null models [R]. (P6)
6. **Two independent solvers disagreeing is the finding; a single trace agreeing is not evidence.**
   Soto Franco's trace passed 623/623 with every tie-high cell wrong, and Jane Street quoted it. The
   consequence for us is an independent second extractor and, better, an independent *simulator* of the
   same netlist, required to agree on random inputs. Sources: Soto Franco §3.2, §3.4 [R]; results post
   [R]. (P7, partly P5)
7. **Prove one block equivalent formally, with a stated reason that the bound is complete and a
   negative control.** Shapovalov's 128-cycle miter and Ebert's all-boards proof are the models;
   COMP names formal methods first. Sources: asicrev [R]; retrace [R]. (P8)
8. **Keep a problems register and one evidence command, with a CI that admits its own boundary.** umut's
   `problems.md` (57 entries; verdicts understood, worked around, retracted), `review_packet.py` and the
   deliberately red gate are the best documentation-of-process in the field. (P9)
9. **Structure the write-up around the standard of evidence, with corrected hypotheses and errors made
   along the way, and write its prose by hand.** Soto Franco and Shapovalov were both featured; the
   puzzle post asked for human-written write-ups. (P10)
10. **Give them something to poke at: an interactive explainer with a shared-ID layout/netlist/RTL view.**
    Jane Street called van Driel's page "possibly our favorite" and Stapleton's viewer worth featuring;
    our extracted instances and nets already carry the data. (P11)

## 5. Anything that contradicts or corrects `notes/asic-puzzle-results-hints.md`

1. **Misattribution.** The old note says Soto Franco's section 7 "records three refuted hypotheses and
   was called out as characterising the design". The results post does not say that. "Section 7
   records them, since each characterises the design" is Soto Franco's own sentence on page 1 of his PDF
   [R]. The advice (record refuted hypotheses) stands; the attribution to Jane Street does not.
2. **Conflated tool list.** The note's "Tooling used by entrants: KLayout, Yosys, Z3, Icarus, cocotb,
   Surfer-style waveform viewers" mixes three sources. The results post names only KLayout, Yosys and Z3;
   Icarus is in Soto Franco's and others' write-ups, cocotb in Shi's, Surfer in the puzzle repository's
   README [R]. Minor.
3. **An omitted rule that matters for rec. 2.** The note recommends being candid about AI use. Correct,
   but the puzzle post also said "nor use it to generate your writeups". The competition post has no
   such sentence, so this is a taste signal and not a rule; it argues for hand-written prose and AI
   disclosure on the code and the checks, which is what the featured Shi/Taboada/Wójcik disclosures do.
4. **"Verify the gate-level netlist" (rec. 8) is not yet true of our tree for the right PDK.** The note
   reads as if our post-layout round trip already covers the shuttle flow. It covers `sg13g2`. See P1.
5. **Our round trip is not unique.** The note's rec. 13 treats a public verification log as something
   that sets us apart. retrace's author is a competitor who has already built an
   independent LVS of his own Tiny Tapeout design on `sg13cmos5l`, a 130-mutant campaign and a pinned CI
   [R]. Do not claim novelty for the round trip as such; what can still be distinctive is what it
   checks that his does not (a lockstep against the Hardcaml RTL with a generic random-input harness, the
   crossed-wire class, and, if P8 lands, a formal proof on our own block).
6. **Gap closed.** The note's §6 said Shapovalov, Ravishankar, Aravapalli, Taboada, Vargas and Wójcik
   were not read in depth. They have now been read (see "Read in full" above), and Ebert's and Kaniyeri's
   Google Drive links were fetched (Ebert read; Kaniyeri's is an mp4, not watched).

## 6. Cautions and limits

- Everything about retrace, asicrev, umut and JGalil beyond their READMEs and docs is from listings;
  I did not run their code or read their extractors line by line. Before building on one of them, read
  the file.
- retrace's results are its author's claims (it says it was "Built with Claude Code after the contest
  deadline"); the 130-mutant table is the author's, and its numbers were not reproduced.
- umut's GitHub licence field says NOASSERTION; the LICENSE file is MIT text. Treat it as MIT, but ask
  before copying files.
- The puzzle files (`janestreet/asic-puzzle-2026`) have no licence. retrace and umut avoid
  redistributing them; so should we.
- Soto Franco, Shapovalov (paper), Stapleton, Garner and Ebert were read as PDFs or pages; the
  repositories behind them either do not exist publicly (Soto Franco, Stapleton, Ebert) or are listed
  only (`FigureZig/asicrev` MIT is Shapovalov's). Ideas only for anything without a repository.
- I did not check Crameri colour-map licensing, IHP's KLayout LVS deck contents, or whether
  `sg13cmos5l_stdcell.v` and `sg13g2_stdcell.v` differ in behaviour (they differ textually after
  renaming the prefix; the 3,228-line diff was not examined).
- P3 is a suspicion from two independent sources and one line of our code, not a measured bug.

## Sources (fetched 2026-10-05)

- Jane Street: <https://blog.janestreet.com/asic-puzzle-results/>,
  <https://blog.janestreet.com/can-you-reverse-engineer-an-asic/>,
  <https://blog.janestreet.com/protocol-emulator-asic-competition/>,
  <https://blog.janestreet.com/using-ascii-waveforms-to-test-hardware-designs/> (Andrew Ray, 2020).
- Write-ups: Soto Franco <https://www.sotofranco.dev/pdfs/asic-reverse-engineering.pdf>; Shapovalov
  <https://figurez.s-ul.eu/i6GwNvSU.pdf>; Shi <https://pakkachan.github.io/asic/>; van Driel and Post
  <https://kjartanvandriel.github.io/asic/>; Ravishankar <https://hackmd.io/@sanrav2016/fh9_eHBIQ_upRtm6F9S4wA>;
  Aravapalli <https://avnlk.github.io/reverse-engineering-an-ASIC.html>; Taboada
  <https://gabbytab.github.io/blog/asic-puzzle-2026/>; Vargas
  <https://jlvargasme.github.io/posts/reverse-engineering-an-asic.html>; Stapleton
  <https://js-chip-solution.vercel.app/>; Garner
  <https://github.com/davidg351/Jane-Street-Puzzle-August-2026/blob/main/JaneStreetPuzzleWriteup_DavidGarner_FINAL.pdf>;
  Smallwood <https://raw.githubusercontent.com/alexseekingalpha/jsasicsolved/main/myjanestreetwriteup.pdf>;
  Wójcik <https://synhex.com/notes/jane-street-puzzle-solution.html>; Ebert (Google Drive, linked from the
  results post).
- Repositories: elementalcollision/retrace, FigureZig/asicrev, umutdinceryananer/asic-reverse-engineering,
  JGalil/gds2netlist-asic-puzzle, zaidharis7/asic-reverse-eng, 4wirtc/Janestreetproblem_PuzzleSolution2026_Christian_Philipp,
  ArkAung/silicon-atlas, GabbyTab/asic-puzzle-2026, sanrav2016/asic-puzzle-2026, shaikhmubin02/asic-puzzle-2026-solution,
  stephenebert/asic-puzzle-solver, davidg351/Jane-Street-Puzzle-August-2026, NotCleo/GDS-to-RTL,
  IHP-GmbH/IHP-Open-PDK (dev). Commits and licences in `notes/learned-from-puzzle-solvers-licences.txt`.
- Searches run: `gh search repos` for "jane street asic puzzle", "star battle gds", "two not touch asic",
  "sky130 reverse engineer gds netlist", "puzzle.gds", "asic-puzzle-2026", "gds2netlist", "asicrev" and
  similar (about 20 queries; roughly 50 distinct repositories surfaced, about half cloned or inspected).
