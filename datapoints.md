# External data points

## 2026-09-16: PIO clone area, from Hacker News

Source: <https://news.ycombinator.com/item?id=49664981>, comment by Neywiny.
They synthesised the UART receiver example of lawrie's fpga_pio
(<https://github.com/lawrie/fpga_pio>, a Verilog RP2040 PIO clone) with
Vivado.

| Item | Figure |
| --- | --- |
| Whole UART RX design | 1.4K LUTs, 322 flip-flops |
| One shift register module | 475 LUTs, 38 flip-flops |

Cause, from reading `src/isr.v` and `src/osr.v`: each builds a 64-bit value
and shifts it by a 6-bit runtime amount; the ISR does both directions and
muxes the results. Logarithmic barrel shifter: 64 muxes per stage, 6 stages,
two directions. PIO needs it because IN/OUT move 1 to 32 bits per
instruction.

Measured 2026-09-16 with Yosys 0.68 against the IHP sg13g2 liberty file
(area-oriented abc, no clock constraint, no place and route). Full notes,
script and logs in `../pio-area-notes/`.

| Design | Cells | Area um2 | DFFs |
| --- | --- | --- | --- |
| isr as written | 1172 | 17,183 | 38 |
| isr, shift by 1 only | 239 | 3,743 | 38 |
| isr, shift by 1 or 8 | 365 | 4,748 | 38 |
| osr as written | 1065 | 15,380 | 38 |
| one PIO state machine | 4713 | 61,638 | 193 |
| uart_rx top (effectively one machine, loader, 512-bit memory in flops) | 5721 | 96,546 | 767 |

One IHP tile is about 31,700 um2 (derived from the Tiny Tapeout memory
page). So one PIO machine is two tiles at full utilisation, three to four at
realistic utilisation, and the two shift registers are 53 % of it. Fixing
the shift width to one bit shrinks the input shifter 4.6x (the flops stay;
logic drops 8x). Four machines plus instruction memory is roughly 280K to
300K um2: it fits the 6x4 allocation but uses 16 to 18 of the 24 tiles at
realistic utilisation. Earlier claim "a straight PIO port with four state
machines does not fit" was wrong; corrected to "fits but eats most of the
budget".

Neywiny's 1.4K LUTs is most likely one effective machine: the uart_rx top's
machine index is a constant, so synthesis removes machines 1 to 3. Ratio
about 4 cells per LUT for the top, 2.5 for the shifter.

## 2026-09-21: FABulous eFPGA tile and fabric area on sg13g2

Measured with fabulous-fpga 2.2.0 and Yosys 0.68 against the IHP sg13g2
liberty file, one latch plus inverter per configuration bit, area-mode abc,
no place and route. Notes, scripts and logs in `../fabulous-notes/`.

| Design | Area um2 | Of which config latches | Of which switch muxes |
| --- | --- | --- | --- |
| one LUT4AB tile (8 LUT4, 616 config bits), hierarchical | 39,039 | 22.4K (57 %) | 13.6K (35 %) |
| same, flattened | 36,322 | 19.0K (52 %) | 13.6K (37 %) |
| 4x4 LUT4AB fabric with IO, terminators and config controller, flattened | 607,704 | 306K (50 %) | 169K (28 %) |

462 of the 616 tile config bits belong to the switch matrix, so routing
plus its configuration is 77 to 78 % of a tile. This reproduces the
"almost 80 %" figure from the collaboration mail on the stock fabric. Per
LUT4 all-in about 4,750 um2, so the 6x4 allocation holds roughly 90 LUT4s
at realistic utilisation with nothing else on the die. A hardened PIO
machine (61.6K) is 1.7 CLB tiles, and a UART receiver in LUTs does not fit
at all: the fabric can only be glue around hardened blocks. Largest lever
is the configuration latch count, i.e. a sparser switch matrix.

## 2026-09-21, later: FABulous levers measured

Same flow as above (details and logs in `../fabulous-notes/NOTES.md`).

| Experiment | Result |
| --- | --- |
| Sparse routing: drop length-4 and length-6 wires | LUT4AB tile 616 to 514 config bits, 36,322 to 29,378 um2 (19 % smaller); routability not yet measured |
| Hardened 8-bit shifter as a tile (13 ports) | tile 22,779 um2, block alone 1,281 (5.6 %) |
| Hardened 32-bit PIO-style shifter as a tile (80 ports) | tile 33,558 um2, block alone 4,962 (14.8 %) |

Reading: every tile carries about 20K um2 of through-routing and its
latches regardless of content, and each extra block port costs only about
160 um2. Tile count, not port count, is what a hardened-block fabric pays
for; blocks worth hardening must be large enough to amortise the tile tax,
or live outside the fabric with fixed wiring.
