# Pin-vector streamer: one generic output primitive, four protocols, no CPU

A step towards "conventional CPU + systolic array + heavy precomputation". The goal is the smallest generic bit-level primitive that takes transmit timing off the CPU entirely, so the CPU is free for protocol logic, not "barely speaking the protocol".

## What it is

Every `period` clocks it drives the next `width`-bit vector (1, 2 or 4 pins) from a four-entry FIFO that the host fills directly, like the SNES's HDMA.
- Each FIFO entry is a 16-bit word plus a 4-bit vector count, so a stream need not end on a word boundary.
- There is an open-drain mask per pin, and an idle state that the pins take when the FIFO runs dry.

It knows nothing about any protocol. Framing bits, clock phases, line codes and end-of-frame behaviour all come from precomputation. The executable specification is `model.ml`, and the RTL is `streamer.ml`.

## Checks (`dune exec ./main.exe`), all on the RTL

**Lockstep** against the model: 200 random configurations × 2,000 clocks, no mismatch. A planted fault at width 2 is caught in exactly the 68 configurations that use width 2.

**Protocols by precomputation**, each judged by an independent reference, with the CPU doing nothing:

| Protocol | Configuration | Precomputation | Reference | Result |
|---|---|---|---|---|
| UART 8N1 | 1 pin | start and stop bits added | a receiver that finds start edges and samples mid-bit | 9 of 9 bytes |
| SPI mode 0 | 2 pins (SCK, MOSI) | two vectors per bit | a slave sampling MOSI on SCK's rising edge | 9 of 9 bytes |
| I2C write | 2 pins, open drain | START, STOP, four vectors per bit, ACK slot released | pull-ups, START/STOP detection, sampling on SCL's rising edge | address + 9 bytes, 1 START, 1 STOP |
| 10BASE-T | 1 pin, 3 clocks per half-bit | Manchester half-bits and TP_IDL; the idle state disables the output | the Ethernet model's own encoder, clock for clock | 3,525 of 3,525 clocks, including TP_IDL and the idle gap |

**Controls:** with bits flipped in one word, each of the four references reports a failure. (The first SPI control flipped a bit that is MOSI during SCK low, which a mode-0 slave rightly ignores; the control was wrong, not the check.)

**A real finding along the way.** Without the per-entry vector count, the last word had to be padded, and the padding showed on the pins. For UART it made a phantom start bit, and the independent receiver decoded a tenth byte that was never sent. For 10BASE-T, no drivable level can stand in for "output disabled". The 4-bit count per entry fixes both, at 4 flip-flops per FIFO slot.

## Area (Yosys, sg13g2 typical corner)

**11,359 µm², 460 cells**, of which 128 flip-flops come to 6,270 µm², 80 of them the FIFO. For comparison:
- one RP2040-style PIO state machine, measured the same way: 61,638 µm², about 5.4 times as much;
- the whole deadline sequencer: 17,300 µm².

## Not yet

- **Receiving:** a mirror-image sampler (every `period` clocks, sample `width` pins into a FIFO), with start-edge triggering for UART. I2C's ACK and SPI's MISO need it.
- **A way for the CPU to feed the FIFO,** for data it computes rather than the host precomputes.
- **The PAL side:** an NCO and pattern table beside the streamer, which is what turns the same primitive into a colour video signal.
