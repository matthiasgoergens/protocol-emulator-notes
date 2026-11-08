#!/usr/bin/env python3
"""Run kv260_run.py only when the chiptop-bench app is the one loaded. Fails closed.

    sudo python3 guard.py -- KV260_RUN.PY [its arguments...]

kv260_run.py maps 0xA0000000 through /dev/mem without checking which design is in the fabric.
A read of a fabric address that the loaded design does not answer can hang a Zynq MPSoC's bus
(josusanmartin/wirelingo's fpga/kv260/host/fabric_guard.py describes such a freeze on a
KV260; the idea of checking the loaded app first is theirs, this code is ours), so every check below must pass first.
None of them touches a fabric address:

1. `xmutil listapps` exits 0 and prints its table: a header line starting with "Accelerator",
   then rows. Exactly one row is active (its last field is not "-1"), and that row is APP. Any
   other line, an error message included, refuses.
2. The overlay's firmware-name (fpga-full on Kria Ubuntu 22.04, else fpga-region) is APP.bit.bin.
3. /sys/class/fpga_manager/fpga0/state is "operating".
4. /lib/firmware/xilinx/APP/APP.bit.bin exists.

Written 2026-11-08 for the board run in ../results/board-2026-11-08/; Python standard library only.
SPDX-License-Identifier: Apache-2.0
"""
import os
import pathlib
import subprocess
import sys

APP = "chiptop-bench"


def refuse(why):
    sys.exit(f"guard: REFUSED, nothing was mapped: {why}")


def text(path):
    try:
        return pathlib.Path(path).read_bytes().replace(b"\0", b"").decode(errors="replace").strip()
    except OSError:
        return None


def check():
    try:
        r = subprocess.run(["xmutil", "listapps"], capture_output=True, text=True, timeout=30)
    except (OSError, subprocess.TimeoutExpired) as e:
        refuse(f"`xmutil listapps` did not run ({e})")
    if r.returncode:
        refuse(f"`xmutil listapps` failed with status {r.returncode}: {r.stderr.strip()}")
    lines = [l for l in r.stdout.splitlines() if l.strip()]
    if not lines or lines[0].split()[0] != "Accelerator":
        refuse(f"`xmutil listapps` printed no table header: {r.stdout.strip()[:200]!r}")
    rows = [l.split() for l in lines[1:]]
    for t in rows:
        if len(t) < 5 or not (t[-1] == "-1" or t[-1].rstrip(",").isdigit() or "->" in t[-1]):
            refuse(f"`xmutil listapps` printed a line that is not a table row: {' '.join(t)!r}")
    active = [t[0] for t in rows if t[-1] != "-1"]
    if active != [APP]:
        refuse(f"active apps are {active}, want exactly [{APP!r}]")
    for node in ("/proc/device-tree/fpga-full/firmware-name", "/proc/device-tree/fpga-region/firmware-name"):
        name = text(node)
        if name is not None:
            break
    if name != APP + ".bit.bin":
        refuse(f"overlay firmware-name is {name!r}, want {APP + '.bit.bin'!r}")
    state = text("/sys/class/fpga_manager/fpga0/state")
    if state != "operating":
        refuse(f"fpga0 state is {state!r}, want 'operating'")
    if not pathlib.Path(f"/lib/firmware/xilinx/{APP}/{APP}.bit.bin").is_file():
        refuse(f"/lib/firmware/xilinx/{APP}/{APP}.bit.bin is missing")


def main():
    args = sys.argv[1:]
    if args[:1] == ["--"]:
        args = args[1:]
    if not args:
        sys.exit(__doc__)
    check()
    print(f"guard: {APP} is the loaded app; running {' '.join(args)}", flush=True)
    os.execvp(sys.executable, [sys.executable, "-I"] + args)


if __name__ == "__main__":
    main()
