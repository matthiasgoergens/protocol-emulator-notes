# The chip on a KV260: an FPGA test bench

This directory puts the chip as submitted to Tiny Tapeout (`tt_um_chip_top`, built from
`../chip-top`) on an AMD Kria KV260. The board's ARM processor plays the host's part, the role the
RP2040 has on Tiny Tapeout's demo board. Everything that can be checked without the board has
been, in simulation, and the steps that need the board are marked **not yet run**.

`../fpga-ulx3s` is an earlier test bench for a different board (Lattice ECP5, open tools). It
carries an older sequencer, not the chip.

## How a run works

The processor never drives the chip's pins in real time. It loads a list of **frames** into the
FPGA and sets start. A frame says what the host drives on the host link (the four data lines
`uio[3:0]`, the strobe `uio[4]`, the read request `uio[5]`) and on `ui_in`, and for how many clocks.
A small **player** in the FPGA then plays the frames, clock by clock, after holding the chip in
reset for a fixed number of clocks. A **recorder** logs every change of the chip's pads with its
clock number. Because the outputs change on both clock edges, each output is logged once for each
half of the clock. The processor reads the log back when the run is done.

The frames come from the same host model that the simulations use (`../chip-top/src/host.ml`), via
`../chip-top/bin/fpga_ops.exe`. A run on the board is therefore fixed clock by clock, and should
record exactly what a simulation of the same frames records. A difference between the two is a
finding: a wrong clock, a timing failure on the FPGA, or an FPGA mapping that differs from the
simulated logic. On its own, the recorded log can also be judged by decoding it (`host/check.py`).

The first demo is the UART, SPI and I2C demo of `../chip-top/bin/demos.exe ds`. The host loads the
earlier sequencer's firmware into the programme store, sets the pins and starts the sequencer.
The chip then sends "OK!" on the UART, 0xa5 0x3c on SPI, and 0xa0 0x5a on I2C. After that the host
drains what the I2C controller reported.

## Files

| file | what |
|---|---|
| `rtl/fpga_bench.v` | board-independent: the chip, the player, the recorder, the register map (in its header comment) |
| `rtl/sram_fpga.v` | stand-ins for IHP's two SRAM macros, under the macros' names, as block RAM |
| `rtl/fpga_axil.v` | AXI4-Lite port for the register map |
| `rtl/kv260_core.v` | the two above; the module that goes into the Vivado block design |
| `rtl/kv260_top.v`, `constraints/kv260.xdc` | the Pmod pins and the fan |
| `vivado/build.tcl` | project, block design (Zynq processor system, `pl_clk0` at 60 MHz), bitstream. **Not yet run** |
| `host/kv260_run.py` | runs frames on the board from its Linux and writes the log. **Not yet run** |
| `host/check.py` | judges a log of the demo, from the board or from simulation |
| `sim/tb_bench.v` | simulation of the whole bench driven through its AXI port, as the processor drives it |
| `sim/tb_sram_equiv.v` | the SRAM stand-ins against IHP's behavioural model |
| `run_sim.sh` | all the checks below that need no board |
| `make_bundle.sh` | packs the generated chip Verilog, the frames and the simulated run for whoever has the board |

## What has been checked here (`./run_sim.sh`, 2026-11-08)

- **The SRAM stand-ins** match IHP's behavioural model (IHP-Open-PDK,
  `RM_IHPSG13_1P_core_behavioral_bm_bist.v`) over 200,000 random clocks with both memories, two
  thirds of them reads, writes often read back at once: 0 differences. Only the case the chip uses
  is modelled (`chip_tt.v` ties the bit mask to all ones and the enables to 1), and a simulation
  stops if those ties change. A read-first stand-in fails this check (110,970 differences).
- **The demo through the simulated bench**: 2,131 frames loaded through the AXI port, 10,753 clocks
  played (the number the exporter computed), and `host/check.py` decodes the right output:
  UART 0x4f 0x4b 0x21 with every edge on the 64-clock bit grid, SPI 0xa5 0x3c, and I2C 0xa0 0x5a
  each without an acknowledge (nothing is on the bus), followed by a STOP. The host read back
  0x01 0x01 from HOSTOUT, the controller's "not acknowledged" report for each byte. With a
  modelled I2C device, `demos.exe ds` gets 0x00 0x00 instead.
- **The checks catch faults**: a stand-in with one more clock of read latency makes every decode
  fail, and the checker fails when told to expect an I2C device. The demo alone does not tell a
  read-first memory from a write-through one (the trace was identical), which is why the
  equivalence check exists.
- **Synthesis for UltraScale+ with Yosys** (`synth_xilinx -family xcup`): the chip's memories map
  to 2 RAMB18E2, the frame memory and log to 60 RAMB36E2 (the KV260's K26 has 144), no latches,
  and `check -assert` passes. The 56 flops clocked on the falling edge are the output stage's
  second edge and the recorder's half-clock capture. This is not Vivado: its timing and its
  handling of the inverted clock are the board run's first questions.

## What a board run adds, and what it cannot

It adds the whole digital design at its real clock rate, synthesised by a second tool, with real
pins on the Pmod connector, a real I2C device if one is attached, and the log checked against the
simulation for every clock.

It cannot show anything about the chip's process: timing on IHP's 130 nm cells, the area, the
analogue parts, or where the half-clock edges land on silicon. It also does not exercise the
quarter-clock grid beyond what the both-edges output stage does.

## Running it on the board

1. **Get the chip's Verilog.** `tt/src/chip_tt.v` is generated from `../chip-top`'s Hardcaml and
   is never committed. Either run `../../tt/scripts/regen_chip.sh` (needs OCaml), or take it from
   a bundle made by `make_bundle.sh` for the same commit.
2. **Build.** `vivado -mode batch -source vivado/build.tcl -tclargs build` needs the KV260 board
   files from XHub. It prints the actual `pl_clk0` frequency, the address of `kv260_core`, and the
   worst setup and hold slack. Expect to fix details on the first run.
3. **Load.** On the KV260's Linux the bitstream is loaded together with a device-tree overlay.
   The overlay is also what starts `pl_clk0` at its set frequency: one report says the PL clocks
   do not run when a bitstream is loaded over JTAG alone. AMD's flow generates the overlay from
   the `.xsa` that `build.tcl` writes.
4. **First check: the clock.** `host/kv260_run.py` measures the chip clock with the bench's
   free-running counter and stops unless it is 60 MHz within 1 %. Pmod pin 10 toggles every
   0.5 s at 60 MHz, which an LED or a meter can see.
5. **Run and compare:**
   ```
   sudo python3 host/kv260_run.py ds.ops board-ds --repeat 10
   diff sim-ds.trace board-ds.trace && diff sim-ds.samples board-ds.samples
   python3 host/check.py ds.meta board-ds
   ```
   `--repeat 10` also checks that ten runs record the same log.
6. **With a real I2C device.** Put a device at address 0x50 (for example a 24C-series EEPROM)
   on Pmod pins 7 (SDA) and 8 (SCL), with pull-ups of about 2.2 kohm to 3.3 V. The demo's bus
   runs near 1 MHz at a 60 MHz chip clock, so the device must support Fast-mode Plus. Then
   `check.py ... --i2c-device` expects both bytes acknowledged and 0x00 0x00 from HOSTOUT. The log
   then differs from the simulation on the I2C pins, as it should.

A logic analyser on Pmod pins 1 to 4 (UART, SPI clock, data and select) shows the same bytes
independently.

## Frames

One 32-bit word each, in hex, one per line; the full layout is in `rtl/fpga_bench.v` and
`../chip-top/bin/fpga_ops.ml`. Bits 15:0 hold the number of clocks (0 ends the run), then the data
lines, whether the host drives them, the strobe, the read request, a flag for sampling the data
lines, and `ui_in`. A demo with an outside world that reacts (an I2C device, a SPI target) needs
that world either on the Pmod pins or in the FPGA. Only fixed levels on `ui_in` can come from
the frames.
