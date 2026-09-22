# USB full-speed device: a prototype

A USB 2.0 full-speed (12 Mbit/s) device in Hardcaml that enumerates and
loops back bulk data, running from a 48 MHz clock through ordinary
digital pins. This is the "run circles around USB" claim made concrete:
the fast protocols are hardened blocks, and at full speed everything fits
through the standard pads.

Why fixed logic rather than the sequencer: a device must answer a token
within 6.5 bit times, about 540 ns, and the sequencer changes a pin at
most every four cycles; recognising a packet, checking two CRCs and
choosing a reply in that time needs a serial interface engine. The engine
is small, and the design rule from the rest of the repository holds:
timing fixed in hardware, everything else precomputed, here the
descriptors and the protocol tables.

## What is here

- `usb_rx.ml`: receiver at four samples per bit. Sampling phase resets on
  every transition and samples mid-bit; NRZI decode; bit unstuffing;
  sync detection; bytes LSB first; SE0 ends the packet.
- `usb_tx.ml`: transmitter. Sync, bytes with bit stuffing (including a
  stuff bit before EOP when the last six bits were ones), NRZI, EOP as
  two bit times of SE0 then one of J.
- `usb_sie.ml`: the protocol engine. Token decode with CRC5 check, data
  packets with CRC16 check by residual, control endpoint 0 with
  GET_DESCRIPTOR for the device and configuration descriptors (with
  zero-length packet handling), SET_ADDRESS and SET_CONFIGURATION, STALL
  for anything else, bulk endpoint 1 as an 8-byte loopback with data
  toggles, and response timing in the legal window. Descriptors are a
  ROM. Packets for other addresses are ignored; receive events are masked
  while transmitting, since a real bus echoes the device's own packets.
- `host.ml`: a bit-level host model written from the specification, not
  from the RTL: encoder to line samples, decoder from line samples, CRC5
  and CRC16. Self-checked against known packet bytes: the SETUP token for
  address 0 is 2D 00 10, and the GET_DESCRIPTOR data packet is
  C3 80 06 00 01 00 00 40 00 DD 94.
- `main.ml`: the enumeration script a real host performs, run against the
  RTL in Cyclesim with the host driving the bus and reading the device's
  drive: device descriptor at address 0, SET_ADDRESS 5, device
  descriptor at 5, configuration descriptor 9 then 32 bytes,
  SET_CONFIGURATION 1, bulk OUT then IN loopback, NAK on an empty buffer,
  and no response to a wrong address. Every reply is checked for bytes,
  CRC and turnaround time within the 2 to 6.5 bit-time window.

Build and run: `opam exec --switch=5.3.0 -- dune build && dune exec ./main.exe`
(Hardcaml v0.17).

## Results

- Enumeration and loopback pass end to end. The first run answered 0.5
  bit times after the host's EOP, which violates the two-bit-time gap and
  would have caused bus contention on real wires; the response delay now
  places replies at about 3.5 bit times, and the test bounds it.
- Planted-bug checks: a transmitter that stuffs after seven ones instead
  of six makes every data stage undecodable; an engine with the CRC check
  disabled acknowledges a corrupted packet, which the suite now tests
  for, and the correct engine stays silent as the specification requires.
- Area (Yosys, area-mode abc, sg13g2 typical liberty, flattened): 1,917
  cells, 29,669 um2, of which 305 flip-flops are 14,940 um2. The whole
  device, receiver, transmitter, engine and descriptor ROM, is half of one
  RP2040-PIO-style state machine measured the same way.
- Place and route (LibreLane 3.0.14 in its container, IHP sg13g2, 20.8 ns
  clock for 48 MHz, 55 % target utilisation, `pnr-metrics/usb48/`): die
  67,671 um2, final utilisation 72 %, zero routing violations, setup slack
  +14.5 / +13.5 / +11.7 ns at the fast / typical / slow corners, hold
  positive everywhere. The worst path is about 9 ns at the slow corner, so
  the engine has room for a faster line rate; the pads, not the logic,
  are the limit above full speed.

## What it does not have

String descriptors, more than one configuration, endpoints beyond the
loopback pair, error recovery beyond ignoring bad packets, suspend and
resume, and the pull-up resistor and series resistors that the board
supplies. It has not run against a real host yet; that is the FPGA's job,
with the board's USB port wired straight to fabric pins and a Linux
machine as the host.
