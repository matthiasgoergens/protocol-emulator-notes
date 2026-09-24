# PAL over 10BASE-T: chasing the beam from network packets

The idea, half a joke: the chip generates PAL composite video on chip, chasing the beam, from compact per-line data that arrives as Ethernet packets.

## Why it fits the wire

The semiring ring (`../semiring-ring`), our on-chip pixel generator, needs 48 bytes per visible line:
- 240 lines × 48 bytes × 50 fields a second is 576 kB/s, or 4.6 Mbit/s;
- that is under half of 10BASE-T's 10 Mbit/s;
- about 20 lines per UDP packet keeps the Ethernet overhead small.

The fixed-function retro console's roughly 60-byte per-line packets would fit too.

## Step 1: can the Ethernet receiver run from the PAL clock? (`main.ml`, `jitter.txt`)

Chasing the beam wants 12 × fsc = 53.203425 MHz, where a Manchester half-bit is 2.66 clocks rather than the 3 of the receiver's native 60 MHz. The receiver classifies transitions by thresholds, so it does not need whole numbers.

The test generates the line in continuous time: 10 Mbit/s, a transmitter clock offset of up to ±100 ppm, and uniform random jitter on every edge. The receiver RTL is the prototype's own `eth_rx.ml` with h = 3, sampling the line at the receiver clock. Every frame must come back intact with a good CRC. 20 random frames per cell, 46–245 bytes each:

| Receiver clock | Jitter ±0–3 ns | ±4 ns | ±5 ns |
|---|---|---|---|
| 60 MHz (native) | 180 of 180 | 60 of 60 | 60 of 60 |
| 53.2 MHz (PAL clock) | 180 of 180 | 23 of 60 | 1 of 60 |

(The ±0–3 ns column pools 0, 2 and 3 ns; every cell passed at ±100 ppm.)

**Reading.** The PAL clock works, with less jitter margin. With 18.8 ns sampling, a jittered 50 ns boundary interval and a jittered 100 ns mid-bit interval overlap near the receiver's 4-clock threshold. Ways to get the margin back:
- sample the line on both clock edges, which doubles the time resolution;
- a receiver that tracks bit phase over several transitions.

Both are receiver design for the array, not blockers. I have not yet checked what edge jitter real 10BASE-T links deliver; that decides how much margin is needed.

## Step 1b: NTSC clocks (`jitter-ntsc.txt`, `rp2040-clocks.txt`)

Same test at NTSC multiples of the subcarrier, fsc = 315/88 MHz:

| Clock | Ethernet receive, all jitter up to ±5 ns | RP2040's closest (12 MHz crystal, PLL search) |
|---|---|---|
| PAL 12 × fsc = 53.20 MHz | fails from ±4 ns (above) | 53.200000 MHz, −64 ppm |
| NTSC 16 × fsc = 57.27 MHz | 300 of 300 | 57.250000 MHz, −397 ppm |
| **NTSC 17 × fsc = 60.85 MHz** | **300 of 300** | **60.857143 MHz, +80 ppm** |
| Ethernet 60 MHz | 300 of 300 | exact |

**17 × fsc gives one clock for NTSC colour and Ethernet receive with full margin,** within 80 ppm from the RP2040, similar to PAL's 64 ppm. Its costs:
- **Line length.** An NTSC line is 227.5 subcarrier cycles, which is 3,867.5 clocks, so lines alternate 3,867 and 3,868 clocks. Every pair of lines is exact.
- **Hue steps.** There are 17 per cycle, an odd number, so there is no exact 180° burst. That is harmless, because hues decode relative to the burst.
- **Receive only.** A transmitted 10BASE-T signal at this clock would be 1.4 % off, far outside ±100 ppm. The display demo only receives.

The search assumes the RP2040's PLL reference must stay at or above 5 MHz (a divider of at most 2 from a 12 MHz crystal). That is from memory of the datasheet; the rows relied on use a divider of 1 or 2. An earlier note gave 1,058 ppm for 16 × fsc; this search found −397.

## Next

- A line buffer, because packets arrive asynchronously to the beam.
- Handling the lack of flow control: repeat the previous line on underrun, or genlock the field to packet arrival within PAL's tolerance.
- A packet format: a line number plus 48-byte ring initialisations, about 20 lines per packet.
- Then the whole chain: receiver → UDP parser → buffer → ring → PAL output, judged through the software TV decoder.
