# FABulous eFPGA area on IHP sg13g2: recreating an "80 % routing" figure

Date: 2026-09-21. Purpose: reproduce, from the stock FABulous fabric, the
often-quoted figure that the switch matrix and routing eat
about 80 % of a small eFPGA built for the Jane Street protocol-emulator
competition, and find the levers for shrinking it.

## Setup

- fabulous-fpga 2.2.0 from PyPI in a project-local venv (`.venv`, Python
  3.12 via uv). No global environment touched.
- Yosys 0.68+118, an oss-cad-suite build.
- Liberty: IHP sg13g2 `sg13g2_stdcell_typ_1p20V_25C.lib`, copy in
  `../pio-area/sg13g2/`, not vendored (PDK commit 721b1499, 2026-01-15).
- Projects (generated trees, not committed): `demo/` is the stock
  `FABulous create-project` fabric (10x14, LUT4AB, RegFile, DSP, RAM_IO);
  `small/` is the same template with `fabric.csv` cut down to 4 columns x
  4 rows of LUT4AB, a W_IO column and N/S terminators (the edited
  `fabric.csv` is committed as `tiles/small_fabric.csv`). Both generated
  with `FABulous -p <proj> run run_fab`.
- Synthesis: `synth/synth_tile.sh` (one tile) and `synth/synth_fabric.sh`
  (whole `eFPGA_top`), flow `synth [-flatten]; techmap latch; dfflibmap;
  abc -liberty; stat -liberty`. Latches map to `sg13g2_dlhq_1` (30.8 um2)
  through `synth/sg13g2_latchmap.v`. The behavioural `config_latch` in
  `models_pack.v` synthesised to two latches per bit (one for Q, one for
  QN); `synth/models_pack_onelatch.v` replaces it with one latch plus an
  inverter, which is what a real config cell costs. Area-mode abc, no clock
  constraint, no place and route. Logs in `logs/`.
- Tile size: one Tiny Tapeout IHP tile is about 31,700 um2 (see
  `../pio-area/NOTES.md`); 6x4 tiles = 760K um2 raw, roughly 420K
  usable at 55 % utilisation.

## Results

One LUT4AB tile (8 x LUT4 with flip-flop, 616 configuration bits of which
462 belong to the switch matrix):

| Run | Cells | Area um2 | Config latches | Switch muxes | LUT BELs |
| --- | --- | --- | --- | --- | --- |
| hierarchical, two latches per bit (stock model) | 2372 | 58,039 | 1232 | | |
| hierarchical, one latch + inverter | 1756 | 39,039 | 616 (22.4K incl. inverters, 57 %) | 13.6K (35 %) | 2.9K (7 %) |
| flattened, one latch + inverter | 2828 | 36,322 | 616 (19.0K, 52 %) | 13.6K (37 %) | rest 3.7K |

Routing share of the tile = switch matrix + its 462/616 of the config
memory = 13.6K + 16.8K = 30.4K of 39.0K = **78 %** (hierarchical) or
13.6K + 14.3K = 27.9K of 36.3K = **77 %** (flattened). The eight LUT4s and
their flip-flops are 7 to 10 %.

Whole 4x4 fabric (16 LUT4AB tiles = 128 LUT4, 4 W_IO tiles, 8 terminators,
config controller with UART and bit-bang loaders, frame registers):

| Run | Cells | Area um2 | Latches | mux4 + mux2 | DFF | Config controller |
| --- | --- | --- | --- | --- | --- | --- |
| hierarchical | 30,919 | 686,727 | 10,312 (318K, 46 %) | 6312 + 1641 (271K, 39 %) | 592 (29K) | 25.5K (3.7 %) |
| flattened | 52,542 | 607,704 | 9,908 (306K, 50 %) | 3855 + 1232 (169K, 28 %) | 586 (29K) | (flattened) |

Per LUT4, all-in: about 4,750 um2 flattened. The Tiny Tapeout budget at
realistic utilisation holds roughly **90 LUT4s and nothing else**; the raw
budget holds about 160.

## Reading

- The 80 % figure is reproduced from first principles on the default FABulous
  tile: about 78 % of a CLB tile is routing once the switch matrix's own
  configuration bits are charged to it. It is structural: the configuration
  latch (30.8 um2) is the single largest cost, and 75 % of the bits
  configure routing, not logic.
- Levers, in order of size: (1) fewer configuration bits, i.e. a sparser
  switch matrix (`Tile/LUT4AB/LUT4AB_switch_matrix.list` and the wire set in
  `Tile/include/Base.csv`: dropping the length-4 and length-6 wires is the
  obvious first cut); (2) coarser BELs so each configuration bit buys more
  function (hardened PIO blocks); (3) a denser storage cell than a
  standard-cell latch, which the open PDK does not offer; (4) sharing the
  select polarity so the QN inverters go away (already what flattening
  achieves for the muxes).
- Cross-check with `../pio-area/`: one hardened PIO state machine is
  61.6K um2, about 1.7 CLB tiles, and a UART receiver on PIO needs on the
  order of a thousand LUTs, so on this fabric it does not fit at all. The
  fabric can only be glue around hardened blocks. At 420K usable, four
  hardened machines (246K) plus the config controller and frame registers
  (35K) leave room for three or four CLB tiles, i.e. 24 to 32 LUT4s.
- Not measured: place and route (routing congestion of switch matrices
  usually costs extra area), the sparse-matrix variant, and a fabric with a
  hardened custom BEL tile. Those are the next experiments.


## 2026-09-21, later: the three open measurements

### Sparse routing

Project `sparse3/` (generated, not committed; `synth/prune_long_wires.py`
recreates it from the small project). Removed the length-4 and length-6 wires (N4, NN4, S4, SS4, EE4, WW4, E6, W6)
from `Tile/include/Base.csv`, pruned the matching mux inputs from every
switch-matrix list elementwise (whole-line removal orphaned jump wires), and
deleted the stale `*_ConfigMem.csv` maps so the generator rebuilt them.

| Tile | Config bits (routing) | Area um2, flattened | Latches | mux4 + mux2 |
| --- | --- | --- | --- | --- |
| LUT4AB stock | 616 (462) | 36,322 | 19.0K | 13.6K |
| LUT4AB sparse | 514 (360) | 29,378 | 15.9K | 9.1K |

19 % smaller with identical logic. Routing share drops from 77 % to about
70 %. Routability of the sparse fabric is NOT measured (needs nextpnr on a
benchmark set); this is the upper bound on the saving from that cut.

### Hardened blocks as tiles

Project `hard/` (generated, not committed); the block Verilog, tile CSVs
and switch lists are committed under `tiles/PIO8/`, `tiles/PIO32/` and
`tiles/hard_fabric.csv`, and `synth/make_hard_tiles.py` regenerates the
lists. Two custom BEL tiles, switch lists derived from the LUT4AB list (inputs
take the LUT-input jump wires, outputs replace LA_O..LH_O in the driver
lists, carry passed through, shared SR/EN jump wires declared):

| Tile | Block | Ports routed | Config bits | Tile area um2 | Block alone | Block share |
| --- | --- | --- | --- | --- | --- | --- |
| PIO8 | 8-bit shifter with load, dir, empty | 13 | 394 | 22,779 | 1,281 | 5.6 % |
| PIO32 | 32-bit fixed-1-or-8 ISR (fpga_pio port list) | 80 | 460 | 33,558 | 4,962 | 14.8 % |
| LUT4AB | 8 x LUT4 + FF | 48 | 616 | 36,322 | 2,860 | 7.9 % |

Reading: a tile carries a fixed through-routing tax of roughly 20K um2
(the N/E/S/W wire switching and its latches) whatever sits in it; each
additional block port costs only about 160 um2 (PIO32 minus PIO8, divided
by 67 ports). So the port count of a hardened block is not the problem;
the number of tiles is. A block worth hardening should be large enough to
amortise the tile tax: a whole PIO machine (61.6K) in a tile is roughly
86K, 29 % overhead, whereas the 8-bit shifter is 94 % overhead. The
alternative is to keep hardened blocks outside the fabric with fixed
wiring and route only their few control signals through it.

### Place and route

Native `gen_tile_macro` failed in LibreLane's Yosys step (`Option 'y' does
not exist`: the wrapper passes a flag the oss-cad-suite Yosys 0.68 rejects).
Running LibreLane 3.0.14 in its container instead (`pnr/run_pnr_util.sh`,
config `synth/librelane_lut4ab.json`, die area 246 x 245 um from the tile's
own `gds_config.yaml`, i.e. FABulous's proven IHP floorplan for this tile:
60,270 um2, which against 36.3K of cells is 60 % utilisation). Getting the container to run took four fixes worth recording: Docker's
credential helper wants D-Bus (empty `DOCKER_CONFIG` fixes it); the
`--dockerized` wrapper attaches stdin even with `--docker-no-tty`, so the
container is run directly with the same mounts (`pnr/run_pnr_util.sh`);
LibreLane phones home to ciel unless given `--manual-pdk`; and with that
flag `--pdk-root` must be the family directory `~/.ciel/ihp-sg13g2`, not
`~/.ciel`.

Result at the absolute 246 x 245 um floorplan (flow log and per-step
metrics in `pnr-metrics/lut4ab_stock/`):
detailed placement failed after clock-tree synthesis and timing repair.
Metrics at that point: die 60,270 um2, core 49,584, instance area 45,238
(91 % of core), of which 5,247 timing-repair buffers and 1,836 other
buffers; the floorplan started at 80 % effective utilisation. So the
FABulous-shipped tile size does not close in this flow at a 20 ns clock.
Follow-up runs let the tool size the die at 55 % and 65 % core
utilisation (`synth/librelane_lut4ab_util{55,65}.json`).

### Place-and-route results, tool-sized die (`pnr-metrics/lut4ab_util55/`, `pnr-metrics/lut4ab_util65/`)

LibreLane 3.0.14 in its container, IHP sg13g2, LUT4AB stock tile with the
one-latch configuration cell, 20 ns clock, default IO constraints, magic
and KLayout DRC disabled for speed. Both runs completed detailed routing
with zero DRC violations, extracted, and streamed out GDS; the flow's only
error is the deferred setup-violation checker.

| Target core util | Die um2 | Core um2 | Synth cell area | After repair | Timing buffers | Final util | Wirelength um | DRC | Setup WS | Hold WS |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 55 % | 83,772 | 72,012 | 39,712 | 47,167 | 7,031 | 65.5 % | 155,488 | 0 | -11.9 ns | +0.40 ns |
| 65 % | 71,766 | 60,619 | 39,712 | 46,670 | 6,545 | 77.0 % | 148,274 | 0 | -13.0 ns | +0.41 ns |
| absolute 246x245 | 60,270 | 49,584 | 39,712 | 45,238 (at CTS) | 5,247 | 91 % | failed in detailed placement | | | |

Reading:

- Routing is not the constraint at these densities: zero violations at
  77 % final utilisation. The 80 % figure is about area
  share, not routability.
- Place and route adds about 18 % over the synthesised cell area, almost
  all of it timing-repair buffers (7K um2), plus the free space of the
  target utilisation. Per stock tile the real die cost is 72K to 84K um2,
  i.e. 2.3 to 2.6 Tiny Tapeout tiles for eight LUT4s; the 6x4 allocation
  holds about 9 to 10 CLB tiles, 75 to 85 LUT4s, with nothing else on it.
- LibreLane's synthesis lands at 39.7K, 9 % above the area-mode Yosys
  number (36.3K), so the earlier tables are slightly optimistic.
- Timing: worst setup slack is about -12 ns against 20 ns, so the tile's
  worst constrained path is around 32 ns at the typical corner with
  default IO delays and no timing-driven optimisation. Take that as
  "tens of MHz for paths crossing a tile", not as a fabric fmax; a real
  fabric clock needs the multi-tile paths and the slow corner. For the
  competition's 66 MHz clock this says the fabric will need pipelining or
  a divided clock, which is one more reason the fast protocols must be
  hardened rather than routed.
- Not done: the sparse and hardened tiles through place and route (same
  script, different config), timing-driven runs, the slow corner, and
  DRC with magic/KLayout. Each is a config change and a few minutes.
