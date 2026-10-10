# Configuration reference

Besides programmes, an image configures the chip: which pad shows which signal, which internal
signals the threads see as flags, the pin-stage helpers (streamer, sampler, edge-tracking sampler,
CRC unit, matcher, pin NCO), the PE array, the data bank and the run state. All of it is host
registers and chains written over the host link ([host-link.md](host-link.md)); this page gives
the register map and the assembler directive for each block.

The definitive encodings are `prototypes/chip-top/src/regs.ml` (registers, pad and flag codes)
and `prototypes/unified-pe/verify/spec.ml` (the PE operation word). The tables marked below are
compared with those files by `tools/asm/test/docs_drift.ml`; the behaviour behind them is
specified in `prototypes/chip-top/src/chip_spec.ml` and the blocks' own models.

## The register map (host-link target REG)

Every register is one byte. "bits" is how many low bits the chip stores (a read returns them);
"r" is a status register, "w" a register whose write is an action, "none" an address with
nothing behind it. Multi-byte fields are little endian.

<!-- register table: parsed by tools/asm/test/docs_drift.ml -->
| address | name | bits | reset | meaning |
|---|---|---|---|---|
| 0x00 | control | 2 | 2 | bit 0 run: the sequencer runs (clear: held in reset, and the programme store and bank are writable); bit 1 hold the assists (streamer, sampler, edge sampler, CRC, matcher, NCO) in clear |
| 0x01 | status | r | - | bit 0 a store or bank access was refused while running, 1 HOSTIN overflowed, 2 HOSTOUT overflowed (all sticky; any write clears them), 3 HOSTIN full, 4 HOSTOUT not empty, 5 sampler FIFO not empty, 6 streamer FIFO full, 7 a host write to a segment register was lost: it was waiting for a thread's SEND to the array and the host's next byte replaced it (sticky) |
| 0x02 | hostin count | r | - | bytes waiting in HOSTIN |
| 0x03 | hostout count | r | - | entries waiting in HOSTOUT |
| 0x04..0x07 | boot pc | 8 | 0 | thread 0..3's pc after reset |
| 0x08 | boot page | 8 | 0 | 2 bits per thread, thread 0 in bits 1:0 |
| 0x09 | restart | w | - | restart a thread while running: bits 1:0 the thread, 3:2 its page; the pc is register 0x0A |
| 0x0A | restart pc | 8 | 0 | the pc for a restart |
| 0x0B | port reset | w | - | bit *j*: empty port *j*'s RECV holding register and make its next SEND byte the low byte |
| 0x0C | crc start | w | - | load the CRC register with its init value |
| 0x10..0x17 | pad select 0..7 | 7 | 0,1,2,3,4,5,6,7 | output pad uo_out[*p*]: bits 4:0 source (table below), bit 5 invert, bit 6 the level shown while the source does not drive |
| 0x18..0x1D | pads 8..13 | none | - | the host-link pads have no select |
| 0x1E..0x1F | pad select 14, 15 | 7 | 6,7 | uio[6], uio[7], the open-drain pads: as above; the source's enable is the pad's output enable |
| 0x20..0x27 | input select 0..7 | 4 | 0,1,2,3,4,5,6,7 | the input pad that logical pin *k* reads (0-7 ui_in, 8-15 uio) |
| 0x28..0x2B | sampler pins | 4 | 0 | the input pads of the sampler's four pins |
| 0x2C | sampler source | 1 | 0 | bit 0: the sampler reads the recovered-bit stream {0, 0, valid, bit} instead of its pads |
| 0x30..0x3F | flag select 0..15 | 5 | 31 | the source (table below) of flag input *f*; thread *t*'s flags are 4*t* .. 4*t* + 3 |
| 0x40 | streamer period low | 8 | 1 | streamer period, bits 7:0 |
| 0x41 | streamer period high, width | 7 | 16 | bits 3:0 period bits 11:8; bits 6:4 width (1, 2 or 4 pins) |
| 0x42 | streamer pins | 8 | 0 | bits 3:0 open-drain mask, 7:4 idle level |
| 0x43 | streamer idle enable | 4 | 0 | output enables while idle |
| 0x44 | sampler period low | 8 | 1 | sampler period, bits 7:0 |
| 0x45 | sampler period high, width | 8 | 16 | bits 3:0 period bits 11:8, 6:4 width, 7 clocked mode |
| 0x46 | sampler offset low | 8 | 0 | offset after the trigger, bits 7:0 |
| 0x47 | sampler offset high, trigger | 7 | 0 | bits 3:0 offset bits 11:8, 5:4 trigger pin, 6 trigger level |
| 0x48 | sampler frame | 8 | 0 | frame length |
| 0x4C | edge sampler mode | 4 | 0 | bits 1:0 mode (0 Manchester, 1 biphase mark, 2 NRZ), 2 invert, 3 use the activity pad |
| 0x4D | edge sampler pads | 8 | 0 | bits 3:0 data pad, 7:4 activity (squelch) pad |
| 0x4E..0x4F | edge sampler holdoff | 8,2 | 0 | 10 bits |
| 0x50..0x51 | edge sampler timeout | 8,2 | 0 | 10 bits |
| 0x52 | edge sampler offset | 8 | 0 | |
| 0x53 | edge sampler period | 8 | 0 | |
| 0x54 | crc control | 2 | 0 | bit 0 reflected, bit 1 start on a matcher hit |
| 0x58..0x5B | crc polynomial | 8 | 0 | |
| 0x5C..0x5F | crc init | 8 | 0 | |
| 0x60..0x63 | crc mask | 8 | 0 | 2^*w* - 1 for a *w*-bit CRC |
| 0x64..0x67 | crc xorout | 8 | 0 | |
| 0x68..0x6B | crc residue | 8 | 0 | the register value that means "good"; flag source crc_ok |
| 0x6C..0x6F | nco increment | 8 | 0 | the pin NCO's phase increment per clock, 32 bits |
| 0x70..0x73 | crc register | r | - | the CRC register |
| 0x74 | matcher | r | - | bits 4:0 the matcher's sum, bit 7 hit |
| 0x75 | sampler overflows | r | - | |
<!-- end register table -->

The assembler writes registers through the directives below; `.reg ADDRESS, BYTE...` writes any
register directly (the disassembler prints it for bytes no directive produces). The control
register is set only by `.run` / `.stop` / `.ctrl`, because it is written twice: first to stop
the chip for loading, last to start it ([host-link.md](host-link.md)).

## Pins

The chip has 8 input pads (ui_in, pads 0-7), 8 output pads (uo_out, pads 0-7) and 8
bidirectional ones (uio, pads 8-15), of which 8-13 carry the host link and 14-15 are general
open-drain pins. The sequencer's eight logical pins reach them through two selects:

- **Output**: `.pad P, SOURCE [, invert] [, undriven=L]` sets pad *P*'s source. A push-pull pad
  (uo_out) always drives: the source's level when the source drives, else the undriven level
  *L*. On uio[6] and uio[7] the source's output enable is the pad's enable, so an open-drain
  source really releases the line.
- **Input**: `.pinin K, PAD` sets the pad that logical pin *K* reads.

After reset, pad *k* (0-7) shows sequencer pin *k* with undriven level 0, uio[6] and uio[7] show
pins 6 and 7, and pin *k* reads ui_in[*k*]. So a UART on pin 0 is `.pad 0, seq0, undriven=1`
(the line idles high before the first SETP), and an I2C bus on pins 4 and 5 is

```
.pad 14, seq4, undriven=0      ; SDA on uio[6]
.pad 15, seq5, undriven=0      ; SCL on uio[7]
.pinin 4, 14                   ; read back through the same pads
.pinin 5, 15
```

Output sources:

<!-- pad source table: parsed by tools/asm/test/docs_drift.ml -->
| code | name | the pad shows |
|---|---|---|
| 0..7 | seq0..seq7 | sequencer logical pin *code*: its four quarter-clock levels and its output enable |
| 8..11 | stream0..stream3 | streamer pin *code* - 8, with its enable |
| 12 | nco_quarter | the pin NCO on the quarter-clock grid |
| 13 | nco_half | the pin NCO on the half-clock grid |
| 14 | nco_clock | the pin NCO on the clock grid |
| 16..19 | tapflag0..tapflag3 | segment *code* - 16's tap flag (the one-bit DAC's output) |
| 20..23 | tapbit0..tapbit3 | bit 0 of segment *code* - 20's tap word |
| 24 | esbit | the edge-tracking sampler's recovered bit |
| 31 | zero | constant 0 (so do 15 and 25-30) |
<!-- end pad source table -->

## Flags

Each thread has four flag inputs (WAITC conditions flag0..flag3, [isa.md](isa.md)); `.flag T, K,
SOURCE` selects what thread *T*'s flag *K* is:

<!-- flag source table: parsed by tools/asm/test/docs_drift.ml -->
| code | name | the flag is |
|---|---|---|
| 0..3 | tapflag0..tapflag3 | segment *code*'s tap flag |
| 4..7 | tapvalid0..tapvalid3 | segment *code* - 4's tap word is valid |
| 8 | es_valid | the edge sampler has a recovered bit this clock |
| 9 | es_bit | the edge sampler's last recovered bit |
| 10 | es_burst | the edge sampler is inside a burst |
| 11 | es_burst_end | the edge sampler's burst ended |
| 12 | crc_ok | the CRC register equals the residue |
| 13 | match | the matcher hit |
| 14 | stream_full | the streamer's FIFO is full |
| 15 | sample_valid | the sampler's FIFO is not empty |
| 16 | nco | the pin NCO's quarter-0 level |
| 31 | zero | constant 0 (so do 17-30; the reset value) |
<!-- end flag source table -->

## The assists

These run only while control bit 1 is clear (`.run assists`); their configuration must change
only while they are held, which the image's load order guarantees.

- `.streamer period=P, width=W [, od=MASK] [, idle=MASK] [, idle_oe=MASK]` — the streamer plays
  words from the host (`.stream WORD, VECTORS` in the image, or the STREAM target at run time)
  onto W pins (1, 2 or 4), one vector every P clocks, without the sequencer.
- `.sampler period=P, width=W [, clocked] [, offset=O] [, trigger=PIN] [, trigger_level=L]
  [, frame=N]` and `.sampler_pins A, B, C, D [, recovered]` — the sampler packs pin samples into
  words for the host (SAMPLE target).
- `.edge_sampler mode=manchester|biphase|nrz [, invert], pad=P [, active=PAD], holdoff=H,
  timeout=T, offset=O, period=N` — recovers bits from a self-clocked or NRZ line.
- `.crc width=W, poly=P, init=I, xorout=X, residue=R [, reflected] [, start_on_match]` — the
  CRC unit on the recovered bits; `crc_ok` is a flag source.
- `.matcher pattern=T, mask=M, threshold=N` — the 16-cell sync-word matcher on the recovered
  bits; `match` is a flag source.
- `.nco inc=N` — the pin NCO: a 32-bit phase accumulator advanced by N per clock and evaluated at
  the four quarter points of each clock (60 MHz × N / 2^32 Hz).

What each assist does is specified by its own model, linked from
`prototypes/chip-top/README.md` (section 1, "What goes in now"); prototypes/chip-top's lockstep
checks the chip's RTL against them.

## The PE array

Sixteen processing elements (PEs) in a line, cut into four segments; the hardened chip starts
with 4 PEs, one per segment (prototypes/chip-top). `.layout A, B, C, D` tells the assembler how
many PEs each segment has (default 1, 1, 1, 1); it is a property of the chip, not written to it.

`.pe SEG, IDX, field=value | flag ...` configures PE *IDX* of segment *SEG*. Each PE has an
8-byte configuration: a 16-bit constant K (bytes 0-1) and a 48-bit operation word (bytes 2-7).
The fields of the operation word:

<!-- pe table: parsed by tools/asm/test/docs_drift.ml -->
| field | bits | values | meaning |
|---|---|---|---|
| x | [1:0] | s=0, a=1, shl=2, shr=3 | operand X: S, A, S << 1 with the serial bit, S >> 1 with the serial bit |
| sin | [3:2] | g=0, lane=1, s15=2, a0=3 | the serial bit: g, the lane, the left PE's S[15], A[0] |
| y | [5:4] | k=0, a=1, s=2, one=3 | operand Y: K, A, S, the constant 1 |
| ymod | [7:6] | none=0, gate=1, negg=2, neg=3 | Y as is, gated by g, negated when g, negated |
| g | [10:8] | one=0, abit=1, lane=2, s15lane=3, crc=4, f=5, window=6, gleft=7 | the condition bit g |
| bit | [14:11] | | the bit of A for g = abit |
| pairlo | [15] | | CRC feedback from the right PE's S[15] |
| alu | [18:16] | sat=0, add=1, max=2, min=3, xor=4, and=5, or=6, y=7 | saturating add, wrapping add, max, min, XOR, AND, OR, Y |
| cin_lane | [19] | | the adder's carry-in is the lane |
| s | [21:20] | hold=0, result=1, x=2, gresult=3 | S <- S, the result, X, or the result when g |
| p | [23:22] | a=0, result=1, loser=2, merge=3 | P <- A, the result, the loser of max/min, or the merge |
| f | [25:24] | hold=0, g=1, zero=2, hold3=3 | F <- F, g, result = 0, F |
| lane | [27:26] | lane=0, s15=1, carry=2, g=3 | the lane register <- the lane in, S'[15], the carry out, g |
| lane_bc | [28] | | the lane in is the segment's broadcast bit |
| del | [29] | | valid out = A valid and not g (deletion) |
| stream | [30] | | step only when A is valid |
| tap_p | [31] | | the PE's tap is P (else S) |
| follow | [32] | | step exactly when the left PE steps |
| ashr | [36:33] | | with x = a: X = A >>> ashr (arithmetic) |
| k | K | | the 16-bit constant K |
<!-- end pe table -->

The precise semantics of each mode are in the header of `prototypes/unified-pe/verify/spec.ml`.
`.pebytes SEG, IDX, B0, ..., B7` gives a PE's eight bytes directly. `.peinit SEG, IDX, VALUE`
sets a PE's state S through the init chain.

`.seg SEG [, src=...] [, flags] [, repeat=R] [, feed=W]` writes segment *SEG*'s registers:
the control register always, the repeat register with `repeat=`, the feed register with `feed=`.
The control register:

<!-- segment table: parsed by tools/asm/test/docs_drift.ml -->
| bits | name | meaning |
|---|---|---|
| [2:0] | src | the first PE's A input: join=0 (the previous segment's end; zero for segment 0), loop=1 (own end), feed=2 (the feed register, written by SEND on port SEG), fixed=3 (a fixed neighbour; segment 0's is the recovered-bit stream), zero=4 |
| [3] | bcast | the segment's broadcast lane bit |
| [4] | run | the segment steps |
| [5] | bcast_prev | take the broadcast from the previous segment (proposed in unified-pe) |
| [6] | lane_loop | the first PE's lane comes from the end of the segment's joined run |
<!-- end segment table -->

The feed register is two bytes: the low byte, then the high byte, which presents the word as
valid for one clock, or, with a nonzero repeat period R, commits it so that the feed repeats it
every R clocks. A thread's SENDs to port SEG write the feed, alternately low and high byte; its
RECVs read the segment's tap word, low byte then high byte.

**Load order matters for the array.** A repeat period starts the feed ticking at once. The
image therefore writes every segment's feed and control registers first and the repeat
registers last, so that a run of joined segments starts in one piece. Written segment by segment
instead, segment 0 of the one-bit DAC stepped while segments 1-3 were still stopped, and its
output no longer matched its bit-exact model (found by
`tools/asm/examples/dac.s`; with the order above, 0 wrong bits in 26,656).

## The data bank and the host FIFOs

- `.bankdata ADDRESS, BYTE or "STRING", ...` preloads the 1,024-byte data bank, which the
  threads read and write with LDB and STB.
- `.hostin BYTE, ...` puts up to 16 bytes (the FIFO's depth) into HOSTIN before the run, for the
  threads' IN; the host streams more at run time.
- `.stream WORD, VECTORS` pushes a word into the streamer's FIFO (after the run starts, since a
  held streamer drops it).

## Run state

`.run` (the default) starts the sequencer with the assists held (control = 3); `.run assists`
starts both (control = 1); `.stop` leaves the chip stopped (control = 2), for an image that only
loads; `.ctrl V` writes V.
