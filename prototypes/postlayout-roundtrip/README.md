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
| `extract.ml` | SG13G2 layer map, connectivity, pins and ports, routing on unknown layers |
| `cells.ml` | reads the PDK Verilog models into gates and flip-flops |
| `sim.ml` | two-valued cycle simulator of the extracted netlist |
| `check.ml` | structural checks |
| `mutate.ml` | writes GDS copies with an element removed or a rectangle added |
| `roundtrip_check.ml` | block-independent: `check` and `controls` (planted cuts and shorts) |
| `test_cells.ml` | Verilog-model interpreter against the liberty functions, every cell, exhaustively |
| `generic_lockstep.ml` | block-independent lockstep: random values on every input, every output compared |
| `seq_lockstep.ml` | the deadline sequencer's lockstep with its real harness, plus planted crossed wires |
| `run_pnr.sh` | LibreLane 3.0.14 in its container, in a scratch directory, keeping the GDS |
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
