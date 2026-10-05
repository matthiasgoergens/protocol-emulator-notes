# A tile platformer on the generic chip

A side-scrolling tile platformer (original art, level and characters) running on the programmable
chip's generic blocks, not on console hardware: the 4-thread deadline sequencer
(`../deadline-sequencer`, with the sub-slot ISA of `../multiphase`), a systolic row of one generic
processing element, gain-cell memory, and an NCO for colour. The special-purpose console of
`../retro-console` is the comparison: which of its parts map directly onto generic blocks, which
needed extensions to the PE, and what the generality costs.

The game GIF is generated locally as `out/game.gif`; the selected stills and
their strip are generated as `out/still_*.png` and `out/stills.png`. These are
build outputs and are not committed here.

The clip is the chip's pin output, simulated cycle by cycle in Hardcaml (sequencer, line buffer,
feeder, PE row, output port), turned into composite video by the resistor-DAC model and decoded by
the software TV (`../composite-video`, through `../retro-console/console_tv.py`). The host side
(game logic, physics, camera, the per-line records) is OCaml standing in for the RP2350. The game:
Pip runs through a meadow, collects coins, knocks a coin out of a bonus block, jumps a pipe with a
snapweed rising behind it, stomps a burrbug, clears a pit onto a ledge and lands on a
lanternsnail. The score bar at the top does not scroll. Input is a scripted SNES pad
(`game.ml`).

The stills strip is produced with `uv run stills.py 36 82 150 205 276`.

## The chip, from generic blocks (`video.ml`)

Per scanline, during the previous line, the host streams a list of 19-bit entries (a 3-bit tag and
16 bits of data) into one bank of a ping-pong line buffer. On the line event the feeder plays the
other bank into the PE row, and the output port turns what comes out of the row into pins.

- **Deadline sequencer, unchanged** (`vprog.ml`, firmware only). Thread 0 makes the sync pulses
  (normal and broad), the line event and the burst gate; thread 1 makes the PAL V-switch as a
  two-line loop in lockstep with thread 0; threads 2 and 3 are free. A thread issues every 4
  clocks, so a line is 3404 clocks (851 slots) rather than 3405.02: the line rate is 294 ppm fast,
  which a TV's line oscillator follows, and the burst is regenerated every line, so hue is
  unaffected. `timed` assembles each line body from (slot, instruction) events, filling the gaps
  with `LDD n; WAITD`, and the interpreter and the RTL both measure every edge exact
  (`results/timing.txt`). Writing it found one layout trap: the first normal line fell through
  ten NOPs of padding into the loop, 40 clocks late once per field; it now jumps.
- **Line buffer:** 2 banks of 256 x 19 bits, a gain-cell bank on silicon (a Hardcaml memory
  here). A value is written at most one line before it is read and is dead a line later, 128 us,
  so thick cells (at least 3.1 ms in the worst corner) need no refresh at all; thin cells (118.8
  us at tt/27 C) would not survive even at room temperature (`results/budget.txt`).
- **Feeder:** a memory-to-array streamer. It generates the step slots (a step every 10 clocks, 256
  of them, starting a fixed time after the line event; the last carries an end-of-run flag) and
  in every other clock plays the next entry: record words go onto the link, `WAIT n` holds the
  entries back until step n has gone out, `PIXELS v` sets the value the steps start with (the
  per-line backdrop colour), `END` stops. It knows nothing about tiles or sprites; the host's
  list decides what goes where and when. 5,994 um2.
- **PE row:** 18 identical PE-Xs (below): 2 configured as looped tile cells, 16 as sprite cells.
- **Output port:** a 64 x 14 colour table (luma code, chroma phase, two chroma enables), written by
  records of class 1 that no PE takes and so fall off the end of the row; a hold of 10 clocks per
  step; and an NCO (`../multiphase/nco.ml`'s accumulator) whose square wave is shifted by the
  entry's phase and reflected about a constant while the V-switch pin is high (PAL). Sync and
  blanking levels come from the sequencer's pins; the burst gate adds chroma from entry 63.
  5,305 um2. Measured through the software TV, its 143 colours match the special-purpose console's
  to 0.007 of full scale (`results/palette-compare.txt`).

## PE-X: pe16 plus five generic extensions (`pex_model.ml`, `pex.ml`)

`../pe-synth`'s pe16 has a 16-bit state s, an add/sub/max/min saturating ALU (x = s or the
neighbour, y = k or s), a pipeline register and a byte-wide configuration chain. It cannot draw a
sprite: nothing in it can pick a bit out of a bitmap or replace part of the word passing through.
PE-X keeps all of pe16 (its enable becomes a tag on the word) and adds:

| extension | what it is | the video use | other uses |
| --- | --- | --- | --- |
| tagged link | each word carries none / step / record word / last word, plus a class bit (AXI-stream's TLAST) | pixels and loads share one link; 9 of every 10 clocks are free for loads | any streaming kernel with in-band control: packet boundaries, sample strobes |
| record loading | a PE of the right class that is not loaded takes the record words passing by (R0 attr, R1-R2 the shift register, R3 s, R4 attr2) and lets go at the end of a run or after its window | sprites loaded every line; tile cells reloaded mid-line with the next slice | per-line coefficients for FIR taps or the semiring ring (whose 48-byte init chain this replaces), work handed to the first idle PE, pattern loads for a matcher |
| window predicate | p = ((s >> w) & (2^n - 1)) = 0 | the 16 pixels a cell covers (sprite: 0 <= s < 16; looped tile: s mod 32 < 16) | framing (only bytes N to M of a packet), gating a correlator or a filter to a window, comparator outputs |
| shift register | 32 bits, 1/2/4/8 bits per step, MSB or LSB first (per record), shift or rotate | 16 pixels at 2 bits; LSB first is horizontal flip | serialisers and deserialisers (SPI MSB first, UART LSB first, Manchester), a correlator's reference sequence, a PN sequence by rotating |
| conditional write | on a step, inside the window, with a nonzero field, unless (flags & block mask) <> 0: value lane <- insert value OR field, flag lane |= set flags | transparency (field 0 writes nothing), tile-over-sprite and sprite-behind-tile priority | first-match-wins priority encoders, compare-and-select in sorting and merging, rewriting header fields |

Tile and sprite cells are configurations (`Pex_model.tile_cfg`, `sprite_cfg`): both count steps
(pe16's ALU adding k = 1 to s) and draw 2 bits per pixel from a 16-pixel window; the tile cell's
window repeats every 32 pixels and lets go after it, the sprite cell's does not repeat and lets go
at the end of the line.

**Area** (Yosys 0.62, sg13g2 typical, `reports/`, `results/area.txt`): PE-X is 18,110 um2, 2.75
times pe16's 6,586; 152 flip-flops against 56. A video-specialised variant that fixes 2 bits per
step and the window position and drops rotate (all the video uses; the chip lockstep passes with
it too) is 14,363 um2, 2.18 times; it is not the generic PE. The difference is the barrel shifter
for the window and the width mux of the shift register. Most of the rest is state: the 32-bit
shift register, two attribute registers, the configuration.

**The least generic of the five** is the conditional write's "only where the field is not zero"
(transparency). The write itself is a masked merge with a fixed mask (the low byte) and an OR into
the flags; a configurable mask, as an adversarial review suggested, would cost 16 more
configuration flops, about 780 um2, and serve field rewriting in general (`results/codex-review.txt`).

**What is still video-specific outside the PEs:** in the output port, the burst pin forcing table
address 63, the V-switch reflection of the phase, and the sequencer's luma pins taking over when no
step is showing. Together they are a few dozen gates of the port's 5,305 um2. The feeder's step
generator and `WAIT` are a timed memory-to-array streamer; `PIXELS` only sets the steps' initial
word.

## What maps directly and what needed an extension

| retro console | here | how |
| --- | --- | --- |
| hcount / vcount, sync, burst gate | sequencer threads 0 and 1 | firmware only |
| 54-byte systolic packet chain, double-buffered in 864 flops | line buffer (thick gain cells) + feeder + record loading | the double buffer becomes memory; the chain becomes records on the link |
| sprite cell: compare x, 8-bit bitmap with 2-pixel bits, overwrite | PE-X sprite configuration: a counter in s, the window, the shift register, the conditional write | needed all four extensions |
| background: two accumulators u, v, colour from bit 12 of u XOR v | not used by the platformer. u alone is pe16's ALU adding a step, with the window on bit 12 and rotate supplying ones: stripes and the perspective ground map directly. The XOR checkerboard does not: the write can only OR a value in | would need an XOR write mode, one more bit |
| 12-phase colour from a mod-12 counter, PAL mirror in logic | NCO with a phase input and a reflection on a pin; per-colour phases in a table the host writes | generic NCO plus a phase input (also PM and PSK for the radio) |
| luma DAC code from the sprite's colour byte | colour table at the end of the row | table lookup at the array edge (also line codes, gamma, sine tables) |
| (not in the console) tiles, 2-bit pixels, flip, priority, split screen | looped tile cells, records, flags | configurations and host data |

## Sprites, tiles and the split screen

- **Sprites:** 16 pixels wide, 2 bits per pixel, 3 colours from one of 4 palettes, transparent where
  0, flipped per record, clipped at both edges by the host (a pre-shifted pattern and a start
  count). Larger or more colourful characters are several cells: Pip is his body cell plus a scarf
  cell on the same lines (later cells win); the lanternsnail is two cells side by side, mirrored
  and swapped when it turns; a bumped block is drawn by a sprite cell while it jumps, as older
  consoles did. The snapweed has the behind flag, so the pipe's opaque pixels hide it.
- **Tiles:** 16 x 16, 2 bits per pixel, 4 palettes, a front flag per tile (the bushes are drawn in
  front of Pip). A line needs 17 slices with fine scroll, and 2 looped cells draw them: cell j mod
  2 draws slice j, and slice j + 2 is loaded into it after step 16(j + 1), when its previous window
  is over and at least one pixel before the next begins. Fine scroll is only the cells' starting
  counts plus a pre-shift of the first slice.
- **Split screen:** every line's scroll is its own records, so the score bar (lines 0-31) has
  scroll 0 and text slices the host renders from the retro console's font, while the play field
  below scrolls with the camera. There is no scroll register to rewrite mid-frame.

## Where the tile patterns live

Streamed from the host with every line (`results/budget.txt`):

- **Streaming (chosen):** 77 entries per visible line with no sprites, 157 with 16 sprite cells,
  183 to 373 bytes. The host link (the pin sampler's clocked mode, 4 pins, a nibble every 2
  clocks, 13.3 MB/s) carries 340 entries per line, so the worst line uses 46 % of it. On the chip it
  costs the 9,728-bit line buffer: about 40,000 um2 of thick gain cells, never refreshed.
- **On-chip tile cache in gain cells:** 64 tiles are 32 kbit, about 135,000 um2 (270,000 for 128
  tiles), plus the map. Each tile row is read once per frame, every 20 ms, but a thick cell lives
  3.1 ms in the worst corner and the 3T read restores nothing, so reads cannot keep tiles alive; an
  explicit refresh would take 0.8 % of a 32-bit port. With the pumped all-thick cell (368 ms worst,
  `../gain-cell/tricks-thick`, not drawn, needs a 2.2 V word-line pump and a sense amplifier) a
  rewrite-on-read would keep on-screen tiles alive while scrolled-off ones expire after 18 fields,
  or the host could re-send the set every 15 fields for 1-2 bytes per line. And a cache does not
  remove the line buffer: sprites, tile indices, scroll and colour updates still arrive with every
  line. It adds 3 to 7 times the line buffer's area to save link bandwidth the link already has.
- **Flops:** 400,000 um2 for a 16-tile cache. No.

The chip's scarce resource is area; the host's is not memory (the RP2350's 520 KB holds 128 tiles
in 8 KB) and the link has twice the bandwidth the worst line needs.

## Division of labour

- **RP2350:** the game (physics, collisions, enemies, camera, score, time), the pad, the tile map
  and slice extraction, sprite clipping and ordering, the palette (including palette cycling of
  the coins and the rolling table refresh), and building each line's entries.
- **Sequencer:** thread 0 video timing, thread 1 the V-switch; threads 2 and 3 free for sound or a
  pad reader (the eight sequencer pins are all used by video here, so the pad stays on the host).
- **Feeder, PEs, output port:** placement in time, compositing, colour.

## Limits per line

- **Sprite cells:** 16 per line, since sprite cells hold their record for the whole line. A 2-cell
  character costs 2. Releasing sprite cells after their window, like the tile cells, would let 16
  cells show more than 16 sprites where they do not overlap; it needs a second class bit so that
  sprite and tile records cannot be taken by the wrong kind of cell (not built).
- **Tiles:** one layer of 17 slices from 2 cells. A slice's record must land in its cell's idle gap
  of 16(K - 1) pixels; with K = 2 that is 160 clocks for 3 words, so 2 cells suffice. A second
  layer costs 2 more PEs and 68 entries per line.
- **Link and buffer:** 340 entries per line at the host link's rate; 256 per bank.
- **Area:** 18 PEs are three quarters of the chip.

## Area against the special-purpose console (`results/area.txt`)

| | um2 |
| --- | --- |
| 18 PE-X (lean) | 325,983 (258,534) |
| feeder, output port | 11,299 |
| deadline sequencer | 18,995 |
| line buffer, colour table, sequencer programme (thick gain cells, estimated periphery) | 63,486 |
| **total** | **419,763 (352,315)** |
| retro console, PAL build, same flow | 100,433 |

The generic chip is 4.2 times the console (3.5 with the lean PE), and does more: tiles, 2-bit
sprites, flip and priority, which the console does not have. The fairer comparison is incremental:
on a chip that already has an array of 18 pe16s and the sequencer with its programme memory, being
a console costs the PE extensions (18 x 7,777 um2 lean, 18 x 11,524 full), the feeder, the output
port, the line buffer and the colour table: 196,780 to 264,228 um2, 2.0 to 2.6 times the
console.

## Checks

| check | result |
| --- | --- |
| PE-X RTL against its model, rows of 4, 300 random configurations x 2,000 cycles (`results/pecheck.txt`) | 0 mismatching cycles; planted faults (no flip, block ignored, early release) caught in 211, 241, 249 of 300 runs |
| the whole chip against the reference renderer, 240 random lines (random tiles, fine scroll, priority, 0-21 sprites with flip and clipping) and 240 directed edge cases (`results/check.txt`) | 0 of 61,440 pixels differ in each set, and 0 with the lean PE; the three planted faults change 7,788, 2,999 and 27,423 pixels |
| sequencer timing, interpreter and RTL pins (`results/timing.txt`) | every line 3404 clocks, broad pulses 1700/1704, first pixel at clock 662 as in the console, 2560 pixel clocks per line |
| palette through the software TV (`results/palette-compare.txt`) | 143 colours within 0.007 of the console's |
| the demo, every visible line of every field against the reference renderer (`results/game.txt`) | 285 fields and 68,400 visible lines differ in 0 pixels; the run takes 2,452 s and the oldest table entry read is 1.020 ms |
| colour-table age (every read, `results/check.txt`) | oldest entry read 1.02 ms after it was written, under the thick cell's 3.1 ms |

## Not done

Looped sprite cells; the XOR write mode; a second tile layer; sound on the free threads; place and
route; a drawn gain-cell line buffer (its periphery here is an estimate); a real host (RP2350 PIO and
DMA streaming 19-bit entries); a real TV.

## Files and how to run

    opam --switch=5.3.0 exec dune build
    ./_build/default/main.exe pecheck           # PE-X lockstep; see results/pecheck.txt
    ./_build/default/main.exe check             # chip against reference; see results/check.txt
    ./_build/default/main.exe timing            # firmware on the interpreter
    ./_build/default/main.exe rtltiming         # the same on the RTL's pins
    ./_build/default/main.exe palette && uv run ../retro-console/console_tv.py palette
    ./_build/default/main.exe game 285 && uv run ../retro-console/console_tv.py frames game
    uv run stills.py 36 82 150 205 276          # generate the local GIF and selected stills
    ./_build/default/main.exe preview 300 6 && uv run preview.py   # host-only preview, reference renderer
    ./_build/default/main.exe verilog pex && ./synth.sh pex        # likewise pex_lean, feeder, outport, deadline_sequencer, retro_console
    uv run budget.py > results/budget.txt; uv run area.py > results/area.txt

`isa.ml` and `sequencer.ml` are symbolic links to `../multiphase`; `console.ml` and `font.ml` to
`../retro-console`.
