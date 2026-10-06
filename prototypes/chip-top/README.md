# chip-top: the first combined prototype of the whole programmable chip

Every block of `notes/architecture-v0.md` so far was built and verified alone. This directory
puts them behind one Hardcaml top level for Tiny Tapeout 6x4 (IHP sg13cmos5l), with:

- an executable specification of the whole chip, composed from the blocks' own OCaml models;
- a lockstep test of the RTL against it, with planted integration bugs;
- the existing demos, unchanged, driven through the host link;
- a harden with the pinned flow, to measure the whole-chip placement factor (gap G13).

Status: milestones 1-6 done: plan; top level, specification and lockstep; demos through the host
link; area, hardens and G13; `tt/` points at this chip; the edge-phase test and coverage. Open
issues are listed at the end. The suite: `./suite.sh quick` (CI, about a minute after the build) or
`./suite.sh full`.

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
| stuff tracker, line coder | `../unified-pe/rtl/assists.v` | **deferred** | area probes only: no model, no verified RTL. The bit path therefore has no destuffer or line decoder yet |
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
| **4 PEs, the 1024 x 8 moved to the right end of the core**, density 60 % | **passes**: global routing without overflow; routing DRC 0, LVS 0 (netgen: circuits match uniquely), antenna 0; **Tiny Tapeout's precheck 9 of 9**, KLayout SG13CMOS5L DRC clean; Magic DRC 141,979, every one inside a macro (`results/harden-pe4/`) |
| 16 PEs (2\|2\|4\|8), same floorplan | 610,596 µm² of standard cells before routing (76 % of the free core); global routing: Metal3 demand 105 % of capacity, overflow 22,240; stopped (`results/harden-pe16-attempt/`) |
| **8 PEs (2\|2\|2\|2)**, same floorplan | **passes**: global routing overflow 398 (Metal3 at 80 %), detailed routing to 0 in 15 iterations; LVS 0, antenna 0; **precheck 9 of 9**; Magic DRC all inside the macros (`results/harden-pe8/`) |

**Why routing, not area, is the limit.** sg13cmos5l's block routes on Metal2 to Metal4 only
(TopMetal1 belongs to Tiny Tapeout's top level), so **Metal3 is the only horizontal routing
layer**, and Metal4 also carries the power stripes. In every run Metal3 was the overflowing layer
while Metal4 stayed at 8-30 % use. Lower placement density spreads the cells and lengthens the
wires (2.44 M µm against 2.22 M at 60 %), which made it worse, not better. What cured the 4-PE
run was floorplanning: the 1024 x 8 macro (336 µm tall) in the middle of a 710 µm die split the
horizontal routing channel.

**The 4-PE chip in numbers** (`results/harden-pe4/`): 27,773 standard cells, 374,588 µm² after
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

**Timing of the 8-PE chip** (`results/harden-pe8/corners.txt`): setup +1.67 ns typical at 20 ns
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

## Open issues

- **Timing.** 60 MHz is not met at the slow corner (4 PEs: -4.17 ns at 20 ns; 8 PEs: -9.21 ns).
  Name the glue's and the array's signals so the worst paths can be read, then pipeline or cut
  them (suspects: the array's per-run ripple chains, the register-file read mux).
- **Routing.** The glue's area and wiring (215,700 µm² synthesised; full 16-pad selects) and the
  hold buffers limit the PE count more than the PEs do; 12 PEs untried.
- **The PE array has no reset** (`../unified-pe/verify/upe_rtl.ml`): its state and segment
  control registers power up unknown. Every pin and flag defaults away from it, so nothing
  observable depends on it until the host configures the array, but a configuration that reads a
  held field (F with fwb = hold, P before the first step) sees the power-up value. In simulation
  everything starts at 0. A clear on the segment controls and the PE state, in the block's own
  commit with an X-propagation test, would close it.
- **Post-layout round trip**: done on both hardens (section 4); the two gaps it reported are closed
  in section 6 (the input samplers' edges by the edge-phase test and, for the second synchroniser
  stage, whose edge no simulation can see, a structural rule; the gate-level coverage with the
  lockstep's generators). The 4-PE GDS of record predates 9a50420, so `tt/` today would build a
  slightly different 4-PE chip.
- **Gate-level runs are short.** At about 350 clocks a second the gate lockstep's 200,000 clocks are a
  twenty-fourth of the RTL lockstep's 4,800,000; the flip-flops still unchanged at the gates are
  reachable ones the RTL lockstep reaches (section 6). Icarus runs the hardened netlist about seven
  times faster, which would be the way to longer gate-level runs.
- **Not in v0**: the stuff tracker and line coder (probes only), fine delay, the gain-cell banks,
  the bank's fixed ports into the array, a second bit-path chain; the quarter-clock phases on
  silicon (the hardened stage uses both clock edges).
- **Contracts** the specification assumes (section 2) are not enforced by the hardware: assist
  configuration changes only while held, legal widths and periods, a CRC mask of the form 2^w - 1.
- The demos run q = 0 firmware only, one DAC channel, no S/PDIF.
