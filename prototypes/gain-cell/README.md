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
  - Monte Carlo mismatch, since the leakiest cell of an array sets its lifetime;
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
6. **Stored 0s are safe.** They stay below 0.03 V for 10 ms in every corner (`results/v5-*`). A read
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

## What would change the numbers

- **A higher write word line.** The written 1 is 1.2 V minus a thick-oxide threshold, about
  0.4 V. The thick-oxide transistor is rated for 3.3 V at its gate, but no IHP Tiny Tapeout tile
  gets a 3.3 V rail: the analog templates offer only VDPWR and VGND, and the 3.3 V variants
  exist for sky130 only (`tt-support-tools`, `tech/ihp-sg13g2/def/analog/`). An on-chip boost of
  the write word line (a bootstrap or a small charge pump, in thick-oxide devices) would write a
  full 1.2 V. That should lengthen the lifetime a good deal, but it is not simulated yet.
- **A sense amplifier** instead of an inverter: it reads a smaller swing, so a lower level still
  reads.
- **Mismatch.** An array's leakiest cell sets its lifetime. Monte Carlo is the next check that
  could shrink these numbers.

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
