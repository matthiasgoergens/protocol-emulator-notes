# Third-party peers on our pins

An unmodified protocol implementation written by someone else listens to the pins of our design. If our
UART and a stranger's UART disagree, the stranger is more likely to be right about the protocol than
our own test bench, which shares our reading of it.

Method after TeslaCoilerOW (`ttihp-protocol-emulator`, `docs/independent-peers.md`, `test_ext/`):
peers vendored unmodified at a pinned commit with a SHA256SUMS file. The peer here is **Alex
Forencich's `verilog-uart`** (MIT, copyright 2014-2017 Alex Forencich), commit
1b867e53af738e4a8bc7c839ca2f1c07f40382dc, the same commit TeslaCoilerOW pins. `vendor/verilog-uart/`
holds `uart_rx.v`, `uart_tx.v`, `COPYING` and `AUTHORS` byte for byte (`PINNED` names the upstream, the
commit and the files; `SHA256SUMS` is checked on every run). The harness, `uart_rx_replay.v` and
`peers.py`, is ours, Apache-2.0.

## What runs

    tools/sigrok-judge/run.sh     # once, makes tools/sigrok-judge/traces/
    tools/peers/peers.py          # -> results/peers.txt

`peers.py` replays the pin trace that the `deadline-sequencer` RTL produced (UART thread, 64 cycles per
bit, bytes `4f 4b 21`) into the peer's `uart_rx` in Icarus Verilog, with `prescale` 8 (the peer takes a
bit as `prescale * 8` clocks). The bytes the peer reports must equal the bytes sent, and neither
`frame_error` nor `overrun_error` may rise. Teeth: a data bit inverted, and a transmitter 10 % and 30 %
slow; each must change the bytes or raise a flag. `results/peers.txt` has the output.

## Limits

- It is a replay of a recorded trace, not a live co-simulation. The sequencer RTL is a Hardcaml
  simulation and the peer is Verilog; they do not share a clock in one simulator, so the peer sees
  exactly the pin levels the RTL produced, one sample per core clock, and cannot push back.
- Only the direction our chip transmits is covered. The peer's `uart_tx` driving our receiver
  (`prototypes/gps-hotcold/seq/uart_rx.ml`) is not wired up, and neither are `verilog-i2c`, SPI peers
  or the JTAG DTM from TeslaCoilerOW's list.
- Verilator was not installed; Icarus is.

## Credits

Alex Forencich (`verilog-uart`, MIT); TeslaCoilerOW (the method).
