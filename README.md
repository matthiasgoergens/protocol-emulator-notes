# Protocol-emulator ASIC: design notes and measurements

Working notes for an entry to Jane Street's protocol-emulator ASIC
competition (<https://blog.janestreet.com/protocol-emulator-asic-competition/>):
a small reprogrammable chip for bit-banging protocols such as UART, SPI and
I2C, to be fabricated on IHP's 130 nm process through a Tiny Tapeout shuttle.

Nothing here is a finished design. It is the record of the brainstorming and
of the measurements that followed, kept so that every number in the notes
can be traced to the run that produced it.

## Contents

- `brainstorm-*.md`: three independent idea lists written by three
  different AI systems from the same prompt, followed by a `synthesis.md`
  that compares them and a `brainstorm-wild.md` that deliberately ignores
  where they agree. `second-layer/` pushes further into unusual execution
  models. Not every idea in them is original to this repository; some arrived
  from outside and are recorded without attribution. They also refer to an
  earlier, separate body of work on a chip reverse-engineering puzzle (paths
  under `hardware-2026-08/`), which is not included here.
- `datapoints.md`: the running list of measured facts, each with a pointer
  to its raw run.
- `measurements/pio-area/`: standard-cell area of an open-source RP2040
  PIO clone on IHP sg13g2, synthesised with Yosys, including two variants
  of its shift register with fixed shift widths.
- `measurements/fabulous/`: area of a FABulous embedded-FPGA tile and of a
  small 4x4 fabric on the same process, a sparse-routing variant, two tiles
  containing hardened blocks, place-and-route results for the stock tile
  with LibreLane and OpenROAD, and a routability benchmark of four small
  protocol designs (one written in Hardcaml) on stock and sparse fabrics.

## Headline numbers

All from Yosys area-oriented synthesis against the sg13g2 typical liberty
file unless stated; details, caveats and logs sit next to each number.

| Thing | Result |
| --- | --- |
| One PIO state machine (fpga_pio, all submodules) | 4,713 cells, 61.6K um2, about two Tiny Tapeout tiles at full utilisation |
| Its two shift registers | 53 % of that area; fixing the shift width to one bit shrinks the input shifter 4.6x |
| One FABulous LUT4AB tile (8 x LUT4) | 36.3K um2 flattened; configuration latches 52 %, switch matrix 37 %, logic about 10 % |
| Routing share of the tile once its own config bits are counted | 77 to 78 % |
| Sparse variant without length-4 and length-6 wires | 19 % smaller; routes the same four protocol designs as the stock fabric at up to 83 % utilisation |
| Hardened blocks as tiles | about 20K um2 of through-routing per tile regardless of content; about 160 um2 per extra block port |
| Stock tile through place and route | routes with zero DRC violations at 77 % utilisation; die 72K to 84K um2; worst path about 32 ns at the typical corner before timing optimisation |

## Reproducing

Each measurement directory has a `NOTES.md` with the exact tool versions,
commits, commands and the reading of the results. The scripts expect
`yosys` on the path and the IHP sg13g2 liberty file from IHP-Open-PDK; the
FABulous scripts additionally expect a project-local install of the
`fabulous-fpga` package and, for place and route, the LibreLane container.
The fpga_pio sources and the PDK are not vendored; the notes name the
commits used.

## Licence

Notes and scripts: MIT. The two shift-register variants under
`measurements/pio-area/variants/` are derived from fpga_pio and keep its
BSD-2-Clause header. `measurements/fabulous/synth/models_pack_onelatch.v` is
derived from FABulous's Apache-2.0 `models_pack.v` with one module replaced.
`measurements/fabulous/yosys-fabulous-0.60/` holds the FABulous technology
files from the Yosys repository at tag v0.60, ISC licence, vendored because
later Yosys releases no longer ship them.
