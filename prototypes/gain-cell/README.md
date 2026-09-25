# Gain-cell dynamic memory for IHP SG13G2

The goal is on-chip memory denser than SRAM, with no SRAM macro at all. The SRAM bit cell in
the PDK is 2.81 × 1.07 µm = 3.01 µm², measured from its placement in the macro GDS
(`prototypes/sram-cut/pdk-cell/refs.txt`; an earlier 3.50 µm² here was wrong). That cell
passes DRC only under the SRAM marker layer's relaxed rules; a 6T drawn at the standard rules
is 3.41 µm² (`prototypes/sram-cut/`). The macros spend 3.6 to 8.6 µm² per bit including
their periphery. A gain cell stores a bit as charge on a transistor gate. Reading it does not
destroy it, and the cell needs no capacitor, so it can be built in a plain logic process. The
price is that the charge leaks away, so every bit has a lifetime. The compiler must schedule a
read or refresh within it: the same bargain as the systolic array, with timing that is hard to
program in exchange for density.

## Status (2026-09-25)

- **Layout:** 3T and 2T arrays, drawn by coordinates (`draw2.py`, gdstk). IHP's DRC deck is
  clean with substrate ties included. The netlist extracted by the PDK's LVS deck shows the
  intended devices and connectivity (`lvs/*/extracted.cir`).
- **Retention:** simulated in SPICE (ngspice 44.2, PSP 103 via OSDI, rootless container,
  `retention/Containerfile`). See below.
- **Read:** simulated for both topologies (`retention/read.py`). The 2T cell does not read. The
  3T cell does, and lives at least 3 ms in every corner (below).
- **Not done:**
  - the periphery (word-line drivers, sensing, refresh);
  - Monte Carlo mismatch for the thick-oxide cell (the thin cell's is in `tricks-thin/`, below);
  - coupling between neighbouring cells;
  - silicon.

## The cell

- **3T:** a write transistor MW (WBL → storage node SN, gate WWL); a storage transistor MS (gate
  SN, source GND); and a read transistor MR (gate RWL, drain RBL).
- **2T:** drops MR and uses the row's MS source as the read word line.

A tile is one column by two rows, mirrored about the shared WBL contact:

```
  strip B (thick oxide):  WBL contact (shared) | MW gate = WWL | SN contact
  keep-out: ThickGateOx must clear thin-oxide Activ by 0.27 um
  diffusion bar across the row: GND (3T) or RWL (2T)
  strip A (thin oxide):   MS gate (poly contact on a pad beside the strip) | [MR gate = RWL] | RBL contact (shared)
```

Two rows share each horizontal ThickGateOx stripe and each bit-line contact. The bit lines run
in Metal2: RBL over the strip, WBL beside it. A strap column every N columns carries a GND track
and one substrate tie per row. The latch-up rule LU.b allows N up to 38.

## Why a thick-oxide write transistor

A first screen of write transistors (`retention/retention-*.txt`, W 0.15 µm, both stored values,
fixed thresholds of 0.45 V for a 1 and 0.35 V for a 0). The ranking stands, but the absolute
figures for a stored 1 are inflated: those runs took the stored 1 from the DC operating point,
not from a write (finding 5).

| write transistor | worst over tt/ff/ss × 27/85 °C |
|---|---|
| thin-oxide NMOS | 1 µs |
| thin-oxide PMOS | < 1 µs (n-well junction leakage lifts a stored 0) |
| thick-oxide PMOS | < 1 µs (same) |
| thick-oxide NMOS | 1.1 ms |

## Findings from drawing and simulating it

1. **The storage transistor's source needs a quiet node.** Tying it to WBL would save the ground
   line, but the stored bit is lost at once. SN is mostly MS gate capacitance, and it follows WBL
   through the channel: a stored 1 fell from 0.88 V to 0.22 V when WBL swung
   (`retention/results/v3-wbl-w30.txt`). Hence the per-row diffusion bar.
2. **The write transistor's width matters far more than linearly.** At W 0.30 its leakage at
   ff and 85 °C is about 28 times that at W 0.15 (`results/v3-gnd-w30.txt` against
   `retention-hv_nmos.txt`). This is most likely the narrow-width
   shift in threshold, which subthreshold leakage magnifies. Hence the option of a dogbone
   strip, narrowed to 0.15 µm under the write gate only.
3. **A 1 is written weakly.** An NMOS pass transistor with its gate at 1.2 V passes about
   1.2 V minus a threshold, and slowly near the end. After a 20 ns write from a stored 0 the
   node reaches 0.33 to 0.56 V at W 0.30/L 0.45, and 0.37 to 0.63 V at W 0.15/L 0.45, across
   the corners (`results/v5-*`).
4. **The 2T cell does not read.** When a read pulls the row's source bar low, the falling edge
   couples through the storage gate and drags SN down by about 0.4 V. That turns the storage
   transistor off before it can discharge RBL. With a realistic written 1, RBL does not move in
   any corner (`retention/results/read-2t.txt`). A stored 0 is kicked negative far enough to turn the
   write transistor on, so each read also degrades it. An earlier run that looked readable had
   a DC-operating-point artefact: the stored 1 started at 1.05 V
   (`retention/results/read-2t-dc-artefact.txt`).
5. **Two of my own artefacts, both in the stored 1.** In the first retention runs the 1 came from
   the DC operating point, which settles far higher than a real 20 ns write reaches: 0.65 V
   against 0.42 V at tt and 27 °C. A fixed 0.45 V threshold was then no criterion at all, since a
   real write starts below it. The corrected method has two parts. `read.py SNSWEEP` finds the
   lowest stored level that still reads, per corner. `run.py` writes from the opposite value and
   reports when SN crosses each level. `analyse.py` joins the two. The `v4-*` runs still carry
   the artefact; `v5-*` do not.
6. **Stored 0s are safe** in the thick-oxide cell. They stay below 0.03 V for 10 ms in every corner (`results/v5-*`).
   Not in the thin-oxide cell: there a 0 fails at 3.2 µs at ff/85 °C (`tricks-thin/`). A read
   couples SN up by about 0.3 V while RWL is high, and the level sweep includes that.

## Lifetime of the 3T cell

Read test: a column of 32 cells, with a 10 fF wire, and the 31 unselected cells all storing a 1
(`results/read-3t-*.txt`, `results/sweep-3t.txt`). A read succeeds when RBL falls below 0.5 V
by the sense time. The lifetime is the time for a freshly written 1 to fall to the lowest
readable level (`results/lifetimes-3t.txt`). The table shows the worst corner for each write
transistor:

| write transistor | 20 ns write, 10 ns sense | 20 ns write, 20 ns sense | 100 ns write, 10 ns sense |
|---|---|---|---|
| W 0.15, L 0.45 (dogbone) | fails at ss/27 °C (written 0.37 V, needs 0.39) | > 3.1 ms (ff/85 °C) | > 3.1 ms (ff/85 °C) |
| W 0.15, L 0.60 | fails at ss/27 °C | > 0.19 ms (ff/85 °C) | — |
| W 0.15, L 0.80 | fails at ss/27 °C | > 0.53 ms (ff/85 °C) | — |
| W 0.30, L 0.45 | fails at ss/27 °C | fails at ss/27 °C | — |

The ff figures are lower bounds. At ff the lowest readable level lies below both the 0.25 V
floor of the retention report and the 0.20 V floor of the level sweep. The slowest corner (ss
at 27 °C) limits the write level and the sense speed; the fast hot corner (ff at 85 °C) limits
retention.

**The choice is W 0.15 / L 0.45:** a dogbone strip at the thick-oxide minimum length, with a
20 ns sense or a 100 ns write. It holds a bit for at least 3 ms in every corner, and for 12 to
20 ms at tt. Its cell is 1.03 × 2.75 µm = 2.83 µm² per bit; with a strap every 32 columns,
2.89 µm². That is **1.04 times the density of the PDK's SRAM bit cell**, and 1.18 times a 6T
drawn at the standard rules. It is not the large win the
core pitch first suggested, because thick oxide costs 0.54 µm of keep-out per row pair.

**The longer gates leak more, not less,** hot: at tt and 85 °C, L 0.60 lasts 0.8 ms against
12 ms for L 0.45. That runs against intuition. It is consistent with a halo implant raising the
threshold near minimum length (the reverse short-channel effect), but I have only the model for
it, not silicon.

## What leaks, and the thin-oxide alternative (2026-09-25)

- **Leakage:** `retention/leak.py` isolates the paths. In the thick-oxide cell, the stored 1
  leaks through the storage transistor's thin gate oxide: 14–200 mV per ms from 0.55 V. The
  write transistor alone loses 1 mV (`results/leak.txt`). A ±100 mV shift of the write
  transistor's threshold leaves the decay rate unchanged (`mkmodels.sh`, `run.py` `DVT`).
- **Thick-oxide storage transistor:** it cuts the droop 30–100-fold
  (`results/v7-3T-mshv-*.txt`). But it needs 0.57–0.77 V to read with an inverter
  (`results/sweep-3t-mshv.txt`), more than the write gives, so it needs a sense amplifier.
- **Thin-oxide write transistor:** its own channel leaks
  (`results/lifetimes-3t-thin.txt`, `results/v6-*.txt`). The lifetime of a 1 is 1.2 µs at
  ff/85 °C, 8 µs at tt/85 °C, 120 µs at tt/27 °C, and about 2 ms at ss/27 °C. Its cell is
  1.03 × 2.10 µm = 2.16 µm² (2.20 µm² with straps), 1.37× the PDK SRAM bit cell's density (1.55× a
  standard-rule 6T).
- **Mixed arrays:** thick and thin row pairs mix in one array on shared bit lines. DRC is clean
  (`drc/v3-ARRAY_MIXED.log`), and extraction shows the intended devices and nets
  (`lvs/mixed/extracted.cir`).
- **For the compiler:** how it would use rows with uneven lifetimes is in
  `notes/gain-cell-compiler.md`.

## Tricks for the thin-oxide cell (2026-09-25, `tricks-thin/`)

Everything here is SPICE on the PDK models (`tricks-thin/cell.py`, `mc.py`), judged the same
way as above: a simulated write from the opposite value, then the time until the stored level
reaches the read threshold of a simulated 32-cell column read (RBL below 0.5 V reads 1, above
0.7 V reads 0, 10 ns after RWL rises unless stated). Unlike before, a stored 0 counts too: in
the thin cell at ff/85 °C a 0 fails at 3.2 µs, barely after the 1. Worst case over tt/ff/ss ×
27/85 °C. Every number points to `tricks-thin/results/`.

**What leaks** (`leakdc.txt`, `leakterm.txt`, DC currents at ff/85 °C). The write transistor
with its gate at 0 and its WBL side at 0 V passes 390 pA. Raising the WBL side to 0.2 V cuts that
265-fold, to 0.3 V 1500-fold (390 pA → 0.26 pA). Below that it stops: about 0.19 pA flows from
SN into the write transistor's gate, tunnelling through the thin oxide over the SN-side
overlap, whatever the WBL side does (`leakterm.py` puts SN on the model's drain pin, the cell on
its source pin; PSP is symmetric). The storage transistor's gate adds 0.07–0.96 pA at 0.7 V
depending on its bar level (`leakdc.txt`). A second write transistor in series does not reach
either current: the gate tunnelling of the one on SN stays.

| trick (thin write transistor unless stated) | worst-corner lifetime | area per bit | verdict |
|---|---|---|---|
| none (drawn thin cell) | 1.31 µs (`hold-lv-vlo0.txt`) | 2.20 µm² | reference |
| two thin write transistors in series | 3.6 µs, 2.7× (`hold-lv2-vlo0.txt`) | 2.53 µm², drawn, DRC-clean | no: the stack effect is weak here, and with the level shift below it adds nothing (`hold-lv2-vlo0.3-bar0.2.txt`) |
| thin + thick in series, either order | written 1 of 0.21–0.62 V: no 10 ns read (`hold-lvhv-*`, `hold-hvlv-*`) | ≥ the thick cell (estimate: keep-out) | no |
| one series gate on a bank write enable | identical to the stack in hold (`hold-lv2g-vlo0.txt`) | 2.53 µm² | no |
| WBL parked at 0.1–0.6 V between writes, 0 written as 0 V | 4.8–23 µs (`lifetime-variants.txt`) | free | no: the 0 drifts up to the park level and reads as 1 |
| **level-shifted data**: 0 written as WBL = VLO, bar at VBAR | see below | free in the cell | **yes, with caveats** |
| storage bar pulled to 0 V for the read only | no better than a fixed bar at the same read level (`lifetime-rbar0.txt`) | free | its only merit: the hold bar sinks no current |
| NMOS version of Giterman's feedback cell | monostable: 1 and 0 both settle at 0.43–0.56 V (`hold-fb-*`) | about 3.1 µm² (estimate) | no, not as sized |
| PMOS storage transistor in an n-well | a written 1 (0.59–0.80 V) never turns it off: needs ≥ 0.77–1.0 V (`read-plv-bar1.2.txt`); the 0 rises 0.3 V in 100 µs at tt/27 °C (`hold-plv-bar1.2.txt`) | 2.65 µm², drawn; **not** DRC-clean (the main deck flags Cnt.g1 and M1.b; only the maximal rule set reports 0) | no |
| PMOS write transistor, 1 written as 0.9 V, bar 0.3 V | 119 µs (`hold-plvw-vhi0.9-bar0.3.txt`): the weak 0 (0.38–0.61 V) rises through the n-well | about 2.65 µm² (estimate) | no: below the NMOS level shift |
| gated diode on SN (2T1D-style boost) | the read threshold falls by about 0.37 V, but the 0 is boosted too and reads as 1 at bar 0.2 V (`read-nlv-gd-bar0.2.txt`, `hold-lv-gd-vlo0.3-bar0.2.txt`); its thin gate adds leakage | about 2.5 µm² (estimate) | no retention gain |

**PMOS gates leak more here, not less.** Chun et al. (VLSI 2010) cite an order of magnitude
lower gate leakage for PMOS in their 65 nm process. In these models the thin PMOS leaks 2–14×
*more* than the thin NMOS at the same |Vgs| up to 0.9 V (`leakterm.txt`: 1.15 against 0.18 pA
at 0.5 V, ff/85 °C). That is the models' claim, not silicon's.

**Level-shifted data.** Write a 0 as WBL = VLO instead of 0 V, and park WBL at VLO. WBL then
never falls below VLO, so a write transistor holding a 1 sits at Vgs ≤ −VLO: the effect of a
negative write word line, without a negative rail. (A stored 0 sits a little below VLO after
the word line's feedthrough, at Vgs ≈ −0.2 V, and drifts up towards VLO or, while WBL is high,
beyond it.) The storage transistor's source bar must
rise with it (to VBAR) or a stored 0 at VLO reads as 1. Worst-corner lifetimes over the grid
are in `matrix.txt`; the good points:

| VLO / VBAR, sense | idle column (WBL parked at VLO) | column written with 1s all the time |
|---|---|---|
| 0.30 / 0.10 V, 10 ns | 1.22 ms (1 at ff/85 °C) | 131 µs (0 at ff/85 °C) (`hold-lv-vlo0.3-bar0.1*-v2.txt`) |
| 0.25 / 0.10 V, 10 ns | 630 µs | 141 µs (`hold-lv-vlo0.25-bar0.1*-v2.txt`) |
| 0.30 / 0.15 V, 20 ns | 1.20 ms | 344 µs |
| bar chosen per corner (0–0.2 V), VLO 0.3–0.4 V, 10 ns | 0.93–1.2 ms | 0.92–1.2 ms |

Writes elsewhere in the column matter only for the stored 0, in proportion to the time WBL
spends high: at VLO 0.3 / VBAR 0.1 V and ff/85 °C, 1 % of the time costs nothing, 10 % gives
257 µs, 50 % 140 µs (`lifetime-duty.txt`). The window is narrow at 1.2 V: the slow cold corner
writes a weak 1 (0.60 V at ss/27 °C) and needs a low bar to read it, while the fast hot corner
reads a 0 at 0.29 V as a 1 unless the bar is high. With a 10 ns sense, a fixed bar above 0.1 V fails
ss/27 °C; below it the 0 fails at ff/85 °C.

**Monte Carlo** (`mc.py`, the PDK's `mos_*_mismatch` libraries, 200 seeds each, one ngspice
session per seed so the hold and the read sweep see the same draws; `seedcheck.txt`). The
worst cell of 64 kbit is extrapolated from a lognormal fit of the lifetimes, at the quantile
ln 2 / 65536 (z = −4.25), both over all samples and over the lower half only
(`mc-base-summary.txt`, `mc-ls-summary.txt`):

| cell | corner | median | 1st percentile | 64 kbit worst cell (fit) |
|---|---|---|---|---|
| thin, no trick | tt/85 °C | 7.7 µs | 1.7 µs | 0.63–0.71 µs |
| thin, no trick | ff/85 °C | 1.2 µs | 0.27 µs | 0.11 µs |
| VLO 0.3 / VBAR 0.1 V, idle column | tt/85 °C | 3.2 ms | 2.1 ms | 1.65–1.8 ms |
| VLO 0.3 / VBAR 0.1 V, idle column | ff/85 °C | 1.0 ms | 35 µs | 0.85–5.9 µs (bimodal: the 0 fails first in 65 of 200) |
| VLO 0.3 / VBAR 0.1 V | ss/27 °C | 4.9 ms | 0 | 7 of 200 cells cannot read a fresh 1 |
| per-corner bar: VBAR 0.15 V | ff/85 °C, idle column | 0.90 ms | 452 µs | 307–380 µs |
| per-corner bar: VBAR 0.15 V | ff/85 °C, busy column | 0.89 ms | 220 µs | 86–186 µs |
| per-corner bar: VBAR 0 V | ss/27 °C | 19.9 ms | 11.8 ms | 9.3–9.8 ms |

With the bar set per corner (0 V at ss/27 °C, 0.1 V at tt/85 °C, 0.15 V at ff/85 °C; VLO 0.3 V
throughout; `mc-track-summary.txt`), every simulated corner keeps a 64 kbit worst cell of
0.3 ms or more with an idle column, and about 0.1 ms with a column written with 1s all the time.
That is about 3000× (idle) and 800× (busy) the untricked cell's 0.11 µs at ff/85 °C.

So mismatch costs the untricked cell a factor of 10 (σ of ln t ≈ 0.56), and the level shift
wins 2500× at tt/85 °C, where its spread is small (σ ≈ 0.13–0.16). At the corners the margins
are tens of millivolts, and a 20–30 mV σ in the written level and the read threshold eats them.

**Area, read time and lifetime** (strap every 32 columns; lifetimes nominal worst corner):

| cell | µm² per bit | read (sense) | worst-corner lifetime | 64 kbit, tt/85 °C (MC) |
|---|---|---|---|---|
| thin 3T, level-shifted, per-corner bar | 2.20 | 10 ns | 0.9–1.2 ms (idle or busy) | ≥ 0.3 ms idle, ≈ 0.1 ms busy (worst of ff/85, tt/85, ss/27 °C) |
| thin 3T, level-shifted, fixed bar | 2.20 | 10 ns | 1.2 ms idle, 131 µs busy | 1.7 ms at tt/85 °C; fails ss/27 °C (4 % unreadable) |
| thin 3T (drawn) | 2.20 | 10 ns | 1.3 µs | 0.7 µs |
| thick-write 3T (drawn) | 2.88 | 20 ns | ≥ 3.1 ms (above), 261 µs in this sweep | not run |
| thin 3T, stacked write | 2.53 | 10 ns | 3.6 µs | — |
| thin 3T, PMOS storage | 2.65 | — | does not read | — |
| 2T thin | 1.88 | — | does not read (finding 4) | — |

The level-shifted thin cell is the only point that moves the front: the density of the thin
cell with the thick cell's milliseconds, if the corners can be handled. The thick-write cell's
ss/27 °C margin is thin too: this sweep (unselected cells at 0.85 V rather than 0.70 V) puts the
lowest readable level at 20 ns at 0.354 V, 10 mV above `retention/`'s 0.344 V, which leaves
12 mV over its 0.366 V written 1 and a lifetime of 261 µs there (`hold-hv-vlo0.txt` with
`read-nlv-bar0.txt`).

**What the level shift needs outside the cell:** a VLO level for the WBL drivers (current only
while writing); a VBAR level for the bars that sinks a whole row's read current, or a per-row
driver that pulls the selected bar to its read level (then the hold level only has to hold);
and, to keep the corners, a bar that tracks process and temperature, as in Chun et al.'s
PVT-tracking read reference. None of it is designed yet.

**Artefacts I hit here.** (1) The first hold runs recorded a stored 0 only at levels above
VLO, so a 0 creeping up to a threshold below VLO went unseen and one idle-column result read
1.2 ms where the 0 in fact had 4 mV of margin; every VLO > 0 run was repeated. (2) The grid
level equal to VLO showed a 'rise' at 40 ps, a start-up transient; the analysis drops crossings
before 25 ns and `cell.py` now measures from 25 ns. (3) `read` sweeps set SN at t = 0 and read
at 40 ns: in the untricked cell at ff/85 °C SN leaks 17 mV in between, so its thresholds are
about 15 mV high (`mc.py` forces SN until the read instead). (4) The first `read` sweeps at bar 0.1 V had WBL at 0.1 V,
not at the 0.3 V of the holds they were joined with; the matched sweep moves the headline
lifetimes by under 5 % (`matched-read-check.txt`). An adversarial review by another model
family (`codex-verdict.txt`) found this and the two mechanism overstatements corrected above.
(5) The Monte Carlo seed is
`.options seed=N`; without it every run draws differently (time-seeded), with it the same seed
reproduces the draws exactly.

## What would change the numbers

- **A higher write word line.** The written 1 is 1.2 V minus a thick-oxide threshold, about
  0.4 V. The thick-oxide transistor is rated for 3.3 V at its gate, but no IHP Tiny Tapeout tile
  gets a 3.3 V rail: the analog templates offer only VDPWR and VGND, and the 3.3 V variants
  exist for sky130 only (`tt-support-tools`, `tech/ihp-sg13g2/def/analog/`). An on-chip boost of
  the write word line (a bootstrap or a small charge pump, in thick-oxide devices) would write a
  full 1.2 V. That should lengthen the lifetime a good deal, but it is not simulated yet.
- **A sense amplifier** instead of an inverter: it reads a smaller swing, so a lower level still
  reads.
- **Mismatch.** An array's leakiest cell sets its lifetime. For the thin cell it costs a factor
  of about 10 at the 64 kbit worst cell (`tricks-thin/`); the thick cell is not yet checked.

## Files

- `draw.py`: the first thin-oxide 3T sketch (superseded).
- `draw2.py`: the v2 arrays. `uv run draw2.py COLS PAIRS EVERY [thick|thin LMW narrow|wide]...`
  writes `gain_v2.gds` (gitignored), with a mixed array when two variants are given.
- `drc/`: logs from IHP's DRC deck.
- `lvs/`: netlists extracted by the PDK LVS deck.
- `retention/run.py`: the retention simulation.
- `retention/read.py`: the read simulation, with the stored-level sweep (`SNSWEEP`).
- `retention/analyse.py`: joins the read sweep and the retention runs into lifetimes.
- `retention/leak.py`: isolates the leakage paths of the storage node.
- `retention/mkmodels.sh`: patches the PDK models to take a per-instance threshold offset.
- `retention/results/`: every run cited above.
- `tricks-thin/`: the thin-cell tricks, Monte Carlo and lifetime analysis (`cell.py`, `mc.py`,
  `life.py`, `matrix.py`, `mcstat.py`, `leakdc.py`, `leakterm.py`; `pod.sh` runs one in the
  container) and every result they produced (`results/`).
- `draw2.py ... thin 0.13 narrow+s2` draws the stacked-write variant, `narrow+p` the PMOS-storage
  one (`drc/v4-*.log`, `lvs/v4/`). Re-checked after merging the thick- and thin-oxide branches
  (`drc/merge-*.log`): every 3T variant passes except the PMOS-storage one, which fails Cnt.g1
  and M1.b in its own branch too (its log's "0 errors" line is the maximal rule set, not the main
  deck). The 2T all-thick variant fails pSD.j1; the 2T cell does not read, so it was not fixed.
