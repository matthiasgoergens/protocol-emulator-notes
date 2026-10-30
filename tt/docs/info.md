<!---
This file is used to generate your project datasheet.
-->

## How it works

A programmable chip for serial protocols, aimed at UART, SPI, I2C, CAN, PS/2, USB low speed and
10BASE-T and at protocols it was not built for: the protocol is a programme, not hardware. Inside:

- a four-thread deadline sequencer (ISA v2) that times pin events to the clock;
- an array of four processing elements, partitionable into segments, for bit-level work;
- bit-path assists: a pin streamer and sampler, an edge-tracking sampler with clock recovery, a CRC
  unit, a pattern matcher and a pin NCO;
- a four-phase pin stage on both clock edges, so outputs move and inputs are sampled four times per
  clock (quarter-clock resolution: about 4.2 ns at 60 MHz).

Every output pin has a source select: a sequencer pin, a streamer pin, the NCO, a PE segment's tap,
or the recovered bit. Every sequencer input reads a selectable input pin. Everything is configured
and loaded through a 4-bit host link.

## Pins

| pins | use |
|---|---|
| `ui[7:0]` | general inputs, any protocol |
| `uo[7:0]` | general outputs, push-pull |
| `uio[3:0]` | host link data (the chip drives them only while the host reads) |
| `uio[4]` | host link strobe, from the host |
| `uio[5]` | host link read request, from the host |
| `uio[7:6]` | general pins with output enable: open drain (I2C, PS/2, CAN via a transceiver) |

## Host link

Every change of the strobe moves one nibble, high nibble first. To write, the host sets the data
lines, waits at least 2 clocks, toggles the strobe and holds the data 2 more clocks. To read, the
host releases the data lines, raises the read request, and toggles the strobe for each nibble, at
least 8 clocks apart. A command is `{op, target}`, address high, address low and a count n
(n + 1 bytes); op 1 writes, op 2 reads. Targets: 0 registers, 1 programme store, 2 data bank,
3 and 4 the host FIFOs, 5 to 7 the PE array, 8 streamer, 9 sampler, 10 matcher. Lowering the read
request returns the parser to idle, which also resynchronises it.

## How to test

1. Hold `rst_n` low for at least 4 clocks, then release it. Register 0 reads back 2: stopped, with
   the assists held.
2. Write each thread's boot page and pc (registers 4 to 8), the programme through target 1, any
   tables through target 2, the array configuration through targets 5 to 7, and the pin map
   through the registers.
3. Write 1 (or 3) to register 0 to run.

The cocotb test in `test/` does exactly this with a two-word programme that drives `uo` to 0xA5.

**Power-up and reselection.** Flip-flops and SRAM start with arbitrary contents. After the reset,
everything the pins do depends only on the inputs and on what the host has loaded. A deselected
design is powered down and loses everything, so after selecting it again, reset it and load the
programme again.

## External hardware

The demo board's RP2040/RP2350 as host, clocking the chip at 60 MHz and driving the host link. A
protocol's own hardware (transceivers, pull-ups, a 10BASE-T magnetics module) goes on a Pmod.
