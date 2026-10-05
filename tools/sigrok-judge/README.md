# sigrok judge

The pin traces our prototypes produce are decoded by sigrok's protocol decoders, which other people
wrote, and the decoded frames are compared with the payloads that were meant to be sent. Every trace
also comes with "teeth": a planted fault (an inverted bit, a late data line, a slow bit clock) that the
judge must flag. A judge that passes the clean trace and also passes the faulty one is blind, and the
teeth are how we find that out.

Method after MarcosAsh (`demo/decode.py`, `test/traces/sigrok/*.trace`, Apache-2.0) in
`MarcosAsh/protocol-emulator`: the decoder judges the pins, any decoder warning fails, a trace names
what the decoder must print, and `--rate` resamples as a slower analyser would. The S/PDIF bridge in
`prototypes/spdif` (`sigrok_check.sh`, `main.exe sigrok-compare`) was the first use of sigrok in this
repository; its captures and its container recipe are reused here.

## Licence

libsigrokdecode is GPL-3.0 and this repository is Apache-2.0. sigrok-cli is therefore run only as an
external program inside a rootless podman container (`Containerfile`); nothing of it is vendored,
copied or translated here, and the comparison code in `judge.py` is written from the annotation text
the program prints. (To diagnose the PS/2 behaviour below, the installed decoder's source was read
inside the container. No line of it is used.) Anyone who wants an OCaml decoder must write it from the
protocol specification, not from sigrok's Python.

## Running it

    tools/sigrok-judge/run.sh                 # traces from the simulations, then the judge
    tools/sigrok-judge/rate-sweep.sh          # the same, resampled to slower analyser rates
    tools/sigrok-judge/judge.py --only can    # one case, traces already made

Needs opam switch 5.3.0 (Hardcaml v0.17), podman and uv. `run.sh` builds and runs the dumpers in the
prototypes (all niced, all waiting while the load is above 20), then the judge, and writes
`results/judge.txt`. The first run builds `localhost/sigrok-judge:0.7.2-1` from `Containerfile`; the
base image is pinned by digest and the three packages by version (sigrok-cli 0.7.2-1+b2,
libsigrokdecode4 0.5.3-4+b4, libsigrok4t64 0.5.2-5.1+b3, Debian 13.7), so a rebuild fails instead of
silently using another decoder. Each results file records the version lines, the commit and the date.

A trace is one byte per sample (bit p is channel p) with a `.expected` file of `key value` lines.
`traces/` is regenerated and not committed.

## What is judged

| protocol | trace source | decoder | judged against |
|---|---|---|---|
| UART | `prototypes/deadline-sequencer` RTL (`demo.exe dump`), pin 0 | `uart` | the three bytes sent |
| SPI | same trace, SCLK, MOSI, CS | `spi` | the two bytes sent |
| I2C | same trace, SDA, SCL, with the demo's slave model in the loop | `i2c` | start, address, ACK, data, ACK, stop |
| PS/2 | `prototypes/sequencer-ps2-can` keyboard firmware, interpreter and RTL in lockstep, to the independent host model (`ps2_dump.exe`) | `ps2` | the four scan codes, odd parity OK |
| CAN | the same prototype, scenario S1 (arbitration between two of our nodes, then a reference node's remote frame), bus as heard by the reference node, 20 MHz (`can_dump.exe`) | `can` | the three frames in bus order: id, RTR, DLC, data |
| USB low speed | `prototypes/usb-ls` hardened device RTL answering GET_DESCRIPTOR (`usb_dump.exe`) | `usb_signalling` + `usb_packet` | the SETUP data and the 18 descriptor bytes; no CRC or sync error |
| S/PDIF | `prototypes/spdif` chip transmitter (`main.exe tx`) | `spdif` | preamble, 24-bit audio, V, U, C, P of every subframe |
| 10BASE-T | n/a | none | no sigrok decoder exists, see below |

The dumpers are read-only taps on the existing benches (a `tap` argument in `ps2_bench.ml`, a `Bench.tap`
hook in `usb-ls/bench.ml`, a `dump` mode in `deadline-sequencer/demo.ml`, two new small executables);
they change no behaviour.

## Teeth

Each protocol has two planted faults, applied to the clean trace before the decoder sees it:

- UART: data bit 3 of byte 0 inverted for half a bit; bit time 10 % long with the receiver fixed.
- SPI: MOSI inverted around the third clock edge; MOSI 40 samples late against a 64-sample clock.
- I2C: SDA inverted over the third SCL pulse; SDA 24 samples late.
- PS/2: DATA inverted over the fifth falling clock edge; DATA 45 samples late (half a period is 40).
- CAN: bit 30 of the first frame inverted; bit time 25 % long, decoder fixed at 500 kbit/s.
- USB: one bit of the first packet inverted on both lines; bit time 25 % long.
- S/PDIF: 30 samples inverted mid-stream; 300 samples stretched by 1.6 mid-stream. Also the chip's
  own planted fault from `prototypes/spdif` (one wrong entry in the transmitter's expansion table,
  11 UIs differ), as a trace judged against the intended payloads.

A tooth that is not flagged fails the run. `results/judge.txt` has the exact output.

## Findings about the oracle itself

- **The installed PS/2 decoder mis-frames.** libsigrokdecode 0.5.3 collects twelve falling clock edges
  per 11-bit frame and emits a frame only when the next frame's start bit arrives, so from the second
  frame on it decodes shifted bits (`f8` for `f0`, parity errors) and the last frame is never
  emitted. It does this on an ideal synthetic trace too (`results/ps2-decoder-quirk.txt`), so the fault
  is not in our trace. The judge inserts one idle clock pulse with DATA high after every 11th falling
  edge, which is what that decoder needs. Treat the PS/2 verdict as "our trace decodes correctly once
  the decoder's framing is worked around", not as an unaided pass.
- **The S/PDIF decoder re-locks on every edge.** A 20-sample deletion mid-stream (half a cell, a
  phase step) was decoded with 897 of 897 subframes equal, so sigrok cannot judge phase steps or
  jitter; the chip's own jitter and tolerance runs do that (`prototypes/spdif/results/jitter.txt`).
  The teeth above are the changes it does see.
- **CAN: a dominant start-up glitch.** In the model the bus is low for 4 samples (200 ns) at time
  zero, before the firmware drives it recessive; the decoder takes it for a start of frame. The judge
  drops the first 200 samples (`trim` in the case table) and says so here; the cause (the model's
  reset value of the TXD and TXE pins) is not investigated.
- **CAN: identifier 0x7FF.** The reference node's remote frame uses identifier 0x7FF, which the CAN
  specification forbids (its seven top bits may not all be recessive). The decoder warns; this one
  warning is allow-listed by exact text in `CAN_ALLOWED_WARNINGS`, any other fails. The decoder also
  reads data bytes for a remote frame, so data is compared only for data frames. The remote frame is
  not acknowledged by anything (ACK slot NACK), which the judge prints but does not judge.
- **Analyser rate.** `rate-sweep.sh` resamples (sample and hold) and judges again, teeth included.
  Passing, with every tooth caught: UART, SPI, I2C and PS/2 at 500, 250 and 125 kHz (from 1 MHz;
  UART at 125 kHz is 8 samples per bit); CAN at 10, 5 and 2.5 MHz (5 samples per bit at the lowest);
  USB low speed at 12, 7.5 and 6 MHz (4 samples per bit at the lowest); S/PDIF at 120 and 48 MHz.
  S/PDIF at 24 MHz (4.25 samples per cell) fails the clean trace (343 unknown preambles), so the
  teeth caught there prove nothing. Results: `results/judge-rates.txt`.

## What is missing

- **10BASE-T and Ethernet:** `results/sigrok-decoders.txt` (what `sigrok-cli --list-supported` prints in the container)
  has no Manchester, 10BASE-T, MII or Ethernet decoder, so `ethernet-10base-t`, `eth10-node`,
  `pin-sampler`, `sequencer-ethernet` and `multi-proto` keep their own oracles. If a decoder
  appears, the pin dumps in those prototypes are the place to add a trace.
- **Gate level:** only RTL and interpreter traces are judged, not the post-synthesis netlist
  (MarcosAsh also runs the decoder on the gate-level simulation).
- **Other directions and roles:** PS/2 host direction, CAN receive on our nodes, I2C slave, SPI slave,
  USB host side are not traced. JTAG/SWD have sigrok decoders (`jtag`, `swd`) but `proto-jtag-swd` is
  not dumped yet.
- **Full-speed USB, 100BASE-TX and HDMI/video:** no trace, and sigrok has no decoder for the last two.

## Credits

MarcosAsh for the method; the sigrok project for the decoders (run, not copied); the S/PDIF bridge
by this repository's `prototypes/spdif`.
