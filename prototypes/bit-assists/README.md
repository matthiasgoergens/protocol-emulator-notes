# Bit-path assists: the stuff tracker and the line coder

`notes/architecture-v0.md` section 2.3 puts two small assists on the chip's bit path, between the
edge-tracking sampler and the rest: a **stuff tracker** (insert or delete a bit after a programmable
run, with a violation flag) and a **line coder** (NRZI and Manchester, encode and decode). Until now
they existed only as area probes (`../unified-pe/rtl/assists.v`, 813 and 477 µm², no model, no
verified RTL), so `../chip-top` left them out. This directory specifies both, builds them in
Hardcaml and checks them.

Build: `opam exec --switch=5.3.0 -- dune build` (Hardcaml v0.17). Run:
`_build/default/check.exe blocks 1000000` (results in `results/blocks.txt`, about 12 s).

## What they do

**Stuff tracker** (`stuff.ml`). Configuration: run length (4 bits, 0 = off), mode ("ones": a bit
equal to `value` continues the run; "either": a bit equal to the last one does) and `value`.
Protocols are configurations: USB run 6 of ones, CAN run 5 of either value, HDLC run 5 of ones.
The run is counted over every bit on the line, stuff bits included, which is what both USB (the
stuffed 0 ends the run) and CAN (a stuff bit and four more of its value make the next run of five)
require. Transmit: when a bit is due and the last `run` bits are a run, the stuff bit goes out and
no data bit is taken; without a data bit it reports an underrun, which the serialiser on the chip
takes as the end of the frame. Receive: the bit after a run is dropped, and a violation if it
continues the run (USB's seven 1s, CAN's stuff error). `restart` clears the count at a frame start.

**Line coder** (`linecode.ml`). Pass, NRZI (a bit equal to `toggle_on` changes the level: USB
toggles on 0) and IEEE 802.3 Manchester (complement then bit: a 1 is low then high), with an
inversion of every symbol. The encoder emits one symbol per tick and takes a bit every tick, or
every second tick in Manchester (`need_bit`); `restart` puts NRZI at the idle level and Manchester
at a bit boundary. The decoder takes one symbol per valid; Manchester gives a bit per two symbols
and flags two equal halves as a code violation. The decoder has no restart: a receiver decodes
across the idle gap, which is the reference level for the first symbol of a USB sync.

Both are written twice from the same rules: a model on integers and the Hardcaml RTL.

## Checks (`check.ml`, `results/blocks.txt`)

| check | result |
|---|---|
| RTL against model, every clock: both stuff directions, encoder and decoder in one circuit, every input random every clock (configuration changes, restarts, gaps in the traffic, runs biased long) | 4 seeds × 1,000,000 clocks, **0 mismatching clocks** |
| USB: the RTL transmit chain (stuffer then NRZI) on random packets, 0xFF-heavy, sync included, against `../usb-ls/fw_codec.ml` (the firmware device's own encoder, written for that prototype) | 300 of 300 symbol for symbol |
| USB: the RTL receive chain on those symbols gives the packet back, no violation; with one stuff bit removed, a violation | 300 of 300; 300 of 300 |
| CAN: the RTL stuffer against `../sequencer-ps2-can`'s host stuffer (copied verbatim to `refs/can_stuff.ml`), runs of either value; destuffed back | 300 of 300; 300 of 300 |
| 10BASE-T: the RTL Manchester encoder against `../ethernet-10base-t/eth_model.ml`'s; decoded back; a flipped half-bit is a code violation | 300 of 300 each |
| round trip through the RTL, random configurations (every mode, run, polarity, inversion) | 300 of 300 |
| planted faults (6 in the stuff tracker, 8 in the line coder), each must make the lockstep fail | **14 of 14 caught** |
| the same faults against the references alone | 12 of 14 fail them; the two that do not are the restart faults, which the references do not exercise (the lockstep catches both) |

The references are other prototypes' encoders, so they are independent of these rules except
where the standards are: they settle the polarity conventions (J as level 0 for USB, 802.3's
Manchester), the stuffing rules across stuff bits, and the stuff bit after the last data bit.

## On the chip

`../chip-top` puts them on the bit path (README section 8): a transmit serialiser (byte FIFO from a
thread, bit timer, stuffer, encoder, a two-phase tail such as USB's EOP) and a receive framer
(decoder, destuffer, start pattern, byte packer, end on line idle).
