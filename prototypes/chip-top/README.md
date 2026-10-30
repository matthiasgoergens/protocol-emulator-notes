# chip-top: the first combined prototype of the whole programmable chip

Every block of `notes/architecture-v0.md` so far was built and verified alone. This directory
puts them behind one Hardcaml top level for Tiny Tapeout 6x4 (IHP sg13cmos5l), with:

- an executable specification of the whole chip, composed from the blocks' own OCaml models;
- a lockstep test of the RTL against it, with planted integration bugs;
- the existing demos, unchanged, driven through the host link;
- a harden with the pinned flow, to measure the whole-chip placement factor (gap G13).

Status: milestones 1-6 done: plan; top level, specification and lockstep; demos through the host
link; area, hardens and G13; `tt/` points at this chip; the edge-phase test and coverage. Section 7:
60 MHz is met at every corner with 4 PEs, the hold buffers fell from 3,206 to 78, the array has a
reset. Section 8: the stuff tracker and the line coder on the bit path (a transmit serialiser and a
receive framer), used by a low-speed USB device and a 10BASE-T node. Open issues are listed at the end. The suite: `./suite.sh quick` (CI, about a minute after
the build) or `./suite.sh full`.

Build: `opam exec --switch=5.3.0 -- dune build --root .` (Hardcaml v0.17). Then
`_build/default/bin/lockstep.exe run 400 12000`, `... controls 30 12000`, `... layouts 40 12000`,
`_build/default/bin/demos.exe ds DIR`, `... dac 400`. Results in `results/`.

## 1. Integration plan

### What goes in now, what is stubbed or deferred

| block | source | in v0? | notes |
|---|---|---|---|
| sequencer, ISA v2 | `../sequencer-v2/sequencer2.ml`, `isa2.ml` | **in**, unchanged | reset fetch fix (ec1650d) included. FINE's `fine_out` and `cfg_out[6:0]` are left unconnected (no fine delay; see D5 below) |
| programme store, 1024 × 16 address space | new glue | **in** | behavioural synchronous RAM in simulation; hardened: the IHP `RM_IHPSG13_1P_512x16` macro (see "The memories") |
| data bank, 1024 × 8 | new glue | **in** | the ISA's LDB/STB port; hardened: `RM_IHPSG13_1P_1024x8`. **The gain-cell banks are deferred** (see "The memories") |
| host link | new, designed here (section 3) | **in** | the architecture note sketches it only (section 2.7) |
| four-phase pin stage, out and in | `../multiphase/stage.ml` | **in**, unchanged, at the TT boundary | see "Phases" below |
| pin map and per-pad source select | new glue | **in** | replaces the note's per-thread pin window with one host-configured map |
| streamer and sampler | `../pin-streamer/streamer.ml`, `../pin-sampler/sampler.ml` | **in**, unchanged | configuration from host registers; the sampler's input can also be the recovered-bit stream |
| pin NCO | `../multiphase/nco.ml` | **in**, unchanged | no phase-offset input yet (it never had one) |
| PE array and segments | `../unified-pe/verify/` | **in**, with two changes in their own commits | (a) a parameterised layout, so the chip can start at 4 PEs and grow; (b) the three generic additions proposed and verified in `../onebit-dac` (lane loop E1, feed repeat E2, arithmetic shift X1), which the one-bit DAC demo needs. Both rerun the block's own lockstep, controls and cells |
| edge-tracking sampler (n = 4) | `../eth10-node/edge_sampler.ml` | **in**, unchanged | one bit-path chain (the note has two) |
| CRC unit | `../eth10-node/crc_unit.ml` | **in**, unchanged | on the recovered bits; "CRC good" is a flag source |
| matcher with enable | `../eth10-node/matcher_en.ml` | **in**, unchanged | on the recovered bits; "hit" is a flag source and can start the CRC |
| flag-input selects | new glue | **in** | 16 flags (4 per thread), each a host-configured 5-bit select; this resolves the ISA's open D5 as "host configuration" |
| stuff tracker, line coder | `../bit-assists` (`../unified-pe/rtl/assists.v` were the area probes) | **in since section 8** | specified and verified blocks, on the bit path as a transmit serialiser and a receive framer (section 8) |
| fine delay (DTC/TDC on two pins) | `../multiphase` (behavioural) | **deferred** | needs a placed delay-line macro; FINE does nothing on this chip |
| bank fixed ports into segments | note section 2.6 | **stubbed** | the bank is single-ported and serves LDB/STB. Segment 0's fixed port carries the recovered-bit stream instead; segments 1-3's fixed ports read zero |
| second bit-path chain, SJW (G6), TRNG | note sections 2.3, 7 | **deferred** | |

### The memories: SRAM macros, not gain cells (decided 2026-10-06)

Both memories are IHP's SRAM macros in the hardened chip: `RM_IHPSG13_1P_512x16` for the
programme store (pages 0 and 1) and `RM_IHPSG13_1P_1024x8` for the data bank (the ISA's whole
1,024-byte bank pointer range). Why:
- **The pinned flow takes them on sg13cmos5l.** `sram-macro/` hardened both side by side in a
  6x4 tile: routing DRC, LVS and antenna 0, positive slack at all three corners, and Tiny
  Tapeout's precheck passes, with the KLayout SG13CMOS5L deck at 0 violations over the merged GDS
  (the PDK at 2bbec755 ships the sg13g2 macros through a symlink, so the "no SRAM macro on cmos5l"
  claim does not hold there). Magic DRC reports errors inside the macros only, which the cmos5l
  precheck does not run; that and Magic's stripe "illegal overlaps" are documented exceptions
  (`sram-macro/README.md`).
- **Gain cells are not used for the bank in this first top**, on the measurements of
  `../gain-cell-macro/README.md`: a 1 kbit bank (32 x 32 plus Berger bits) hardens DRC- and
  LVS-clean on sg13cmos5l but its die is 39,900 µm², against 45,309 µm² for the whole 8 kbit
  512 x 16 SRAM macro; it needs VDD at 1.20 V (at the slow, cold corner a written 1 is
  unreadable at 1.17 V); and its power pins are Metal4 stripes that need a custom power-grid
  script in a Tiny Tapeout tile, where TopMetal1 is not allowed. The gain-cell bank stays a
  separate experiment.
- **Flip-flop arrays are too large**: 512 x 16 plus 1024 x 8 bits is 16,384 flip-flops, about
  800,000 µm² at 49 µm² each, more than the whole tile.

The macros' functional models equal the core's behavioural memory read for read
(`sim/macro_check.sh`, `results/macro-check.txt`: 200,000 random reads each, 0 differences; a
read-first control differs on about a quarter of them), so the lockstep's memory model is the
hardened one.

### Port map onto Tiny Tapeout's pins

Tiny Tapeout gives 8 inputs (`ui_in`), 8 outputs (`uo_out`) and 8 bidirectional pins (`uio`).
Inside the chip they are numbered as 16 input pads and 16 output pads:

| pads | TT pins | use |
|---|---|---|
| in 0-7 | `ui_in[7:0]` | general inputs |
| out 0-7 | `uo_out[7:0]` | general outputs, push-pull only |
| in/out 8-11 | `uio[3:0]` | host link data (bidirectional; the chip drives them only while the host asks to read) |
| in 12 | `uio[4]` | host link strobe, from the host |
| in 13 | `uio[5]` | host link read request, from the host |
| in/out 14-15 | `uio[6]`, `uio[7]` | general pins with output enable: the only true open-drain pins (I2C, PS/2, CAN TX/RX via a transceiver) |

**Output pads 0-7, 14 and 15** each have a host-set source select (5 bits), an invert bit and an
"undriven" level:

| source | what drives the pad |
|---|---|
| 0-7 | sequencer logical pin 0-7: its quarter-clock nibble (`pin_sub`) and its output enable |
| 8-11 | streamer pin 0-3, with its enable |
| 12, 13, 14 | pin NCO: quarter-grid, half-grid, clock-grid nibble |
| 16-19 | segment 0-3 tap flag (the one-bit DAC's output) |
| 20-23 | segment 0-3 tap data bit 0 |
| 24 | the recovered bit of the edge-tracking sampler |
| others | constant 0 |

A push-pull pad (0-7) whose source is not driving shows the "undriven" level. On pads 14-15 the
source's enable becomes `uio_oe`, so an open-drain source really releases the line.

**Inputs.** Each of the sequencer's 8 logical pins reads a host-selected input pad (4 bits each);
`pin_in4` is that pad's four quarter samples and `pin_in` its latest (quarter 3) sample. The
sampler's four pins have their own pad selects, or take the recovered-bit stream. The edge-tracking
sampler reads one selected pad's four quarter samples, with an optional "active" (squelch) pad.

**Phases.** The core is one clock domain. Its outputs are, per output pad, the nibble of levels for
the four quarters of the clock, and its inputs, per input pad, the four quarter samples; the
four-phase stage (`../multiphase/stage.ml`, unchanged) sits between them and the pins. Its
invariants, which `../multiphase` verified, set the simulation boundary: the pad shows nibble k
during clock k + 1, and the core sees in clock j + 2 the samples taken in clock j. Tiny Tapeout
gives one clock, and the note's quarter phases need the calibrated delay line (deferred). The
hardened chip therefore runs the stage on **both clock edges**: phases 0 and 1 on the rising
edge, 2 and 3 on the falling edge, and the core's nibble folded onto the half grid
(`n0 n0 n2 n2`), so lanes 1 and 3 never toggle. An edge requested at quarter 1 or 3 then appears a
quarter late. This is the note's "both clock edges first (free)" step, marked here as a
deviation of the hardened chip from the simulated one at the pins only.

**Where the half-clock edges land** (section 8's density-70 harden, the submitted one; post-route
timing with extracted parasitics, `results/edge-placement-pe4-assists-dens70/`, 2026-10-30). Every `uo_out` pad is a rising-edge lane
flip-flop and a falling-edge one (clocked through a local inverter) into one `xor2` and one buffer,
so at most one XOR input changes per half clock and the logic cannot make a runt pulse. What moves
an edge off the half-clock grid is the clock path and the data-dependent delay through the XOR.
Taking the worst pairing of the two, a falling-edge-launched edge lands at most 0.46 ns early
relative to a rising-edge-launched one at the slow corner (0.31 typical, 0.21 fast; 11, 7 and 5 % of a
quarter clock), and the narrowest half-clock pulse is 7.70 ns of the ideal 8.34 (7.92, 8.07). On the
density-60 harden it was 0.56 ns and 7.58 ns (`results/edge-placement-pe4-assists/`). These
assume a 50 % duty cycle at the `clk` pin: each 1 % of duty-cycle error moves the falling-edge
edges by a further 0.17 ns, which only a measurement on the board can bound.

### Host link protocol

Four data lines `D` (`uio[3:0]`), a strobe `S` from the host (`uio[4]`), and a read request `R`
(`uio[5]`). The chip sees all three through the input stage's synchronisers (the latest quarter
sample). The host clocks the chip (the RP2040/RP2350 makes the 60 MHz), so all timing is in chip
clocks.

- **Every change of S moves one nibble**, in either direction. Bytes go high nibble first.
- **Write (R low).** The host sets D, waits at least 2 clocks, toggles S, and holds D for at least
  2 more clocks. The chip takes D in the clock in which it sees S change.
- **Read (R high).** The chip drives D with the current nibble. The host samples D, then toggles S
  to ask for the next nibble, with at least 8 clocks between toggles (input latency, the read and
  the output stage). Before raising R the host releases D; after lowering R it waits 8 clocks
  before driving D.
- **Commands** are bytes in the write direction: `{op, target}`, then address high, address low
  and a count byte n, which means n + 1 bytes. op 1 writes the n + 1 data bytes that follow; op 2
  reads: the host raises R and reads 2 (n + 1) nibbles. Each data byte goes to (target, address)
  and the address increments. Lowering R returns the command parser to idle, which is also the way to
  resynchronise.

| target | write | read |
|---|---|---|
| 0 REG | configuration and control registers (map in `regs.ml`) | registers and status |
| 1 PROG | programme store, byte address (word a/2; low byte at even a; the word is written with its high byte). Only while the sequencer is stopped; otherwise ignored and a sticky error bit is set | the same bytes, while stopped |
| 2 BANK | data bank, while stopped | the same |
| 3 HOSTIN | push the byte into the 16-byte FIFO that the threads' IN reads (dropped, with a sticky bit, when full) | |
| 4 HOSTOUT | | pops the 8-entry FIFO filled by OUT: two bytes per entry, `{valid, tag}` then the byte |
| 5 PECFG | one byte into the configuration chain of segment (address bits 9:8) | |
| 6 PEINIT | one byte into the init chain of segment (address bits 9:8) | |
| 7 PESEG | segment (address / 4 mod 4) register (address mod 4): feed low, feed high, control, repeat | |
| 8 STREAM | three bytes per word: low, high, vector count; the word is pushed with its count byte | |
| 9 SAMPLE | | pops the sampler FIFO: three bytes per entry, `{valid, count}`, low, high |
| 10 MATCH | bit 0 of the byte is shifted into the matcher's configuration chain | |

Control: register 0 bit 0 is **run**. While it is clear the sequencer is held in clear, and its
memory and FIFO strobes are gated off (the core's strobes are combinational of the fetched word,
and the clear does not mask them). Register 0 bit 1 holds the bit-path assists, streamer,
sampler and NCO in clear. Each thread's boot page and pc are registers; another register
restarts one thread at a page and pc while running (the core's `ctl` port).

**How the programme store is loaded.** Hold run clear, write the boot pages and pcs, write the
programme through PROG (and any tables through BANK), configure the array through PECFG, PEINIT
and PESEG and the pins through REG, then set run. Programmes for the earlier ISA variants are
translated once by the host (`../sequencer-v2/compat.ml`) and relocated into the store, which is
the compiler's job anyway.

### The thread ↔ array glue (MBX ports 4-7 ↔ segments 0-3)

- **SEND on port p** (always ready): the byte goes into segment p's feed register, alternately
  as the low byte and as the high byte; the high byte commits the word (as the note says and as
  the one-bit DAC's pump assumes). The SEND reaches the array one clock after it executes,
  because the core registers its port output. A host write to the same path waits a clock if a
  thread's byte is going in.
- **RECV on port p**: a holding register per port takes segment p's tap word whenever it is
  empty and the tap is valid; RECV returns its low byte, then its high byte, then it is empty.
- Segment taps' flags and valid bits are flag sources; tap flags and tap bit 0 are pad sources.

### Sizes and how the PE count grows

Simulation: the 1024-word store, the 1024-byte bank and any layout. The hardened chip starts at
**4 PEs** (segments 1|1|1|1, so that all four MBX ports have a segment) and grows towards 16
(2|2|2|2 for 8, then the note's 2|2|4|8) while the measured area allows. The programme store
and bank sizes are parameters of the hardened top; which memory implementation is used is
recorded with each harden.

### Verification plan

1. **Executable specification** (`chip_spec.ml`): the blocks' own models stepped together: ISA
   v2's interpreter (`isa2.ml`), the PE array model, the streamer and sampler models, the edge
   sampler, CRC and matcher models; new code only for the glue (host link, FIFOs, registers,
   pin map, port holds) and for the NCO, which has RTL but no model.
2. **Lockstep** (`lockstep.ml`): RTL against the specification every clock, on random programmes,
   random pin inputs and random host-link traffic (including programme loads and array
   configuration), comparing every pad, the host link's read data and the architectural state of
   the sequencer and the array.
3. **Planted integration bugs**, each of which the lockstep must catch: swapped pin lanes, a
   wrong mailbox port wiring, a miswired segment, a flag select off by one, a host-link nibble
   order, ungated strobes during clear, and more.
4. **Demos, unchanged firmware, through the host link** (`demos.ml`): UART, SPI and I2C from
   `../deadline-sequencer` with its decoders and I2C slave; the same pins to
   `../../tools/sigrok-judge`; then the one-bit DAC from `../onebit-dac` end to end, judged
   bit for bit against its own fast model.
5. **Area and G13**: synthesis, then `../../tt/scripts/harden.sh` at 6x4, reporting the
   placement factor against the note's 1.5 and 2.0 and the PE count that fits; then
   `../postlayout-roundtrip`'s lockstep and `compare_def` on the hardened layout if practical.

Generated Verilog is never committed (as `../../tt/scripts/regen.sh` does).

## 2. The top level, the specification and the lockstep (milestone 2)

| file | what it is |
|---|---|
| `src/regs.ml` | the host-visible encoding: link targets, register map, pad and source codes |
| `src/chip_spec.ml` | the executable specification of the core, composed from the blocks' models |
| `src/chip_rtl.ml` | the core in Hardcaml: the blocks' RTL unchanged, and the glue; 27 plantable integration bugs |
| `src/host.ml`, `src/board.ml` | the host's side of the link, and the board: the stage's pad timing, the outside world |
| `src/tt_top.ml`, `bin/emit.exe` | the Tiny Tapeout top (`chip_tt`): core, stage on both edges, reset synchroniser, memories |
| `bin/lockstep.exe` | random lockstep and the planted-bug controls |
| `blocks/*` | symlinks to the blocks' sources, one dune library each |

**What the specification composes, and what is new.** The sequencer is ISA v2's interpreter, the
array is `unified-pe/verify/model.ml`, the streamer, sampler, edge sampler, CRC unit and matcher
are their own models. Written new, because nothing specified them: the glue (host link, FIFOs,
register file, pin map, flag selects, port holds, memories) and the pin NCO (its RTL has no
model; the spec follows `nco.ml`'s header). The glue is specified once in `chip_spec.ml` and
built separately in `chip_rtl.ml`; they share only the encoding in `regs.ml`.

**Lockstep** (`results/lockstep.txt`, `results/lockstep_layouts.txt`). Each trial: the host
loads random programmes (biased towards ports, mailboxes, WAITC on flags, the bank), random pin
maps, flag selects, assist configurations, PE configurations and init chains, a matcher chain,
bank bytes; then runs, while random host traffic continues (FIFO traffic, register and status
reads, feed writes, restarts, port resets, stops with store and bank access, refused writes,
assist reconfiguration under hold) and random pad inputs toggle at per-pad rates; a quarter of
the trials reset the chip mid-run. Five generators: mixed, ports, host, memory and race.
Compared every clock: every output pad's four-quarter nibble and the uio enables; the full
architectural state of the sequencer (every thread's registers, inboxes, latch), every PE (S,
P, valid, F, lane, 64 configuration bits), every segment register (feed, control, repeat,
committed word), the port SEND order and RECV holds, the host FIFO counts, the CRC register,
the NCO register, the matcher sum, the edge sampler's outputs, the link's read buffer, the heads
of the host FIFOs and of the sampler FIFO, and the streamer's pins. Not compared directly: FIFO
entries behind the head (they are compared when they reach it), the register file and the
memories (compared when read, by the host or the core), the NCO accumulator and the matcher's
configuration chain (compared through their outputs). The random pad inputs drive pads 0-7, 14
and 15; pads 8-13 carry only host-link traffic, which the pin maps can also select.
- 400 trials × 12,000 clocks at 4 PEs (1|1|1|1), 1024-word store: **4,800,000 clocks, 0
  mismatches**; coverage counts every opcode, 79,128 SENDs to segments, 8,762 RECVs, 63,851
  OUTs, 369 host feed writes held back by a SEND, 46 HOSTOUT entries arriving between a read's
  two bytes.
- At 8 PEs (2|2|2|2), 16 PEs (2|2|4|8) and with a 256-word store: 480,000 clocks each, 0
  mismatches.

**Planted integration bugs: 27 of 27 caught** (`results/controls.txt`): swapped pin lanes,
swapped quarters, input pin map and quarter, SEND to the wrong segment, RECV from the wrong
port, SEND byte order, a hold taking the wrong segment's tap, the recovered-bit stream on the
wrong fixed port, host feed writes beating thread SENDs, flag select off by one, flags of the
wrong thread, both host-link nibble orders, IN and STB strobes not gated in clear, HOSTOUT
popping without its tag, sampler pins, uio enables, boot pcs, the restart page, edge-sampler
quarter order, NCO byte order, programme byte order, PECFG segment bits, sticky status, HOSTIN
overwrite. Two needed biased generators: the ungated STB (the memory mode puts STB at a boot
word, which the core fetches on every clock in clear) and HOSTOUT without its tag (the race
mode); the first version of the ungated-STB bug was structurally a no-op, which the control
showed.

**Found by integration, fixed in the blocks' own commits:**
- `pin-streamer` (b2c1433): the RTL refused a push into a full FIFO even when the head left in
  the same clock; the model accepted it. Its lockstep never pushed into a full FIFO. New test:
  198,264 mismatching clocks before, 0 after.
- `unified-pe/verify` took the one-bit DAC's three additions (d56d9d0) and a layout parameter
  with an embeddable `array_create` (b24bf63); all its results rerun identically.

**Found by integration, handled in the glue (no block change):**
- The core's strobes (IN pop, STB, port pops) are combinational of the fetched word and are not
  masked by its clear, so the glue gates them with run. Without that, a store word fetched in
  clear writes the bank and pops FIFOs (the two "ungated" controls).
- The edge sampler's bit output is defined only while its valid is high (its RTL leaves the
  last unrolled sub-sample's value there). The glue holds the last recovered bit, so pads,
  flags, the sampler and the fixed port see a level.
- The streamer and sampler models take a width of 1, 2 or 4; the registers reset to width 1,
  and the assists reset held (control register 0 resets to 2).

**Contracts the specification assumes** (the random host keeps them; a real host must):
the streamer's, sampler's and matcher's configuration changes only while the assists are held
(their models fix the configuration at creation, and the matcher's closed form counts from its
last clear); widths 1, 2 or 4, periods at least 1, a CRC mask of the form 2^w - 1; the host-link
timing of section 1; after resetting the chip mid-transaction the host starts again.

## 3. The demos through the host link (milestone 3)

`bin/demos.exe`. Each demo runs the specification and the RTL together on the board and compares
every pad every clock; both agree throughout in every run below.

Each demo is run twice, once with the board (host, outside world, I2C slave) seeing the
specification's pads and once seeing the RTL's (`results/demo-*-spec.txt`, `results/demo-*-rtl.txt`),
so each is an end-to-end run of the RTL as well. "Unchanged" means the firmware, the I2C slave,
the payloads and the decoders are the original files; the bench around them is new (the host
loads the firmware through the link, and the stage's pad latency is in the loop).

**UART, SPI and I2C** (`results/demo-ds-*.txt`). The firmware is `../deadline-sequencer`'s
compiler output, unchanged; the host's loader translates it to ISA v2 (`compat.ml`), relocates
thread t to offset 64 t and loads it through PROG. UART, SCLK, MOSI and CS on `uo_out[3:0]`;
SDA and SCL on `uio[6]`, `uio[7]`, the open-drain pins, with the demo's own I2C slave model on
the bus. The demo's own decoders: UART "OK!" (0x4f 0x4b 0x21), SPI 0xa5 0x3c, I2C 0xa0+ack
0x5a+ack and STOP, the host reads the two ACK bytes 0x00 0x00 from HOSTOUT; edge timing as the
original checks it (UART edges at multiples of 64 clocks, SPI SCLK period 64, SCL high 32).
**PASS** both ways. The RTL-driven run's trace through `tools/sigrok-judge`, run separately
(`results/sigrok-judge.txt`): UART, SPI and I2C decoded by sigrok's decoders, all six teeth caught.

**One-bit DAC** (`results/demo-dac-*.txt`). `../onebit-dac`'s pump firmware and order-2 PE
configuration (FB1, I1, FB2, I2, without the pass-through PEs) on the 4-PE chip as one run over
the four segments; the host streams a 997 Hz tone at -6 dB through HOSTIN, polling the FIFO
count and HOSTOUT for underrun reports. The pin is segment 3's flag through the pad select,
inverted. Judged against `../onebit-dac`'s bit-exact fast model: **54,349 steps (400 samples), 0
wrong bits**; the start of the modulator is placed exactly, and the lead-in on the feed's
initial word 0 is the one fitted parameter: of the 2,001 lead-ins tried exactly one gives 0
wrong bits, the next best 19,654. Control: the same bits against the order-3 model
are 48 % wrong. No underruns, no overflow. **PASS.**

What the demos do not show: the UART/SPI/I2C pins run with q = 0 only (the base ISA), so the
quarter grid is exercised by the lockstep alone; the DAC uses one channel (four PEs); S/PDIF
was not run.

**The standard protocol settings and the target roles** (`bin/roles.exe`,
`results/roles-*.txt`): `../protocol-roles`'s ISA v2 firmware, loaded through PROG at page
boundaries with its peer models on the pads; specification and RTL compared on every pad every
clock, run with the board following either. UART at 115200 baud: thread 0 sends the host's bytes
(HOSTIN) on `uo_out[0]`, thread 1 receives on `ui_in[0]` and reports to HOSTOUT. SPI controller:
thread 0 in mode 0 at 1 MHz and thread 1 in mode 3, lsb first, at 1.5 MHz, each against a peer
target, replies to HOSTOUT. I2C controller in Fast-mode on `uio[6]`, `uio[7]` with a target
stretching the clock, 300 ns edges, the host feeding 22 command bytes through HOSTIN (16 deep):
the whole transaction with a repeated START and reads. I2C target on the same pins against a
Fast-mode controller, the host answering each request as it reads HOSTOUT: the target holds SCL
low up to 717 clocks while the host link turns round. SPI target in modes 3 and 0 at 1 MHz on
`ui_in` and `uo_out[2]`, and a speed search: right up to 1.36 MHz with bytes back to back (the
pads' latency costs 2 clocks of half period against the bench's 1.5 MHz). **PASS** both ways for
each. The host must drain HOSTOUT often (8
entries; the two SPI threads make 9 within 2,000 clocks), and the run checks the sticky
overflow bit.

## 4. Area, the harden, and G13 (milestone 4)

**Synthesis** (`synth/synth.sh`, Yosys 0.66 of the pinned LibreLane image, sg13cmos5l typical,
area-mode abc, flattened, the SRAM macros as black boxes; `synth/reports/`):

| layout | standard-cell area, µm² | cells | flip-flops |
|---|---|---|---|
| 4 PEs (1\|1\|1\|1) | 274,741 | 18,833 | 2,519 |
| 8 PEs (2\|2\|2\|2) | 333,783 | | 2,915 |
| 16 PEs (2\|2\|4\|8) | 454,462 | | 3,707 |

A PE costs 14,760-15,085 µm² (the step from 4 to 8 and from 8 to 16), as the block's own synthesis
said (14,359 for upe_v1, plus the shift X1). **Everything else is about 215,700 µm²**, against
126,603 in section 6 of the architecture note: the sequencer alone is 41k (its README), and the
register file, host FIFOs, input and output pin selects, the stage's 192 input and 128 output
flops and the assists are the rest. Macros: 45,309 µm² (512 x 16) and 49,419 µm² (1024 x 8).
The 6x4 tile on sg13cmos5l has a 916,214 µm² die and a 902,417 µm² core (larger than the note's
751,641 for sg13g2's tiles).

**Hardens** (`tt/scripts/harden.sh`'s flow through `sram-macro/scripts/harden.sh`: LibreLane
3.1.0.dev3, tt-support-tools d66cf17, 6x4, 20 ns, the macro recipe of `sram-macro/`):

| run | result |
|---|---|
| 4 PEs, macros side by side at the lower left, placement density 60 % (TT default) | global routing overflows Metal3 (1,601); detailed routing stalls near 400 violations after 61 iterations; stopped (`results/harden-pe4-d60/`) |
| the same at density 45 % and 75 % | overflow 3,898 and 2,418 at global routing; stopped (`results/harden-pe4-d45/`, `-d75/`) |
| **4 PEs, the 1024 x 8 moved to the right end of the core**, density 60 % | **passes**: global routing without overflow; routing DRC 0, LVS 0 (netgen: circuits match uniquely), antenna 0; **Tiny Tapeout's precheck 9 of 9**, KLayout SG13CMOS5L DRC clean; Magic DRC 141,979, every one inside a macro (`results/harden-pe4-20ns/`) |
| 16 PEs (2\|2\|4\|8), same floorplan | 610,596 µm² of standard cells before routing (76 % of the free core); global routing: Metal3 demand 105 % of capacity, overflow 22,240; stopped (`results/harden-pe16-attempt/`) |
| **8 PEs (2\|2\|2\|2)**, same floorplan | **passes**: global routing overflow 398 (Metal3 at 80 %), detailed routing to 0 in 15 iterations; LVS 0, antenna 0; **precheck 9 of 9**; Magic DRC all inside the macros (`results/harden-pe8-20ns/`) |

**Why routing, not area, is the limit.** sg13cmos5l's block routes on Metal2 to Metal4 only
(TopMetal1 belongs to Tiny Tapeout's top level), so **Metal3 is the only horizontal routing
layer**, and Metal4 also carries the power stripes. In every run Metal3 was the overflowing layer
while Metal4 stayed at 8-30 % use. Lower placement density spreads the cells and lengthens the
wires (2.44 M µm against 2.22 M at 60 %), which made it worse, not better. What cured the 4-PE
run was floorplanning: the 1024 x 8 macro (336 µm tall) in the middle of a 710 µm die split the
horizontal routing channel.

**The 4-PE chip in numbers** (`results/harden-pe4-20ns/`): 27,773 standard cells, 374,588 µm² after
place and route (1.36 times the synthesised area: 3,206 hold buffers and 5,453 timing-repair
buffers), 46 % of the core, wire length 1.40 M µm. Timing at 20 ns: setup +4.06 ns typical
(about 63 MHz), +4.62 ns fast, **-4.17 ns at the slow corner** (81 endpoints; about 41 MHz);
hold positive at every corner (+0.095 ns fast). The flow fails only on the typical corner, so the
harden passes, but **60 MHz is met only at the typical corner**. The worst path runs between two
unnamed glue registers through about thirty gates; naming the glue's signals to locate it is an
open issue.

**The placement factor, measured** (section 6 of the note assumed 1.5, pessimistic 2.0):
- the growth from synthesis to placed cells is **1.36** (the factor's lower bound, no white space);
- the area the 4-PE logic was given and routed in, core minus macros and a 10 % halo, is **2.91**
  times its synthesised area (an upper bound: the run met it with room for more);
- the 16-PE run shows the other side: at 610,596 µm² of placed cells, 76 % of the free core and a
  free core of 798,215 µm² against its 454,462 µm² synthesised (a factor of 1.76), it does not route;
- the 8-PE run routes with 451,806 µm² of placed cells (growth 1.35) in the same free core, a
  factor of **2.39**, with Metal3 at 80 % of its capacity at global routing.

So on sg13cmos5l, in Tiny Tapeout's 6x4 tile with its flow, the whole-chip factor that routes
lies **between 1.76 (fails) and 2.39 (passes)**: the note's 1.5 does not hold, and its
pessimistic 2.0 is about the boundary. The cause is the single horizontal routing layer, which a
factor measured on a row of PEs (`../pe-synth`, on sg13g2's routing stack) could not show.

**What fits.** **8 PEs** (segments 2|2|2|2) with both SRAM macros and everything in section 1:
hardened, routed, LVS-clean, precheck-clean. **16 PEs do not route.** 12 PEs were not tried: at
about 394,000 µm² synthesised (8 PEs plus four at 15,085) the free core is 2.03 times the
logic, inside the uncertain band. The levers, before cutting PEs: the glue (215,700 µm²
synthesised, more than 14 PEs) and its wide selects (every pin and sampler select reads all 16
pads' four quarters), and the 3,200-3,700 hold buffers that Tiny Tapeout's 0.25 ns clock
uncertainty forces onto short register-to-register paths.

**Timing of the 8-PE chip** (`results/harden-pe8-20ns/corners.txt`): setup +1.67 ns typical at 20 ns
(about 55 MHz), +4.44 ns fast, -9.21 ns at the slow corner (265 endpoints, about 34 MHz); hold
positive everywhere. The longer critical path with more PEs points at the array's combinational
chains (the step, g and lane-loop signals of a joined run ripple through every PE of the run in
one clock); not confirmed. **Neither size meets 60 MHz at the slow corner**; the 4-PE chip meets
it at the typical corner, the 8-PE chip does not.

Tiny Tapeout's `tt/` now builds the 4-PE chip by default (`CHIP_SIZES=1,1,1,1`; section 5).

**Post-layout round trip** (`../postlayout-roundtrip`, section "The combined chip, with its SRAM
macros"; logs in `../postlayout-roundtrip/results/chip-top/`). The extractor now keeps the SRAM
macros as black boxes with their pins (from their GDS labels, checked against their LEFs) and
simulates them with IHP's functional model. On both hardens: the structural check is clean (0
undriven, 0 multiply driven nets); `compare_def` matches every placement (73,133 at 4 PEs, 75,061 at
8) and every net as an endpoint set against the DEF and nl.v (27,514 and 33,458, all 178 macro pins
included); every placed master equals the PDK's GDS, sub-cells included. `bin/gate_lockstep.exe`
runs the extracted gates edge by edge against this Hardcaml (`Tt_top.reset_sync`, `Tt_top.core_side`
and the stage with phases 2-3 on the falling edge): 8 x 25,000 clocks each, 400,000 output words, 0
differ, and 915 bytes written to the two memories read back through the pins correctly. The 4-PE
harden was made from 233c71e (before the pad selects got reset values), so its lockstep uses those
sources; against this branch's sources it differs, as it should (32 words). Planted cuts and shorts
at macro pins are caught by the structural check, `compare_def` and the lockstep; swapped macro pins
by `compare_def` and, except for two address pins (a permutation of a single-port RAM's addresses,
invisible through that port), by the lockstep. The 25 flip-flops "clocked directly from the clock
port" in the first check were a printout artefact (the check looked for a port named `clock`, and
all 2,519 flip-flops failed; 25 fitted in the printout); 42 flip-flops take the falling edge, which
are the both-edges stage's phase-2/3 flip-flops left after synthesis.

## 5. Tiny Tapeout's `tt/` now builds this chip

`../../tt/info.yaml`, `src/config.json` (the template plus the macro recipe, with the 1024 x 8
at the right end), `docs/info.md` and the wrapper `src/chip_project.v` are the combined chip's;
`tt/scripts/regen_chip.sh` generates `chip_tt.v` (never committed) and `harden.sh` and
`stage-for-action.sh` call it (`CHIP_SIZES` picks the layout; default 4 PEs). The cocotb test
`tt/test/test_chip.py` (`make`, needs `PDK_ROOT` for the macro models) loads a programme through
the host link on the real both-edges stage and passes. The earlier sequencer harness stays in
`tt/variants/seqv2/` (`TT_VARIANT=seqv2`, `make CHIP=no`, and CI's `tt-harness.yaml`).

## 6. Which half of the clock each pin is sampled in, and what the tests reach (milestone 6)

Two gaps the post-layout round trip left (section 4): the 32 falling-edge input samplers of the
both-edges stage were pinned to their edge only by the structural trace (moving one to the rising
edge in the extracted netlist was caught by none of the 5 tried), and about a third of the
rising-edge flip-flops never changed under the gate lockstep's stimulus. Logs: `results/edge-phase/`
and `results/coverage/`.

### The edge-phase test (`bin/edge_phase.ml`)

Each input pad under test toggles at most once per clock, at random in the first half (+T/4,
between the rising edge E and the falling edge F) or the second half (+3T/4, between F and the
next E), or not at all. Four threads loop on `SHI quad`, which shifts a logical pin's four quarter
samples into the accumulator, two pins per thread, and store a byte every 16 clocks in the data
bank; the host stops the chip and reads the bank back. For every pad the test then asks which
sample instants reproduce every stored nibble, for some alignment between the threads' clocks and
the pad log: quarters 0-1 at E, at the previous F or at F; quarters 2-3 at E, at F or at the next E.
The design must fit (q0 at E, q2 at F) and nothing else; a first-stage sampler moved to the rising
edge samples quarter 2 at the next E instead, and the test names that pad and that instant. This
check reads the stored bytes against the pad schedule, not against a reference. All 16 pads are
tested, the host-link pads included: the data lines while the strobe is still, the strobe and read
request with the data lines held at 0 (a strobe change then moves a 0 nibble, which the parser
ignores, and a read-request change resets the nibble phase). Then every general output pad is put
on the pin NCO's quarter or half grid, whose edges fall on quarter 2: lane 2 is the only output
lane on the falling edge, so every pin must change after falling edges as well as rising ones.
Every half clock the outputs are also compared with a second simulator.

It runs on the two-part Hardcaml reference (`edge_phase.exe rtl`), on the gates extracted from a
GDS (`edge_phase.exe gates`, compared with the reference), and in Icarus Verilog on the RTL or on
the hardened netlist (`sim/edge_iverilog.sh`: the same stimulus replayed with the inputs changing
at T/4 and 3T/4 of a 20 ns clock, the trace checked by `edge_phase.exe replay` and compared with
the reference). 9,461 clocks; each run reproduces every stored nibble with exactly one alignment.
A schedule too regular to tell the instants apart would make several hypotheses fit, which fails
the check rather than passing it; `edge_phase.exe rtl-control` runs the test on the reference with
the stage's own planted fault (a quarter-1 sampler on the falling edge), and it fails.

| simulator | 4 PEs (233c71e, the GDS of record) | 8 PEs |
|---|---|---|
| Hardcaml reference | every pad (q0 at E, q2 at F) only; 10 of 10 pins change after falling edges | the same |
| extracted gates, compared with the reference | the same; 0 of 18,922 half clocks differ | the same |
| Icarus, RTL (`chip_tt.v`) | the same; 0 differ (unknown outputs only in the first 4 half clocks, inside the reset) | the same |
| Icarus, P&R netlist with the cell and SRAM models | the same; 0 differ (4 s for the run) | the same |

**Every falling-edge flip-flop moved to the rising edge, one at a time** (42 per harden; in the
extracted gates by `edge_phase.exe gates ... all`, in Icarus by `sim/edge_plants.sh`, which marks each
one's clock in a copy of the netlist so that `+plant=k` inverts it):

| role (traced in the netlist) | count | caught by the test (both simulators, both hardens) | structural rule |
|---|---|---|---|
| lane-2 output toggle | 10 | 10: the pin has no falling-edge changes, and the outputs differ | not its job |
| first-stage input sampler | 16 | 16: the test names the pad as fitting (q0 at E, q2 at E+1) only, and the outputs differ | 16 |
| second-stage input sampler | 16 | **0** | 16 |

The 16 misses are exactly the second-stage samplers on both hardens, and they are not a gap in
the stimulus: **moving the second synchroniser stage to the rising edge is a functionally
equivalent change.** `edge_phase.exe prove` explores the product of the quarter-2 path (s on F
samples the pad, r on F samples s, the retiming flop t on E samples r, each with the synchronous
clear) and each variant, from every common state under every input sequence: with r on the rising
edge, t agrees in every reachable state (8 product states); with s on the rising edge it does not
(36). r then captures s at the next E instead of the next F, and t still takes that value at the E
after; only the time r gives s to resolve changes, from a full clock to half of one, which is a
metastability margin, not a behaviour, so no simulation can see it. Those 16 flip-flops are pinned
by **a structural rule** instead (`edge_phase.exe structure`, run before every gate test): for each
input pad, the flip-flops whose D depends on the pad within 12 gates (the first stage) must include
a rising-edge and a falling-edge one; every flip-flop a first stage feeds (its second stage) must
take the same edge, as a phase's two synchroniser flops share the phase's clock in
`../multiphase/stage.ml`; and the retiming flip-flops after them must be on the rising edge. It holds
on both hardens and is violated by each of the 32 input-sampler plants and by none of the 10
lane-2 plants, which the test catches by behaviour. (The structural check of section 4 only
accepted an inverted clock as the falling edge; it did not say which flip-flops must have one. A
first version of this rule asked only for some falling second stage per pad; a cross-model review
pointed out that with two falling pairs per pad one could then move unnoticed, hence the pairing.) Of the five
plants tried in section 4, four were first-stage samplers of pads the random traffic never read at
clock resolution (the host's data lines `uio_in[0]` and `uio_in[3]`, whose two-clock margins absorb
the shift, and `uio_in[6]`, `ui_in[4]`), now caught; the fifth was a second-stage sampler, which
cannot be. The strobe's first-stage sampler, which none of them was, shifts the whole host link by
a clock: in Icarus its outputs differ on 7,743 half clocks.

### Register toggle coverage (`src/cov.ml`)

`lockstep.exe coverage SIZES TRIALS CLOCKS SEED NEVER_FILE [wide]` runs the lockstep with every
register bit of the core tapped, records which bits ever rise and fall, and groups them by block
and source line through Hardcaml's Caller_id (the debug outputs and the register file's addresses
name the bits). A three-valued fixpoint from reset (inputs, memory data and power-up states
unknown) proves bits constant: zero-extended register-file bits, a word's top bit that a shift
always clears, the first matcher cell's upper sum bits. The proof is checked against every run: a
bit it calls constant must never change (0 so far). Coverage below is of the bits not proved
constant.

**Coverage-directed stimulus** (`src/gen.ml`, `Gen.wide`; without it the generator is the old one,
draw for draw). The never-changed lists showed what the random traffic never did, and each
addition targets one cause: the assists' configuration from the whole legal range (12-bit periods
and offsets, 10-bit holdoff and timeout, any frame length); 16-bit host-link addresses and
transfers up to 256 bytes (the link's address and count registers); bursts that fill the streamer,
sampler and host FIFOs; a matcher configuration that a run of zeros matches in all 16 cells (its
sum's top bit); a slow pad rate, for long constant runs; LDD immediates up to 4095 (the deadline
counters' upper bits); 32-bit CRC register values (`Random.State.bits` gives 30); and in the ports
mode, threads that SEND on every issue slot, so that a host feed write waits until the next host
byte arrives and is dropped (the sticky bit). The lockstep still compares against the
specification every clock, and the planted bugs are still all caught: 400 x 12,000 clocks at 4 and
8 PEs, 0 mismatches; 27 of 27 planted bugs caught with the wide generator.

| RTL lockstep, 400 x 12,000 clocks | bits | constant (proved) | changed, before | changed, wide |
|---|---|---|---|---|
| 4 PEs | 2,696 | 152 | 2,419 of 2,544 (95.1 %) | **2,519 of 2,544 (99.0 %)** |
| 8 PEs | 3,092 | 152 | 2,816 of 2,940 (95.8 %) | **2,915 of 2,940 (99.1 %)** |

The PE array and the sequencer were at 100 % in the RTL lockstep already; the gaps were in the glue
(register file, link address and count), the assists' counters, the matcher and the streamer and
sampler. **The 25 bits left at either size are unreachable by design**, each by a one-line
invariant of its block (the sampler's and streamer's under the specification's contract that widths
are 1, 2 or 4):

| bits | where | why they never change |
|---|---|---|
| 22 | matcher partial sums, `matcher_en.ml:24` | cell k's sum counts k + 1 one-bit matches, so it never exceeds k + 1: bits 2-4 of cells 1-2, 3-4 of cells 3-6, 4 of cells 7-14 (cell 0's are proved constant; cell 15's top bit, a full 16-cell match, is reached) |
| 1 | sampler word, `sampler.ml:43`, bit 15 | the sample that fills bit 15 (or bits 14-15, 12-15 at widths 2, 4) is the one that pushes the word, which clears the register in the same clock |
| 1 | sampler vector count `n`, `sampler.ml:44`, bit 4 | n is reset when n + 1 reaches the 16 vectors a word holds, so it never exceeds 15 |
| 1 | streamer `left`, `streamer.ml:36`, bit 4 | `left` takes the vectors left minus one, at most 15 |

So every register bit of the core that can change, changes. The pin stage is outside the core and
not in these counts; at the gates it is covered by the edge-phase test.

**At the gates** (`gate_lockstep.exe ... stim=wide`: the lockstep's generators in the gate harness,
the outside world as quarter nibbles, quarter 0 at the rising and quarter 2 at the falling edge;
`ffs=FILE` lists each flip-flop's changes, and `sim/gate_cov.py` maps them through the DEF placement
and the netlist's Q-net names, which Yosys keeps from the Hardcaml, to the RTL registers and blocks).
Same budget as section 4, 8 x 25,000 clocks, 0 output words differ:

| gate lockstep, 200,000 clocks per run, 0 output words differ in any | 4 PEs (233c71e) | 8 PEs |
|---|---|---|
| section 4's host traffic (`stim=host`), 8 x 25,000 clocks | 1,879 of 2,519 (74.6 %) | 1,994 of 2,915 (68.4 %) |
| the lockstep's wide generator (`stim=wide`), 8 x 25,000 | 2,408 (95.6 %) | 2,772 (95.1 %) |
| the same, 40 x 5,000 | 2,480 (98.5 %) | 2,851 (97.8 %) |
| merged: both wide runs, another 40 x 5,000 (seed 3) and the edge-phase test | **2,500 (99.2 %)** | **2,896 (99.3 %)** |

The same budget in many short trials beats few long ones: every trial draws a new configuration,
and most never-changed flip-flops at the gates were configuration and pointer bits drawn too few
times. By block (8 PEs, section 4's traffic against the merged runs; the 4-PE harden is alike):
PE array 553 of 932 (59.3 %) to 932 of 932; glue 741 of 996 to 996; sequencer 231 of 317 to 317;
CRC 3 of 32 to 32; edge sampler 11 of 24 to 24; streamer 80 of 127 to 126; sampler 123 of 142 to
140; matcher 50 of 138 to 122; NCO and pin stage complete in both. **The 19 flip-flops that never
change, at either size, are all bits the RTL classification found unreachable by design**: 16
matcher partial-sum bits (synthesis removed six of the 22; of the 12 sum top bits left exactly one
changes, the last cell's, the only one that can), the sampler's word bit 15 and count bit 4 and the
streamer's `left` bit 4. So every reachable flip-flop of both GDS-extracted netlists changes.
`sim/gate_cov.py` classifies by source line and label against the RTL list (`rtl-never` /
`rtl-changed`); the matcher's cells share a line and have no label, hence the direct check above.
Logs: `results/coverage/gates/`.

**hwfuzz on the chip** (`lockstep.exe fuzz SIZES BUDGET SEED OUTDIR`, `results/coverage/hwfuzz-pe4.txt`).
The fuzz input is a string of commands, each a code byte and its operands: register, programme,
bank, PE-chain and segment writes, FIFO traffic, reads, run and stop, restarts, and per-pad toggle
rates. The decoder keeps the specification's contracts (assist changes wrapped in a hold, legal
widths, non-zero periods, CRC masks of the form 2^w - 1); the first run without that stopped on a
streamer width of 0, which the specification divides by. A transducer turns the commands into the
core's per-clock pad samples for hwfuzz's instrumented simulation, the commands are hwfuzz's
mutation units, and every seed and every input hwfuzz keeps is replayed on the board against the
specification, every pad and the architectural state compared every clock, with register coverage
recorded. 16 seeds set the chip up as a host would, with random operands. At 4 PEs, 3,115
executions in 821 s (one worker; about 2.3 executions a second at up to 6,000 clocks each, the
core's simulator rebuilt per execution because the memories have no reset) kept 102 inputs, and
coverage of the bits not proved constant went from 69.0 % (the seeds) to 77.4 % (seeds and queue);
**0 of the 118 inputs disagree with the specification.** Every bit the queue reaches the wide
generator reaches as well, since the wide generator leaves only the 25 unreachable bits. At this
budget the coverage-guided search is far behind the directed generator, mostly because it is slow
on a circuit of this size (every multiplexer select and register of the core is a probe, read every clock); a snapshot of the simulator
after the seeds' common setup, which hwfuzz's README already names as its next speed step, would be
the place to start.

**Running it.** `./suite.sh quick` (CI: `.github/workflows/chip-top.yaml`; about 70 s after the
build: 20 wide lockstep trials, the 27 planted bugs, coverage with a 95 % floor, the edge-phase test
and its control and proof) or `./suite.sh full` (the recorded runs, floors at 99 %). At the gates,
with a harden's `tt_submission/` and the PDK's cell models `M`:

    _build/default/bin/edge_phase.exe gates GDS M 2,2,2,2 [all]       # the test, or every plant
    _build/default/bin/edge_phase.exe structure GDS M all
    sim/edge_iverilog.sh gates 2,2,2,2 OUT tt_um_chip_top.v            # Icarus, needs PDK_ROOT
    sim/edge_plants.sh 2,2,2,2 OUT tt_um_chip_top.v
    _build/default/bin/gate_lockstep.exe GDS M 2,2,2,2 40 5000 2 stim=wide ffs=FFS
    _build/default/bin/lockstep.exe regmap 2,2,2,2 512 REGMAP
    sim/gate_cov.py FFS[,FFS...] DEF tt_um_chip_top.v REGMAP chip_tt.v NEVER RTL_NEVER

The 4-PE GDS needs the sources of 233c71e (section 4); the runs above used a scratch copy of that
commit with this branch's tools (not the RTL) copied in.

## 7. Timing at 60 MHz, the hold buffers, and the array's reset

The host clocks the chip at 60 MHz (16.67 ns). Section 4's hardens ran at 20 ns and failed the
slow corner (`nom_slow_1p08V_125C`) by 4.17 ns (4 PEs) and 9.21 ns (8 PEs).

**Reading the paths.** Netlist nets keep Hardcaml's names, and an anonymous signal `_N` is the
net `chip._N`; `bin/origins.exe` maps every signal to the OCaml call sites that built it
(Hardcaml's caller ids), `synth/paths.py` groups a run's STA paths by start and end origin, and
`synth/sta.sh` reruns OpenSTA on a run with several paths per endpoint. The glue's registers, the
array's per-PE state and chains, the edge sampler's outputs and the reset synchroniser now have
names. Findings (`results/critical-paths.txt`): every violating endpoint was a PE register,
reached from the edge sampler's output register through segment 0's fixed port, PE 0's A input,
the window difference, the g multiplexer, **the g chain** (a PE whose g source is 7 takes the
previous PE's g, across segment boundaries, one multiplexer per PE: the reason 8 PEs were 5 ns
worse than 4) and then the last PE's adder, saturation and result multiplexer. The step chain
(follow) rippled the same way. Next: the programme store's SRAM into the sequencer (its
clock-to-output is 6.25 ns at this corner), the input stage into the edge sampler's four unrolled
sub-sample steps, and the reset's fan-out. About a third of the worst path's delay was undersized
drivers on long wires (1.0-2.1 ns slews): the flow's setup repair judged timing on estimated
parasitics and found nothing to do.

**Fixes that keep every clock's behaviour** (each its own commit; the blocks' own results rerun
byte-identical, and chip-top's lockstep identical):

| change | where | how it is checked |
|---|---|---|
| g and step chains as a Kogge-Stone prefix: log2 n levels instead of n | `../unified-pe/verify` | block lockstep, controls, cells, shared faults, layouts, latency lint |
| `x + yn + c` as one adder with a carry-in, then the adder, both signed comparisons and the window difference as prefix adders (`prefix_add`, `signed_ge`) | `../unified-pe/verify` | the same, and a SAT proof against Hardcaml's operators with a failing control (`formal/arith_equiv`, `results/arith-equiv.txt`) |
| the edge sampler compares `since` with `holdoff - 1` and the timeout directly, not `since + 1` after the increment | `../eth10-node` | SAT proof of the sub-sample step against its plain form, with a failing holdoff + 1 control (`formal/edge_step_equiv`, `results/edge-step-equiv.txt`); `results/rx.txt` identical |
| the edge sampler's held level as a register of its own (`create_with_level`), equal to the glue's `mux2 es_v es_b es_last` | `../eth10-node`, `src/chip_rtl.ml` | chip lockstep |

Each moved the slow-corner slack of a 4-PE partial run (`results/timing-experiments.txt`); the
runs vary by about a nanosecond from one netlist to the next, so the table records them rather
than credits each change with a number. Rejected: Yosys's delay-oriented synthesis strategy
(-3.68 ns against -0.59, and 30 % more wire).

**The hold buffers.** 3,206 at 4 PEs and 3,696 at 8, 52,350 and 60,350 µm². The cause was not the
macros or the both-edges stage (3 % of the buffers sit behind the stage's flip-flops, none behind
a macro output) but the constraints: LibreLane's `base.sdc` applies the 0.25 ns clock
uncertainty to hold as well as setup, and sg13cmos5l has no enable flip-flop, so every register
with an enable or a synchronous clear has Q returning to its own D through a gate or two. That
loop has no skew and no jitter between launch and capture, yet clock-to-Q plus one gate is
shorter than 0.35 ns plus the hold time, so the flow buffered it: 2,115 of the 3,190 buffer
chains were such self-loops (`results/holds.txt`). Measured after CTS at the typical corner,
endpoints inside the hold margin by hold uncertainty: 1,692 at 0.25 ns, 72 at 0.15, 27 at 0.10.
`../../tt/src/chip.sdc` is `base.sdc` with the uncertainty on setup only and 0.1 ns on hold;
propagated clocks, the 5 % early/late derate and the flow's hold margins (now 0.05 ns after
placement and after global routing) remain. **78 hold buffers at 4 PEs, 121 at 8**, and hold is
positive at every corner (fast +0.031 and +0.025 ns).

**The flow** (`../../tt/src/config.json`, above Tiny Tapeout's "do not change" line):
`CLOCK_PERIOD` 16.67, `chip.sdc` for place and route and sign-off, a 0.5 ns transition limit
and a 400 µm wire-length limit, design repair and setup repair after global routing, 3 ns of
setup margin in both setup repairs. `../../tt/info.yaml` says 60 MHz.

**The glue's area** (`results/glue-area.txt`, `synth/area_by_origin.py`: flip-flops by the call
site that built them, combinational cells shared among the flip-flops they feed): about 90,000
µm² of the 4-PE chip's 298,000 (typical-liberty areas); the register file (550 configuration
bits, each a flip-flop with its enable multiplexer, about 43,000), the host FIFOs (17,000) and
the host link's read multiplexer (9,000) are the largest items. Each is fixed by the host-visible
register map and FIFO depths of the specification, and none was cut here. What came down is the
placed area around it: the hold buffers above, so the growth from synthesis to placed cells fell
from 1.36 to 1.21 (4 PEs) and from 1.35 to 1.22 (8 PEs).

**The array's reset.** `Upe_rtl.array_create` takes an optional synchronous clear of every
register (PE state and configuration chains, feed and control registers) to 0, the model's
initial state, and `chip_rtl.ml` drives it from the chip's reset. This changes behaviour: before,
the array ran on through a reset with idle inputs; now a reset clears it, so `chip_spec.ml` does
the same (a fresh model on reset). Why change it rather than prove it harmless: it was not
harmless. A pad whose source is a segment's tap bit, a flag on a tap, or a configuration that
reads P or F before writing them showed the power-up value. The power-up proof
(`formal/array_powerup.sby`, the method of `../formal/powerup`: two copies from arbitrary
register contents, the same inputs, one clock of clear; every register and tap equal from then
on) passes with the clear and fails without it, at 4 and 8 PEs (`results/array-powerup.txt`). A
new planted bug, `array_unreset`, is caught by the lockstep (28 of 28). Cost: about 2,800 µm²
of synthesis at 4 PEs together with the prefix adders (274,741 to 277,535).

**Verification after all of it**: lockstep 4.8 M clocks at 4 PEs and 480,000 at each of 1|1|1|1,
2|2|2|2, 3|3|3|3, 2|2|4|8 and a 256-word store, 0 mismatches (`results/lockstep.txt`,
`results/lockstep_layouts.txt`); 28 of 28 planted integration bugs caught
(`results/controls.txt`); both demos pass; the cocotb test of `../../tt/test` passes on the RTL.

**The hardens** (Tiny Tapeout's flow through `../../tt/scripts/harden.sh`, 6x4, 16.67 ns, the
1024 x 8 at the right end as before; setup / hold worst slack in ns):

| PEs | slow 1.08 V 125 C | typical | fast | slowest corner's period | hold buffers | cells | DRC, LVS, antenna, precheck |
|---|---|---|---|---|---|---|---|
| 4 (1\|1\|1\|1), `results/harden-pe4/` | **+0.255** / +0.253 | +3.095 / +0.114 | +3.619 / +0.031 | 16.42 ns, 60.9 MHz | 78 | 26,004 | 0, match, 0, 9 of 9 |
| 8 (2\|2\|2\|2), `results/harden-pe8/` | **-1.333** / +0.234 | +2.827 / +0.106 | +3.420 / +0.025 | 18.00 ns, 55.5 MHz | 121 | 32,822 | 0, match, 0, 9 of 9 |
| 12 (3\|3\|3\|3), `results/harden-pe12-attempt/` | -0.789 / +0.226 | +2.717 / +0.039 | +3.288 / **-0.070** | (17.46 ns) | | 39,402 | **508 routing DRC violations**: does not route; stopped before sign-off |

Magic DRC reports errors only inside the macros, as before (`magic-drc-by-region.txt`). The
4-PE harden is the refresh of section 4's: it includes 9a50420's pad-select reset defaults and
every change above. "Period" is the 16.67 ns clock minus the worst slack, so it includes the
0.25 ns setup uncertainty. The post-layout round trip's edge-by-edge gate lockstep
(`bin/gate_lockstep.exe`, two-edge, against this branch's Hardcaml) on both new GDS files: 8 x
25,000 clocks each, 400,000 output words, 0 mismatching, and the 915 bytes written to the memories
read back correctly (`gate-lockstep-two-edge.txt` in each harden directory).

**What limits 8 PEs.** The 8 failing endpoints are PE registers reached from a segment's control
register (its source select, `upe_rtl.ml` 308) or from a P register: the same PE route as before,
now with the chains in log depth. Their worst cells are drivers of long wires (0.25-0.30 pF, 1.9-2.6 ns at this
corner): global routing put Metal3, the only horizontal layer, at 81 % with an overflow of 1,049,
and detailed routing's detours are longer than the parasitics the repairs sized for. The 4-PE
chip has the same logic and meets 60 MHz with 0.26 ns to spare; at 8 PEs it is wire, not depth.

**12 PEs do not route.** Global routing put Metal3 at 88 % with an overflow of 4,096 (8 PEs: 81 %,
1,049); detailed routing went from 38,908 violations to about 500 and stayed there through its
iterations and the antenna repairs, ending at 508. The timing of that unfinished routing
(-0.79 ns slow, a fast-corner hold violation of 0.07 ns on 11 endpoints) is indicative only. So,
in this tile and floorplan: **8 PEs is the largest chip that routes**, as before; 12 would need
the routing lever (a floorplan or fewer horizontal wires), not a timing one.

## 8. The bit-path assists: stuffing and line coding on the chip (2026-10-10)

Jane Street's organisers say that for USB and Ethernet, the more of the protocol work (line
coding, CRC, clock recovery) the chip does itself, the better. Sections 1-7 had clock recovery
(the edge sampler) and the CRC unit; the stuff tracker and the line coder were area probes. They
are now specified and verified blocks (`../bit-assists`: model, Hardcaml RTL, lockstep, independent
references, planted faults) and sit on the chip's bit path, together with the two byte-level
blocks built from them.

### What was added

| block | from | what the chip gets |
|---|---|---|
| receive framer (`Rxpath`) | `../bit-assists/rxpath.ml` | behind the edge sampler: the line decoder (pass, NRZI, Manchester), the destuffer (inside a frame only), a start pattern on the last 8 chain bits (USB's sync, Ethernet's SFD), a byte packer with a two-byte FIFO, the end of a frame when the line goes inactive, at the sampler's burst end or by the host; a sticky stuff/code error; the CRC unit's feed after a skip count |
| transmit serialiser (`Txpath`) | `../bit-assists/txpath.ml` | a two-byte FIFO, a symbol timer, the stuffer, the encoder and a two-phase tail (USB's SE0, SE0, J; 10BASE-T's TP_IDL), as pad sources 25 and 26 (lines a and b); while idle they show two sequencer pins (`r_tx_idle`), so the threads keep the line between frames (link pulses, the released USB bus) |
| the bit path's port | glue | `r_bp_ctrl` names one MBX port: a SEND on it fills the serialiser (ready while the FIFO has room for it, counting a SEND still on its way out of the core), a RECV reads the framer; the segment behind that port keeps its feed from the host only |
| CRC source | glue | the CRC unit takes the framer's feed (and starts with each frame) or, as before, the edge sampler's bits |
| line activity | glue | `r_es_mode` bit 4: the line is active while the data pad or the active pad is high (a pair's common mode: USB's SE0 is inactive); flags for it and its inverse |
| flags 17-23, status 0x8E | glue | frame ended and read, frame error, byte waiting, serialiser active, line active, line inactive, in a frame |

Registers 0x80-0x8E (`regs.ml`; the register space grows to 0x90). At reset everything is off and
the CRC unit takes the edge sampler's bits, so the chip behaves as before until the host turns the
bit path on. The two new blocks read their configuration live: unlike the streamer and sampler,
they need no "change only while held" contract.

### Specification, lockstep, controls, coverage

`chip_spec.ml` steps the blocks' models (`Txpath.step`, `Rxpath.step`), `chip_rtl.ml` instantiates
their RTL; the lockstep compares the serialiser (lines, busy, FIFO) and the framer (chain bit,
history, byte, frame bits, FIFO head, flags) every clock. The generator (`gen.ml`) draws the bit
path's configuration from a stream of its own, seeded from the trial's, so every earlier draw is
unchanged: a quarter of the trials keep it off; USB-like and Ethernet-like loopbacks put the
serialiser on uio 6 and 7 and the edge sampler on the same pads (they read back what the chip
drives), with directed sender and receiver threads now and then; the rest is random. 9 new planted
integration bugs: the bit path on port p + 1, SEND readiness ignoring a SEND in flight, pad sources
25 and 26 swapped, the idle pin ignored, a RECV popping the segment's holding register too, the
line-active OR ignored, the CRC source ignored, the hold not clearing the paths, the host's frame
pulses swapped.

**Results** (`./suite.sh full`, all passed; `results/lockstep.txt`, `controls.txt`,
`lockstep_layouts.txt`, `coverage/`): lockstep 400 x 12,000 clocks at 4 PEs with the earlier
generator and again with the wide one, 4,800,000 clocks each, **0 mismatches**; 40 x 12,000 at
1|1|1|1, 2|2|2|2, 3|3|3|3, 2|2|4|8 and a 256-word store, 0 mismatches; **37 of 37 planted bugs
caught** with either generator (one, the RECV that also pops the segment, needed the ports mode
biased towards a loopback before the earlier generator caught it in 30 trials); register coverage
99.1 % at 4 PEs (2,733 of 2,759 bits not provably constant) and 99.2 % at 8 PEs. At 4 PEs the
framer (60 of 60 bits), the stuff trackers (10 of 10) and the line coders (6 of 6) are complete and
the serialiser has 51 of 52: its symbol timer's bit 11, which only a period above 2,047 clocks
reaches; it is reachable (an earlier 400-trial run of the same generator reached it, and at 8 PEs
it changes), the random draw of a large period simply came too rarely. The other 25 never-changed
bits are the unreachable ones of section 6; the edge-phase test, its control and its proof as
before. Synthesis (`synth/reports/pe4-assists.stat.txt`): **300,567 µm² at 4 PEs, +23,032 µm²
(+8.3 %)** over section 7's 277,535; the area probes' 813 + 477 µm² were the bare stuffer and coder,
without the FIFOs, the symbol timer, the start pattern, the 14 configuration registers, the read
multiplexer's growth and the pad and flag selects.

**Found by integration, fixed in `../bit-assists` with a failing test first** (each its own
commit): the destuffer took the sync's first 0 for a stuff bit after six idle J (decoded 1s), so
the first SETUP's data packet was framed from its 0x80 byte (chip-top's USB device found it; 65 of
75 packets after idle gaps of 0 to 14 bits before, 75 of 75 after: the destuffer now drops only in a
frame); and the frame's end overtook its last bit at 4 clocks per bit and less (the loopback sweep
below found it; 30 of 60 before, 60 of 60 after: the end conditions now wait for the sampler's
two-clock latency). The block's references also found that a cleared start-pattern history looked
like received zeros.

### Using them: low-speed USB and 10BASE-T end to end

**Low-speed USB device** (`src/usb_dev.ml`, `bin/usb_chip.exe`, `results/assists/usb-ls.txt`). The
HID boot keyboard of `../usb-ls`, run against that prototype's independent host model, reference
device, bench and scenarios, unchanged (`blocks/usbls`, symlinks), with the specification and the
RTL in lockstep on the board. The bit layer is the hardware: edge sampler (NRZ on D+, 160
sub-samples per bit, SE0 as the line's inactive state), NRZI decoder, destuffer, framer (sync
0x80, end at SE0), CRC-16 after the PID; serialiser (40 clocks per bit, NRZI, stuffing, EOP as
the tail) on uio 6 and 7. The firmware sees bytes: T0 checks tokens by table lookup in the data
bank, forwards SETUP and OUT data, answers NAK, STALL, ACK or the staged data packet; T1 applies the
controller's messages from HOSTIN to the bank (the chip's store and bank cannot be written while it
runs, so `../usb-ls`'s programme patches became messages, with a flush byte that drops replies
staged before a SETUP, an OUT to endpoint 0 or a reset); T2 detects bus resets; T3 is free.

| | `../usb-ls` firmware device | chip-top with the assists |
|---|---|---|
| directed enumeration and reports, host clock -1.5 %, 0, +1.5 % | 3 of 3 | **3 of 3**, 0 NAKs while preparing, the same replies byte for byte |
| constrained random sessions (8 seeds, 120 transactions, seeds 1 and 2 at -1.5 % and +1.5 %) | 8 of 8 | **8 of 8**, 2,690 host packets, 1,320 replies, 202 required silences, 0 errors |
| specification against RTL, every pad every clock | (interpreter against RTL) | 0 mismatching clocks in 12.0 million (the 11 sessions) |
| turnaround | 2.51 to 6.07 bits (replies front-padded) | 2.93 to 3.68 bits |
| beyond the specification (directed) | -4 % fails, -3 % to +3 % pass | the same; +4 % fails too |
| controls: J and K swapped, reply 4 bits late, reply early, CRC not checked | 4 of 4 caught | **4 of 4 caught** (the early reply is 1.5 bits early here: the replies start at about 3 bits, so 1 bit early is 2.0 bits, the bound itself) |
| programme words | T0 63 (bit layer), T1 180, T2 186: 429 | T0 244, T1 47, T2 17: **308**, none for the bit layer |
| the bit layer's thread time | all of T0: a software DPLL that polls the line in every slot (10 slots per bit) | none; over the directed session T0 moved on in 6.7 % of its slots, T1 1.5 %, T2 0.4 %, the rest waiting in place |
| per received byte | about 80 slots of T0 plus 3 to 5 slots per bit of T1 or T2 | 4 slots of T0 (RECV, OUT, the loop) |
| per transmitted byte | 4 slots per symbol (WAITD, SHO pair, LDD, JNZ) on symbols the controller had stuffed and NRZI-coded | 4 slots (LDB, SEND, the loop); sync, stuffing, NRZI and EOP in hardware |

**10BASE-T node** (`bin/eth_chip.exe`, `results/assists/eth10-node.txt`). `../eth10-node`'s ARP and
ping demo: requests built by `host_stack.py` (scapy) go down the line (`line.ml`) into ui_in[2]
and its squelch into ui_in[3]; the edge sampler (Manchester), the framer (after the SFD, to the
burst's end) and the CRC unit (CRC-32 residue) receive them, and T0 (16 words) moves each byte to
the host as it arrives and reports a good or bad frame. The host answers with `../eth10-node`'s
engine model (that prototype's match-and-rewrite engine, which the architecture note would put in a
PE segment, is not on this chip), and T2 (53 words) copies the reply from HOSTIN into the bank,
defers while the line is busy, sends preamble, SFD and frame to the serialiser (Manchester, 3 clocks
per half-bit, TP_IDL of 6 half-bits as the tail), keeps the 9.6 µs gap and sends link pulses while
idle. Judged by the clause-14 checker and by `host_stack.py check`:

| run | result |
|---|---|
| seed 1: 19 directed and 20 random requests | 29 of 29 replies correct, 10 correctly unanswered (the bad FCS reported bad by the chip's CRC check); 0 clause-14 violations, TP_IDL 300 to 350 ns; host stack **PASS** |
| seed 2: directed and 100 random | 109 of 109, 10 unanswered; 0 violations; host stack **PASS** |
| specification against RTL | 0 mismatching clocks in 6.3 million |
| controls: TP_IDL of 4 half-bits, a 6-byte preamble, inverted Manchester, the receive CRC unchecked | 4 of 4 fail: the first two at the clause-14 checker, the last two at the host stack (and the model comparison) |
| transmit | one thread, 53 words, 4 slots per byte (12 available) plus 4 to copy the frame in; `../eth10-node`'s firmware used all four threads (two of every three slots each) and 33 words each, 132 words, with a hardware feeder permuting the bits |

**Headroom** (`usb_chip.exe rates`, `results/assists/bit-path-rates.txt`). The chip talks USB to
itself: T2 sends a 64-byte data packet (a third 0xFF, so plenty of stuffing) through the serialiser
on uio 6 and 7, the receive side reads the same pads, T0 stores what arrives and the CRC verdict
in the bank. 4 of 4 packets whole with a good CRC at 40, 20, 10, 5, 4, 3 and **2 clocks per bit
(30 Mbit/s)**; at 1 clock per bit none, because a thread moves a byte in 4 slots (16 clocks): the
limit is now the byte loop, not the bit layer. The firmware bit layer needed 10 slots per bit and
works at low speed only (1.5 Mbit/s, -4 % to +2 %); full-speed USB's 5 clocks per bit now fits as
far as moving bits and bytes goes. Not measured: full-speed turnaround (the host model is
low-speed only; T0's token check takes about 20 slots, more than full speed's 7.5-bit window at 5
clocks per bit, so a full-speed device would need the IN reply decided before the token ends).

### The harden with the assists (4 PEs, 16.67 ns)

`../../tt/scripts/harden.sh` (the pinned flow of section 7: LibreLane 3.1.0.dev3, tt-support-tools
d66cf17, 6x4, `CLOCK_PERIOD` 16.67, `chip.sdc`, the 1024 x 8 at the right end), then
`tt/scripts/precheck.sh`; record in `results/harden-pe4-assists/` (setup / hold worst slack in ns):

| | slow 1.08 V 125 C | typical | fast | slowest corner's period | cells | hold buffers | flip-flops | placed area | wire | routing DRC, LVS, antenna, precheck |
|---|---|---|---|---|---|---|---|---|---|---|
| section 7, `results/harden-pe4/` | +0.255 / +0.253 | +3.095 / +0.114 | +3.619 / +0.031 | 16.42 ns, 60.9 MHz | 25,931 | 78 | 2,519 | 335,998 µm² | 1.44 M µm | 0, match, 0, 9 of 9 |
| **with the assists**, `results/harden-pe4-assists/` | **-0.224** / +0.256 (2 endpoints) | +2.609 / +0.124 | +3.209 / +0.047 | **16.89 ns, 59.2 MHz** | 28,227 | 85 | 2,735 | 366,498 µm² | 1.71 M µm | **0, match, 0, 9 of 9** |
| **with the assists, density 70** (submitted), `results/harden-pe4-assists-dens70/` | **+0.140** / +0.251 | +2.976 / +0.118 | +3.511 / +0.030 | **16.53 ns, 60.5 MHz** | 28,208 | not counted | 2,735 | 366,536 µm² | 1.58 M µm | **0, match, 0, 9 of 9** |

Area: 300,567 µm² synthesised, 366,498 placed (growth 1.22, as before); 45 % of the core. By RTL
origin (`synth/area_by_origin.py`), the serialiser, the framer, the stuff trackers and the line
coders are about 9,400 µm² of the placed logic; the rest of the growth is glue: the 14
configuration registers, the register read multiplexer, the pad and flag selects, the port routing.
Routing: global routing put Metal3, the one horizontal layer, at 70.9 % with an overflow of 633; detailed routing went from 23,008
violations to 0, then after the post-route repairs from 706 to 0. Magic DRC reports errors inside
the macros only, as before.

**What it costs: 60 MHz at the slow corner.** Typical and fast keep 2.6 and 3.2 ns; the slow corner
misses by 0.22 ns on 2 endpoints (`critical-paths.txt`). Both failing paths, and every path within
0.3 ns, are the PE array's: from segment 0's control register (its source select,
`upe_rtl.ml:308`) through the PE's operand and result multiplexers (`upe_rtl.ml:142`, `341`), the
family that limits 8 PEs in section 7. None starts or ends in the assists. With 9 % more cells and
18 % more wire in the same floorplan the array's wires got longer: section 7 measured this path
at about 31 cells and its worst cells as drivers of long Metal3 wires. Options, cheapest first:
accept 59.2 MHz at the slow corner (the RP2040 host can make 57.6 or 58.0 MHz as easily as 60, but 10BASE-T transmit needs exactly 60 MHz: 3 clocks per half-bit against a ±100 ppm tolerance, `../eth10-node/README.md`, so this option gives up Ethernet transmit and was rejected on 2026-10-30);
a floorplan that keeps the array together, away from the assists' glue; a register stage at each
segment's input (a change of the array's specification, one more clock of latency per segment);
fewer configuration bits for the assists (the 14 registers are most of their glue). The 8-PE chip
was not hardened again (it missed 60 MHz before).

**Closing 60 MHz (2026-10-30): placement density 70.** The cheapest lever turned out to be none of
those: `PL_TARGET_DENSITY_PCT` 70 instead of the template's 60 (one line in `tt/src/config.json`,
nothing else changed) packs the placement, cuts the wire by 8 % (1.71 to 1.58 M µm) and turns the
slow corner's -0.224 ns into +0.140 ns with no violations at any corner (row "density 70" above,
`results/harden-pe4-assists-dens70/`). Fast-corner hold drops from +0.047 to +0.030 ns. Routing DRC 0,
LVS match, antenna 0 and Tiny Tapeout's precheck 9 of 9 as before; on its GDS the gate lockstep
compares 200,000 output words with 0 mismatches (20 trials of 5,000 clocks, wide stimulus), and the
edge-phase test and structural rule give exactly the plant counts of the earlier hardens (26 of 42
plants caught by behaviour, the 16 second-stage samplers by the rule only). The other
lever tried at the same time, `SYNTH_STRATEGY` "DELAY 1" at density 60, made it worse: -1.100 ns
with 56 violations at the slow corner, 1.92 M µm of wire (+13 %) and utilisation 54 % against 51 %:
synthesising for delay grows the logic, and on this die the longer wires cost more at the slow
corner than the faster gates gain (`/var/tmp/tt-closure-2026-10-30/stage-delay/`, metrics not kept
in the repository).

## Open issues


- **Timing at 8 PEs and more.** 60 MHz was met at every corner with 4 PEs (+0.26 ns at the slow
  corner); with the assists of section 8 the 4-PE chip missed it at the slow corner by 0.22 ns
  (59.2 MHz) on the same array paths, and meets it at placement density 70 (+0.14 ns). 8 PEs miss it at the slow corner only (-1.33 ns, about 55.5 MHz), on long Metal3 wires
  around a congested horizontal layer (section 7); typical and fast have about 3 ns to spare.
  Levers not tried: a floorplan with the PE rows nearer to each other, a register stage at each
  segment's input (a change of the array's specification), a lower placement density only around
  the array.
- **Routing.** Metal3 is the limit (81 % at 8 PEs, 88 % at 12 at global routing). The glue's area
  (about 90,000 µm², mostly the register file and the host FIFOs that the host-visible
  specification fixes) was not cut.
- **Post-layout round trip**: done on section 4's hardens and, with a two-edge gate lockstep, on
  section 7's 60 MHz 4- and 8-PE GDS (0 mismatches in 400,000 words each). The two gaps it reported
  are closed in section 6 (the input samplers' edges by the edge-phase test and, for the second
  synchroniser stage, whose edge no simulation can see, a structural rule; gate-level coverage with
  the lockstep's generators). Section 6's gate-level coverage was measured on section 4's hardens;
  it has not been rerun on section 7's.
- **Gate-level runs are short.** At about 350 clocks a second the gate lockstep's 200,000 clocks are a
  twenty-fourth of the RTL lockstep's 4,800,000; the flip-flops still unchanged at the gates are
  reachable ones the RTL lockstep reaches (section 6). Icarus runs the hardened netlist about seven
  times faster, which would be the way to longer gate-level runs.
- **Not in v0**: fine delay, the gain-cell banks,
  the bank's fixed ports into the array, a second bit-path chain; the quarter-clock phases on
  silicon (the hardened stage uses both clock edges).
- **Contracts** the specification assumes (section 2) are not enforced by the hardware: assist
  configuration changes only while held, legal widths and periods, a CRC mask of the form 2^w - 1.
- The demos run q = 0 firmware only, one DAC channel, no S/PDIF.
- **Bit-path assists (section 8), from one cross-model review (`results/assists/codex-review.txt`,
  codex, read-only) and checked at the source:** (a) the framer ends a USB frame at any SE0; it
  does not check the EOP's length or the J after it, so a short SE0 ends a frame that may still have
  a good CRC (the tests use conforming EOPs only); (b) in the USB firmware, T1 reads the flush byte
  once per staged write and then writes all its bytes, so a stale write being applied in the ~12
  slots in which T0 sets flush still lands; (c) a report staged for endpoint 1 stays answerable
  between a SETUP and the controller's restaging (correctly: the reference device answers it too),
  but if the host ACKs it in that window the controller, which has already dropped it, does not pop
  it and sends it again later. None of the three occurred in the 11 USB sessions; (b) and (c) need a
  SETUP, an OUT or a reset to land inside a window of a few slots, which the scenarios do not aim
  at. The review's fourth point, that the specification starts the CRC on every frame start whatever
  `r_bp_ctrl` bit 3 says, does not hold: both `chip_spec.ml` and `chip_rtl.ml` gate it on that bit.
- The USB device answers full speed's bit rate in loopback but not its turnaround (section 8); the
  10BASE-T node's replies are computed by the host, and its firmware takes frames of up to 255
  bytes (the bank holds 1,024).
