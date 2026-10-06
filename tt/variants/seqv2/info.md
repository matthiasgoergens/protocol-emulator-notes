<!---
SPDX-License-Identifier: Apache-2.0
Section headings follow TinyTapeout/ttihp-verilog-template docs/info.md.
-->

## How it works

The core is the ISA v2 deadline sequencer of `prototypes/sequencer-v2`: four threads sharing eight
pins, executing 16-bit instructions on a fixed round-robin schedule. Its Verilog is generated from
the Hardcaml source (`tt/scripts/regen.sh`) and is not edited by hand.

This wrapper is a harness placeholder. It holds a 64-word programme store in registers and loads
it serially; the final design is meant to use the SRAM macro instead. The data bank, mailbox
ports and flag inputs are tied off.

## How to test

Hold `run` (uio[2]) low. Shift each 16-bit instruction word in, MSB first, on `load_data` (uio[0])
with `load_strobe` (uio[1]) high for 16 clocks; the load address advances after every word.
Raise `run`. All four threads start at address 0.

## External hardware

None.
