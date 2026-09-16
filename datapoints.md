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

Implication: at several cells per LUT the design is plausibly 5K to 10K
sg13g2 cells for one state machine, a quarter to a half of the 24-tile
budget before SRAM. A straight PIO port with four state machines does not
fit. Fix widths at compile time; shift-by-1 and shift-by-8 cost one or two
muxes per bit.

Unverified: LUT-to-cell ratio, and how many state machines the measured top
level instantiated. Both settled by running Yosys on fpga_pio with the
sg13g2 liberty file, which is also the synthesis bake-off's baseline.
