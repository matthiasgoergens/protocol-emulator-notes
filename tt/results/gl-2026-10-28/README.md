# Gate-level test of the hardened 4-PE chip with the bit-path assists, 2026-10-28

The chip's cocotb test (`tt/test/test_chip.py`, two tests) at RTL and on the hardened netlist.

- Netlist: `tt_submission/tt_um_chip_top.v` of the 2026-10-10 harden (`/var/tmp/tt-harden/assists-pe4`,
  chip at 395f566), sha256 28331400a56c4487d77734516aa62d0c1973a1066d349ee5faa30643c6b2a00e,
  166,265 lines, 75,454 cell instances; copied to `tt/test/gate_level_netlist.v` (not committed).
- Test bench and sources: master at febf60a. PDK: the cmos5l copy the harden used
  (`PDK_ROOT=/var/tmp/roundtrip-cmos5l/pdk`). Icarus Verilog, cocotb 2.0.1, Python 3.12.
- Command, in `tt/test`: `uv run --no-project --python 3.12 --with-requirements requirements.txt make`
  then the same with `GATES=yes`.

| run | result | file |
|---|---|---|
| RTL | 2 of 2 pass | `rtl.txt` |
| gate level | 2 of 2 pass | `gl.txt` |
| gate level, control: the netlist's `uo_out[0]` tied to 0 | `test_programme_drives_pins` fails (`pins 0xa4`, expected 0xa5); the other passes | `gl-planted-uo0.txt` |

The harness survives gate level: it touches only the top-level ports, and the control shows the
gate-level run simulates the netlist. **What it does not show**: the test is thin (register read-back
and one programme driving the pins), with zero-delay cells and no SDF timing. The protocols, the PE
array and the assists are not exercised at gate level here.
