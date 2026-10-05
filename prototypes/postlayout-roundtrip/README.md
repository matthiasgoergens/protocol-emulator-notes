# Post-layout round trip: from our own GDS back to the RTL

Tiny Tapeout's precheck runs DRC and a handful of structural checks, but no LVS, so nothing in the
shuttle flow tells us that the routed layout is the circuit we simulated. This directory closes that
loop independently of the place-and-route tools: it reads the final GDS, extracts a gate-level
netlist from the metal geometry alone, checks its structure, and runs it cycle by cycle against the
Hardcaml RTL.

## Credit

The method and much of the code come from Matthias's solution to Jane Street's August 2026 ASIC
reverse-engineering puzzle (`~/prog/janestreet/hardware-2026-08`): the from-scratch GDSII parser
(`oxcaml/gds.ml`, copied here with AREF support and element byte ranges added), the extractor's
union-find over conductor shapes with pins found from the cells' own labels (`oxcaml/extract.ml`,
after `work/extract.py`), and the idea of interpreting the PDK's Verilog cell models as gate
primitives (`oxcaml/cells.ml`, `oxcaml/sim.ml`). The undriven-net check comes from the same puzzle:
its chip shipped with a floating net, which a SAT solver treats as a free variable and a simulator
reads as 0, so both kinds of tool agree with the broken chip unless the structure is checked first.

## What changed for IHP SG13G2

- **Layers** from the PDK's KLayout map (`libs.tech/klayout/tech/sg13g2.map`): Metal1 8, Metal2 10,
  Metal3 30, Metal4 50, Metal5 67, TopMetal1 126, TopMetal2 134 (drawing datatype 0, pin datatype 2);
  Via1 19, Via2 29, Via3 49, Via4 66, TopVia1 125, TopVia2 133 (datatype 0); pin-name text on datatype
  25; fill on datatype 22 is ignored. Cont (6) is mapped but deliberately not followed: it leads into
  diffusion and poly, through which every cell would short its input to its output. Below Metal1 the
  PDK's cells are trusted, so the extracted netlist is at gate level.
- **Pins** from the cell GDS's own labels (`sg13g2_stdcell.gds`, layer 8/25), transformed by each
  placement; top-level ports from the top cell's labels on Metal2/Metal3 (10/25, 30/25).
- **Functions** from the PDK's Verilog models (`sg13g2_stdcell.v`), not from the liberty files
  that synthesis mapped against, so the simulator does not share its source with the thing being
  checked. Added: the `ihp_mux2`/`ihp_mux4` primitives, the flip-flop primitives
  (`ihp_dff_r`, `ihp_dff_sr_*`), constants in tie cells, the `delayed_X` aliases. Latches,
  tristate drivers and `inout` cells are recognised and rejected.

## Files

| file | what |
| --- | --- |
| `gds.ml` | GDSII parser and hierarchy flattening (from the puzzle solution) |
| `extract.ml` | SG13G2 and SG13CMOS5L layer maps, connectivity, pins and ports, routing on unknown layers |
| `cells.ml` | reads the PDK Verilog models into gates and flip-flops |
| `sim.ml` | two-valued cycle simulator of the extracted netlist |
| `check.ml` | structural checks |
| `mutate.ml` | writes GDS copies with an element removed or a rectangle added |
| `roundtrip_check.ml` | block-independent: `check` and `controls` (planted cuts and shorts) |
| `test_cells.ml` | Verilog-model interpreter against the liberty functions, every cell, exhaustively |
| `test_via_overlap.ml` | synthetic GDS cases for the join rule (vias must overlap, same-layer metal may abut) |
| `generic_lockstep.ml` | block-independent lockstep: random values on every input, every output compared |
| `seq_lockstep.ml` | the deadline sequencer's lockstep with its real harness, plus planted crossed wires |
| `compare_def.ml` | the extraction against the run's DEF and `nl.v`, per placement and per net, as partitions |
| `run_pnr.sh` | LibreLane 3.0.14 in its container, in a scratch directory, keeping the GDS (`sg13g2` or `sg13cmos5l`) |
| `roundtrip.sh` | the whole round trip for one block |
| `results/` | the logs behind every number below |

Build: `opam exec --switch=5.3.0 -- dune build` (Hardcaml v0.17 for the lockstep only; the rest is
the OCaml standard library). `isa.ml`, `sequencer.ml`, `harness.ml` are links into
`../deadline-sequencer`.

## The structural check

Run before any simulation, because a simulator hides exactly these faults:

- every net has exactly one driver (a cell output or an RTL input port), and every net that is read
  has one: undriven and multiply driven nets are errors;
- every cell input pin has metal under its label (a floating input is an error);
- every flip-flop clock pin leads back to the clock port through buffers and inverters only, with an
  even number of inversions, and the cell model clocks its flip-flop from that pin;
- no signal pin sits on a supply net (the VPWR/VGND grid labels mark those nets);
- the layout's port labels are exactly the RTL's ports, bit by bit, each on one net;
- the routing (shapes in the top cell itself) uses no layer the extractor does not follow.

## Results on the deadline sequencer

Fresh place and route of the current `../deadline-sequencer/deadline_sequencer.v` (with the
quarter-clock ports; the earlier run kept no GDS): LibreLane 3.0.14, 15 ns, 202 s wall time, die
39,781 um2, 2,017 standard cells besides fill and decap, worst setup slack +7.0 ns at the slow
corner. All logs are in `results/`; the GDS and run directory are in
`/var/tmp/postlayout-roundtrip/pnr/runs/seq15ns/`.

| step | result | time |
| --- | --- | --- |
| cell models against liberty | 2,636 comparisons, 0 disagreements (14 latch, tristate, sighold cells skipped) | < 0.1 s |
| extraction | 60,230 conductor shapes, 6,495 components, 2,017 instances, 2,086 nets | 0.4 s |
| per-cell-type counts | equal to LibreLane's own final netlist, all 30 types | |
| structural check | clean: 0 undriven, 0 multiply driven, 0 floating inputs, 189 flip-flops all on the clock tree; 3 driven nets nobody reads | 2 ms |
| lockstep with the sequencer's harness | 300 programmes x 2,000 cycles, every output bit every cycle: 0 mismatching cycles, 2.89 million output-bit toggles | 46-52 s |
| generic random-input lockstep (clear pulsed 1 cycle in 64) | 300 runs x 2,000 cycles: 0 mismatching cycles | 47 s |

The lockstep compares the GDS against `Sequencer` as built from the current sources, so it would
also catch a stale `deadline_sequencer.v`.

### Planted faults

Every check above was made to fail on purpose, because a check that has never failed may be
checking nothing.

- **Cell models:** with `or` changed to `and` in `sg13g2_a21oi_1` and the tie-high cell made to drive
  0 (`results/test_cells_planted.log`), the model-against-liberty test reports 5 disagreements. (One
  entrant's model of the puzzle chip reproduced the sample waveform with every tie-high cell wrong.)
- **Cuts and shorts in the GDS** (`roundtrip_check.exe controls`, seed 1): 10 copies with one
  random top-level via or Metal2/Metal3 shape removed, 10 with a Metal2 rectangle joining a wire to
  the nearest wire of another net. All 20 changed the connectivity (net count +1 or -1/-2) and all
  20 were caught by the structural check. The lockstep (20 programmes each) caught 17. The three it
  missed show why the structural check comes first: a cut net that the simulator reads as 0 and
  that happened not to matter on these programmes, a cut in the clock tree (the simulator clocks
  every flip-flop regardless, as any cycle simulator would), and a short whose two drivers the
  simulator resolves silently by evaluation order.
- **A route on a layer the extractor ignores** (a rectangle on layer 11/0, written by gdstk, a
  different GDS writer, so this also cross-checks the parser: 2,086 nets either way): reported.
- **Crossed wires** (`seq_lockstep.exe --swaps 50 1`): two input pins of different cells exchange
  nets in the extracted netlist. Every net keeps one driver, so this is the fault class only
  behaviour can see. With 20 programmes each: 44 of 50 differ from the RTL (one of them by making a
combinational loop), 1 is caught only structurally (a cell input swapped with a flip-flop's clock
pin, which the clock-tree check sees and a cycle simulator cannot), and 5 by neither. Re-running
those 5 with 300 programmes catches 2 more and leaves 3, each explained by tracing the netlist:
two swap buffered copies of one signal (both nets lead back through buffers to the same driver, so
the swap is no fault) or two clock-tree leaves (skew aside, also no fault); the third crosses a
tie-high with a buffered "not clear". That one is a real fault, invisible to the sequencer's
harness because it asserts `clear` only at the start. The generic lockstep, which now pulses
`clear` on one cycle in 64, catches it (1,692 mismatching cycles in 20 runs;
`results/lockstep_generic_swaps.log`). So the only crossed wires nothing catches here are the two
that are not faults.

A planted fault counts only when it changes the connectivity (the number of pin-carrying nets for
the GDS controls). A first version of the short planting put the rectangle between bounding-box
centres, which lie outside L-shaped wires; two "shorts" touched nothing and were reported as
missed. They are now planted from a vertex and checked for effect, so a no-op plant is reported as
such rather than counted.

### Touch versus overlap at vias

Two solvers of the puzzle found independently that a via joins a metal only where the cut overlaps
it with positive area, while shapes on the same metal that merely abut are one wire (Shapovalov's
paper on [FigureZig/asicrev](https://github.com/FigureZig/asicrev), section II-C, and the README of
[JGalil/gds2netlist-asic-puzzle](https://github.com/JGalil/gds2netlist-asic-puzzle)). Our extractor
used one closed intersection test for both. `test_via_overlap.ml` writes eleven two-port cases to a
GDS and reads them back through the extractor: before the change, four were wrong (a cut sharing
only an edge with Metal1, only an edge with Metal2, only a corner, and only a vertex of a diagonal
edge were all joined; `results/test_via_overlap_before.log`). Via-to-metal joins now require
positive clipped area, and the eleven cases pass (`results/test_via_overlap.log`). On the
sequencer's GDS the change does nothing: the extracted netlist is byte-identical, 0 via-metal pairs
touch without overlapping (the extractor now counts and logs them), and the 20 planted controls give
the same log as before. So this was a latent false short that LibreLane's routing never produced,
and the eleven cases stay as a regression test.

## Port to SG13CMOS5L, the shuttle's PDK

Tiny Tapeout's IHP shuttle uses `sg13cmos5l`, not `sg13g2`: its layer map says "M1-M4-TM1 stack"
and "Via4, Metal5, TopVia2, TopMetal2 not available". Everything above was measured on `sg13g2`, so
the round trip was ported and rerun on the same block. The variant's facts below agree with what
[elementalcollision/retrace](https://github.com/elementalcollision/retrace) found for its own
`sg13cmos5l` LVS (`tools/retrace/tech.py`, `docs/TEMPO_LVS.md` section 2, Apache-2.0); our tables
were written from the PDK files, no code was copied.

- **PDK.** ciel 3.0's `ihp-sg13` releases do not carry the revision Tiny Tapeout pins, so the PDK
  is a checkout of IHP-Open-PDK 2bbec755 made with `install_sg13cmos5l.sh` from
  TinyTapeout/tt-gds-action (branch `ihp-cmos5l`), in `/var/tmp/roundtrip-cmos5l/pdk`; the shared
  `~/.ciel` is untouched. `run_pnr.sh BLOCK SCRATCH TAG ihp-sg13cmos5l` with `PDK_ROOT` set uses
  it, mounted read-only.
- **Layers.** Same numbers as `sg13g2`, five metals, and one trap: TopVia1 (125) joins **Metal4** to
  TopMetal1 here, not Metal5. With the `sg13g2` table the 38 TopVia1 cuts in this block would hang
  the TopMetal1 power straps (57 shapes, carrying `VPWR`/`VGND` labels) on a Metal5 that does not
  exist. The extractor now reads the variant from the GDS's cell names, refuses a GDS that mixes
  both libraries, and logs which table it used (`extract.ml`, `sg13g2` and `sg13cmos5l`).
- **Cells.** Same 84 cell names; the user primitives moved to `sg13cmos5l_udp.v` and their tables
  are identical to `sg13g2`'s apart from comments and spacing. Two model changes broke our reader:
  `sighold` has an `` `ifdef DISPLAY_HOLD `` branch with a drive-strength `buf` (the tokenizer now
  follows `` `define``/`` `ifdef``/`` `else``/`` `endif `` and reads the branch a plain simulator would),
  and every flip-flop ties its error input with `buf (xcr_0, 0)`, a bare `0` that read as a wire
  and made all nine flip-flop types look like combinational loops (bare `0`/`1` are now constants).
  After that the model-against-liberty test gives the same 2,636 comparisons and 0 disagreements as
  on `sg13g2`, with the same 14 latch, tristate and sighold cells skipped; the two planted model
  faults give 5 disagreements, as before (`results/sg13cmos5l/test_cells*.log`).
- **Tie cells, antenna diodes, supplies.** `tiehi`/`tielo` outputs are their own Metal1 islands
  (we never follow Cont, so no resistor cut is needed; retrace verified the same with poly joined).
  `antennanp` is kept as an instance, its pin `A` a load; the flow inserted none in this block.
  Cell supplies are `VDD`/`VSS` (not extracted as pins); the block's supply ports are `VPWR`/`VGND`
  on Metal4 and TopMetal1.
- **Orientations.** The comparison below maps all eight LEF/DEF orientations from the reference's
  transform; this block uses N, S, FN and FS. For E, our map gives DEF y = GDS y - width, the
  formula retrace derived from its SRAM macro.
- **Place and route** (`results/sg13cmos5l/`): LibreLane 3.0.14 in its container cannot finish a
  `sg13cmos5l` run. The PDK's Magic techfile requires Magic 8.3.657 and the image has 8.3.623;
  Magic then fails to read the DEF ("No cut layer") and spins at 100% CPU with an empty log (13
  minutes in `Magic.StreamOut`, 7 in `Magic.WriteLEF`; 4 and 8 s on `sg13g2`). Every step up to
  and including KLayout's stream-out (the primary GDS writer) completes, so the round trip uses
  that step's GDS and the DEF and `nl.v` it was written from (steps 56, 53, 52), and the run was
  stopped there. Tiny Tapeout's own action installs LibreLane 3.1.0.dev3, which presumably carries a
  newer Magic; not tried here. Same design and constraints as above: die 190.31 x 209.03 um,
  2,983 components (2,016 logic cells), worst setup slack +6.69 ns at the slow corner, no hold,
  slew or capacitance violations (`sta_summary.rpt`).

| step | sg13cmos5l result |
| --- | --- |
| extraction | 84,198 conductor shapes, 6,491 components, 2,016 instances, 2,085 nets, 0.40 s |
| structural check | clean: 0 undriven, 0 multiply driven, 189 flip-flops on the clock tree, 3 unread (the CTS dummy loads) |
| lockstep with the sequencer's harness | 300 programmes x 2,000 cycles: 0 mismatching cycles, 2.89 million output-bit toggles |
| generic random-input lockstep | 300 x 2,000 cycles: 0 mismatching cycles |
| planted cuts and shorts (seed 1) | 16 of 16 effective caught structurally (4 cuts removed redundant patches and had no effect); lockstep 13 of 16 |
| crossed wires (`--swaps 50 1`, 20 programmes) | 47 differ, 1 caught only structurally, 2 by neither |

KLayout writes a different GDS from Magic: wires as paths and vias as references to `VIA_*` cells,
where the `sg13g2` GDS (Magic's) has every wire and cut flattened into boundaries. The first
`sg13cmos5l` controls run therefore cut only boundaries, which here are redundant patches: 10 of 10
cuts had no effect. The cut planting now also removes paths and via references (27,220 candidates:
2,630 boundaries, 12,225 paths, 12,365 via references); on `sg13g2` it picks the same ten elements
as before. Two via-metal pairs in this GDS touch without overlapping (a Via1 and a Via2 abutting the
ends of short Metal2 pieces at one stack); both pairs lie in one component anyway, so the
touch-versus-overlap rule changes nothing here either, and the extractor now names such pairs.

## Per placement and per net against the P&R run's own record

Equal per-cell-type counts would pass a layout with two nets swapped or merged elsewhere.
`compare_def.exe GDS TOP DEF NL.V CELL.LEF` compares the extraction with LibreLane's DEF and final
netlist element by element, following the ladder in Shapovalov's paper
([FigureZig/asicrev](https://github.com/FigureZig/asicrev), Table I) and retrace's checks (a)-(c)
(`docs/TEMPO_LVS.md` section 1.5):

- **Placements.** Each standard-cell reference in the GDS becomes the DEF's
  `(master, x, y, orientation)`: the orientation from the reference's transform (all eight), the
  position as the lower-left of the transformed LEF abutment box, which for a flipped or rotated
  cell is not the GDS origin. The LEF box is checked against each cell's own prBoundary (189/4)
  first. Every extracted instance takes its DEF name from that key.
- **Nets**, against DEF `NETS` and separately against `nl.v`: each net is the set of its endpoints,
  `(instance, pin)` or `(PIN, port)`, and the two sides are compared as partitions, never by net
  name; a differing net is reported as split or merged. Supply nets are in neither record's signal
  nets and are left out, counted; a pin on no wire (a clock-tree dummy load's output) is a
  one-endpoint net in the extraction and absent from the record, which is the same partition, so
  those are set aside and listed.

| | sg13g2 | sg13cmos5l |
| --- | --- | --- |
| abutment box equals prBoundary | 34 of 34 cell types | 33 of 33 |
| placements matched | 2,867 of 2,867 (N 993, S 488, FN 533, FS 853) | 2,983 of 2,983 (N 1,068, S 486, FN 531, FS 898) |
| matched if the GDS origin were taken as the DEF position | 1,033 | 1,101 |
| extracted instances named from the DEF | 2,017 of 2,017 | 2,016 of 2,016 |
| nets identical as endpoint sets, vs DEF and vs `nl.v` | 2,081 of 2,081 (6,145 endpoints) | 2,080 of 2,080 (6,143 endpoints) |
| pins on no wire set aside | 3 (`clkload0-2/Y`) | 3 (`clkload0-2/Y`) |

The origin-as-position row is the trap Shapovalov describes (his check scored 96 of 230 before he
compared transformed boxes): about two thirds of the placements here are in flipped or rotated rows.

Controls, each of which must make the comparison fail and point at its own fault
(`results/compare/`): a planted cut splits exactly one record net (sg13g2 `cut01`, `cut02`;
sg13cmos5l `cut01`, and `cut10`, which the lockstep missed); a planted short merges exactly two
(sg13g2 `short01`, `short02`; sg13cmos5l `short03`, also missed by the lockstep); one inverter
mirrored in place and one `nand2_1` replaced by the `nor2_1` of the same footprint
(`plant_placement.py`, written with gdstk) each leave exactly one DEF component unmatched, named,
and one instance unnamed. The master swap is the case retrace reports surviving every
extraction-level check of its own; here the placement key includes the master, so it is caught.

## What it does not check

- Anything below Metal1: the cells' transistors, contacts and poly are trusted as the PDK's.
- Timing, skew, antenna and electrical rules: this is connectivity and logic only (STA and DRC are
  LibreLane's and the precheck's).
- Faults that do not change behaviour on the programmes run; the structural check has no such gap
  for opens and shorts between driven nets, but a crossed wire between two nets is only as visible
  as the stimulus makes it.
- A cross-model review (`results/codex-review.md`) found four gaps, now closed: routing on a layer
  the extractor does not follow would silently split a net (now an error, with a planted control);
  the clock check did not confirm the model's flip-flop is clocked from the cell's clock pin; a
  lockstep with no outputs, or none that ever change, would report agreement (now refused); and
  malformed GDS record lengths were not rejected.
- The deeper review question of whether a cut can leave the net count unchanged while still moving
  a pin: for one removed shape it cannot (the pins left on each side either still share a net or
  form a new one), so the effect test is sound for these single-element plants, not in general.

## Cost and how to make it routine

The round trip costs well under a minute against a few minutes of place and route: 0.4 s to
extract, milliseconds to check, about 8 s for ten planted GDS faults, and 50 s for 600,000 cycles of
lockstep. It needs no new tools: OCaml, the PDK files LibreLane already uses, and Hardcaml for the
lockstep.

For every block: after `run_pnr.sh`, run

    ./roundtrip.sh RUN/final/gds/TOP.gds TOP RTL.v OUTDIR [LOCKSTEP_EXE RUNS CYCLES]

which runs the cell-model test, the structural check, five cuts and five shorts (and fails if any
effective one is missed), and the block's lockstep if it has one. `generic_lockstep.ml` needs only
the block's `Circuit.t`, so a block without its own harness still gets a random-input lockstep; a
block with a harness should use it as well, since coherent stimulus (here, a real instruction
memory) reaches states random inputs do not.

For the whole chip later, the same extraction should scale linearly (a spatial hash, no all-pairs
step): 24 tiles of about 1,000 cells is about twelve times this block, so seconds to extract and
roughly ten minutes for the same 600,000 cycles at this simulator's speed (about 13,000 cycles per
second here for 3,756 gates, both simulators included), or bit-parallel lanes if that becomes the bottleneck. Two additions are needed first: macros
(the SRAM) need their pin labels mapped and a behavioural model on the simulator side, and the Tiny
Tapeout wrapper's port names must be mapped to the RTL's.
