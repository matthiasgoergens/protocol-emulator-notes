# Loading the bench on a Kria KV260 (Kria Ubuntu 22.04)

These are the commands used for the board run of 2026-11-08 (`../results/board-2026-11-08/`). The board ran Kria Ubuntu 22.04.4 (kernel 5.15, dfx-mgr 2023.1, `xmutil` 1.2, Python 3.10). The bench is loaded as a Kria app named `chiptop-bench`.

| File | What |
|---|---|
| `chiptop-bench.dtsi` | Device-tree overlay. Its target is `fpga-full` (this image's). It sets `pl_clk0` to 100 MHz, from which `../vivado/build.tcl`'s MMCM makes the 60 MHz bench clock, and the M_AXI_HPM0_FPD width to 32 bit. The comments say why |
| `shell.json` | dfx-mgr's app description: `XRT_FLAT`, one slot |
| `bit.bif` | `bootgen` input that turns the bitstream into the `.bit.bin` the FPGA manager loads |
| `guard.py` | Runs a host script only when `xmutil listapps` shows `chiptop-bench` as the one active app, the overlay names its bitstream, `fpga0` is operating, and the bitstream is installed. `../host/kv260_run.py` maps 0xA0000000 without checking which design is loaded, and a read of an address the loaded design does not answer can hang the board |

## On the build machine

```
vivado -mode batch -source vivado/build.tcl -tclargs build I2C_INTERNAL   # in prototypes/fpga-kv260
cp build/kv260_bench.runs/impl_1/kv260_top.bit kria/chiptop-bench.bit
cd kria && bootgen -image bit.bif -arch zynqmp -process_bitstream bin -w on   # -> chiptop-bench.bit.bin
```

`I2C_INTERNAL` resolves the open-drain I2C lines inside the FPGA, as `../sim/tb_bench.v` does. Without it, the pins come from the Pmod pads, and with nothing attached, the internal pull-ups alone make the log differ from the simulation (`../results/board-2026-11-08/README.md`).

## On the board

Copy `chiptop-bench.bit.bin`, `chiptop-bench.dtsi` and `shell.json` to a directory on the board, and `guard.py`, `../host/kv260_run.py`, `../host/check.py`, `ds.ops`, `ds.meta` and the simulation's `sim-ds.*` to another. Then:

```
dtc -q -@ -I dts -O dtb -o chiptop-bench.dtbo chiptop-bench.dtsi
sudo mkdir -p /lib/firmware/xilinx/chiptop-bench
sudo cp chiptop-bench.bit.bin chiptop-bench.dtbo shell.json /lib/firmware/xilinx/chiptop-bench/

sudo fpgautil -R                    # only if a bitstream was loaded with fpgautil
sudo xmutil unloadapp               # "-1 (Error)" is expected when no app is loaded
sudo xmutil loadapp chiptop-bench   # "chiptop-bench: loaded to slot 0"
sudo xmutil listapps                # chiptop-bench must be the one row whose Active_slot is not -1

sudo python3 guard.py -- kv260_run.py ds.ops board-ds --repeat 10
diff sim-ds.trace board-ds.trace && diff sim-ds.samples board-ds.samples
python3 check.py ds.meta board-ds

sudo xmutil unloadapp               # "0 (Ok)"
```

Run one command at a time, and stop at the first error. While the app is loaded, the fan runs at full speed (`../rtl/kv260_top.v` holds it on).
