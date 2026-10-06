# chip-top: the first combined prototype of the whole programmable chip

Every block of `notes/architecture-v0.md` so far was built and verified alone. This directory
puts them behind one Hardcaml top level for Tiny Tapeout 6x4 (IHP sg13cmos5l), with:

- an executable specification of the whole chip, composed from the blocks' own OCaml models;
- a lockstep test of the RTL against it, with planted integration bugs;
- the existing demos, unchanged, driven through the host link;
- a harden with the pinned flow, to measure the whole-chip placement factor (gap G13).

Status: milestones 1-3 done (plan; top level, specification and lockstep; demos through the host
link). Milestone 4 (area and G13) is below.

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
| 8 PEs (2\|2\|2\|2), same floorplan | PE8_RESULT |

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
  factor of 1.79 over its 454,462 µm² synthesised, it does not route.
PE8_FACTOR

**What fits.** PE8_FITS

**Post-layout round trip** (`../postlayout-roundtrip`, its structural check on the 4-PE GDS,
`results/harden-pe4/postlayout-roundtrip-check.txt`): the extractor finds 27,773 cells, 2,519
flip-flops and 57,595 primitive gates, and reports 25 undriven nets, all inputs read next to the
SRAM macros: the macros' outputs, which it cannot see because it knows only the standard cells'
geometry. It also reports 25 flip-flops whose clock pin is on the top-level clock port with no
clock buffer between, which its clock-tree rule does not accept. The lockstep and `compare_def`
need macro support in the extractor first and were not run; netgen's LVS above is the
connectivity check of record.
