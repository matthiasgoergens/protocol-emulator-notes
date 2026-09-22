# 10BASE-T Ethernet, digital side: a prototype

The network stretch goal from the competition post, as far as it can be
built without a transformer on the bench: a 10 Mbit/s Ethernet
transmitter and receiver in Hardcaml, with a host model that builds a real
UDP/IPv4 broadcast frame and encodes and decodes the line independently.

The clock choice removes the fractional-ratio problem the notes worried
about: at 60 MHz, which the demo board's RP2040 can supply, a half bit is
exactly three cycles and a bit six, so Manchester needs no fractional
timing at all. The 20 MHz toggle rate is inside the pads' 33 MHz limit.

## What is here

- `eth_model.ml`: CRC-32 (checked against the standard "123456789"
  vector), UDP/IPv4 framing with the IP checksum computed on the host and
  padding to 60 bytes, Ethernet bit order (each byte LSB first), Manchester
  encoding with preamble, SFD and TP_IDL, and a Manchester decoder that
  finds frames by mid-bit transition timing. The CRC residual the receiver
  checks, 0xDEBB20E3, is derived here rather than assumed.
- `eth_tx.ml`: transmitter. Preamble and SFD, frame bytes from a ROM
  loaded from the host model, FCS computed on the fly and sent
  complemented low byte first, TP_IDL, the inter-packet gap, and a 100 ns
  link pulse every 16 ms in idle so the far end shows link up.
- `eth_rx.ml`: receiver. Takes a comparator's output and an activity
  flag, times mid-bit transitions, finds the SFD, assembles bytes and
  checks the CRC-32 residual at end of frame.
- `eth_top.ml`: both side by side, as they would sit on the chip.
- `main.ml`: the checks below.

Build and run: `opam exec --switch=5.3.0 -- dune build && dune exec ./main.exe`
(Hardcaml v0.17).

## Results

| Check | Result |
| --- | --- |
| Model round trip, CRC vector, residual constant | pass |
| Transmitter's frame decoded by the model | 60 bytes plus FCS, matches, FCS correct |
| Transition spacing over the whole frame | only half-bit and full-bit gaps, zero others |
| Link pulses in idle | 100 ns pulses at exactly the configured period |
| Receiver on the model's frame | 64 bytes, CRC ok |
| Receiver on a corrupted frame | rejected |
| Receiver on the transmitter's own output | CRC ok, bytes match |
| Synthesis on sg13g2, flattened, transmitter and receiver with the frame ROM | 1,002 cells, 16,347 um2, 173 flip-flops |
| Place and route at 60 MHz (`pnr-metrics/eth60/`) | die 41154 um2, utilisation 78 %, routing violations 0, setup slack +11.2 / +10.1 / +8.3 ns at fast / typical / slow |

## What the wires need

Transmit: two pins through series resistors into the transformer of an
RJ45 jack with integrated magnetics, the same arrangement hobbyists use to
send 10BASE-T from a microcontroller without a PHY; receivers accept it.
Receive needs a comparator on the other pair to turn the differential
signal into the `rx` and `rx_active` bits, since a CMOS input threshold
cannot resolve the transformer's output on its own. That comparator is
the one analogue part of the stretch goal, and it is a board component,
not a chip one. Neither has been tried on wires yet; the FPGA is where
that happens.

One tooling note: an output port named `byte` passed Yosys but failed
LibreLane's Verilator lint, since it is a SystemVerilog keyword; it is
now `rx_byte`.
