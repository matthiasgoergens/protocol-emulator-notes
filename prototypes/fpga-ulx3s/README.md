# FPGA test bench on the ULX3S (ECP5-85F), ready before the board

Jane Street's post suggests testing RTL on an FPGA before the ASIC flow. This directory is that
test bench, prepared so that bring-up is flashing and running: a top level for the ULX3S, a
bitstream built with the open toolchain, a host runner, and a checker. The runner and checker
have already passed end to end against a Verilator model of the same RTL. The bring-up steps are
in `BRINGUP.md`.

## What is on the FPGA

- **The deadline sequencer** (`../deadline-sequencer`, Hardcaml-generated Verilog, symlinked in
  `rtl/gen/`), with its 256 x 16 instruction memory in block RAM. The memory has a one-cycle
  synchronous read, the same contract as the SRAM macro it stands in for. The eight sequencer pins
  are on header pins GP0 to GP7, bidirectional, with the pads' weak pull-ups.
- **The pin streamer and pin sampler** (`../pin-streamer`, `../pin-sampler`). The streamer drives
  GN0 to GN3 from a 64-word buffer that the host preloads; the sampler reads GN4 to GN7 into a
  256-word capture. An internal loop joins them without wires.
- **The USB full-speed device** (`../usb-fs-device`) on its own 48 MHz clock, on the US2
  connector. US2's D+ and D- reach FPGA pins through 27 ohm resistors, and a switchable pull-up
  (1.1 k and a diode, per `usb.sch`) signals a full-speed device.
- **Routes to on-board parts**, selected by a control register. Sequencer pins 1, 2, 3 and 6 can
  go to the configuration flash (its clock only through the `USRMCLK` primitive), and pins 4 and
  5 to the I2C bus of the on-board RTC. With those routes, a bare board already has a real SPI
  device and a real I2C device to test against.
- **`rtl/emu_core.v`**, the board-independent glue: the UART host link and command engine, the
  memories, the routing, and a trace recorder. The recorder logs every change of what the core
  sees (inputs after the two-flop synchroniser) and does (pins, output enables, host bytes), with
  its cycle number: 2,048 entries of 80 bits in block RAM. The same module runs on the board and
  in the simulator, so the simulated runs exercise the real host link and command engine.
- **`rtl/ulx3s_top.v`**, board-specific: the PLL (25 MHz in; 60 MHz and 48 MHz from one
  EHXPLLL), the pads, `USRMCLK`, USB, LEDs, reset on FIRE1. The ESP32 is held in reset
  (`wifi_en` low) so that it cannot drive shared pins.

## Host link: the FTDI serial port, at 1 Mbaud

The ULX3S offers two ways in: the FT231X on US1, and the ESP32. The FT231X is the simpler and
more robust choice:

- it is already the cable that powers and programmes the board;
- it needs no firmware: Linux sees `/dev/ttyUSB0`, and pyserial drives it;
- the rate is exact at both ends. 1,000,000 baud is 3 MHz / 3 in the FT231X's baud generator and
  60 MHz / 60 in the FPGA, so the error is zero (the FT231X goes to 3 Mbaud if more is needed).

The ESP32 path would need its own firmware and network setup, adds latency, and shares GPIOs with
header pins and the SD card. The link carries only programmes, configuration and dumps, so its
speed hardly matters. Every command is acknowledged, and the runner pipelines the 256 instruction
writes and reads them all back before a run.

## Checking a run: replay, prediction, decoders

`host/emu_runner.py` loads a test's programme image, verifies it by readback, sets the routes and
peripheral registers, runs for an exact number of cycles, then dumps the trace and the capture.
`ocaml/fpga_tests.exe check` judges the result three independent ways:

1. **Replay.** The captured inputs of every cycle go through `Isa.step`, the interpreter that is
   the sequencer's executable specification. Its outputs must equal the captured outputs on every
   cycle. This is the lockstep test of `deadline-sequencer/main.ml`, with the FPGA in place of
   Cyclesim. It is exact on the board too, because it uses what the core actually saw.
2. **Prediction.** The interpreter runs free against `ocaml/env.ml`, a model of the board: pads
   and pull-ups, jumpers, the flash, the RTC, and I2C and SPI parts on the header.
   `sim/sim_main.cpp` ports those models statement for statement, so in simulation the whole trace,
   inputs included, must be identical. On the board, the pins and the cycles on which host bytes
   appear must still match. Only `uart_jumper`, where a real wire can move an edge across a clock
   boundary, is excused. Byte values that come from real parts (a flash ID) are left to 1 and 3.
3. **Protocol.** `deadline-sequencer/decoders.ml`, which samples where a receiver would and knows
   nothing of the compiler's arithmetic, must recover the expected bytes from the pins.

The tests (`ocaml/programs.ml`) are the demo's compiled UART, SPI and I2C programmes. Two new
programmes, written in the compiler's style, fill its gaps: a UART receiver (WAITP on the start
edge, then SHI at mid-bit) and an SPI read (SHI while SCLK is high). With them come tests against
the on-board RTC and flash, the host byte path, the streamer and sampler, trace overflow, and three
cheap header parts. `fpga_tests.exe list` prints them all.

## Results

**Build** (`./build.sh`; yosys 0.69+77, nextpnr-0.11.1-30, oss-cad-suite; nextpnr seed 1; logs in
`reports/`):

| | |
| --- | --- |
| Device | LFE5U-85F, CABGA381, speed 6 |
| Flip-flops | 1,706 of 83,640 (2 %) |
| LUT4 and carry (comb) | 2,958 of 83,640 (3 %) |
| Block RAM (DP16KD) | 11 of 208: instruction memory, trace (80 x 2,048), sampler capture |
| Distributed RAM | 30 RAMW |
| I/O | 46 of 365; PLLs 1 of 4; USRMCLK 1 |
| 60 MHz domain | fmax 68.27 MHz, **passes at 60 MHz** with 2.0 ns slack |
| 48 MHz domain (USB) | fmax 90.02 MHz, **passes at 48 MHz** |
| Bitstream | `bitstream/ulx3s_85f.bit`, 358 KB compressed, sha256 c00e0287... |

The 60 MHz critical path is the instruction fetch: block-RAM clock-to-output (5.83 ns, since the
DP16KD has no output register, as the chip's one-cycle SRAM read requires) into the sequencer's
decode and next-PC logic, about 14.6 ns in all. On the chip the SRAM macro's clock-to-output is far
shorter, so the FPGA is the harsher case here. Both PLL outputs come out exactly at 60.00 and
48.00 MHz: nextpnr recomputes them from the hand-edited dividers (VCO 480 MHz), so it confirms
that arithmetic.

**Simulated end to end** (`uv run host/emu_runner.py --sim --cpb 60 --controls`, with the
board's real UART divider; evidence in `evidence/2026-09-25-sim/`): 16 tests pass, and the 2
negative controls fail as they must. In every test, the trace is identical to the OCaml
prediction on every cycle. The same holds with the fast divider (8 clocks per bit). The controls:

- one output bit flipped in one recorded entry: the replay and the prediction fail;
- a programme one bit different from the one the checker replays (a delay one count longer):
  the replay fails at cycle 73, while both UART decodes and the host bytes still pass. The replay sees what
  protocol-level checks cannot.

Further runs rehearse board behaviour. A simulated board with an ISSI flash, judged in board mode
(`--judge board --sim-flash-id 9D6018`), passes; the same run judged strictly fails, as it should.
An MCP7940N trace judged against the PCF8523 variant of the test fails.

## Protecting the configuration flash

Routing the sequencer to the flash that holds the board's configuration is useful (a real SPI
part on a bare board) and dangerous (a stray erase). There are two guards:

- **In software.** The runner refuses any flash-routed test unless the OCaml model shows that
  every command byte it sends is on the test's allow-list (`flash_id`: 0x9F only).
- **In hardware** (`emu_core.v`, after a review pointed out that the software guard is the only
  one). The first byte after chip select falls must stay a prefix of a read-only command: 0x9F,
  0x03, 0x0B or 0x05. On the first bit that leaves them, the SCLK edge is suppressed and chip
  select forced high, so the flash never receives a complete write, erase or status-write command.
  LED 7 lights when it trips. The simulation-only test `flash_interlock` sends WRITE ENABLE (0x06),
  and the simulated flash must see no complete byte. With the interlock disabled in a mutated
  copy, the same test fails (the flash sees 0x06): `evidence/2026-09-25-sim/interlock-mutant/`.

`USRMCLKTS` is driven from the route bit, not tied to a constant, as Lattice's sysCONFIG guide
asks; it tristates the flash clock while the route is off.

## Four-phase output stage on the ECP5

`prototypes/multiphase` (on master) puts pin edges on a quarter-clock grid. Each pin has four
toggle flip-flops, clocked on 0, 90, 180 and 270 degree phases and XORed onto the pin, plus a
sampler per phase. The ECP5 can prototype this directly:

- **Phases from the PLL.** One EHXPLLL gives four outputs of the same frequency with static
  phase offsets: CPHASE in whole VCO periods, FPHASE in eighths of one. At a 600 MHz VCO and
  60 MHz out, a step is 1.67 ns / 8 = 208 ps, so 90 degrees (4.17 ns) is exact (2 CPHASE +
  4 FPHASE). `rtl/pll_4phase_example.v` is that PLL, generated by `ecppll`. The PLL can also step
  its phase at run time (PHASESEL, PHASEDIR, PHASESTEP), which is how to prototype a shmoo: move
  one edge against another in 208 ps steps.
- **Build variant (`build_multiphase.sh`, `-DEMU_MULTIPHASE`).** Sequencer pins 0 and 1 go through
  the stage. A second EHXPLLL makes the four phases, and the core runs on phase 0. Trial-built
  against master's sequencer and stage, extracted with `git show` (commit in
  `reports/multiphase/`), since this branch predates them. Results: 1,752 flip-flops, 2 PLLs,
  5 global clocks; the core domain meets 60 MHz (67.5 MHz). The quarter-period transfers are
  inside budget: phase 0 to phases 1/2/3 at most 2.58 ns against 4.17 ns, and phases 1/2/3 back
  to phase 0 at most 1.24 ns. nextpnr treats the phases as unrelated clocks, so that budget check
  is by hand, and it does not include skew between the PLL outputs' clock trees.
- **What it will not show faithfully.** The XOR is a LUT, and each lane has its own route to the
  pad, so quarter edges will sit a few hundred picoseconds off the ideal grid.
  The multiphase study found ±400 ps costs little, but only a scope can measure the real figure,
  and it needs at least 350 MHz of bandwidth. An independent on-chip check: loop the pin into an
  ECP5 input gearbox (IDDRX2F, four samples per clock). That gearbox, with ODDRX2F on the output
  side, is also the FPGA-native way to make the same quarter-clock waveform, a second
  implementation to compare the lane-XOR stage against.
- Replay does not cover the variant yet. The trace records the core's clock-grid pins, not
  `pin_sub` or `pin_in4`.

## Limits of the trace

The recorder sees what the core saw and drove. For header pins, "saw" is the pad read back
through its input buffer, so it catches a pin held by something else. For the flash route it
records the core's outputs, not the flash pads, and it sees nothing of USB or of electrical
contention. The cheap logic analyser (BRINGUP.md, step 8) is the independent view. Commands the
host sends while a run is in progress are discarded, except `X` (abort): the runner waits for `g`.

## What the FPGA cannot test

- **IHP sg13g2 timing.** ECP5 timing says nothing about the chip's corners. OpenROAD's STA on
  sg13g2 remains the reference, and the two critical paths even differ (block RAM here, logic
  there).
- **Anything analogue.** The IHP pads (drive, slew, input thresholds); the gain cells (retention,
  decay with temperature, the compiler-scheduled lifetimes); charge pumps; level-shifted bit
  lines; the delay-line DTC and TDC as silicon.
- **Faithful sub-clock behaviour** beyond what the PLL gives. The PLL offers static phases and
  208 ps run-time steps. ECP5 DELAYF elements (128 taps, nominally 25 ps each, uncalibrated and
  varying with process, voltage and temperature) could stand in for a programmable edge delay. None
  of these is the sg13g2 delay line with its 63 ps taps and 3 % mismatch.
- **The SRAM macro itself**: block RAM is the right function, not the right timing, and the
  macro's built-in self-test is absent.
- **The Tiny Tapeout environment**: the mux, the I/O ring, the shared clock pin, the pin count.
- **Silicon variation**: the calibration-by-search and portability experiments exist for that.

## After merging master

- `rtl/gen/deadline_sequencer.v` (a symlink) will then be the sub-slot sequencer, with a new
  `pin_in4` input and a new `pin_sub` output. Old programmes behave identically. The base build's
  `emu_core` leaves `pin_in4` unconnected. Before relying on it, connect it (four copies of each
  pin's sample; the `EMU_MULTIPHASE` branch of `emu_core.v` shows how) and re-run the
  simulated suite.
- `rtl/gen/multiphase_stage.v` is already a symlink to `../multiphase/multiphase_stage.v`, which
  resolves after the merge. `build_multiphase.sh` then needs no `GEN=`.
- `ocaml/isa.ml` is a symlink too. Master's `Isa.step` gains only an optional `?pin_in4`
  argument, and `compiler.ml` and `decoders.ml` are unchanged, so the checker should build as it
  is. Re-run it to confirm.

## Files

| Path | What |
| --- | --- |
| `rtl/emu_core.v` | board-independent core: host link, memories, routing, trace |
| `rtl/ulx3s_top.v`, `constraints/ulx3s.lpf` | ULX3S top and pins (subset of emard/ulx3s `ulx3s_v20.lpf`) |
| `rtl/pll_60_48.v`, `rtl/pll_4phase_example.v` | PLLs |
| `build.sh`, `build_multiphase.sh`, `reports/` | synthesis, place and route, timing, bitstream |
| `sim/sim_main.cpp`, `sim/build.sh` | Verilator board model (C++ port of `ocaml/env.ml`) |
| `ocaml/` | tests, board model, checker (`isa.ml`, `compiler.ml`, `decoders.ml` symlinked) |
| `host/emu_runner.py`, `host/usb_check.py` | runner for board and simulator; USB enumeration and loopback check |
| `BRINGUP.md` | the checklist |
| `evidence/2026-09-25-sim/` | the simulated runs quoted above: 60 and 8 clocks per UART bit, the board-mode rehearsal, the interlock mutation |

## Review

One adversarial review (codex, gpt-luna) of the RTL, constraints and checker before the board
arrives. It changed two things: `USRMCLKTS` now comes from a register, and the flash has a
hardware interlock (both above). Two findings were refuted at source. "The overflow header uses
the entry count as the cycle count": the runner writes the test's cycle count (`write_trace(...,
test["cycles"], ...)`), and the checker stops at the truncation cycle. "Replay is blind between
recorded entries": the recorder compares every cycle with the one before, so a transient change
produces its own entries. Its note that R and K are not refused during a run is true but
harmless, since the command engine ignores every byte but `X` while running. Its I2C pull-up
concern stands, as an open question: the schematic's 4.7 k resistors near the DDC lines go to
+5 V on the HDMI side, and I have not traced which pull-ups are on the RTC's side of the bus.
