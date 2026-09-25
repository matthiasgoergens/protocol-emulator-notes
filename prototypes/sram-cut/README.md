# Cutting corners on SRAM in IHP SG13G2 (1.2 V only)

The question: the gain cells (`../gain-cell/`) reach 2.20–2.88 µm² per bit but forget within
microseconds to milliseconds. What if we kept a static cell and cut corners on it instead, with
the compiler guaranteeing whatever access discipline the cell needs?

**Short answer.** At the standard design rules, the density of an SRAM-family cell is set by the
rules, not by the transistor count or sizes: two n-well crossings per cell (0.62 µm each), contact
pads (Cnt.c) and poly end caps (Gat.c) set the width, and Metal1 sets the height. A 6T drawn at
those rules is 3.41 µm², 13 % larger than the PDK's bit cell, which only passes DRC because its
SRAM marker layer relaxes those rules. Removing transistors (5T, loadless 4T) does not remove a
diffusion strip or a well crossing in this topology, so it buys no area. The electrical corner cuts
work or fail as below, but none of them gets under ~3.4 µm². Only removing the n-well altogether
would, and every all-NMOS static cell I tried either does not hold its state across corners and
mismatch or needs a separate read port. **For density, the gain cells stay the only option; SRAM
corner cuts buy power, not area.**

All numbers below are simulations (ngspice 44.2, PSP 103, PDK corner and mismatch decks) or
DRC-checked layout, unless marked *estimate*.

## Comparison

Leakage is the total current drawn from the supply and both bit lines in hold, per bit, at tt/27 °C,
tt/85 °C and ff/85 °C.

| cell | area µm²/bit | holds? | leakage pA (tt27 / tt85 / ff85) | what the compiler must guarantee | verdict |
|---|---|---|---|---|---|
| PDK bit cell (SRAM marker rules) | 3.01 (3.19 with its tap rows) | static | 20 / 212 / 1680 (same sizes as ours) | nothing | only via the macros; its rules are not ours to use |
| **6T, standard rules (drawn, DRC-clean)** | **3.41** (3.52 with a tap row per 36 rows) | static; worst MC read SNM μ/σ 13.8 | 20 / 212 / 1680 | nothing | the baseline |
| 6T minimum size (all W 0.15) | ≥ 3.41 (*estimate*: a dogbone NMOS strip makes it 3.06 × 1.14) | static; MC read μ/σ 8.7 | 12 / 164 / 1665 | nothing | sizing buys nothing at these rules |
| 6T at 0.4 V cell supply in idle ("drowsy") | 3.41 + a supply switch per row or column | static, hold SNM ≥ 129 mV | 7 / 111 / 909 (bit lines at 0.4 V too) | rows are idle, or returned to 1.2 V, before any access | 2–3× less current; a linear drop from the one rail saves current, not V² |
| 6T thick oxide (all devices) | ~7.4 (*estimate*: L 0.45, NW.c1/d1 0.62) | static | 0.12 / 6.5 / 49 | nothing (slower) | 30–170× less leakage for 2.2× the area |
| 5T (one bit line) | ≈ 3.4 (*estimate*: same strips and wells) | static | 14 / 131 / 1180 | write 1 only with the column's cell supply lowered to ≤ 0.6 V | no area gain; needs a write assist |
| loadless 4T (PMOS access, Noda), word line idle at 1.2 V | ≈ 3.4 (*estimate*) | **no**: fails at fs; 149 of 200 MC samples monostable at tt/27 | 4 / 77 / 1030 | a "kick" (word-line pulse, bit lines precharged) every ≤ 10 µs | dead: no area gain, mismatch kills it |
| loadless 4T, word line idle at 1.0 V | ≈ 3.4 (*estimate*) | static at all corners; MC fs/85 μ/σ 4.3 | 575 / 4490 / 58400 | a regulated 1.0 V idle word-line level; map out a few bits per 64 k | dead: 30× the leakage, no area gain |
| loadless 4T, thick-oxide drivers | > 3.4 (*estimate*: TGO and NW.d1 0.62) | static, hold SNM ≥ 69 mV | 2 / 43 / 655 | read with the word line at 0.7 V, not 0 V (full-on reads destroy) | larger than the 6T |
| all-NMOS 4T (no PMOS, no n-well) | ~2.2 (*estimate*: the 6T's two NMOS strips, no well) | never bistable (word line idle 0.3–0.6 V); dynamic 3–10 µs at tt/27 | – | refresh through sense amplifiers; a blind kick loses the data | worse than the thin-oxide gain cell |
| all-NMOS 6T with leakage loads (gate tied to node) | ~2.9–3 (*estimate*; + a read port) | thin: hold SNM 23–64 mV; thick drivers: MC ss/85 6 of 200 fail | 7–20 at tt/27 | never read through the access transistors (read SNM ≤ 12 mV at word lines of 0.8 and 1.2 V) | dead |
| standard-cell latch sg13g2_dlhq_1 | 30.8 (+ a read mux) | static | 288 / 2330 / 14000 | nothing | reference only: 9× the area, 14× the leakage |
| gain cell, thin-oxide write (`../gain-cell`) | 2.20 | 1.2 µs worst lifetime | – | refresh within 1.2 µs | the density option |
| gain cell, thick-oxide write | 2.88 | ≥ 3 ms | – | refresh within 3 ms | |

## 1. The PDK bit cell

- **Pitch:** the macros place `RM_IHPSG13_1P_BITKIT_CELL` on a 2.81 × 1.07 µm grid, i.e. 3.01 µm²,
  not the 2.96 × 1.18 = 3.50 µm² quoted in `../gain-cell/README.md`. A tap row every 16 rows (18.14 µm per 16 rows)
  makes it 3.19 µm² (`pdk-cell/refs.txt`, `pdk-cell/refs2.txt`).
- **Devices** (`RM_IHPSG13_*.cdl`): PD 0.30/0.13, PG 0.30/0.13, PU 0.15/0.13, a cell ratio of 1.
- **Its rules:** the cell carries the SRAM marker (layer 25/0). With it, IHP's DRC deck reports only
  `Cnt.c.digibnd` (204, contacts 0.02 inside Activ where the digital rule is 0.05). With the marker
  stripped, the "maximal" deck adds `Gat.c` (poly end caps of 0.13–0.17), `NW.c`/`NW.d` (0.27 where
  0.31 is required), `pSD.i` and `Cnt.c.Digi` (`pdk-cell/drc-summary.txt`). Those relaxations are
  exactly what our own layout cannot use.

## 2. Our 6T at the standard rules

`layout/sram6t.py` draws the PDK cell's topology (a point-symmetric "thin" cell: bit lines, VDD
and VSS in Metal2, word line in Metal3) at the standard rules.

- **3.19 × 1.07 µm = 3.41 µm².** IHP's DRC deck (main and maximal) passes a 4 × 4 array with tap
  rows (`drc/sram6t-v3/`, `drc/sram6t-v3.log`). The PDK LVS deck extracts 24 devices for the 4
  cells of a 2 × 2 array, with the intended cross-coupling (`lvs/6t/extracted.cir`).
- **What sets it** (half cell, x): 0.105 between the two PMOS pads (Act.b, corner to corner), 0.30
  pad (Cnt.c), 0.31 + 0.31 across the well (NW.c, NW.d), 0.30 NMOS strip, 0.27 to the boundary
  (Gat.c end cap + half of Gat.b between the mirrored pull-down gates) = 1.595. y: the bit-line
  Metal1 pad (0.21), a Metal1 space (0.18), a storage-node track (0.16) and half a space = 0.535.
  The PDK cell gains its 0.38 µm of width from 0.20-wide pads, 0.27 well margins and 0.13–0.17 end
  caps.
- **Minimum size does not shrink it.** A 0.15 NMOS strip needs 0.30 contact pads anyway, and the
  pads must keep 0.07 from the gates, which lengthens the strip from 1.02 to 1.14 µm (*estimate*
  3.06 × 1.14 = 3.49 µm², including a word-line contact that no longer fits beside the pads).
- **Margins** (`sim/results/6t-pdk-sizes-corners.txt`, layout sizes PD/PG 0.30, PU 0.15): hold
  SNM ≥ 438 mV, read SNM ≥ 163 mV (fs/85), write margin ≥ 367 mV (sf/27, bit-line voltage at which
  the cell flips). **Mismatch** (300 samples of the PDK mismatch model per corner,
  `6t-0.30,0.30,0.15-mc-*.txt`): read SNM mean/σ 13.8 at fs/85, write 17.5 at sf/27. Minimum size
  (all 0.15): read mean/σ 8.7 at fs/85 (`6t-0.15,0.15,0.15-mc-*.txt`).
- **A real read** (`6t-0.30,0.30,0.15-read.txt`): 64 cells on 10 fF bit lines, the 63 others
  storing the opposite value; the bit lines split fully within 1 ns and the low node peaks at
  0.17–0.22 V, far below the trip point, in every corner.
- **Leakage:** 20 pA at tt/27, 212 pA at tt/85, 1.68 nA at ff/85 per bit
  (`6t-pdk-sizes-corners.txt`).

**Caveat on mismatch.** The PDK's mismatch deck uses A_VT = 3.9 mV·µm (NMOS) and 2.2 mV·µm (PMOS)
(`sg13g2_moslv_mismatch.lib`), low for 130 nm. With twice that, the worst mean/σ would be about 7:
still enough for a 6T, not for the marginal cells below.

## 3. The corner cuts

- **Loadless 4T** (NMOS drivers, PMOS access, the access leakage from the precharged bit lines is
  the only load; `cellsim.py 4tp`). With the word line idling at VDD it is not bistable at fs, and
  barely at tt (hold SNM 3.7 mV, the stored 1 settles at 0.15 V; `4tp-d0.30-a0.15-corners.txt`);
  with mismatch, 149 of 200 samples at tt/27 are monostable (`4tp-wlidle1.2-mc-tt-27.txt`).
  Biasing the idle word line to 1.0 V makes it static everywhere, but the leakage rises 30-fold and
  the fs/85 mean/σ is 4.3, i.e. a few failing bits per 64 k (`4tp-*-wlidle*`,
  `4tp-wlidle1.0-mc-fs-85.txt`). As a **kick** cell (word line idle at VDD, periodically pulsed
  with the bit lines precharged, which recharges whichever node is high) it survives 100 ms at tt
  and ss but fails between 10 and 100 µs at fs/85 and between 0.1 and 1 ms at fs/27
  (`4tp-d0.30-a0.15-kick.txt`, nominal devices, no mismatch).
  Thick-oxide drivers make it static at every corner, but a read with the word line fully on
  destroys it (read with 0.7 V instead: read SNM ≥ 381 mV), and thick oxide next to the n-well
  costs NW.d1 = 0.62 (`4tp-hvd-*`). In none of these forms is it smaller than the 6T: the PMOS
  access strips take the place of the PMOS load strips.
- **All-NMOS 4T** (`4tn`): no idle word-line level between 0.3 and 0.6 V makes it bistable (the
  stored 1 cannot rise above the word line); as a dynamic cell the 1 decays in 3–10 µs at tt/27 and
  a kick flips or equalises it at most corners (`4tn-*`).
- **All-NMOS 6T with leakage loads** (`6n`: an NMOS from VDD to each node with its gate on the
  node, so it only ever leaks, and the driver-to-load leakage ratio is set by width, not by corner).
  Bistable at every corner, but with the thin-oxide driver the stored 1 is only 0.33–0.57 V and the
  hold SNM 23–64 mV; with thick-oxide drivers the hold SNM is 58–146 mV but mismatch leaves 6 of
  200 samples monostable at ss/85, and reads through the access transistors are destructive (read
  SNM ≤ 12 mV at word lines of 0.8 and 1.2 V, `6n-*`). It would need a separate read port and TGO keep-outs: no gain.
- **5T** (`5t`): hold and read as the 6T; a 1 cannot be written through the single NMOS at any
  corner. Lowering the column's cell supply (VDD already runs per column in Metal2) to 0.6 V during
  the write fixes that at every corner (`5t-*-vcell*`). No area gain in this topology.
- **Drowsy idle** (`6t-0.30,0.30,0.15-vsweep-blcell.txt`): the 6T holds at 0.4 V at every corner
  (hold SNM ≥ 129 mV; ≥ 31 mV at 0.2 V). The leakage current falls only 2–3× (the thin-oxide
  subthreshold leakage barely depends on the drain voltage), so from a single 1.2 V rail through a
  linear header the power saving is 2–3×, not the 5–9× that V × I would suggest.
- **Thick oxide everywhere** (`6t-hv-0.30,0.30,0.15-corners.txt`): works at 1.2 V (hold ≥ 488,
  read ≥ 221, write ≥ 316 mV) with 30–170× less leakage; the area *estimate* of ~7.4 µm² comes from
  L = 0.45 µm on four gates in series (y 1.66 µm) and NW.c1/NW.d1 = 0.62 (x 4.43 µm).
- **Latch** (`latch-dlhq1-leakage.txt`): `sg13g2_dlhq_1` is 8.16 × 3.78 = 30.8 µm² and leaks 14×
  the 6T; a register file of them needs a read multiplexer on top.

## What would change the conclusion

- Being allowed the SRAM marker rules (they are foundry-qualified for IHP's own cell only).
- A different 6T topology with one well crossing per cell (both PMOS on one side, cells mirrored so
  neighbours share the n-well): on paper up to ~12 % narrower, but it needs four gate contacts per
  cell instead of two, and the pull-down end caps meet in the middle; not drawn.
- A second supply or an on-chip boost, for word-line or cell-supply assists.

## Files

- `pdk-cell/`: extraction of the PDK bit cell (`extract.py`, `dump_cell.py`, `refs*.py`) and its DRC.
- `layout/sram6t.py`: our 6T and tap row; `drc/`, `lvs/`: its DRC and extraction.
- `sim/common.py`: shared helpers (SNM by Seevinck's method, checked against a brute-force square
  search in `sim/check_snm.py`, `results/check-snm.txt`).
- `sim/sram6t.py`: 6T corners, Monte Carlo, read transient. `sim/cellsim.py`: the variants
  (`4tp`, `4tn`, `6n`, `5t`, `6t` supply sweep, kick refresh). `sim/latch.py`: the latch.
- `sim/run.sh`: runs a script in the simulation container with its own work directory.
- `sim/results/`: every run cited above.
