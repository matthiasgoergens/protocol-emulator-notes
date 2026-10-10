# Protocol modes and roles on ISA v2: standard settings, controller and target

The organisers name "common UART baud rates, SPI modes 0-3, I2C at 100 and 400 kHz" as a good
target, and supporting both controller and target roles as a plus. Before this directory the
firmware did SPI mode 0 as controller only, an I2C controller write whose rates had not been
checked against 100 and 400 kHz, and no target firmware. This directory adds, as ISA v2
programmes (`../sequencer-v2/isa2.ml`) for the chip's 60 MHz clock:

1. UART transmit and receive at the common baud rates, with the bit-time error of each;
2. (to come) SPI controller in modes 0-3, msb or lsb first, full duplex;
3. (to come) I2C controller at 100 and 400 kHz, with read, repeated start and clock stretching;
4. (to come) I2C target;
5. (to come) SPI target in modes 0-3.

Build: `opam exec --switch=5.3.0 -- dune build --root .` (Hardcaml v0.17). `./run_all.sh`
regenerates every result file (niced, one job at a time, waiting while the load is 16 or more).

## Files and what checks every programme

| file | what |
|---|---|
| `asm.ml` | an assembler for ISA v2 with labels and exact delays (`Wait n` is n slots); it fails if a programme does not fit its thread's 256-word page |
| `fw.ml` | the firmware generators; each states its schedule in slots in its comment |
| `peers.ml` | the devices at the other end, written from the protocols' definitions, in real time at 60 MHz: they know nothing of slots or threads |
| `bench.ml` | interpreter (`isa2.ml`) and RTL (`sequencer2.ml` through `harness2.ml`) in lockstep, every clock: effects and all architectural state of all four threads |
| `t_uart.ml` | task 1 |
| `isa2.ml`, `sequencer2.ml`, `harness2.ml` | links to `../sequencer-v2`, unchanged |

Every programme here is checked six ways:
- **lockstep**: interpreter and RTL every clock, with controls that plant RTL mutants
  (`Sequencer2.cert_mutants`) which the comparison must catch;
- **peer model**: the bytes and the timing judged by `peers.ml`, which shares no code with
  `fw.ml`;
- **sigrok**: traces judged by sigrok's decoders in `../../tools/sigrok-judge`, with planted
  faults ("teeth") that must be flagged (`results/judge-roles.txt` there);
- **static verifier**: `../verifier` proves each programme against a timing specification
  written in `../verifier/roles_progs.ml` from the closed forms in `fw.ml`'s comments; the
  images are in the verifier's sweep, its certificate ledger and its planted bugs;
- **page fit**: `Asm.assemble` refuses a programme longer than 256 words; sizes are listed;
- **combined chip**: `../chip-top/bin/roles.exe` runs one of each through the host link on the
  chip's specification and RTL in lockstep (`../chip-top/results/roles-*.txt`).

Times are in slots: one instruction of one thread, 4 clocks, 66.67 ns at 60 MHz. In the bench
the core reads the world one clock after it drives it; on the combined chip three clocks.

## 1. UART at the common baud rates (`results/uart.txt`)

A bit at 115200 baud is 130.21 slots, not a whole number. The transmitter therefore places each
edge of a frame on the slot nearest its ideal time: edge k at slot round(k s) after the start
edge, s = 15e6 / baud. Every edge is within half a slot (2 clocks) of the ideal grid, and the
error does not accumulate over the frame: a bit lasts floor(s) or ceil(s) slots. With whole
slots for every bit the error would accumulate to 9.5 times the bit-time error at the stop bit's
sample, 16 % of a bit at 921600 baud. The receiver detects the start edge by polling once a slot
and samples at the slot nearest each bit's middle, assuming the edge came half a slot before it
was seen.

Measured, interpreter and RTL in lockstep, peers at the exact baud rate (60 MHz / baud clocks a
bit):

| baud | slots a bit | bit lengths sent (clocks) | worst edge, % of a bit | whole slots would be | worst receive sample, % of a bit | receiver tolerance | words tx / rx |
|---|---|---|---|---|---|---|---|
| 9600 | 1562.5 | 6248..6252 | 0.03 | +0.03 % | 0.0 | -4.75 / +5.50 % | 33 / 36 |
| 19200 | 781.25 | 3124..3128 | 0.06 | -0.03 % | 0.1 | -4.75 / +5.50 % | 33 / 36 |
| 38400 | 390.625 | 1560..1564 | 0.13 | +0.10 % | 0.2 | -4.75 / +5.50 % | 33 / 36 |
| 57600 | 260.42 | 1040..1044 | 0.19 | -0.16 % | 0.4 | -4.75 / +5.50 % | 33 / 36 |
| 115200 | 130.21 | 520..524 | 0.35 | -0.16 % | 0.7 | -4.75 / +5.25 % | 33 / 36 |
| 230400 | 65.10 | 260..264 | 0.74 | -0.16 % | 1.5 | -4.75 / +5.25 % | 33 / 36 |
| 460800 | 32.55 | 128..132 | 1.47 | +1.38 % | 2.8 | -4.50 / +5.25 % | 33 / 36 |
| 921600 | 16.28 | 64..68 | 2.98 | -1.70 % | 5.8 | -4.00 / +5.00 % | 33 / 36 |
| 1000000 | 15 | 60 | 0 | 0 | 3.0 | -4.00 / +5.00 % | 33 / 36 |
| 1500000 | 10 | 40 | 0 | 0 | 9.7 | -3.25 / +5.50 % | 33 / 36 |
| 2000000 | 7.5 | 28..32 | 6.67 | +6.67 % | 9.8 | -2.75 / +5.00 % | 33 / 36 |
| 3000000 | 5 | 20 | 0 | 0 | 8.3 | -2.25 / +4.50 % | 33 / 35 |

- **Transmit.** Five bytes (0x55 0x00 0xFF 0x4F 0xA5) back to back; the peer receiver decodes
  all of them at every rate. The bit lengths and edge positions are measured from the clocks at
  which the thread writes the pin, all ten edges of each frame, including those that leave the
  level unchanged, and the next frame's start. The worst edge is at most 2 clocks from the ideal
  grid at every rate, which is the rounding to a slot; at 1, 1.5 and 3 Mbaud it is exact.
  Words: 33 for the transmitter fed by the host (IN), as on the chip; the test image with five
  constant bytes unrolled is 155.
- **Receive.** The peer sends 8 random bytes at random phases against the core clock, a third
  of them back to back (one stop bit); 3 runs a rate. "Worst receive sample" is the largest
  distance of a sample from the ideal mid-bit instant: the start edge is seen up to one slot late,
  so it is about one slot, 4 clocks, whatever the rate. "Tolerance" is the peer's bit-time
  error the receiver still takes (steps of 0.25 %, 4 runs of 6 bytes, interpreter only): about
  -4.75 / +5.5 % at the low rates, the limit being the stop bit sampled at 9.5 bits, and
  narrower at 1.5 Mbaud and above, where the one-slot start uncertainty is a larger part of a bit.
- **Limits.** The receiver is back at its start wait 3 slots after the stop sample, in time for a
  back-to-back frame when 9.5 s + 2.5 <= 10 s, i.e. s >= 5: 3 Mbaud is its fastest rate, and it
  passes there. The transmitter needs s >= 3 (5 Mbaud). Rates below 9600 need waits longer than
  one LDD (4,097 slots); `Asm.Wait` chains them, but they were not run.

**Controls**, each of which must fail the check named, and does: the transmitter with one bit's
wait a slot short (worst edge 5.8 clocks, over the 2-clock bound); sent msb first (the peer
decodes other bytes); the receiver sampling half a bit late (bytes differ); a frame whose stop
bit is low (reported with tag 1, a framing error, as it must be); the peer 8 % slow (not
received); and two RTL mutants under the lockstep, "WAITD leaves at dl = 1" under the
transmitter (25,008 clocks differ) and under the receiver. The mutant "a wait times out at
dl = 1" cannot show under the receiver, whose waits for the line all run at dl = 0.

**sigrok** (`../../tools/sigrok-judge/results/judge-roles.txt`): sigrok's `uart` decoder at
each of the 12 rates, on the transmitter's pin and on the line the receiver read (against the
bytes it reported to the host): 24 traces decoded correctly, and both teeth (a data bit
inverted for half a bit; the bit time 10 % long) caught on each, 48 of 48.

**Verifier** (`../verifier/roles_progs.ml`): specifications from the closed forms above. The
transmitter: each edge at its grid slot, every data bit's level the declared bit of its byte
(lsb first), and for the host-fed one a start any time after the idle level or a full stop bit.
The receiver: the start check at d + m 0, the samples at d + m k, the stop check at d + m 9,
m k = round((k + 1/2) s - 1/2), the waits for the line unbounded. Four images a rate (five
bytes, one byte, from the host, receive), 48 in all: **48 of 48 proved**, each cross-checked on
the interpreter (the receiver against a peer transmitter and against noise), in the ledger.
Planted: one bit's wait a slot short, sent msb first, one receive sample a slot late: 3 of 3
rejected.

**Combined chip** (`../chip-top/results/roles-uart-*.txt`): at 115200 baud, thread 0 sends the
host's bytes on `uo_out[0]`, thread 1 receives on `ui_in[0]` and reports to the host: the peer
receiver decodes "Hi!\n" and the host reads back the 5 bytes the peer sent; specification and
RTL agree on every pad, every clock, driven either way.
