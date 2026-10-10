# Bit-path assists: the stuff tracker and the line coder

`notes/architecture-v0.md` section 2.3 puts two small assists on the chip's bit path, between the
edge-tracking sampler and the rest: a **stuff tracker** (insert or delete a bit after a programmable
run, with a violation flag) and a **line coder** (NRZI and Manchester, encode and decode). Until now
they existed only as area probes (`../unified-pe/rtl/assists.v`, 813 and 477 µm², no model, no
verified RTL), so `../chip-top` left them out. This directory specifies both, builds them in
Hardcaml and checks them.

Build: `opam exec --switch=5.3.0 -- dune build` (Hardcaml v0.17). Run:
`_build/default/check.exe blocks 1000000` (`results/blocks.txt`, about 12 s) and
`_build/default/check.exe paths 1000000` (`results/paths.txt`, about 45 s).

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

## The two paths built from them (`txpath.ml`, `rxpath.ml`)

On the chip the assists need a byte interface to the threads, so this directory also specifies the
two composite blocks that `../chip-top` integrates. Both read their configuration live (no
"change only while held" contract) and are specified, built and checked like the assists.

**Transmit serialiser.** A two-byte FIFO (a thread's SEND), a symbol timer (`period` clocks, 12
bits), the stuff tracker and the encoder, LSB or MSB first, and a two-phase tail of 0 to 15 symbols
each with a level per line. A frame starts one clock after a byte reaches the idle serialiser;
an underrun at a bit boundary ends the data (a stuff bit due after the last data bit still goes
out), then the tail, then idle. Line b is the complement of line a during data (a differential
pair). USB low speed: 40 clocks per symbol, run 6, NRZI with J as the idle level, tail SE0 × 2
then J × 1. 10BASE-T: 3 clocks per half-bit, Manchester, tail TD+ high for 6 symbols (TP_IDL).

**Receive framer.** The decoder and the destuffer on every recovered bit, one registered chain
bit with an error flag; an 8-bit history of the chain (newest bit in bit 7) and a pattern with a
mask start a frame (USB's sync 0x80, Ethernet's SFD 0xD5), or the host does; half duplex stops a
start while the transmitter is active (so a device does not receive itself). In a frame, bytes go
into a two-byte FIFO; the frame ends when the line goes inactive (USB's SE0), at the edge
sampler's burst end (Ethernet), or by the host. Stuff and code violations in the frame set a
sticky error. The chip's CRC unit can take the frame's bits after a `skip` count (USB: the 8-bit
PID). Two decisions found by the references: the history counts only bits received since the
last clear or frame end (a cleared history looked like received zeros, and a packet ending in
seven 0s followed by the EOP's decoded 1s completed a sync: 21 of 100 USB packets started a
second, empty frame before this), and the destuffer drops and flags bits only inside a frame,
counting the run outside one (the idle J before a packet decodes as 1s, and after six of them the
sync's first 0 was dropped as a stuff bit: 10 of 75 packets after idle gaps of 0 to 14 bits were
lost, found by chip-top's USB device and then by a new reference test, `results/paths.txt`).

| check (`check.exe paths 1000000`, `results/paths.txt`, 43 s) | result |
|---|---|
| RTL against model, both paths in one circuit, the receiver fed from the transmitter's own line or from random bits, random configurations (USB, Ethernet, random), pushes, pops, host starts and stops, burst ends | 4 seeds × 1,000,000 clocks, **0 mismatching clocks** |
| USB: the serialiser's whole frame (sync to EOP) at 40 clocks per symbol against `fw_codec.symbols` | 100 of 100 |
| USB: the framer on that line returns the bytes after the sync, with the CRC fed after the PID; CRC-16 over the feed of a data packet leaves 0xB001; a missing stuff bit sets the error flag | 100 of 100 each |
| 10BASE-T: the serialiser against `eth_model`'s Manchester, the pair complementary, then 6 symbols of TP_IDL; the framer after the SFD returns frame and FCS, CRC-32 over its feed leaves 0xDEBB20E3 | 100 of 100 each |
| USB: a packet after 0 to 14 bit times of idle J is received whole | 75 of 75 |
| planted faults (6 in the serialiser, 9 in the framer) | **15 of 15 caught** by the lockstep; 11 of 15 also fail the references |

## On the chip

`../chip-top` puts both paths on its bit path (its README, section 8).
