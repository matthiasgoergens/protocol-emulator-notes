# chip-top: the first combined prototype of the whole programmable chip

Every block of `notes/architecture-v0.md` so far was built and verified alone. This directory
puts them behind one Hardcaml top level for Tiny Tapeout 6x4 (IHP sg13cmos5l), with:

- an executable specification of the whole chip, composed from the blocks' own OCaml models;
- a lockstep test of the RTL against it, with planted integration bugs;
- the existing demos, unchanged, driven through the host link;
- a harden with the pinned flow, to measure the whole-chip placement factor (gap G13).

Status: milestone 1 (this plan). Results are added below each milestone as they land.

## 1. Integration plan

### What goes in now, what is stubbed or deferred

| block | source | in v0? | notes |
|---|---|---|---|
| sequencer, ISA v2 | `../sequencer-v2/sequencer2.ml`, `isa2.ml` | **in**, unchanged | reset fetch fix (ec1650d) included. FINE's `fine_out` and `cfg_out[6:0]` are left unconnected (no fine delay; see D5 below) |
| programme store, 1024 × 16 address space | new glue | **in** | behavioural synchronous RAM in simulation. Hardened: the IHP `RM_IHPSG13_1P_512x16` macro if the pinned flow takes it (trial in `sram-macro/`, see below), else a register array, clearly marked, of the size that fits |
| data bank, 1024 × 8 | new glue | **in** | the ISA's LDB/STB port. Simulation: behavioural RAM. Hardened: `RM_IHPSG13_1P_1024x8` if the macro works, else a small register array. **The gain-cell banks are deferred**: they are drawn custom cells with no flow integration yet |
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
  and the address increments. Any change of R returns the command parser to idle, which is also
  the way to resynchronise.

| target | write | read |
|---|---|---|
| 0 REG | configuration and control registers (map in `regs.ml`) | registers and status |
| 1 PROG | programme store, byte address (word a/2; low byte at even a; the word is written with its high byte). Only while the sequencer is stopped; otherwise ignored and a sticky error bit is set | the same bytes, while stopped |
| 2 BANK | data bank, while stopped | the same |
| 3 HOSTIN | push the byte into the 16-byte FIFO that the threads' IN reads (dropped, with a sticky bit, when full) | |
| 4 HOSTOUT | | pops the 8-entry FIFO filled by OUT: two bytes per entry, `{valid, tag}` then the byte |
| 5 PECFG | one byte into segment (address mod 4)'s configuration chain | |
| 6 PEINIT | one byte into segment (address mod 4)'s init chain | |
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
