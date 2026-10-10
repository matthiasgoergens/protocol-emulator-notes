# Protocol modes and roles on ISA v2: standard settings, controller and target

The organisers name "common UART baud rates, SPI modes 0-3, I2C at 100 and 400 kHz" as a good
target, and supporting both controller and target roles as a plus. Before this directory the
firmware did SPI mode 0 as controller only, an I2C controller write whose rates had not been
checked against 100 and 400 kHz, and no target firmware. This directory adds, as ISA v2
programmes (`../sequencer-v2/isa2.ml`) for the chip's 60 MHz clock:

1. UART transmit and receive at the common baud rates, with the bit-time error of each;
2. SPI controller in modes 0-3, msb or lsb first, full duplex, from 100 kHz to 1.5 MHz (1.875 MHz in modes 1 and 3);
3. I2C controller at Standard-mode (100 kHz) and Fast-mode (400 kHz), with reads, repeated START and clock stretching, against the specification's timing parameters;
4. I2C target with a 7-bit address, ACK and NACK, writes drained and reads supplied by the host, clock stretching while it waits for the host;
5. SPI target in modes 0-3, msb or lsb first: 1.5 MHz in every mode, 1.88 MHz in modes 0 and 2 with gaps between bytes, and why.

Build: `opam exec --switch=5.3.0 -- dune build --root .` (Hardcaml v0.17). `./run_all.sh`
regenerates every result file (niced, one job at a time, waiting while the load is 16 or more).

## Files and what checks every programme

| file | what |
|---|---|
| `asm.ml` | an assembler for ISA v2 with labels and exact delays (`Wait n` is n slots); it fails if a programme does not fit its thread's 256-word page |
| `fw.ml` | the firmware generators; each states its schedule in slots in its comment |
| `peers.ml` | the devices at the other end, written from the protocols' definitions, in real time at 60 MHz: they know nothing of slots or threads |
| `bench.ml` | interpreter (`isa2.ml`) and RTL (`sequencer2.ml` through `harness2.ml`) in lockstep, every clock: effects and all architectural state of all four threads |
| `t_uart.ml`, `t_spi.ml`, `t_i2c.ml`, `t_i2c_target.ml`, `t_spi_target.ml` | tasks 1 to 5 |
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

## 2. SPI controller, modes 0-3, msb and lsb first, full duplex (`results/spi.txt`)

**How full duplex works with one accumulator.** The bit going out and the bit coming in cannot
share one shift: SHO with capture would sample MISO at the instant MOSI changes, which is the
shift edge, not the sampling edge. So MOSI is written by SETP after a branch on the outgoing
accumulator bit (WAITC on acc bit 7, or bit 0 for lsb first, at dl = 0; both paths three slots),
which does not shift, and MISO is sampled by SHI one slot after the sampling edge, which does: the
bit just sent leaves at the top and the received bit enters at the bottom. After eight bits the
accumulator holds the received byte, which goes to the host (OUT).

**Schedule** (`fw.ml`, `spi_ctl`, slots; act = idle = half the period P):
- CPHA 0 (modes 0, 2): MOSI written 3 slots after the trailing edge, so idle - 3 slots before
  the leading edge; MISO sampled 1 slot after the leading edge. Needs P >= 10 slots: 1.5 MHz.
- CPHA 1 (modes 1, 3): MOSI written 2 slots after the leading edge, act - 2 before the trailing
  edge; MISO sampled 1 slot after the trailing edge. Needs P >= 8 slots: 1.875 MHz.
- Between bytes SCLK idles 3 slots longer (OUT, LDA, LDC). CS falls idle + 1 slots before the
  first edge and rises idle slots after the last.

**Measured** on the bus trace at clock resolution, interpreter and RTL in lockstep, against a
peer target in the same mode answering 4 random bytes to 4 random bytes, two runs a row, for
all 8 configurations (4 modes x 2 bit orders) at P = 10, 15, 30 and 150 slots (1.5 MHz, 1 MHz,
500 kHz, 100 kHz; and P = 8, 1.875 MHz, in modes 1 and 3): 36 rows, every one correct both ways
with 0 lockstep mismatches. Each row checks that the sampling-edge period is exactly 4P clocks
within a byte, both phases are P/2 slots, MOSI changes only in the phase where the mode does
not sample, and MISO is sampled 3 clocks after the sampling edge appears on the bus (the bench
reads the bus one clock after driving it). A sample of the table (clocks; 16.67 ns each):

| mode | SCLK | MOSI set-up / hold around the sampling edge | MISO margin | CS set-up / hold |
|---|---|---|---|---|
| 0, 2 | 1.5 MHz (P 10) | 8 / 32 | 23 (58 % of the period) | 24 / 20 |
| 0, 2 | 1 MHz (P 15) | 20 / 40 | 35 | 36 / 32 |
| 0, 2 | 100 kHz (P 150) | 288 / 312 | 303 | 304 / 300 |
| 1, 3 | 1.875 MHz (P 8) | 8 / 24 | 19 (59 %) | 16 / 20 |
| 1, 3 | 1 MHz (P 15) | 20 / 40 | 31 | 32 / 36 |
| 1, 3 | 100 kHz (P 150) | 292 / 308 | 303 | 300 / 304 |

The bit order changes no timing. "MISO margin" is the longest delay of the peer's MISO after its
own shift edge that the controller still reads correctly (bisection on the interpreter): about
half a period plus 3 clocks, since the sample is 3 clocks after the sampling edge. Page sizes,
4 constant bytes: 66 words (CPHA 0), 70 (CPHA 1).

**Controls**, each of which must fail and does:
- In every mode, the firmware sampling MISO one slot after the *shift* edge instead of the
  sampling edge. This is a race with the target's output: it reads the next bit against a target
  without output delay in CPHA 0, and the previous bit against one 8 clocks late in CPHA 1 (a
  CPHA 1 target without delay holds each bit from leading edge to leading edge, so there the
  wrong edge reads the right bit). Each is caught by wrong bytes and by the sample's position,
  while the correct firmware reads right at the same delays.
- The MOSI = 0 path a slot shorter than the MOSI = 1 path (the sampling period varies, 56 and
  60 clocks).
- Firmware built for mode 1 judged as mode 0, and the reverse: 13 MOSI changes in the sampling
  phase. This check is needed because the data alone does not tell CPHA apart: a mode 0
  controller and a mode 1 target without output delay exchange the right bytes (MOSI is held
  past the trailing edge, MISO sampled just after the leading one).
- Mode 2 firmware against a mode 0 peer, and msb first against an lsb-first peer: wrong bytes.
- The peer's MISO one clock past the margin: read wrongly.
- The RTL mutant "WAITD leaves at dl = 1" under the lockstep: 3,364 clocks differ.

**sigrok**: sigrok's `spi` decoder, configured with the mode, bit order and active-low CS,
decodes MOSI and MISO of all 8 configurations at 1 MHz and of modes 0 and 3 (msb, lsb) at
1.5 MHz: 10 traces, both directions correct, and 30 of 30 teeth caught (MOSI inverted around
the third sampling edge, MISO inverted around the fifth, MOSI half a period late).

**Verifier**: specifications with every SCLK edge, MOSI write, MISO sample and CS edge at its
exact slot, per mode. MOSI's value is not declared (it is a SETP after a branch on the
accumulator, which the analysis loses once SHI has shifted an input into it); the peer and
sigrok check the data. 48 images (8 configurations x 3 periods x 1 or 3 bytes), cross-checked
against the peer target with random MISO delays: **48 of 48 proved**. Planted: MISO sampled
after the trailing edge, the MOSI = 0 path a slot short, mode 1 firmware against the mode 0
specification: 3 of 3 rejected.

**Combined chip**: thread 0 in mode 0, msb first, at 1 MHz and thread 1 in mode 3, lsb first,
at 1.5 MHz, at the same time, each against a peer target on the pads (MISO from `ui_in`): both
peers receive the bytes sent, the host reads both peers' replies from HOSTOUT, and specification
and RTL agree on every pad. The host has to drain HOSTOUT often: it holds 8 entries and the two
threads produce 9 within 2,000 clocks; the first version lost one, which the status register's
sticky overflow bit (now checked) reports. The peers are held in reset until the host has set
the pads' undriven level high, since CS shows the reset level 0 before that.

## 3. I2C controller at 100 and 400 kHz (`results/i2c.txt`)

**A command loop, not a compiled transaction.** The first version compiled each transaction
into a programme, as `../deadline-sequencer/compiler.ml` does; the test transactions (seven
bytes written, three read) came to 373 words, more than a page. The controller is now a fixed
programme of 143 words driven by host commands through IN: `S` START (or repeated START), `P`
STOP, `W` and a byte (write; the target's ACK goes to the host, tag 1), `R` and `N` (read a
byte and ACK or NACK it; the byte goes to the host, tag 0). The size no longer depends on the
transaction, and on the chip the host feeds the commands through HOSTIN.

**Schedule** (`fw.ml`, `i2c_ctl`). Each SCL clock: SCL driven low at slot a; SDA changes at
exactly a + 5 (333 ns, more than the largest fall time); SCL released at a + low; WAITP sees SCL
high at s, a slot or more later (later while a target stretches the clock or the line rises
slowly), bounded by a stretch limit after which the controller releases both lines and reports
a timeout; a read bit or an ACK is sampled at s + smp; SCL low again at s + high. So the high
phase is counted from SCL seen high: rise time and stretching never shorten it. The next command
is fetched in the high phase of a byte's ACK clock, so a slow host lengthens tHIGH (for which
the specification sets no maximum) and every SDA change stays 5 slots after SCL falls.

| slots | low | high | SDA after SCL low | tHD;STA | tSU;STA | tSU;STO | tBUF | sample |
|---|---|---|---|---|---|---|---|---|
| Standard-mode | 76 | 74 | 5 | 66 | 71 | 61 | 86 | 37 |
| Fast-mode | 25 | 12 | 5 | 15 | 10 | 10 | 25 | 6 |

**Measured against the specification** (NXP UM10204 rev. 7.0, table 10). The bus model gives
each line a fall time tf and a rise time tr (a line reads low tf clocks after it starts to fall,
high tr after release), and every run is made at the four corners tr, tf in {0, the maximum}
(Standard 1,000 / 300 ns, Fast 300 / 300 ns). Each parameter is measured on the trace
conservatively: an interval ending at an edge is taken to the edge's start, one starting at an
edge from its end, so the value is at most the true one for any threshold; the worst over the
corners is then a bound for every edge time up to the maximum. The transaction: write 0x55 0xAA
to registers 0x10 and 0x11 of the peer target at 0x50, STOP; set the pointer, repeated START,
read 3 bytes (ACK, ACK, NACK), STOP. Worst over the corners, ns:

| parameter | Standard limit | Standard measured | Fast limit | Fast measured |
|---|---|---|---|---|
| fSCL | <= 100 kHz | 99.3 kHz | <= 400 kHz | 394.7 kHz |
| tLOW | >= 4,700 | 4,767 | >= 1,300 | 1,367 |
| tHIGH | >= 4,000 | 5,000 | >= 600 | 833 |
| tHD;STA | >= 4,000 | 4,100 | >= 600 | 700 |
| tSU;STA | >= 4,700 | 4,800 | >= 600 | 700 |
| tSU;DAT | >= 250 | 3,733 | >= 100 | 1,033 |
| tHD;DAT | >= 0 | 33 | >= 0 | 33 |
| tVD;DAT, tVD;ACK | <= 3,450 | 1,333 | <= 900 | 633 |
| tSU;STO | >= 4,000 | 4,133 | >= 600 | 700 |
| tBUF | >= 4,700 | 4,933 | >= 1,300 | 1,567 |

At every corner the target sees exactly the intended transaction (3 STARTs, one of them
repeated, 2 STOPs, every ACK and NACK) and the host gets the ACK reports, the three bytes read
and the two ends; interpreter and RTL agree on every clock. A second run at each corner has the
target stretch one SCL low phase in three by up to 400 clocks: same result, tHIGH still at
least 817 ns (Fast). With the slowest rise the clock is 357 kHz (Fast) and 90.4 kHz (Standard),
because the high phase is counted from the rise. A host sending a command every 2,000 clocks is
handled too (the high phases get longer; data correct).

**A finding on the way.** The first command loop fetched the next command after driving SCL low,
which made the first bit of each byte change SDA up to 1,100 ns after SCL fell, beyond Fast-mode's
tVD;DAT of 900 ns. UM10204 lifts tVD for a device that stretches its low period, which a
controller fetching a command arguably does, but moving the fetch into the high phase removes
the question: tVD is now 633 ns at worst.

**Controls**, each of which must fail and does: SCL low 19 slots in Fast-mode (tLOW 967 ns);
high 8 slots (441 kHz); tSU;STO 5 slots (400 ns); tHD;STA 7 slots (467 ns); SDA changed 22 slots
after SCL low (tSU;DAT -100 ns: SCL starts to rise before SDA has; tVD 1,767 ns); no target at the address
(two NACKs reported, STOP sent); the target NACKing from its third data byte (reported); the
target holding SCL for ever with a stretch limit of 200 slots (timeout reported, SDA released);
the ACK read while SCL is still low, against a target whose ACK comes 833 ns after SCL falls
(legal: within tVD;ACK): every ACK read as a NACK; no wait for SCL high, against a target that
stretches 150 clocks (tHIGH 100 ns); the RTL mutant "a wait times out at dl = 1" under the
lockstep in the timeout run (2,080 clocks differ).

**sigrok**: sigrok's `i2c` decoder on both modes at the slowest corner with random stretching:
every annotation in order (Start, Address write: 50, ACK, Data write: 10, ..., Start repeat,
Address read: 50, ..., Data read: A5, NACK, Stop), against the intended transaction; both teeth
caught (SDA inverted over the third SCL high phase; SDA 0.6 of an SCL period late).

**Verifier**: one specification for the command loop, written from the schedule: a
deterministic automaton over SDA and SCL events whose states are the protocol's (idle, START,
a command's SCL low, write bit k, write ACK clock, read bit k, repeated START, STOP, timeout),
with exact gaps within a pulse and lower bounds where the host's IN may wait (the next
command's SCL low, the START). Read and repeated START share their first pulse, so they share
its states until the sample (read) or SDA's fall (repeated START) tells them apart. Six images
(two modes, stretch limits 7, 200 and 4,095), cross-checked against the peer target stretching
at random and a host sending mostly commands: **6 of 6 proved**. Planted: the ACK read while
SCL is low, no wait for SCL high, SCL low 19 slots against the declared 25: 3 of 3 rejected.

**Combined chip**: Fast-mode on `uio[6]` (SDA) and `uio[7]` (SCL), the chip's open-drain pins,
rise and fall 300 ns, the target stretching at random; the host keeps HOSTIN topped up with the
22 command bytes (it holds 16) and drains HOSTOUT: the target sees the whole transaction, the
host reads every result, the shortest SCL period is 170 clocks (352.9 kHz; the chip's pads add
3 clocks to every rise seen), and specification and RTL agree on every pad.

## 4. I2C target (`results/i2c-target.txt`)

**Host interface** (`fw.ml`, `i2c_target`, 95 words). The target reports its address byte when
it is addressed (tag 1), each byte written to it (tag 0), the controller's answer to each byte
it sends (tag 2: 0 ACK, 1 NACK), and every STOP (tag 3). After a byte written to it, it holds
SCL low until the host answers through IN (0 to ACK, anything else to NACK); before each byte it
sends, it holds SCL low until the host supplies the byte. A host that answers late therefore
only stretches the clock.

**How it follows the bus.** Every wait is a poll (WAITP on itself at dl = 0, one look a slot);
the target answers from the slot it sees an edge: it samples SDA 1 slot after seeing SCL high,
drives the address ACK 3 or 4 slots after seeing SCL low (write or read address; the two SKNE
comparisons), sends each later bit of a read 1 slot after SCL low, pulls SCL low to stretch 1
or 2 slots after SCL low, and releases SCL a set-up time (6 slots in Fast-mode, 19 in
Standard-mode, which covers the rise time and tSU;DAT) after setting SDA. While SCL is high after
a byte's first bit it polls SDA (3 slots a look): a fall is a (repeated) START, a rise a STOP.

**Measured**, interpreter and RTL in lockstep, against the controller of `peers.ml`, a script at
the specification's timing that waits for SCL to read high and so honours stretching. The
transaction: write 0x10 0x55 to the target, read three bytes (ACK, ACK, NACK), then a write to
0x52, which it must not acknowledge. At all four corners of rise and fall time in both modes
the controller sees every ACK and NACK and the three bytes the host supplied, and the host gets
the ten reports in order. The target's own timing on the trace (ns; least, or greatest for tVD):

| | SDA hold after SCL low | SDA set-up before SCL rises | tVD, where it did not stretch | SDA changes while SCL high | SCL pulled while high |
|---|---|---|---|---|---|
| Standard (limits) | >= 0 | >= 250 | <= 3,450 | 0 | 0 |
| Standard (measured, worst corner) | 83 | 3,567 | 1,133 | 0 | 0 |
| Fast (limits) | >= 0 | >= 100 | <= 900 | 0 | 0 |
| Fast (measured, worst corner) | 83 | 200 | 617 | 0 | 0 |

With a host that answers each request only 50 us after the target makes it, the target holds
SCL low for up to 51.6 us (Standard) and 50.7 us (Fast), five times, and everything still
arrives right; its set-up before releasing SCL is then at least 1,033 ns and 167 ns.

**How fast it can follow.** The Fast-mode controller with every time scaled down, each speed at
12 phases against the core clock: right at every phase up to SCL low 18 / high 15 clocks
(1.77 MHz); at 16 / 14 clocks (1.94 MHz) the data still arrives, but the target changes SDA
while SCL is high: the read address's ACK, driven 4 slots (16 clocks) after the target sees SCL
low, lands after the controller's 16-clock low phase has ended (traced at clock 1,273 of the
run). So the limit is the address comparison: 3 to 4 slots plus the input latency must fit in
the controller's tLOW. Standard-mode and Fast-mode, whose tLOW is at least 4.7 and 1.3 us (282
and 78 clocks), are far from it.

**A finding about the peer.** At first the peer controller changed SDA 100 ns after starting to
pull SCL low. With a 300 ns fall time SCL still reads high then, so the target saw a STOP. UM10204
puts this on the transmitter: a note to its table 10 requires a device to hold SDA internally for
at least 300 ns after SCL falls through VIH(min), to bridge the undefined region of SCL's falling
edge. So the peer was out of specification; it now holds 333 ns,
as this repository's controller does (5 slots). That out-of-specification controller is kept as a
control. A version of the target that bridged the region itself (looking at SCL again 333 ns
after seeing SDA move) was tried and dropped: it made the START detection take up to 600 ns,
which is Fast-mode's tHD;STA itself.

**Controls**, each of which must fail and does: the host NACKing the second byte written (the
controller sees the NACK); addressed at 0x51 (no ACK, nothing reported but the STOP); a set-up of
1 slot instead of 6 with a 300 ns rise, a slow host and a first bit of 1 (tSU;DAT -167 ns; 6
slots give 167 ns); the controller without the 300 ns hold at a 300 ns fall (a false STOP); the
RTL mutant "WAITD leaves at dl = 1" (40 clocks differ).

A measurement bug found on the way: the set-up time was taken to the first SCL rise after the end
of SDA's edge, which skips a rise that starts during the edge. It is now taken to the first rise
after the change begins, so it can be negative; this changed one number of section 3's controls
(the SDA-changed-late control now reads -100 ns, not 200 ns), and none of its results.

**sigrok**: sigrok's `i2c` decoder on both modes at the slowest edges, with the target
stretching for a host answering 50 us late: every annotation in order (the NACKed address and
data byte to 0x52 included), against the intended transaction; both teeth caught.

**Verifier**: a specification of the target's responses, written from the schedule above:
polls are expiries and observations with no deadline; every response after an observation has
its exact gap (the sample 1 slot after SCL high, the address ACK 3 to 4 slots after SCL low, the
stretch 2 slots after, SCL released su + 1 slots after the ACK or the first bit, each read bit
1 slot after SCL low, the controller's ACK looked at 1 slot after SCL high), and gaps of at least
a bound across the host's IN. Three images (Standard with su 19, Fast with su 6 and su 1),
cross-checked against the peer controller running random transactions (writes, reads, repeated
STARTs, other addresses) with a random host: **3 of 3 proved**, 6,035 events checked each.
Planted: a read's first bit one slot later; su 6 against a declared 7: 2 of 2 rejected.

**Combined chip**: on `uio[6]` and `uio[7]` with the Fast-mode controller and 300 ns edges, the
host polls HOSTOUT and answers each request through HOSTIN; its own latency through the host
link makes the target hold SCL low for up to 717 clocks (the controller's own low phase is 80).
The controller sees every ACK and byte, the host gets every report, and specification and RTL
agree on every pad.

## 5. SPI target, modes 0-3 (`results/spi-target.txt`)

**Design** (`fw.ml`, `spi_target`, 45 words in CPHA 0, 46 in CPHA 1). The target follows SCLK
by polling (one look a slot) and uses the controller's trick for full duplex: MISO is written by
SETP after a branch on the outgoing accumulator bit (3 slots), MOSI is sampled by SHI, which
shifts. CPHA 0: MOSI sampled 1 slot after the poll sees the leading edge, MISO's next bit written
3 slots after it sees the trailing edge. CPHA 1: MISO written 2 slots after the leading edge,
MOSI sampled 1 slot after the trailing edge. The bytes it sends are the host's (IN), or 0xFF when
the host has none ready (it cannot hold an SPI controller back); each byte received goes to the
host, and CS rising releases MISO and reports the end. Between bytes the target reports the byte
and takes the next one (OUT, WAITC, IN: 4 slots), placed where it costs least: in CPHA 0 in the
active phase of the eighth bit, in CPHA 1 after its trailing edge. CS is looked at only between
bytes, so a transaction must be a whole number of bytes.

**Measured** against the controller of `peers.ml`, which samples MISO exactly at its own sampling
edge (no time allowed after the edge): at 100 kHz, 500 kHz and 1 MHz in all 8 configurations,
interpreter and RTL in lockstep, the controller reads the host's bytes, the host gets the
controller's, and every MISO change falls in the phase where the mode does not sample.

**The fastest SCLK it follows** (half periods equal; every run right at that speed and every
slower one; back to back: 12 phases of the controller against the core clock; with gaps: the gap
over 12 consecutive values, 40 to 51 clocks, at 4 phases each, so that the next byte's first edge
falls at every point of the target's poll):

| | bytes back to back | gaps between bytes |
|---|---|---|
| modes 0 and 2 | 20 clocks a half period: **1.50 MHz** | 16: **1.88 MHz** |
| modes 1 and 3 | 20: **1.50 MHz** | 20: **1.50 MHz** |
| mode 0 on the combined chip | 22: **1.36 MHz** | |

The first search used one gap (40 clocks) and reported 1.67 MHz for modes 1 and 3. With one gap
the next byte's first edge lands at only 4 of the 12 points of the target's 3-slot poll between
bytes; varying the gap finds the slower alignment.

**Why.** One clock faster, in every case that fails it is MISO, never MOSI: the controller reads
wrong bits, the host gets every byte right (`results/spi-target.txt` shows two failing runs of
each). MOSI is sampled one slot after the target sees the sampling edge, half a period before the
controller changes it, so it has room. MISO must be written after the target sees the shift edge
and be on the pin by the controller's next sampling edge. The chains, in the bench (the core reads
an edge one clock after the controller makes it; the poll then sees it within one slot, 0 to 3
clocks; a write shows on the pin in the clock it is made):
- CPHA 0, gaps between bytes: MISO is written 3 slots (12 clocks) after the poll sees the trailing
  edge, so 13 to 16 clocks after it, and must be there by the next leading edge, a half period
  later: the limit is a half period of 16 clocks (1.88 MHz), as measured.
- CPHA 0, bytes back to back: in the eighth bit the poll for the trailing edge starts only 6 slots
  after the leading edge is seen (the sample, OUT, and 3 slots to take the next byte), 25 to 28
  clocks after that edge; the next byte's first bit follows 12 clocks after the trailing edge is
  seen, 37 to 40 clocks after the eighth leading edge, and must come by the next leading edge, two
  half periods after it: the limit is 20 clocks (1.50 MHz), as measured. The failing runs have
  exactly that bit wrong (0xE0 read as 0x60, 0x48 as 0xC8).
- On the chip the pads add a clock each way (the pad shows an output a clock later, the core sees
  samples two clocks old instead of one), 41 to 44 clocks, so 22 (1.36 MHz), as measured there.
- CPHA 1: MISO is written 2 slots after the leading edge is seen. Within a byte the poll sees it
  within a slot; between bytes the poll for a byte's first leading edge also looks at CS, so it
  looks at SCLK only every third slot and sees the edge up to 11 clocks late; MISO then comes
  up to 19 clocks after the leading edge and must be there by the trailing edge, a half period
  later: the limit is 20 clocks (1.50 MHz), gaps or not, and one clock faster only the first bit
  of a byte is ever wrong (3 of 48 runs at 19 clocks), as measured. In CPHA 0 one clock past the
  limit with gaps (15 clocks) many bits are wrong, not only the first: there the per-bit chain
  above binds.
A faster target would need the next byte fetched before the eighth bit, or MISO's next bit
prepared without the 3-slot branch; neither fits one accumulator. These numbers are for 50 %
duty; the requirement is per phase.

**Controls**, each of which must fail and does: the host with no data (the controller reads
0xFF); firmware built for mode 1 judged as mode 0, and the reverse (15 and 16 MISO changes in the
sampling phase); a mode 3 target against a mode 2 controller, and msb first against lsb first
(wrong data); one clock past the limit (wrong); the RTL bug "WAITC 9 inverted" under the
lockstep (4,156 clocks differ). As with the controller, the data alone does not tell CPHA apart at
these speeds (a mode 0 target and a mode 1 controller exchange the right bytes), and a polling
mode 0 target also works with a mode 2 controller: it takes the idle-high SCLK at CS fall as an
immediate first leading edge. The MISO phase check is what tells the modes apart.

**sigrok**: sigrok's `spi` decoder on all 8 configurations at 1 MHz, MOSI against the
controller's bytes and MISO against the host's: 8 of 8, and 24 of 24 teeth caught.

**Verifier**: specifications with the polls unbounded and the responses exact (MOSI sampled 1 slot
after the leading or trailing edge is seen, MISO written 3 slots after the trailing edge or 2
after the leading edge, MISO released 1 slot after CS is seen high). The target takes the next
byte with IN only after WAITC has seen it ready, which on the chip cannot wait unless another
thread reads HOSTIN in between; the verifier's assumption A1 lets the input change on any slot,
so there the specification says "at least" (the first MISO write after CS, at least 5 or 4
slots; in CPHA 0 the trailing-edge poll after the eighth sample, at least 5). The first version
of the specification said "exactly" and was rightly rejected. 8 images, cross-checked against
the peer controller running random transactions at random speeds: **8 of 8 proved**. Planted:
mode 1 firmware against the mode 0 specification, MOSI sampled after the trailing edge: 2 of 2
rejected.

**Combined chip**: mode 3, lsb first, and mode 0, msb first, at 1 MHz on `ui_in` (SCLK, MOSI, CS)
and `uo_out[2]` (MISO), the host prefilling HOSTIN with the replies and draining HOSTOUT: both
right, specification and RTL agree on every pad. Mode 0 with bytes back to back, 8 phases a
speed: right up to 22 clocks a half period (1.36 MHz), wrong at 21; the two extra clocks of pad
latency over the bench cost about 2 clocks of half period.

## Summary of the checks

| | lockstep | peer | sigrok (traces, teeth) | verifier (images proved, planted rejected) | page (words) | chip |
|---|---|---|---|---|---|---|
| UART tx/rx, 12 rates | 0 mismatches | bytes and timing | 24, 48 | 48, 3 | 33 / 36 | 115200 baud both ways |
| SPI controller | 0 | 8 configurations x 4-5 periods | 10, 30 | 48, 3 | 66 / 70 | modes 0 and 3 at once |
| I2C controller | 0 | 4 corners x 2 modes, stretching | 2, 4 | 6, 3 | 143 | Fast-mode with stretching |
| I2C target | 0 | 4 corners x 2 modes, slow host | 2, 4 | 3, 2 | 95 | Fast-mode, host over the link |
| SPI target | 0 | 8 configurations x 3 rates, speed search over every alignment | 8, 24 | 8, 2 | 45 / 46 | modes 3 and 0, 1.36 MHz limit |
