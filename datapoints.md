# External data points

## 2026-09-16: PIO clone area, from Hacker News

Source: <https://news.ycombinator.com/item?id=49664981>, a comment there.
They synthesised the UART receiver example of the fpga_pio project
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
script and logs in `measurements/pio-area/`.

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
realistic utilisation. The estimate above this table, made before measuring, said a
four-machine PIO port would not fit; the measurement says it fits but
eats most of the budget.

The commenter's 1.4K LUTs is most likely one effective machine: the uart_rx top's
machine index is a constant, so synthesis removes machines 1 to 3. Ratio
about 4 cells per LUT for the top, 2.5 for the shifter.

## 2026-09-21: FABulous eFPGA tile and fabric area on sg13g2

Measured with fabulous-fpga 2.2.0 and Yosys 0.68 against the IHP sg13g2
liberty file, one latch plus inverter per configuration bit, area-mode abc,
no place and route. Notes, scripts and logs in `measurements/fabulous/`.

| Design | Area um2 | Of which config latches | Of which switch muxes |
| --- | --- | --- | --- |
| one LUT4AB tile (8 LUT4, 616 config bits), hierarchical | 39,039 | 22.4K (57 %) | 13.6K (35 %) |
| same, flattened | 36,322 | 19.0K (52 %) | 13.6K (37 %) |
| 4x4 LUT4AB fabric with IO, terminators and config controller, flattened | 607,704 | 306K (50 %) | 169K (28 %) |

462 of the 616 tile config bits belong to the switch matrix, so routing
plus its configuration is 77 to 78 % of a tile. This reproduces, on the stock fabric, the
"almost 80 %" routing share that is often quoted for small LUT fabrics. Per
LUT4 all-in about 4,750 um2, so the 6x4 allocation holds roughly 90 LUT4s
at realistic utilisation with nothing else on the die. A hardened PIO
machine (61.6K) is 1.7 CLB tiles, and a UART receiver in LUTs does not fit
at all: the fabric can only be glue around hardened blocks. Largest lever
is the configuration latch count, i.e. a sparser switch matrix.

## 2026-09-21, later: FABulous levers measured

Same flow as above (details and logs in `measurements/fabulous/NOTES.md`).

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

## 2026-09-21, later: FABulous LUT4AB tile through place and route

LibreLane 3.0.14 in its container on IHP sg13g2, 20 ns clock, defaults
otherwise; flow logs and per-step metrics under `measurements/fabulous/pnr-metrics/`.

| Target util | Die um2 | Final util | DRC violations | Setup worst slack |
| --- | --- | --- | --- | --- |
| 55 % | 83,772 | 65.5 % | 0 | -11.9 ns |
| 65 % | 71,766 | 77.0 % | 0 | -13.0 ns |
| FABulous's shipped 246 x 245 um floorplan | 60,270 | 91 % at CTS | placement failed | |

Routing closes with room to spare at 77 % utilisation, so the routing
share is an area fact, not a congestion problem. Timing repair adds about
18 % to the synthesised cell area. A stock tile really costs 2.3 to 2.6
Tiny Tapeout tiles, so the 6x4 allocation holds 75 to 85 LUT4s. Worst
tile-crossing path is about 32 ns at the typical corner before any
timing optimisation, so a fabric clock near 66 MHz is not available
without pipelining; fast protocols must be hardened.

## 2026-09-21, later: routability of the sparse fabric

Four small protocol designs (UART TX hand-written and in Hardcaml, SPI
master, I2C bit engine) routed with nextpnr on stock and sparse FABulous
fabrics; details, driver and logs in `measurements/fabulous/bench/` and
`measurements/fabulous/NOTES.md`.

| Fabric | Result |
| --- | --- |
| stock and sparse 4x4 (128 cells) | all four route; identical cell counts and wirelength on both |
| stock and sparse 3x3 (72 cells) | all route, UART at 83 % utilisation; identical wirelength on both |
| 2x2 (32 cells) | fails on cell capacity, not routing |

The 19 % tile-area saving from dropping the length-4 and length-6 wires
costs nothing on these designs. The utilisation at which the sparse fabric
first loses a design is still unknown.

## 2026-09-21, later: remaining place-and-route runs

LibreLane 3.0.14, IHP sg13g2, 65 % target utilisation, 20 ns clock unless
stated; metrics under `measurements/fabulous/pnr-metrics/`, reading in
`measurements/fabulous/NOTES.md`.

| Run | Die um2 | Setup slack fast / typ / slow (ns) |
| --- | --- | --- |
| stock LUT4AB | 71,766 | -3.5 / -11.7 / -25.5 |
| stock LUT4AB at 40 ns | 71,766 | +8.5 / +0.4 / -13.4 |
| sparse LUT4AB | 57,815 | -1.6 / -8.8 / -20.9 |
| PIO8 hardened tile | 47,343 | +5.5 / +5.4 / +5.2 |
| PIO32 hardened tile | 65,900 | +5.5 / +5.4 / +5.2 |

All route with zero violations; magic DRC, KLayout DRC and XOR are clean
on the stock tile. The sparse tile's 19 % saving holds after place and
route. The LUT tile's worst path is about 32 ns typical and 45 ns at the
slow corner; both hardened tiles close at 20 ns at every corner, so the
LUT tile's slow paths are in the LUT input muxes, not the wire switching.

## 2026-09-21, later: deadline sequencer prototype

Four-thread deterministic sequencer in Hardcaml (`prototypes/deadline-sequencer/`),
lockstep-tested against its OCaml interpreter on 300 random programmes x
2000 cycles with zero mismatches, mutation-checked (inverted branch:
514,694 mismatches), UART transmitter and deadline programmes passing.

| Design | Cells | Area um2 | Flip-flops |
| --- | --- | --- | --- |
| deadline sequencer, 4 threads, instruction memory external | 1,052 | 17,300 | 179 |
| one fpga_pio state machine (same flow) | 4,713 | 61,638 | 193 |
| one FABulous LUT4AB tile (same flow) | 2,828 | 36,322 | 8 + 616 latches |

Place and route at 15 ns: die 36,663 um2, zero routing violations, setup
slack +8.2 / +7.8 / +7.3 ns at fast / typical / slow corners. The core
runs at the competition clock at every corner where the LUT fabric does
not reach it at any.

## 2026-09-21, later: systolic pattern correlator prototype

Sixteen-cell systolic correlator in Hardcaml (`prototypes/systolic-matcher/`),
lockstep-tested against its closed-form specification on 300 random
configurations x 500 samples with zero mismatches; directed pattern tests
pass.

| Design | Cells | Area um2 | Flip-flops |
| --- | --- | --- | --- |
| systolic correlator, 16 cells, 37 config bits | 458 | 10,015 | 139 |

Place and route at 5 ns: die 31,488 um2, zero routing violations, setup
slack +2.7 / +2.2 / +0.9 ns at fast / typical / slow corners, so the array
runs at 200 MHz at the slow corner. 241 hold buffers were needed after
clock-tree synthesis, which is the price of an all-register design.

## 2026-09-22: protocol compiler demo on the deadline sequencer

Three protocols compiled onto three threads (38, 27, 63 words), run on the
RTL with an I2C slave model; interpreter and RTL agree on every cycle;
independent decoders recover all payload bytes; edge spacings equal the
closed forms with zero deviation. Fault injection: a stretched data bit
breaks a mid-bit-sampling receiver at exactly half a bit of cumulative
shift. Baud sweep: +-3.1 % decodes, +-6.2 % fails. The ISA gained an
open-drain shift-out mode for I2C. Details in
`prototypes/deadline-sequencer/README.md`.

## 2026-09-22: USB full-speed device prototype

Receiver, transmitter and protocol engine in Hardcaml
(`prototypes/usb-fs-device/`), enumerated in simulation by a bit-level host
model written from the specification: device and configuration
descriptors, SET_ADDRESS, SET_CONFIGURATION, bulk loopback, NAK on empty,
rejection of a corrupted packet, silence to a wrong address, every reply
within the 2 to 6.5 bit-time window. Two planted bugs caught.

| Design | Cells | Area um2 | Flip-flops | Place and route |
| --- | --- | --- | --- | --- |
| USB full-speed device, 48 MHz | 1,917 | 29,669 | 305 | die 67,671 um2, slack +11.7 ns at the slow corner, 0 violations |
