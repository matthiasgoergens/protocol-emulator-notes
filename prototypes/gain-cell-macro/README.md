# Gain-cell memory bank as a macro for sg13cmos5l (2026-10-06)

Work in progress; one section per milestone. The cell is the thick-oxide 3T cell of
`../gain-cell/` (write transistor W 0.15 / L 0.45 dogbone, thin storage and read transistors
W 0.30 / L 0.13). Target: IHP sg13cmos5l (Metal1–Metal4 and TopMetal1 only), IHP-Open-PDK
2bbec755 at `/var/tmp/roundtrip-cmos5l/pdk`, the revision Tiny Tapeout pins. Every DRC and LVS
here runs IHP's own sg13cmos5l KLayout decks in the pinned LibreLane image
(`tools/librelane-tt`, KLayout 0.30.9).

## 1. Port of the cell and array to sg13cmos5l

**Layers.** The cell and its straps use Activ, GatPoly, Cont, Metal1, Via1, Metal2,
ThickGateOx and pSD; the macro edges add Via2, Metal3, Via3 and Metal4. All exist in
sg13cmos5l with the same GDS numbers (`sg13cmos5l.lyp`, and `layers_def.drc` of the DRC deck).
The cmos5l deck's forbidden-layer table (`3_2_forbidden_cmos5l.drc`) bans Metal5, Via4,
TopMetal2, TopVia2, TRANS, nBuLay, MIM and Vmim, none of which the cell uses. ThickGateOx is
allowed and has its own rule table (`5_7_thickgateox.drc`).

**DRC** (`drc.sh`, density off since it is a whole-chip rule):
- the unchanged `../gain-cell/draw2.py` array (8 columns × 4 rows, thick, dogbone): clean
  (`drc/m1-ARRAY_3T_thick_L45n_8x4.log`);
- the macro array `GC_ARRAY_32x38` (below): clean (`drc/m1-GC_ARRAY_32x38.log`). It took four
  fixes, all at the new edges: Metal1 and Metal3 pads below the minimum area (M1.d, M3.d), the
  bit-line Metal2 end caps (M2.c1), Activ enclosure of the strap contacts at the array's left and
  right ends, where no tile abuts (Cnt.c), and a pSD area (pSD.k).

**LVS** (`lvs.sh`, the PDK's `run_lvs.py` comparing against the schematic `gc_array.py` writes):
`GC_ARRAY_32x38` matches, 1,216 sg13_hv_nmos W 0.15 L 0.45 and 2,432 sg13_lv_nmos W 0.30 L 0.13
(`lvs/m1-GC_ARRAY_32x38.log`, `lvs/m1-GC_ARRAY_32x38.extracted.cir`). A planted error, one read
transistor's gate moved to the other row's word line in a 2 × 2 schematic, fails as it should
(`lvs/m1-planted-2x2-wrong-rwl.log`).

**An LVS finding about the old strap.** In `draw2.py` the storage transistors' source bar
(N+) meets its substrate tie (P+, under pSD) by abutment, and the only contact sits on the P+
part. Silicide joins the two in silicon, but the LVS deck does not model silicide, so it
extracted every bar as a floating net. The old "LVS" in `../gain-cell/lvs/` was extraction only,
with no comparison, and this went unnoticed there (`../gain-cell/lvs/3T/extracted.cir`: the
storage transistors' sources are `$11` and `$12`, not GND). The macro's strap (`strap_gc` in
`gc_array.py`) stops the pSD 0.09 µm past the P+ contact and adds a second contact on the N+
part, joined in Metal1; LVS then sees the bar on GND.

**Retention SPICE** (`spice/run.sh`, which runs `../gain-cell/retention/*.py` unchanged against
either PDK; all results in `spice/results/`).

What differs between the old PDK (ciel c4b8b4e5, every number in `../gain-cell/`) and 2bbec755:
- the MOS model cards are byte-identical except the default of `mm_ok` (mismatch on or off) in
  `sg13g2_mos{lv,hv}_mod.lib`, which the nominal subcircuits do not use. sg13cmos5l ships the
  same `sg13g2_*` model files as sg13g2 at the same revision;
- the PSP compact-model code moved from 103.6 to 103.8.2 (`libs.tech/verilog-a/psp103`), which
  `spice/run.sh` compiles with openvaf-r. **PSP 103.8.2 adds `gmin · V` across every source and
  drain junction** (`PSP103_module.include` line 1726), with gmin taken from the simulator.
  ngspice's default is 1e-12 S. On a storage node of about 1.5 fF that is a 1.5 ms time
  constant, unrelated to any physical leak.

With ngspice's default gmin, the cmos5l revision cuts every lifetime 30–200-fold, to 0.04–0.45 ms
(`m1-v5-3T-w0.15-l0.45-gmin-default.txt`; the write transistor alone then drains 0.254 V in 1 ms
in every corner and at both temperatures, `m1-leak-cmos5l.txt`). That droop does not depend on
corner or temperature, which no physical leak does. With gmin at 1e-15, 1e-18 or 1e-21 S the
leakage paths agree with each other and with the old `leak.txt` to the millivolt
(`m1-leak-cmos5l-gmin1e-*.txt`), so everything here uses gmin 1e-18. **Anyone simulating this
cell, or any small floating node, with this PDK revision must lower gmin.** The gate current
of the storage transistor, the dominant real leak, is identical in both builds
(`m1-gate-current-{cmos5l,g2old}.txt`).

Reproducing the old number first: the old PDK and build give `v5`'s tt/27 °C row exactly with
W 0.30, WMW 0.15, LMW 0.45 (`m1-repro-g2old-W0.30.txt`: 0.468 V written, 0.45 V crossed at
693.1 µs), and not with the script's default W 0.15 (`m1-repro-g2old-W0.15.txt`).

Lifetimes of a written 1, 20 ns write, 32-cell column read (`../gain-cell/retention/analyse.py`):

| corner | old PDK, 10 / 20 ns sense (`../gain-cell/retention/results/lifetimes-3t.txt`) | cmos5l, gmin 1e-18, 10 / 20 ns sense (`m1-lifetimes-3t.txt`, `m1-lifetimes-3t-low.txt`) |
|---|---|---|
| tt 27 °C | 12.06 / 19.33 ms | 12.74 / 20.63 ms |
| tt 85 °C | 12.21 / > 12.78 ms | 12.64 / 19.38 ms |
| ff 27 °C | > 4.95 / > 4.95 ms | 7.02 / 9.91 ms |
| ff 85 °C | > 3.10 / > 3.10 ms | 5.94 / **8.88 ms** |
| ss 27 °C | unreadable / 8.26 ms | unreadable / 10.62 ms |
| ss 85 °C | 14.88 / 26.01 ms | 16.59 / 29.44 ms |

What changed, plainly:
- **The written levels and the read thresholds did not change** (the 2bbec755 read sweep is
  identical to the old one line for line, `m1-sweep-3t.txt` against `sweep-3t.txt`).
- **The decay is slower** under PSP 103.8.2: the times to cross 0.45–0.25 V grow by 0.3–0.7 %
  at ff/85 °C, 1.4–3.5 % at tt/85 °C, 3–7 % at tt/27 °C, 9–15 % at ss/85 °C and 27–31 % at
  ss/27 °C (e.g. tt/27 °C crosses 0.30 V at 12.80 ms against 12.12 ms). The old PDK with gmin 1e-18
  reproduces its old numbers exactly (`m1-v5-g2old-gmin1e-18-ss27-tt27.txt`), so the shift is the
  model code, not the gmin setting.
- **The ff rows are no longer lower bounds.** The old runs stopped reporting at 0.25 V; with the
  levels extended to 0.10 V and the read sweep to 0.075 V, ff/85 °C reads down to 0.117 V at a
  20 ns sense and its 1 lasts 8.88 ms. The worst nominal corner at a 20 ns sense is ff/85 °C,
  8.88 ms, not "≥ 3.1 ms".
- The 10 ns sense still fails at ss/27 °C, as before.

None of this includes mismatch (no Monte Carlo of the thick cell exists), neighbour coupling or
the real periphery; section 2 replaces the ideal precharge switch and the 0.5 V criterion with
standard cells.

## 2. Periphery and the bank layout

**Size.** The bank is 32 words of 32 bits (1 kbit of payload, smaller than architecture-v0's
4 kbit banks): 32 rows of 38 columns, 32 data bits and a 6-bit Berger check, the count of 0s in
the data word (`notes/gain-cell-compiler.md`, "Detect expiry"). 32 rows is the column the read
was simulated with in `../gain-cell/`, so no new column length enters untested.

**Circuit** (`rtl/gc_bank.v`, all standard cells of `sg13cmos5l_stdcell`):
- one flop per word line (32 WWL, 32 RWL), so no decoder glitch ever reaches a word line;
- one flop per write bit line;
- per read bit line, an `ebufn_2` with A tied high as the precharge, and as the sense a
  `nand4_1` with all four inputs on RBL. Four series NMOS against four parallel PMOS switch
  above VDD / 2, so a smaller discharge reads as 1. Both are instantiated by hand, and the
  resizer may not touch RBL (`RSZ_DONT_TOUCH_RX`); the final netlist has no buffer on any RBL
  (7 references to each of the 38 nets, all ports of these cells or the macro);
- the Berger encoder on the write data and the checker on the captured word (`rerr`).

**Timing** (60 MHz, architecture-v0 2.8; cycle counts are parameters): a write drives the bit
lines for a cycle, raises WWL for 2 cycles (33 ns) and holds the bit lines at least one cycle
after; 4 cycles per write. A read raises RWL and stops the precharge at the accept edge,
captures the sense outputs 2 cycles (33 ns) later, then precharges for at least one cycle;
3 cycles per read. Refresh-free: no access waits for, or is delayed by, a refresh; a word must
simply be rewritten within its lifetime (below), which is the compiler's job.

**Read path in SPICE** (`spice/bankread.py`): the standard cells' transistor netlists, a
32-cell column with 31 unselected cells storing 1 at 0.70 V, RBL left at 0 V by the previous
read and precharged for one cycle only, the sense output taken 0.3 ns before the capture edge.
The precharge reaches VDD in every corner. Joined with the write-and-hold runs for a 33 ns
write (`spice/banklife.py`, `spice/results/m2-banklife.txt`). Lifetime of a written 1:

| VDD, sense, RBL load | tt 27 | tt 85 | ff 27 | ff 85 | ss 27 | ss 85 |
|---|---|---|---|---|---|---|
| 1.20 V, inverter, 30 fF (`m2-bankread-1v20.txt`) | 19.0 ms | 18.0 | 9.2 | 8.4 | 9.6 | 26.9 |
| 1.20 V, NAND4, 30 fF (`m2-bankread-nand4-1v20.txt`) | 20.4 | 20.0 | 10.8 | > 10.9 | 10.0 | 28.6 |
| **1.20 V, NAND4, 35 fF** (`m2-bankread-nand4-1v20-cbl35.txt`) | **19.4** | **19.2** | **10.1** | **10.3** | **6.9** | **26.8** |
| 1.14 V, NAND4, 30 fF (`m2-bankread-nand4-1v14.txt`) | 15.5 | 17.1 | 8.9 | 9.0 | unreadable | 19.0 |
| 1.08 V, NAND4, 30 fF (`m2-bankread-nand4-1v08.txt`) | 9.4 | 13.9 | 7.5 | 7.8 | unreadable | 7.5 |

35 fF is the bit line's load after place and route: 2.5–20.8 fF of routed wire on the 38 RBL
nets (the final bank run `b11`, its SPEF at nominal RC; 2.3–19.7 fF in the earlier run `b7`) plus about 13 fF of Metal2 inside the
array (estimated, 88 µm next to two bit lines). The NAND4 lowers the readable level by 9–26 mV
at tt and ff and does nothing at ss/27 °C.

**The slow cold corner sets the bank's limits.**
- At 1.20 V it lives 6.9 ms, but its written 1 (0.383 V) is only 17 mV above the lowest
  readable level (0.366 V). Any mismatch, which is not simulated for this cell, eats that.
- **Below 1.20 V it does not work.** A thick-oxide write transistor passes VDD minus its
  threshold: 0.327 V at 1.14 V and 0.266 V at 1.08 V, against 0.378 and 0.396 V needed. Neither
  a 300 ns write (0.349 V at 1.08 V, `m2-ret-tw300-1v08-ss27.txt`) nor 4 cycles of evaluation
  (needs 0.345 V, `m2-bankread-nand4-1v08-eval4.txt`) closes it. The standard-cell libraries
  are characterised at 1.08 V, so a supply that may sag 10 % needs a boosted write word line
  (`../gain-cell/tricks-thick/`) or a sense amplifier; neither is here.
- The read-path figures are nominal corners; the cell has no Monte Carlo.

**Layout** (`bank/config.json`, `bank/harden.sh`: LibreLane 3.1.0.dev3, the pinned image, the
array placed as a macro at (73, 60) in a 190 × 210 µm die). Final run `b11`
(`bank/results/b11/metrics.json`), after the power-grid change of section 3:
- Magic DRC 0, KLayout DRC 0, routing DRC 0, antenna 0, KLayout/Magic XOR 0;
- netgen LVS: circuits match uniquely (the array as a black box, `lvs.netgen.rpt`);
- **full KLayout LVS of the whole bank, the array's 3,648 transistors included:** match
  (`lvs/m2-gc_bank_32x32-full.log`, hierarchical mode; `pnl2spice.py` turns the powered netlist
  into the schematic). Two planted faults fail as they should: one sense gate's input moved to
  the neighbouring bit line (`lvs/m2-planted-bank-sense-input.log`) and one read transistor's
  gate moved to the next row's word line inside the array (`lvs/m2-planted-bank-array-cell.log`).
  The deck's flat mode (on run `b7`) reported a mismatch only because every standard cell's
  pin labels became top-level pins; its cross-reference matched;
- setup slack +7.22 ns (slow corner), hold +0.16 ns (fast), at 16.667 ns; power-grid check 0
  violations;
- 1,344 standard cells, 21,165 µm², against 4,050 µm² of array: **the periphery is 84 % of
  the bank**, 152 of its cells flops (7,446 µm²). Bank die 39,900 µm², 39 µm² per payload bit;
  the array alone is 3.33 µm² per bit with its edges, 3.05 µm² in its core.

What it took (each a finding about the hand-drawn array, now fixed in `gc_array.py`):
- the GDS needs 1 nm database units, or Magic refuses it;
- Magic checks each cell of a hierarchy alone, and the tiles and straps share diffusion and
  implant across cell edges, so it reported 2,584 overlaps and 96 broken butted ties: the macro
  is now one flat cell;
- Magic's butted-tap rule (pSD.e/f) wants the P+ tie to reach 0.3 µm clear of N+ on some side:
  the strap grew from 0.60 to 1.00 µm (the array from 43.8 to 45.0 µm wide);
- read word-line pins only 0.51 µm apart left notches below M3.b next to the router's landings;
  the pins now sit at the row pitch (2.75 µm), jogged in Metal2, and are 0.30 µm tall.

## 3. Macro views (`views/`)

For a design that places the bank (`gc_bank_32x32`, 190 × 210 µm):
- `gc_bank_32x32.gds`: the layout of run `b11`, array included. Layers used: Activ, GatPoly,
  Cont, nSD/pSD, NWell, ThickGateOx, Metal1–Metal4 and their vias; no TopVia1 or TopMetal1
  (checked on the GDS; the run before, `b10`, had let the router use TopMetal1, hence
  `RT_MAX_LAYER Metal4`).
- `gc_bank_32x32.lef`: abstract by Magic. **Pins only on Metal2 and Metal3 (signals) and
  Metal4 (VPWR, VGND)**; obstructions on GatPoly, Metal1–Metal4, none on TopMetal1.
- `gc_bank_32x32__nom_{typ_1p20V_25C,slow_1p08V_125C,fast_1p32V_m40C}.lib`: Liberty timing
  models. **Method:** LibreLane's post-route STA writes them with OpenSTA's timing-model
  extraction (`write_timing_model`) on the routed netlist with OpenRCX parasitics, one per
  standard-cell library corner: setup and hold arcs from clk to all 40 inputs, clk-to-output
  arcs to all 35 outputs. They are digital timing only. The analogue requirements are not in
  them and are the user's: the clock period at least 10 ns (2 cycles of write and of evaluation
  must reach 20 ns; 16.667 ns is what was simulated), VDD at 1.20 V (section 2: the slow cold
  corner cannot read below it, so the 1.08 V model describes timing that the cell itself
  would not deliver there), and every word rewritten within the retention bound.
- `gc_bank_32x32.vh`: the black-box Verilog header.
- `../rtl/gc_bank_beh.v`: **the behavioural model**, same ports and cycle-level protocol as
  the RTL. A read whose capture edge comes more than `RETENTION_NS` after the row's last write,
  or of a row never written, returns `rdata = X` and `rerr = X`, prints `GC_BANK EXPIRED`, and
  counts in `expired_reads`. The whole word goes X even though only 1s decay, so a scheduling
  bug cannot hide in a word of mostly 0s.
- the array's own views, for whoever re-hardens the bank: `GC_ARRAY_32x38.{gds,lef,lib,cir,bb.v}`
  from `gc_array.py`. The array's Liberty has pin capacitances only (estimates, see the
  file) and no timing arcs.

**What the model's bound is.** `RETENTION_NS` defaults to 3.0 ms. The shortest simulated
lifetime of a 1 in the bank is 6.9 ms (ss/27 °C, 1.20 V, section 2), so the default leaves a
factor 2.3 for what is not simulated: mismatch (no Monte Carlo of this cell; for the thin cell
it cost a factor 10 at the 64 kbit worst cell, `../gain-cell/tricks-thin/`), coupling and
silicon. The 3.0 ms is a choice, not a measurement; it is also architecture-v0's plan of
record (≥ 3.1 ms, 2.6), slightly lowered.

**Planted controls** (`rtl/sim.sh`, Icarus Verilog 13; outputs in `rtl/results/`):
- the RTL bank (`gc_bank.v`, with `gc_array_beh.v`, the array's behavioural model, and the
  PDK's models of the two hand-placed cells) and the bank model (`gc_bank_beh.v`) run one
  testbench (`tb_bank.v`) with the bound lowered to 5 µs: all 32 rows written and read back,
  2,000 random operations with a refresh pass every 16, a read 4 µs after its write (inside),
  a read 6 µs after (outside) and a read of a row never written. Both print `PASS`; the
  outside and never-written reads return X and are counted (2 each,
  `sim-rtl.txt`, `sim-beh.txt`); the first 1,041 reads of the two traces are identical in time,
  data and `rerr` (`sim-compare.txt`);
- the RTL alone: one stored 1 of a live word forced to 0 inside the array model (a decay the
  model's timing would not produce) makes the Berger check raise `rerr`;
- a 7 ns clock gives 14 ns write pulses, below the 20 ns the cell needs: the array model
  reports 5,028 short writes (`sim-rtl-7ns-clock.txt`);
- the test top (section 4) with the bank model and a 20 µs bound: a pass with a 4.3 µs wait
  reads 0 bad words, a pass with a 34 µs wait reads all 32 bad and Berger-failed
  (`sim-top-rtl.txt`).

## Files

- `gc_array.py`: the macro array generator (GDS, LEF, LVS schematic).
- `drc.sh`, `lvs.sh`: the cmos5l DRC and LVS decks in the pinned image; logs in `drc/`, `lvs/`.
- `spice/run.sh`: runs a simulation script against the cmos5l or the old PDK; `spice/results/`.
- `spice/gate_current.py`: DC gate current of the storage and write transistors.
- `spice/bankread.py`, `spice/banklife.py`: the bank's read path and its lifetimes.
- `magic_drc.sh`: Magic DRC of one GDS cell with the sg13cmos5l techfile.
- `rtl/`: the bank (`gc_bank.v`), its behavioural models, testbenches and `sim.sh`.
- `bank/`: the bank's LibreLane configuration, `harden.sh` and results.
- `pnl2spice.py`: powered netlist to SPICE for a full KLayout LVS.
