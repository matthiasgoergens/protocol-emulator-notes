<!---
This file is used to generate your project datasheet.
-->

## How it works

The combined prototype of a programmable chip for protocol emulation: a four-thread deadline
sequencer (ISA v2), a partitionable array of processing elements, a four-phase pin stage (here on
both clock edges), a pin streamer and sampler, an edge-tracking sampler with a CRC unit and a
matcher, and a pin NCO. Everything is configured and loaded through a 4-bit host link on
uio[5:0]. See prototypes/chip-top/README.md in the repository.

## How to test

Hold run clear, load a programme through the host link, configure the pin map, set run.

## External hardware

The demo board's RP2040/RP2350 as host, driving the clock and the host link.
