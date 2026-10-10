# tools/asm: the chip's toolchain

An assembler, disassembler, timing-verifier driver and runner for the chip of
`prototypes/chip-top`: its sequencer (ISA v2, `prototypes/sequencer-v2/isa2.ml`), its pin map
and assists, its PE array and its host link. The manual is `docs/assembly.md`; the instruction
set, configuration and host link are in `docs/`.

Everything executes the repository's own specifications, never copies: `vendor/` holds symlinks
to the prototypes' sources (ISA v2's interpreter and encoder, chip-top's specification, RTL,
register map, host driver and board, the PE array, the assists, the static verifier, the
deadline-sequencer compiler and decoders, the one-bit DAC), as `prototypes/chip-top/blocks`
does.

    opam exec --switch=5.3.0 -- dune build --root .      # Hardcaml v0.17
    _build/default/bin/asm.exe examples/uart_tx.s --verify --listing -
    _build/default/bin/run.exe examples/uart_tx.hlk --clocks 2500 --vcd uart_tx.vcd
    ./run_all.sh                                           # every result file below

| file | what |
|---|---|
| `src/assembler.ml`, `lexer.ml`, `syntax.ml`, `expr.ml` | the language: labels, expressions, `.include`, `.macro`, `.rep`, `.if`, `.thread`, `.page`, every instruction and EXT sub-operation, quarter-clock sub-slots, configuration and host-link directives |
| `src/insn.ml` | instructions as values, encoded through isa2.ml's encoder functions; shared by assembler and disassembler |
| `src/image.ml` | the image: the host-link byte stream, in one canonical order; parsing it back |
| `src/config.ml` | the configuration's named fields (pads, flags, assists, PE op word, segments) |
| `src/disasm.ml` | image to source |
| `src/timing.ml`, `src/verify.ml` | `.timing` blocks as the verifier's automata; `--verify` and certificates |
| `src/runner.ml`, `src/peers.ml`, `src/wave.ml` | the runner: interpreter and chip (specification and RTL in lockstep) on one board model, peers and stimulus files, VCD and sigrok output |
| `lib/std.inc`, `lib/proto.inc` | macros for waits and branches; UART, SPI and I2C controllers |
| `examples/` | the example programmes (below) |
| `test/roundtrip.ml` | assemble, disassemble, reassemble: identical bytes |
| `test/examples.ml`, `test/judge_examples.py` | every example end to end, with independent decoders and controls |
| `test/docs_drift.ml` | the docs against the code |

## The examples

Each is checked by `test/examples.ml` (results in `results/examples.txt`) and its pins by
`test/judge_examples.py` (`results/judge.txt`):

| example | what | ported from, proved equal | independent checks |
|---|---|---|---|
| `uart_tx.s` | UART transmitter, "OK!" | deadline-sequencer's compiler: words equal; `.timing` equal to the verifier's uart_spec and proved | repository decoder; sigrok `uart` with teeth; Forencich's `uart_rx` (Verilog, unmodified) |
| `uart_rx.s` | UART receiver to the host | new | stimulus from Forencich's `uart_tx` in Icarus; the runner's UART at 16 phases; a 12 % slow sender must fail |
| `spi.s` | SPI controller, mode 0 | compiler: words equal; `.timing` equal to spi_spec and proved | repository decoder; sigrok `spi` with teeth |
| `i2c_write.s` | I2C write, with clock stretching | compiler: words equal; `.timing` equal to i2c_spec and proved | the runner's I2C target, stretching 0 and 7 clocks; repository decoder; sigrok `i2c` with teeth; no target must fail |
| `i2c_read.s` | I2C register read: pointer write, repeated START, read with ACK and NACK | new (the compiler's byte macros) | the I2C target at stretch 0 and 5; repository decoder; sigrok `i2c` annotations with teeth |
| `bridge.s` | UART to SPI through a mailbox, two threads | new | Forencich's `uart_tx` in, repository and sigrok SPI decoders out |
| `dac.s` | one-bit DAC: sigma-delta on 4 PEs, fed from the host | onebit-dac's pump programme and PE configuration: words and bytes equal | the modulator's bit-exact model (0 wrong bits); a low-pass decode correlated with the input |
| `ws2812.s` | WS2812 LEDs (`docs/tutorial.md`) | new | `.timing` proved; a decoder written from the datasheet; sigrok `rgb_led_ws281x` with teeth |

Every example also runs on the ISA interpreter and on the chip's specification and RTL, which
must agree on every pin on every clock, and a planted RTL bug on the example's pins must break
that lockstep.
