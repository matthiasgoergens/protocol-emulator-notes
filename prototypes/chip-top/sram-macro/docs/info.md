<!---
SPDX-License-Identifier: Apache-2.0
Section headings follow TinyTapeout/ttihp-verilog-template docs/info.md.
-->

## How it works

A probe for IHP's single-port SRAM macros on sg13cmos5l: `RM_IHPSG13_1P_512x16_c2_bm_bist` and
`RM_IHPSG13_1P_1024x8_c2_bm_bist`. The host writes address, data, bit mask and control registers
over the pins; a rising edge on `go` gives the selected macro a one-clock access. Both macros'
outputs are registered every clock and can be read a byte at a time. The BIST ports are unused.

## How to test

Registers (index on uio[3:0], value on ui_in, written while uio[4] is high). Register 1 selects a macro and sets its controls; registers 0, 2-5 then go to the selected macro: 0 address[7:0];
1 {select 1024x8, read enable, write enable, 3'b0, address[9:8]}; 2 data[7:0]; 3 data[15:8];
4 bit mask[7:0]; 5 bit mask[15:8]. Raise uio[5] for one access. uio[7:6] picks what uo_out
shows: 0 and 1 the two bytes of the 512x16's output, 2 the 1024x8's output, 3 status.

## External hardware

None.
