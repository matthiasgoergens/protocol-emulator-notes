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

## Files

- `gc_array.py`: the macro array generator (GDS, LEF, LVS schematic).
- `drc.sh`, `lvs.sh`: the cmos5l DRC and LVS decks in the pinned image; logs in `drc/`, `lvs/`.
- `spice/run.sh`: runs a simulation script against the cmos5l or the old PDK; `spice/results/`.
- `spice/gate_current.py`: DC gate current of the storage and write transistors.
