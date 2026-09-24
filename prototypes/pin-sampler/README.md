# Pin sampler: the receive-side generic primitive

The mirror image of `../pin-streamer`, and just as protocol-agnostic. It samples `width` pins (1, 2 or 4), packs the vectors into 16-bit words with a vector count, and pushes them into a four-entry FIFO that the host drains. Two modes:
- **timed:** trigger on an edge of a chosen pin, wait an offset, sample every `period` clocks for `frame_len` vectors, then re-arm. This is UART receive, or 10BASE-T capture.
- **clocked:** sample on every edge of a chosen pin. This is SPI's MISO on SCK, or I2C's SDA on SCL.

The executable specification is `model.ml`, and the RTL is `sampler.ml`.

## Checks (`dune exec ./main.exe`)

**Lockstep** against the model: 300 random configurations × 2,000 clocks, with random pins and random host pops. No mismatched pop.

**Control:** a planted fault (a full word's count written as n, not 0) is caught only where it can show: at widths 2 and 4 (88 of 111, 74 of 79), never at width 1, where 16 wraps to 0 in the 4-bit field (0 of 110). An earlier breakdown claimed catches at width 1; that was my test replaying the random draws in the wrong order, since OCaml does not fix the evaluation order of a record's fields. The width now comes back from the run itself.

**Receive paths**, each judged by an independent reference:

| Path | How it is driven | Result |
|---|---|---|
| UART receive | a reference transmitter with random gaps between bytes; timed mode on the start edge | 12 of 12 bytes |
| SPI full duplex | the streamer RTL drives SCK and MOSI; a reference mode-0 slave reads MOSI and replies on MISO; the sampler is clocked on SCK | the slave saw all 6 bytes, and all 6 reply bytes were captured |
| I2C ACK readback | the streamer drives an open-drain write; a reference slave pulls SDA low through each ACK slot and NACKs byte 3; wired-AND lines with pull-ups | every byte read back; ACK bits `00010`, as expected |
| 10BASE-T capture | the Ethernet model's waveform on the comparator and activity pins; timed mode on activity, every clock; the host decodes the capture with the model's decoder | the exact frame sent |

## A bug that lockstep could not find

The first I2C run read every byte shifted by one bit. The sampler's previous-pins register resets to 0, so a clock line idling *high* looked like a rising edge on the first clock after reset, and produced a sample that was never there. The model had the same behaviour, so lockstep passed. Lockstep compares the RTL with its specification and cannot see a bug the specification shares. Only the check against an independent device model on the other end of the wire found it.

The fix is a one-bit `primed` flag, set after the first clock, in both the model and the RTL: no edge counts until the previous-pins register holds a real sample.

## Area (Yosys, sg13g2 typical corner)

**12,639 µm²**, of which 142 flip-flops come to 6,956 µm². With the streamer (11,359 µm²), transmit plus receive for one pin group is about 24,000 µm². That is less than half of one RP2040-style PIO state machine (61,638 µm²), and covers UART, SPI and I2C in both directions plus 10BASE-T transmit and capture, with protocol knowledge entirely in precomputation.

## Caveats

- **10BASE-T capture is fidelity only.** Capturing every clock at 60 MHz is 7.5 million words a second for the host to drain, which is far more than it can realistically sustain. Real 10BASE-T receive wants decoding on the chip, which is a job for the systolic array (Manchester edge timing, the systolic matcher for the SFD).
- **UART receive assumes matching baud rates.** Tolerance to clock mismatch between the two ends is untested.
