# Documentation

The chip's architecture, instruction set, configuration, host link and toolchain. Each page
links to the executable specification it describes; `tools/asm/test/docs_drift.ml` compares the
tables of these pages with that code and runs every code block that states expectations, so the
pages cannot silently drift from the chip.

| page | what |
|---|---|
| [architecture.md](architecture.md) | the blocks, the timing model (threads and slots), the path to the pins, determinism |
| [isa.md](isa.md) | ISA v2 of the sequencer: every instruction's encoding, fields, timing in slots, examples and edge cases |
| [configuration.md](configuration.md) | the register map, the pin map, flags, the assists, the PE array and its load order |
| [host-link.md](host-link.md) | the host link's wires, timing and commands, and the image format |
| [assembly.md](assembly.md) | the assembly language, the assembler, disassembler, verifier driver and runner |
| [tutorial.md](tutorial.md) | write your first protocol: WS2812 LEDs from the datasheet to a verified, running image |

The toolchain and its example programmes are in `tools/asm` (its README lists them and the
checks each passes).
