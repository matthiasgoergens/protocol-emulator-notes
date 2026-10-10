# The host link, and the image format

The chip is loaded and fed by a host: on Tiny Tapeout's demo board, its RP2040 or RP2350. The
host link is the only way in: programmes, configuration, data streams and the threads' IN and OUT
all go over it. It is specified in `prototypes/chip-top/README.md` ("Host link protocol"), built
in `prototypes/chip-top/src/chip_rtl.ml`, and driven from the host's side by
`prototypes/chip-top/src/host.ml`; `tools/asm/test/docs_drift.ml` compares the tables below with
`regs.ml` and `host.ml`.

## Wires and timing

Four data lines D (uio[3:0]), a strobe S from the host (uio[4]) and a read request R (uio[5]).
The chip sees all three through its input synchronisers. The host clocks the chip, so all timing
is in chip clocks.

- **Every change of S moves one nibble**, in either direction. Bytes go high nibble first.
- **Write** (R low): the host sets D, waits at least 2 clocks, toggles S, and holds D for at
  least 2 more clocks. The chip takes D in the clock in which it sees S change.
- **Read** (R high): the chip drives D with the current nibble. The host samples D, then toggles
  S for the next nibble, at least 8 clocks apart. Before raising R the host releases D; after
  lowering R it waits 8 clocks before driving D again.

So a written byte takes 8 clocks with these margins, 7.5 MB/s at 60 MHz.

## Commands

A command is bytes in the write direction: `{op, target}`, address high, address low, and a
count byte *n* meaning *n* + 1 bytes (1 to 256). Op 1 writes the *n* + 1 data bytes that follow;
op 2 reads: the host raises R and reads 2 (*n* + 1) nibbles. Each byte goes to or comes from
(target, address), and the address increments. Lowering R returns the command parser to idle,
which is also how a host resynchronises.

<!-- op table: parsed by tools/asm/test/docs_drift.ml -->
| op | name | meaning |
|---|---|---|
| 1 | write | the data bytes follow the command |
| 2 | read | the chip answers with the bytes while R is high |
<!-- end op table -->

<!-- target table: parsed by tools/asm/test/docs_drift.ml -->
| target | name | write | read |
|---|---|---|---|
| 0 | REG | configuration and control registers ([configuration.md](configuration.md)) | registers and status |
| 1 | PROG | programme store, byte address: word *a*/2, low byte at even *a*; only while stopped (otherwise ignored, with a sticky status bit) | the same bytes, while stopped |
| 2 | BANK | data bank, while stopped | the same |
| 3 | HOSTIN | a byte for the threads' IN (16-byte FIFO; dropped with a sticky bit when full) | |
| 4 | HOSTOUT | | pops the 8-entry FIFO the threads' OUT fills: two bytes per entry, {valid, tag} then the byte |
| 5 | PECFG | one byte into segment (address bits 9:8)'s configuration chain | |
| 6 | PEINIT | one byte into segment (address bits 9:8)'s init chain | |
| 7 | PESEG | segment (address / 4 mod 4)'s register (address mod 4): feed low, feed high, control, repeat | |
| 8 | STREAM | three bytes per streamer word: low, high, vector count | |
| 9 | SAMPLE | | pops the sampler FIFO: three bytes per entry, {valid, count}, low, high |
| 10 | MATCH | bit 0 of the byte shifts into the matcher's configuration chain | |
<!-- end target table -->

The chains shift: the first byte written to a segment's configuration chain ends in the last
PE's byte 7. To load a segment of *n* PEs, write 8*n* bytes: the last PE's bytes 7 down to 0,
then the PE before it, down to the first PE's byte 0 last. The init chain likewise takes the
last PE's S high byte first and the first PE's S low byte last.

## The image format

An image (`.hlk`, made by `asm`) is exactly the byte stream a host sends to load the chip and
start it: a sequence of write commands, nothing else. A host loads an image by sending its bytes
over the link with the write timing above; it needs no knowledge of what is in it. The commands
come in this order, which the assembler always uses, so that the same source gives the same
bytes:

1. REG control ← 2: the sequencer stopped (and the store and bank writable), the assists held.
2. The registers the source sets, by address (always the boot pcs and pages, 0x04-0x08).
3. PROG: the programme words, two bytes each, low byte first.
4. BANK: data bank bytes.
5. PECFG and 6. PEINIT, per segment, as above.
7. PESEG: every segment's feed and control registers, then every segment's repeat register (see
   [configuration.md](configuration.md), "Load order matters for the array").
8. MATCH: the matcher's 37 configuration bits.
9. HOSTIN: up to 16 bytes for the threads.
10. REG control ← the run state: the sequencer starts, from each thread's boot page and pc.
11. STREAM: streamer words (after 10, because a held streamer drops them).

`asm --disasm IMAGE` prints any image made this way back as source; assembling that source gives
the same bytes (`tools/asm/test/roundtrip.ml`).

## At run time

Once running, the host keeps HOSTIN fed and drains HOSTOUT: it reads register 0x02 (bytes
waiting in HOSTIN) to know how much it may send, and reads HOSTOUT, whose entries come as
{valid, tag} and the byte; an entry with the valid bit (0x80) clear means the FIFO was empty.
`tools/asm`'s runner does exactly this (`src/runner.ml`, `host_program`): it polls HOSTOUT 16
bytes at a time and tops HOSTIN up. A thread's OUT reaches HOSTOUT one clock after it executes;
an OUT into a full HOSTOUT is lost and sets status bit 2, so a programme that outputs faster
than its host drains must pace itself.

The host can also restart one thread while the others run: write the pc to register 0x0A, then
{page, thread} to register 0x09.
