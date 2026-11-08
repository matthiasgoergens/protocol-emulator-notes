# First board run on a KV260, 2026-11-08

This answers issue #1. The bench is `prototypes/fpga-kv260` at `8db03c9`, with the changes on this branch. The board is a KV260 starter kit running Kria Ubuntu 22.04.4, and the build used Vivado 2026.1.

**Result.** The chip as submitted (`tt_um_chip_top`) runs on the KV260 at 60.017 MHz. With the I2C lines resolved inside the FPGA (`I2C_INTERNAL`), the board's log and samples are **byte-identical to the simulation's** in **10 of 10 runs**, and `check.py` passes. With the I2C lines on the Pmod pads, the log differs. The internal pull-ups make the lines slow, and that slow, asynchronous edge also reaches the recorder unsynchronised. Neither effect is in the chip (see "The first run" below).

## Issue #1, item by item

| | Asked for in issue #1 | Result |
|---|---|---|
| ✅ | Use the bundle's `chip_tt.v` at 8db03c9 | We generated it with `run_sim.sh` at 8db03c9 (OCaml 5.3.0, Hardcaml v0.17.1, Icarus 14.0 devel). It is **byte-identical** to the release `kv260-bundle-8db03c9`, and so are `ds.ops`, `ds.meta`, `sim-ds.*` and `check-sim-ds.txt` (`bundle-compare.txt`). So the board ran exactly the bundle's chip and frames |
| ✅ | Run `vivado/build.tcl` | Ran. Three changes were needed (below; `vivado/build-printouts.txt`) |
| ✅ | Report the actual `pl_clk0` frequency | **58.822941 MHz** when asked for 60, outside `kv260_run.py`'s 1 %. Now `pl_clk0` is 99.999001 MHz and an MMCM makes **60.011954 MHz** |
| ✅ | Report the bench's address | **0xA0000000**, 4 KiB: `--base` not needed |
| ✅ | Report the worst setup and hold slack | **+2.433 / +0.017 ns**, all constraints met. With `I2C_INTERNAL`: +2.518 / +0.018 ns. 0 critical warnings in synthesis and implementation (`vivado/timing-summary.txt`) |
| ✅ | Report what `methodology.rpt` says about clocks | Only **CLKC-56** (advisory: the MMCM has no LOC). With `I2C_INTERNAL`, also HPDR-1 ×2, because Pmod 7 and 8 are then only driven (`vivado/methodology-summary.txt`) |
| ✅ | Report how Vivado treats `assign _516 = ~ clk;` | **Folded into the flip-flops.** 56 registers have `IS_C_INVERTED = 1`: the 56 falling-edge flops Yosys predicted. Net `_516` is driven by the MMCM's BUFGCE, and **no clock net is driven by a LUT** (`vivado/inverted-clock.txt`, from `vivado/query_inverted_clock.tcl` on the routed design) |
| ✅ | Load with a device-tree overlay | Written and used: `../../kria/` (overlay, `shell.json`, `bootgen` recipe, a guard, and the exact commands) |
| ✅ | `kv260_run.py ds.ops board-ds --repeat 10` | Chip clock **60.017 MHz**. `I2C_INTERNAL`: **all 10 runs identical**, each with status 2, 10,753 clocks and 2,269 entries (`i2c-internal/`). Pads: run 1 differs from run 0 (`pads/`) |
| ✅ | `diff sim-ds.trace board-ds.trace` | `I2C_INTERNAL`: **no difference**, in all 10 runs (`i2c-internal/all-runs.md5`). Pads: first difference at trace line 2110, sim `4602 00000404 01430080`, board `4602 00000404 01030080` (`pads/diff-head.txt`) |
| ✅ | `diff sim-ds.samples board-ds.samples` | **No difference**, in both builds |
| ✅ | `check.py ds.meta board-ds` | `I2C_INTERNAL`: **PASS**. UART 0x4f 0x4b 0x21 at clocks 4580, 5220 and 5860, with all 20 edges on the 64-clock grid; SPI 0xa5 0x3c; I2C 0xa0-nak 0x5a-nak, STOP; host 0x01 0x01. Pads: FAIL (`pads/check.txt`, explained below) |
| ✅ | Leave Pmod 7, 8 and 9 unconnected | Nothing was attached. The pads run fits that: the lines rose only on the internal pull-ups, and no I2C byte was acknowledged |
| ⬜ | Pmod 10 toggling every 0.5 s | Not observed: we work on the board remotely (see below). The clock was measured instead, by `kv260_run.py`'s counter: 60.017 MHz |
| ⬜ | Check the Pmod pin mapping against the carrier schematic | Not against the schematic. The same package pins are used in josusanmartin/wirelingo's KV260 constraints, which cite AMD's `kv260_bist` platform. Nothing was wired, so nothing was at risk |
| ⬜ | I2C EEPROM at 0x50 (Fast-mode Plus) with 2.2 kΩ pull-ups, `check.py --i2c-device` | Not possible for now: it needs parts wired to the board, and we are remote from it. A virtual alternative is below. Before a real device, see "Recommendation" |
| ⬜ | Logic analyser on Pmod 1–4 | Not possible for now, for the same reason. Virtual alternatives are below |

**Why four items are open.** We run the KV260 remotely, over the network, with nobody at the board. So for now we can't wire anything to the Pmod connector or watch a pin. The tests above that need hands at the board stay open. Instead, we are looking at ways to test the same things virtually (next section).

## Remote-only alternatives for the open items (proposed, not done)

| Open item | Virtual alternative | What it would and wouldn't show |
|---|---|---|
| Pmod 10 blink | Read the pad back. Give the heartbeat pin (and Pmod 1–4) an input buffer, and expose the levels the pads actually carry in a bench register. The host then sees pin 10 toggle every 0.5 s | That the pad drivers really toggle at the pins, which the counter alone doesn't show. Not what is on the wire outside the FPGA |
| I2C device at 0x50 | **An I2C target inside the FPGA** on the internally resolved bus (`I2C_INTERNAL`). This could be a small EEPROM model, or the chip's own I2C target role on a second thread. Then `check.py --i2c-device` should see both bytes acknowledged and 0x00 0x00 from HOSTOUT, as `demos.exe ds` does with its modelled device | That the chip handles a device that answers and stretches the clock, on real hardware at speed. Not real pull-ups, rise times or a third-party device's timing |
| Logic analyser on Pmod 1–4 | The bench's recorder is already an in-fabric logic analyser: it logs every pin change clock by clock. For an **independent** decode, run the board's trace through sigrok's decoders (`tools/sigrok-judge`), and add the pad read-back above | That a decoder written by someone else agrees with the board's pins, and that the levels reach the pads. Not the analogue signal on the wire |

Once someone can be at the board, the original items still apply. The `I2C_INTERNAL` build makes no difference to them: the pads show the chip's drive either way.

## The three build changes (`../../vivado/build.tcl`)

1. **Clock.** The PS makes 58.822941 MHz when asked for 60 (its PLL divided by 17). Now `pl_clk0` runs at 100 MHz, and an MMCM (`clk_wiz_0`) makes 60.011954 MHz. The PS's `maxihpm0_fpd_aclk`, the SmartConnect and `kv260_core` all run on that clock, so the bench is still one clock domain. They are wired by hand rather than by the AXI automation, so that nothing lands on `pl_clk0`.
2. **Verilog.** Vivado reads all sources as one compilation unit. The `` `default_nettype none `` of the files before `chip_tt.v` reaches it, and the generated ports, which have no net type, fail ([Synth 8-6735], [Synth 8-9844]). `build.tcl` now reads a copy of `chip_tt.v` with `` `default_nettype wire `` first. `tt/src/chip_tt.v` itself is unchanged.
3. **MMCM input frequency.** Set by hand to 99.999, it failed validation against the PS's 99.999001 MHz (FREQ_HZ 99999000 vs 99999001, [BD 41-238]). It now propagates from the PS.

`build.tcl` also takes optional Verilog defines after OUT_DIR, for example `I2C_INTERNAL`.

Resources: 5,131 LUTs, 3,662 flip-flops, 56 of 144 block-RAM tiles, 1 MMCM, 9 I/O pins (`vivado/utilization-summary.txt`).

## The first run: I2C pins on the Pmod pads

The log differed from the simulation, and run 1 differed from run 0: 2,292 and 2,293 entries, against 2,269. There are two effects, both on the I2C pads.

1. **Slow lines.** Only the internal pull-ups hold up the open-drain lines. After the chip released a line, it read high **18–50 clocks later for SCL (median 19, about 320 ns) and 41 clocks later for SDA (about 680 ns)**. In `tb_bench.v` it reads high at once. At the demo's roughly 1 MHz bus, that changes what the I2C thread does: `uio_in[7:6]` differ from clock 4,602 on, and `uio_oe[7:6]` from 4,658.
2. **Corrupt log entries.** `uio67_in` goes from the pad, with no synchroniser, into the recorder's change detector and into the 96-bit-wide trace RAM, which spans about 50 BRAM tiles. Where SCL crosses the threshold slowly, a few entries were written wrong:
   - two were all zero, after clock 5,046 in both runs and after 5,810 in run 0;
   - two were stale in run 1, left over from run 0, so they look like repeats;
   - one was partly written: run 0 at clock 6,227 lost the byte `uo_out` second half.

   Three readouts of the same stored trace were identical, and TRACE_ADDR advanced exactly once per entry (`pads/readtwice.txt`, from `../../host/readtwice.py`). So the fault is in recording, not in reading. `check.py`'s "21,609 clocks" and its garbled UART come from these entries: a zero entry sends the timeline back to clock 0.

**With those entries dropped**, run 1 equals the simulation clock for clock on every signal except `uio_in[7:6]` and `uio_oe[7:6]`. That covers the UART pin, the SPI pins, `uo_out[7:4]`, the host link in both directions, `ui_in` and `rst_n`. Run 0 is the same apart from the partly written entry.

So **`I2C_INTERNAL`** (`../../rtl/kv260_top.v`) has the chip read the lines as `tb_bench.v` resolves them, `~(oe & ~out)`, while the pads still show the chip's drive for a logic analyser. That is the build that gave the 10 identical runs.

## Recommendation (not done here)

For a run against a real I2C device on the pads:
- use real pull-ups, as the README says;
- **pass `uio67_in` through a two-flop synchroniser before the recorder**. The chip has its own synchronisers; the recorder doesn't. Otherwise a slow or asynchronous edge can corrupt the log again.

The board log will then differ from the simulation on the I2C pins, as the README expects. Only `check.py --i2c-device` judges that run.

## What this run does not show

- Anything about IHP's 130 nm cells, the pads, the SRAM macros (block RAM stands in for them) or the quarter-clock grid on silicon.
- A real I2C device: the bus was resolved inside the FPGA, nothing answered, and the bytes went unacknowledged, as in the simulation.
- Anything outside the FPGA: we are remote from the board, so no pin was watched or wired.
- Demos other than `ds`.

## Board notes

- **The overlay's `config-afi` persists.** It sets the PS's AFI_FS register (HPM0/1 width), and the register keeps its value after `xmutil unloadapp`. On our shared board, the next design expected 128 bit and timed out until its own overlay set `<14 0xa00>`.
- **Run times.** Both runs took a few minutes of board time, 12:53–13:00 and 13:06–13:08 UTC.
