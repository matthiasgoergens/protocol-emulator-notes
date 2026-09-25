# Synthesised PE and bank-periphery areas for the systolic-storage study (2026-09-25)

`../systolic-storage` sized its candidate arrays with a 16-bit PE of 5,000 µm², scaled from the
semiring ring, and with a gain-cell bank periphery estimated from standard-cell areas. This
directory replaces both with synthesised numbers, and adds place and route. Every number points
to a file here. IHP SG13G2, typical liberty at 1.2 V and 25 °C.

## Flow

- **RTL:** Hardcaml, `pe_rtl.ml`. `main.exe verilog NAME` writes `rtl/NAME.v`.
  `main.exe check 4000` runs each PE against an OCaml model (`check.txt`: 0 of 4,000 cycles differ
  for each). With `FAULT=1` the model computes min as max, and 752 / 944 / 756 cycles differ for
  the three ALU PEs, so the check can fail.
  - The bank periphery (`rtl/gc_periph.v`) and the latch register file (`rtl/latch_rf.v`) are
    written in Verilog. They instantiate their drivers and latches.
- **Synthesis:** `synth.sh NAME` runs `synth -flatten; dfflibmap; abc` (area mode) and `stat`.
  - The default is Yosys 0.62 inside the LibreLane 3.0.14 container (`ghcr.io/librelane/librelane:3.0.14`,
    run with docker). Nothing was installed on the host.
  - `YOSYS_HOST=1` uses Yosys 0.69+77 from the oss-cad-suite in `~/prog/janestreet/fabulous-notes`.
    That is the build that produced the ring's 169,641 µm², and it reproduces the figure
    exactly (`reports/semiring_ring-y069.stat.txt`).
  - `periph.sh` synthesises the bank periphery for four shapes.
  - Logs are in `logs/`, statistics in `reports/`, and the summary is `results/areas.txt`
    (`python3 summary.py`). Netlists are in `/var/tmp/pe-synth/netlists` (scratch).
- **Place and route:** `pnr/run_pnr.sh NAME PERIOD UTIL` runs LibreLane 3.0.14 with its own Yosys
  synthesis. It uses a 20 ns clock (50 MHz) and a relative floorplan at the target utilisation.
  - Metrics, config, flow log and LibreLane's synthesis statistics are in `pnr-metrics/<tag>/`.
    The summary is `results/pnr.txt` (`python3 pnr/metrics.py`).
  - Run directories are in `/var/tmp/pe-synth/pnr` (scratch).
- **Tool spread:** Yosys versions differ by up to 8 % on the same RTL. The ring gives 169,641 µm²
  with 0.69+77, 172,554 with 0.68+118 (not kept), and 176,496 with 0.62. The flop area is the
  same in all three; the difference is in abc's combinational mapping.

## Where 10,603 µm² came from, and what one cell costs

The ring's README gives 169,641 µm² for the whole ring, and 169,641 / 16 = 10,603. So that number
also includes the ring's shared logic:
- PAL timing and colour output;
- the palette, taps, LUT and ramp configuration (42 of the 106 configuration bytes);
- the output multiplexers.

`ring_cell24` is one cell cut out with the same arithmetic, muxes and configuration/init chains.
It comes to **8,762 µm²** (0.69) or **9,339** (0.62), with 56 flops. The other ~29k µm² of the ring
is shared.

## Synthesised areas (`results/areas.txt`, µm²; Yosys 0.62, with 0.69 in brackets)

| design | cell area | flops | what it is |
|---|---|---|---|
| ring_cell24 | 9,339 (8,762) | 56 | one ring cell, 24 bit |
| ring_cell16 | 6,481 (6,072) | 40 | the same cell narrowed to 16 bit |
| **pe16** | **6,586 (6,085)** | 56 | the PE `candidates.py` describes: add/sub/max/min with saturation, one neighbour input, y = state or k, 16-bit state and pipeline registers, 24 configuration flops |
| pe16_row8 / 8 | **6,559 (6,035)** | 56 | eight pe16s chained (pipeline and configuration chain) |
| minplus16 | 4,443 (4,251) | 48 | acc = min(acc, a + b), saturating; a and b registered and passed on |
| mac16 | 23,437 (23,130) | 64 | acc += a × b signed, 32-bit accumulator |
| mac16, `synth -booth` | 17,004 (17,104) | 64 | the same with Yosys's Booth multiplier |

The 16-bit PE is **6,559 µm², 31 % above the 5,000 estimate**. The estimate scaled the whole
ring's per-cell figure by width, 0.47 times. A real cell scales much less than that:
- pe16 is 0.70 of ring_cell24;
- its 24 configuration and 32 state/pipeline flops, at 49 µm² each, are 2,743 µm² on their own.

A MAC PE costs 2.6–3.6 times an add/min PE. Min-plus is the cheapest useful PE, at 4,443.

## Place and route (`results/pnr.txt`; LibreLane 3.0.14, 20 ns clock)

| tag | synth (LibreLane) | std cells after PnR | core | final utilisation | setup slack typ / slow | fmax slow |
|---|---|---|---|---|---|---|
| pe16_row8, 65 % target | 57,162 | 70,856 | 87,320 | 0.81 | 12.98 / 11.35 ns | 116 MHz |
| **pe16_row8, 72 % target** | 57,162 | 70,658 | **78,814 (9,852 per PE)** | 0.90 | 12.89 / 11.22 ns | 114 MHz |
| pe16_row8, 80 % and 90 % | | | | | detailed placement failed (`pnr-metrics/pe16_row8_20ns_u80`, `_u90`) | |
| pe16 | 7,239 | 9,139 | 10,728 | 0.85 | 12.94 / 11.32 | 115 MHz |
| ring_cell16 | 7,177 | 9,589 | 10,680 | 0.90 | 12.28 / 10.23 | 102 MHz |
| minplus16 | 5,111 | 6,492 | 7,679 | 0.85 | 12.63 / 10.82 | 109 MHz |
| mac16 (no Booth) | 23,896 | 26,822 | 36,197 | 0.74 | 9.39 / 5.76 | 70 MHz |

Hold slack is positive everywhere, with zero routing DRC errors. Every PE closes 50–60 MHz at
the slow corner (1.08 V, 125 °C) with room to spare. The MAC closes 70 MHz.

**A placed PE takes 9,852 µm² of core, 1.50 times its Yosys cell area** (6,559). The growth
comes from four places:
- LibreLane's timing-driven synthesis: 57,162 against 52,474 area-mode.
- Repair and tie cells: 186 port buffers, 328 fanout buffers (for the configuration strobe and
  enables), 508 hold buffers (flop-to-flop shift chains) and 448 tie-high cells. The library's
  only flop, `dfrbpq_1`, has an asynchronous reset pin that must be tied off.
  (`pnr-metrics/pe16_row8_20ns_u72/librelane.log`.)
- The clock tree.
- 90 % final utilisation, the densest that placed.

The port buffers (186 `buf_1`, 1,350 µm²) would not exist inside a larger array. They are 1.9 % of the stdcell area.

## Gain-cell bank periphery (`reports/gc_periph_*.stat.txt`, `latch_rf_8x16`)

The periphery contains:
- registered address and enables;
- a one-hot decoder gated into a write and a read word line per row, each driven by an
  instantiated `buf_2`;
- per column, an `ebufn_2` write driver, an `inv_1` sense inverter and a `dlhq_1` output latch.

It leaves out, as the estimate does: read-bit-line precharge, the VLO level for the level-shift
trick, refresh control and Berger logic.

| shape (rows × columns) | synthesised | estimate (`storage_options.gain_array` minus cells) |
|---|---|---|
| 32 × 64 | 5,369 | 4,935 |
| 128 × 38 (the 128×32 thick bank with Berger) | 8,363 | 6,481 |
| 32 × 21 (the 32×16 thin bank with Berger) | 3,028 | 2,595 |
| 8 × 21 (an 8-word per-PE bank) | 1,784 | 1,854 |
| 8×16 latch register file | 5,343 | 5,835 |

The periphery of the three larger banks comes out 9–29 % above the estimate. This is mostly
because the word-line drivers here are `buf_2` against the estimate's `buf_1`, and the 128-row
decoder is larger. The 8-row bank is 4 % below. The latch
file comes out 8 % below: abc builds its read mux from `a22oi`/`nand4` rather than a `mux4` tree.

## Open questions

- **Word-line driver size:** the choice of `buf_2` is mine. The load is 38 gates plus wire, and
  the right size needs the drawn array's capacitance.
- **Periphery and latch file are synthesised, not placed.** `../systolic-storage` scales them by
  the PE's placed/synthesised ratio (1.50), which is an assumption.
- **Arrays larger than 8 PEs:** the per-PE core area is not measured beyond eight.
- **Cheaper configuration:** latches for configuration, as the ring README suggests, would save
  about 18 µm² per bit on the 24 configuration bits, and the tie cells with them.
