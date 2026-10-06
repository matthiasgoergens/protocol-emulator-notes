# prototypes/chip-top/sram-macro: IHP SRAM macros through the pinned Tiny Tapeout cmos5l flow

Group F of `notes/learned-from-others.md` (A6, A7, A8). Question: does the Tiny Tapeout flow as we
pin it (tt-support-tools d66cf17, LibreLane 3.1.0.dev3 in `localhost/librelane-tt:3.1.0.dev3`,
IHP-Open-PDK 2bbec755, PDK `ihp-sg13cmos5l`, 6x4 tiles, 20 ns) harden a block holding
`RM_IHPSG13_1P_512x16_c2_bm_bist`, and then that macro together with
`RM_IHPSG13_1P_1024x8_c2_bm_bist`?

## Answer

**A6 holds; A8 does not, at our pinned PDK.** IHP-Open-PDK 2bbec755 ships the macros for
sg13cmos5l: `ihp-sg13cmos5l/libs.ref/sg13cmos5l_sram` is a git symlink (mode 120000) to
`../../ihp-sg13g2/libs.ref/sg13g2_sram`, with GDS, LEF, CDL, Verilog and Liberty at typ, slow and
fast for all 1P and 2P sizes. So "the slim PDK ships no SRAM macro" (kaikino) is wrong for this
revision; the macros are the sg13g2 ones, not separately characterised for cmos5l.

With tt_um_loom's recipe the flow hardens both macros side by side in a 6x4 block, end to end
(`tt_tool.py --harden --ihp`, exit 0) with 0 routing DRC, 0 LVS errors, 0 antenna violations, a
connected power grid and positive setup and hold slack at all three corners, and Tiny Tapeout's
precheck passes on the result, including the KLayout SG13CMOS5L DRC deck over the merged GDS
(0 violations, 3.15 million polygons). Magic DRC is not clean: it reports about 58,000 errors per
macro, every one of them inside a macro, and Magic DRC is not part of the cmos5l precheck. That
exception and one more (Magic "illegal overlaps" where the power stripes cross the macro's LEF
obstruction band) are documented below.

| run | design | result |
|---|---|---|
| 1 | 512x16 alone (`variants/config-512x16-only.json`) | all clean; slew/cap/fanout clean |
| 2 | 512x16 + 1024x8, one register set driving both | all clean, **but** 22 max-slew violations on macro inputs at the slow corner; precheck passes |
| 3 | 512x16 + 1024x8, separate input registers per macro (`src/`) | all clean except one clock-tree fanout item; precheck passes |

## The config.json keys, and why each

`src/config.json` is `tt/src/config.json` (the template) with one block added after `CLOCK_PORT`
and three PDN keys changed; `scripts/mkconfig.py` writes it and the 512x16-only variant. The
recipe is thomasgilbert481/tt_um_loom's (Apache-2.0; `src/config.json`, `src/pdn_cfg.tcl` and
`docs/tt_cmos5l_facts.md` sections 10 and 11 at commit fdaa854). Their failed CI runs are the
evidence for why each key is needed; this directory only ran the full recipe, so "needed" below is
their measurement except where a run here says otherwise.

| key | value here | why |
|---|---|---|
| `MACROS.<name>.instances` | key = **flattened instance path** (`sram512`, `sram1024`: the instances sit in the top module; a nested one would be `u_a.u_b.sram`), location, orientation `FS` | `CheckMacroInstances` rejects any other name (Loom run 1). `FS` mirrors about X so the signal pins (all at LEF y 0..0.26, 108 on the 512x16 and 70 on the 1024x8) face the rows above the macro; Loom's run 4 with `N` and the pins 6 um from the core edge never finished routing. Mirroring about X keeps the power columns' x. |
| `MACROS.<name>.gds/lef/spice` | `pdk_dir::libs.ref/sg13cmos5l_sram/{gds,lef,cdl}/<name>.*` | `pdk_dir::` expands to `$PDK_ROOT/ihp-sg13cmos5l` (LibreLane `config/preprocessor.py`), so nothing is vendored and the paths work wherever the action installs the PDK. The symlinked directory resolves inside the container because the whole `PDK_ROOT` is mounted. |
| `MACROS.<name>.lib` | keys `*_typ_*`, `*_slow_*`, `*_fast_*` | The cmos5l STA corners are `nom_typ_1p20V_25C`, `nom_slow_1p08V_125C`, `nom_fast_1p32V_m40C`; LibreLane loads every key that matches the corner, so keys must name the process corner. Verified here: each corner's post-route STA log reads exactly that corner's macro lib. The macro's fast lib is characterised at -55 C, the std cells' at -40 C. |
| `MACROS.<name>.nl` | `dir::<name>.v`, a port-only blackbox in `src/` | Synthesis reads it with `read_verilog -lib`; the PDK model would also do for synthesis, but the blackbox keeps lint simple. Not in `info.yaml`'s `source_files`. |
| `PDN_MACRO_CONNECTIONS` | `<inst> VPWR VGND VDD! VSS!` and `<inst> VPWR VGND VDDARRAY! VSS!` per instance | Ties both macro supplies (periphery and array) to the block's single supply without power pins in the RTL. |
| `PDN_CFG` | `dir::pdn_cfg.tcl` (Loom's, unchanged, plus a header) | On cmos5l the block's only stripe layer (Metal4) is also the macro's power-pin layer and TopMetal1 belongs to `tt_top`, so LibreLane's default macro grid (Metal4 to TopMetal1) is empty (Loom runs 2, 3). Loom's wrapper runs pdngen's four steps with the macros briefly unfixed, so the stripes run **full height through** the macros' same-net Metal4 power columns (the precheck pin check requires every power port to reach both block edges; Loom run 5), then fails the step if any stripe over a macro leaves its columns or any macro supply has no stripe. kdp1965's `ExtendPowerStripes` plugin (A7) solves the same problem with a plugin step; not used here. |
| `FP_PDN_VPITCH` 67.44, `FP_PDN_VSPACING` 3.52, `FP_PDN_VOFFSET` 26.36 (template: 50, -, -) | | Puts POWER stripes at x 29.24 + 67.44 n and GROUND stripes 5.62 um to the right: 67.44 = 6 x 11.24, the macros' same-net column pitch; 5.62 the POWER-to-GROUND column distance. `FP_PDN_VWIDTH` stays 2.1 (the precheck's minimum power-port width). |
| macro x positions | 512x16 at x 12; 1024x8 at x 326.72 | A macro's x must put stripes inside its columns. 512x16: x = 12 + 67.44 k (stripes at macro-local 17.24 + 67.44 j). 1024x8 (new here): x = -10.48 + 67.44 k, i.e. 259.28, 326.72, ...; two stripe pairs cross it, at local 39.72 / 107.16 (POWER) and 45.34 / 112.78 (GROUND), 0.02 um inside the column edges as on the 512x16. Checked offline (columns from the LEF) and by the wrapper in runs 2 and 3. |
| `MAGIC_EXT_ABSTRACT_CELLS` | `["RM_IHPSG13_.*"]` | Magic extracts the macros as abstract cells for LVS (urish/ttihp-sram-test's fix "blackbox SRAM macros during LVS"). LVS: 0 errors. |
| `ERROR_ON_MAGIC_DRC` | `false` | See "Magic DRC exception". |
| `ERROR_ON_ILLEGAL_OVERLAPS` | `false` | See "Illegal overlaps". |
| `MAGIC_MACRO_STD_CELL_SOURCE` | `PDK` | Kept from the recipe; harmless. cmos5l streams out the final GDS with KLayout (`PRIMARY_GDSII_STREAMOUT_TOOL klayout`). Not tested without it. |

Placement and the probe logic: the macros sit at y = 40 with the signal pins up, the 1024x8 to the
right of the 512x16. Tiny Tapeout's 6x4 DEF template puts all 43 block pins on the top edge.

## Results

Run directories (scratch, kept): `/var/tmp/chip-top-sram/run1-512x16`, `run2-both`, `run3-both`;
LibreLane run in `<stage>/runs/wokwi`, Tiny Tapeout submission in `<stage>/tt_submission`
(runs 2 and 3), precheck reports in `<stage>/tt/precheck/reports`. Small copies in `results/`.

| | run 1: 512x16 | run 2: both, shared inputs | run 3: both, per-macro inputs |
|---|---|---|---|
| std cells (excl. fill) / area | 561 / 8,878 um2 | 630 / 9,607 um2 | 851 / 12,857 um2 |
| hold buffers | 134 | 147 | 197 |
| macros / area | 1 / 45,309 um2 | 2 / 94,729 um2 | 2 / 94,729 um2 |
| placement | 512x16 FS (12, 40), bbox to (248.80, 231.34) | + 1024x8 FS (326.72, 40), bbox to (473.60, 376.46) | same |
| detailed routing DRC (iterations 0..3) | 187, 56, 83, **0** | 2, 0, 52, **0** | 259, 61, 59, **0** |
| Magic DRC | 57,923, all inside the 512x16 | 116,033 = 57,923 + 58,110, all inside the macros | 116,032 = 57,923 + 58,109, all inside the macros |
| Magic illegal overlaps | 5 | 11 | 11 (same boxes as run 2) |
| KLayout DRC in the flow | off (template: `RUN_KLAYOUT_DRC 0`) | off | off |
| LVS (netgen) | 0 errors | 0 errors | 0 errors ("Circuits match uniquely") |
| antenna (after repair) | 0 nets, 0 pins | 0, 0 | 0, 0 |
| power grid (PSM) | 0 violations, VPWR and VGND connected | same | same |
| max slew / cap / fanout | 0 / 0 / 0 | **22** (slow), 2 (typ) / 0 / 1 | 0 / 0 / 1 (`clkbuf_0_clk_regs`, CTS root, 16 > 8) |
| setup WS slow / typ / fast (ns) | +9.93 / +10.61 / +10.99 | +9.95 / +10.62 / +11.01 | +9.40 / +10.28 / +10.78 |
| hold WS slow / typ / fast (ns) | +0.661 / +0.327 / +0.139 | +0.664 / +0.328 / +0.138 | +0.596 / +0.301 / +0.125 |
| reg-to-reg setup WS slow / typ / fast | +12.79 / +18.25 / +18.73 | +11.75 / +14.96 / +18.63 | +11.83 / +18.08 / +18.62 |
| Tiny Tapeout precheck | not run | **pass**, 9/9 checks | **pass**, 9/9 checks |
| `--harden` wall time | 1,171 s (Magic DRC 1,067 s) | 1,006 s (Magic DRC 900 s) | 1,073 s (Magic DRC 883 s) |

Setup and hold slack are LibreLane's post-route multi-corner STA with the generic Tiny Tapeout
SDC (4 ns input and output delay, 0.25 ns uncertainty, 5% derate). The worst setup path at every
corner is input to output (`uio_in` to `uo_out` through the read-select mux), not a macro path.
Worst paths at a macro are in `results/*/macro-paths.txt`. Run 3, slow corner: the worst setup
path at a macro is the 1024x8's read (`sram1024` A_DOUT to a flop), +11.83 ns; in run 1 the
512x16's read had +12.79 ns, with the macro's clock-to-output at 6.60 ns in the report (6.29 ns
from the table plus the 5% derate). The worst hold checks in run 3 are all flop to macro input:
+0.596 ns (slow), +0.301 ns (typ), +0.125 ns (fast), which are also the design's worst hold. The flow fails only on the typical
corner (`TIMING_VIOLATION_CORNERS *typ*`); slow and fast are reported, and are positive here.

Run 2's slew violations: one register drove each address/data/mask bit of both macros over a net
about 300 um long; at the slow corner 22 macro input pins (A_ADDR, A_DIN, A_BM, A_WEN) saw up to
0.75 ns against the macro's `max_transition` of 0.5952 ns, and the flow did not repair or fail on
it (max-slew is a warning in LibreLane's checker). Run 3 gives each macro its own input registers
and has 0 slew violations at every corner. The one remaining item in runs 2 and 3 is max fanout on
the clock-tree root buffer `clkbuf_0_clk_regs` (16 sinks, limit 8): a CTS buffer with slew and
capacitance within limits, left as is.
The lesson for a larger design: drive each macro's inputs from nearby flops, or the resizer must
be told the slow-corner limit.

Simulation: `test/tb_probe.v` writes and reads both macros through the TT pins against IHP's
behavioural models (`-DFUNCTIONAL`), including a byte-masked write; it passes, and a mutated copy
with two wrong expectations fails on exactly those two.

### Magic DRC exception

Magic reports 57,923 errors for the 512x16 (the same count tt_um_loom reported) and 58,110 for the
1024x8. `scripts/magic-drc-by-region.py` places every box of `drc.magic.rpt`: **all of them lie
inside a macro's bounding box, none in the standard-cell area**. The rules are Metal2 minimum area
(M2.d, 30,720 per macro), "Can't overlap those layers" (~25,950), LU.d (~590), subcell overlap,
and the SRAM-exception rules NW.d and Cnt.c, which the KLayout deck relaxes inside the `SRAM`
marker layer and Magic's cmos5l techfile does not. Justification: Magic DRC is not one of the
cmos5l precheck checks (tt-support-tools `precheck/precheck.py` runs Magic DRC only for sky130A
and gf180mcuD); the sign-off check is the KLayout SG13CMOS5L deck over the merged GDS, which
reported 0 violations on runs 2 and 3. Watch for any Magic DRC box **outside** the
macros: that would be a real problem, and `magic-drc-by-region.py` prints it as `outside`.

### Illegal overlaps

Magic, extracting the macros from their LEF, reports "Illegal overlap between obsm4 and metal4"
wherever a POWER stripe crosses the LEF's Metal4 obstruction between a column's `VDD!` part (local
y 0..38.825) and its `VDDARRAY!` part (45.465..): 5 boxes for the 512x16 (as Loom), 6 for the
1024x8 (its two POWER stripes, which Magic reports as 4 and 2 pieces), all at the POWER stripes' x and the band's
y. `scripts/obs-band-metal.py` reads the macro GDS (flattened) and finds **no Metal4, Via3 or
TopMetal1 strictly inside that band under any of the stripes, for either macro**; within 1 um
there is only the same-net column metal ending and starting at the band's edges, and the `VDD!`
Via3 row at y 38.38..38.57 (`results/obs-band-metal.txt`). So the stripe only bridges `VDD!` to
`VDDARRAY!`, both on VPWR. LVS is clean and the KLayout deck sees the real metal.

### Precheck

`scripts/precheck.sh STAGE` runs what the GDS action runs after hardening:
`tt_tool.py --create-tt-submission --ihp`, then tt-support-tools' `precheck/precheck.py` (same
pinned commit) on `tt_submission/<top>.gds`. Two differences from the action: KLayout is the
pinned LibreLane image's 0.30.9 (the action's precheck environment lists 0.30.4), and KLayout runs
with 4 threads instead of every CPU (run 3; on run 2 the thread cap did not yet work and it used
32). On runs 2 and 3: 9 of 9 checks pass; the SG13CMOS5L deck ran its main table, 333 rules, over
3,149,349 (run 2) and 3,154,484 (run 3) polygons, and its report has 0 items in 332 categories
(`results/run*-both*/precheck*`). The precheck took 106 s each time. Run 1 was not prechecked.

## Macro pin timing at 20 ns (from the Liberty files)

`scripts/lib-timing.py` gives table minima and maxima over the characterised slew/load range
(`results/lib-timing.txt`). Slow corner (1.08 V, 125 C):

| | 512x16 | 1024x8 |
|---|---|---|
| A_CLK -> A_DOUT (clock-to-output) | 6.14 .. 6.56 ns | 6.94 .. 7.35 ns |
| setup A_MEN / A_WEN / A_REN (max) | 0.97 / 0.97 / 0.65 ns | same |
| setup A_ADDR / A_DIN, A_BM (max) | -0.07 / -0.05 ns | -0.07 / +0.03 ns |
| hold A_ADDR / A_DIN, A_BM / A_MEN (max) | 1.38 / 0.90 / 0.91 ns | 1.38 / 0.82 / 0.91 ns |
| A_CLK min pulse width | 0.40 ns | 0.40 ns |
| input max_transition | 0.5952 ns | 0.5952 ns |

Typical: clock-to-output 3.67..3.93 ns (512x16) and 4.16..4.42 ns (1024x8); fast: 2.26..2.42 and
2.56..2.72 ns. At 20 ns a synchronous read leaves about 20 - 7.35 x 1.05 - 0.25 = 12 ns for logic
after the 1024x8's output at the slow corner (less any clock skew and the capturing flop's setup).
The macro inputs' hold requirements (up to 1.38 ns on the address) are large next to a flop's,
and the worst hold checks in run 3 are all at macro inputs; the flow inserted 134 to 197 hold
buffers in runs 1 to 3 (not attributed path by path). Budget for them.

## Files

| path | what |
|---|---|
| `info.yaml`, `docs/info.md` | 6x4 project `tt_um_chip_sram_probe` |
| `src/project.v` | the probe: host-written registers drive every functional macro input, both macros' outputs registered and readable on `uo_out`; BIST ports tied off, `A_DLY` high |
| `src/RM_IHPSG13_1P_*.v` | port-only blackboxes for the macros |
| `src/config.json` | template plus the SRAM block (both macros) |
| `src/pdn_cfg.tcl` | tt_um_loom's PDN script (LibreLane default + macro-stripe wrapper and check) |
| `variants/config-512x16-only.json` | run 1's config (defines `SRAM_PROBE_NO_1024X8`) |
| `scripts/harden.sh` | `tt/scripts/harden.sh` taking the project directory (and optionally a config) as arguments; caps OpenROAD at 6 threads in the stage's copy of the config |
| `scripts/precheck.sh` | Tiny Tapeout submission + precheck on a hardened stage |
| `scripts/mkconfig.py` | writes the two configs from `tt/src/config.json` |
| `scripts/lib-timing.py`, `magic-drc-by-region.py`, `obs-band-metal.py`, `macro-paths.sh` | the measurements above |
| `test/tb_probe.v` | RTL test against IHP's behavioural models |
| `results/` | metrics, LVS report, PDN stripe check, Magic DRC by region, overlap boxes, STA checks, precheck results, log tails |

Commands:

    scripts/harden.sh . /var/tmp/chip-top-sram/NEW [variants/config-512x16-only.json]
    scripts/precheck.sh /var/tmp/chip-top-sram/NEW
    cd test && iverilog -g2012 -DFUNCTIONAL -o /var/tmp/probe.vvp tb_probe.v ../src/project.v \
      $PDK_ROOT/ihp-sg13cmos5l/libs.ref/sg13cmos5l_sram/verilog/{RM_IHPSG13_1P_512x16_c2_bm_bist,RM_IHPSG13_1P_1024x8_c2_bm_bist,RM_IHPSG13_1P_core_behavioral_bm_bist}.v \
      && vvp /var/tmp/probe.vvp

## Not covered

Silicon; chip-level IR drop and `tt_top` integration (Tiny Tapeout's job); gate-level simulation of
the hardened netlist; the BIST ports; the precheck with the action's own KLayout 0.30.4.

## Credits

- **thomasgilbert481/tt_um_loom** (Apache-2.0), commit fdaa854: the whole macro recipe
  (`src/config.json` keys, `src/pdn_cfg.tcl` copied unchanged below our header, the FS
  orientation, the stripe arithmetic, the illegal-overlap waiver and its GDS check idea).
- **kdp1965** (Apache-2.0): the `ExtendPowerStripes` idea for macro PDN (A7); not used.
- **kaikino**: the counter-claim (A8) this settles.
- **urish/ttihp-sram-test** (via Loom's notes): port-only blackbox and `MAGIC_EXT_ABSTRACT_CELLS`.
- **TinyTapeout/ttihp-verilog-template** (Apache-2.0): `info.yaml`, `docs/info.md` layout and the
  base `config.json`; **IHP-Open-PDK** (Apache-2.0): the macros and their models.
