# fpga_pio area on IHP sg13g2: measurement notes

Date: 2026-09-16. Purpose: turn the LUT figures from
<https://news.ycombinator.com/item?id=49664981> (a commenter) into standard-cell
numbers, and test the claim that fixed shift widths shrink the PIO shift
registers.

## Setup

- fpga_pio: <https://github.com/lawrie/fpga_pio> at commit
  f38be97cdfa86d4551c96bb98599e3443000628b (2023-05-03), cloned to `fpga_pio/`.
- Liberty: IHP-Open-PDK `sg13g2_stdcell_typ_1p20V_25C.lib`, fetched from the
  `main` branch on 2026-09-16; last commit touching that file: 721b1499ce1c786c4e83c783fc3497a6b4d58a61 2026-01-15T13:25:34Z.
  Copy in `sg13g2/`.
- Yosys 0.68+118 (git sha1 144c707b7-dirty) from the oss-cad-suite in
  `../hardware-2026-08/oss-cad-suite/`.
- Flow: `read_verilog -sv; hierarchy -check; synth -flatten; dfflibmap -liberty;
  abc -liberty; opt_clean; stat -liberty`. Area-oriented abc, no clock
  constraint, no place and route, so real numbers after OpenROAD will be
  larger. Script: `synth_sg13g2.sh`; variants in `variants/`; logs in `logs/`.
- Tile size: from the Tiny Tapeout memory page, a 256x8 SRAM of 17,547 um2 is
  27.7 % of a 1x2 tile, so one IHP tile is about 31,700 um2. Usable
  standard-cell area at a typical 50 to 60 % utilisation is about 16,000 to
  19,000 um2 per tile.

## Results

| Design | Cells | Area um2 | DFFs | mux2 | mux4 |
| --- | --- | --- | --- | --- | --- |
| isr (input shift register, as written) | 1172 | 17,183 | 38 | 267 | 99 |
| osr (output shift register, as written) | 1065 | 15,380 | 38 | 120 | 107 |
| isr, shift by 1 only | 239 | 3,743 | 38 | | |
| isr, shift by 1 or 8 | 365 | 4,748 | 38 | | |
| machine (one PIO state machine, all submodules) | 4713 | 61,638 | 193 | 388 | 229 |
| top/uart_rx.v (pio with NUM_MACHINES=4 plus loader) | 5721 | 96,546 | 767 | 632 | 275 |
| pio alone, NUM_MACHINES=4 | 26,370 | 414,765 | 2728 | | |

## Reading

- One state machine is about 4.7K cells and 61.6K um2, roughly two tiles at
  full utilisation and three to four at realistic utilisation. The two shift
  registers are 2,237 cells, 32.6K um2, 53 % of the machine.
- Restricting the input shifter to one bit per step cuts it from 17.2K to
  3.7K um2 (4.6x); the 38 flops (1.9K um2) stay, the logic drops 8x.
  Allowing 1 or 8 costs 4.7K um2.
- The uart_rx top is smaller than four machines because its `mindex` register
  is only ever 0, so Yosys constant-propagates the configuration of machines
  1 to 3 away. This is probably also what Vivado did for that commenter, so their
  1.4K LUTs is effectively one machine plus loader plus a 512-bit instruction
  memory in flops (767 DFFs here; Vivado likely put the memory in LUTRAM,
  which explains their 322 FFs). Ratio: about 4 cells per LUT for the top,
  2.5 for the isr.
- The standalone `pio` figure is NOT trustworthy: Yosys warned of multiple
  conflicting drivers on `pin_directions_prev` and `output_pins_prev`
  (pio.v lines 96 and 101), so the netlist may not match the intended design.
  Do not quote it.
- Budget: four real machines (4 x 61.6K) plus a 32-word instruction memory in
  flops (about 30K) plus glue is roughly 280K to 300K um2, which is 9 tiles at
  full utilisation and 16 to 18 at realistic utilisation. A straight PIO
  clone fits the 6x4 allocation but eats most of it; with the shifters fixed
  to 1 and 8 bits it drops by about 25K um2 per machine.
