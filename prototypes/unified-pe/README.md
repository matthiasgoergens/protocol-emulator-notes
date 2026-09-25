# Area probes for architecture v0 (2026-09-25)

Supporting measurements for `../../notes/architecture-v0.md`: the unified processing element (PE)
with every mode switchable by a define, the dedicated assists it competes with, and the segment
interconnect of a partitionable array. **These are area probes, not verified designs.** None of
the RTL here has an executable specification or a lockstep test yet; the architecture note lists
that as its first gap. A probe whose logic is wrong can still have roughly the right area, which is
all it is used for.

## Flow

`synth.sh TAG FILE TOP "DEFINES" "CHPARAM"` runs Yosys 0.62 inside the LibreLane 3.0.14 container
(`synth -flatten; dfflibmap; abc` in area mode, IHP sg13g2 typical liberty), the recipe of
`../pe-synth/synth.sh`. **Control:** `pe16` (copied from `../pe-synth/rtl/pe16.v`) gives
6,586.1964 µm², the figure `../pe-synth/results/areas.txt` reports for the same Yosys, so numbers
here compare directly with pe16. `python3 summary.py > results/areas.txt` tabulates every report.
`python3 budget.py > results/budget.txt` is the chip-level area budget.

## Files

- `rtl/upe.v`: the unified PE. Defines remove one mode each (`NO_GF2`, and its parts `NO_SHIFT`,
  `NO_LOGIC`, `NO_GATE`; `NO_POP`, `NO_LUT`, `NO_WIN`, `NO_LANES`) or add one (`BITSEL`). The
  configuration recommended in the note is `-DNO_POP -DNO_LUT -DBITSEL` (`upe_v0`).
- `rtl/assists.v`: a programmable CRC/LFSR unit (width and bits per clock as parameters), a bit
  stuffer/destuffer with programmable run length, a line coder (NRZI, Manchester, differential
  Manchester), a pin NCO that evaluates its phase at four points per clock, an oversampling
  bit-recovery front end, and the segment interconnect (`seg_xbar_cfg`).
- `reports/`, `logs/`: Yosys statistics and logs. `results/areas.txt`: the table.

## Results (`results/areas.txt`)

The PE ablation is on the final RTL: the `upe_full_*` rows remove one mode from the PE with every
mode, the `upe_v0_*` rows one mode from the recommended PE.

| probe | µm² | reading |
| --- | --- | --- |
| pe16 (control) | 6,586 | reproduces `../pe-synth` exactly |
| upe_none (base: operand and writeback selects, 8-byte configuration, init chain, flag) | 11,118 | the price of generality before any mode: +4.5k over pe16 |
| upe_full (every mode) | 16,332 | |
| upe_v0 (no popcount, no LUT, plus bit test) | see `results/areas.txt` | the recommended PE |
| mode increments on upe_full: GF(2) (shift, logic, gate, POP result path) / POP / WIN / LANES / LUT | 3,066 / 1,798 / 838 / 267 / 241 | full minus the variant |
| GF(2) parts alone on upe_full: SHIFT / LOGIC / GATE | 185 / 713 / 13 | the three overlap: together they are 3,066 |
| programmable CRC/LFSR, 32 bit, 1 bit per clock, with its poly and state registers | 7,127 | cf. 6,956 for `eth10-node`'s CRC unit without configuration registers (master) |
| the same, 16 bit | 3,387 | |
| the same, 32 bit, 8 bits per clock | 20,902 | a byte-wise CRC for 100 Mbit/s costs three 1-bit units |
| stuff unit / line coder | 813 / 477 | |
| pin NCO, 24 bit, four phase points per clock | 6,678 | |
| bit-recovery front end (probe) | 3,881 | cf. `eth10-node`'s verified edge-tracking sampler: 2,991 at 1 sample per clock, 9,184 at 4 |
| segment interconnect, 16 PEs, segments of 2 / 4 / 8, eight sources and eight destinations | 62,818 / 31,570 / 18,226 | a full crossbar is several PEs |
| the same, lean: two sources (feed register, fixed neighbour) and two destinations | 21,472 / 11,090 / 5,312 | the design in the note |

Abc's mapping moves individual increments by around a hundred µm² between runs of different
variants, so the small increments (LANES, LUT, BITSEL) are good to about ±100 µm².
