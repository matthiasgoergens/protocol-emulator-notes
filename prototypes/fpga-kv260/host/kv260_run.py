#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Run frames on the KV260 test bench, from the board's own Linux (as root, for /dev/mem).

    kv260_run.py FRAMES OUT_PREFIX [--base 0xA0000000] [--repeat N]

Does what sim/tb_bench.v does in simulation and writes the same files: OUT_PREFIX.info,
.samples and .trace. So `diff` against a simulation of the same frames compares the board with
the simulation clock for clock, and host/check.py judges either.

Before the run it checks the bench's identifier and measures the chip clock with the bench's
free-running counter; it stops if the clock is not 60 MHz within 1 %, since a wrong or stopped
PL clock is the likeliest first-bring-up fault. With --repeat N it runs N times and stops at the
first run whose files differ from the first: the run is fixed clock by clock, so they should not.

Python standard library only. --base is where the block design put kv260_core (build.tcl prints
it; M_AXI_HPM0_FPD's window starts at 0xA0000000).
"""
import argparse
import ctypes
import mmap
import os
import sys
import time

ID = 0x46423031


class Bench:
    def __init__(self, base):
        fd = os.open("/dev/mem", os.O_RDWR | os.O_SYNC)
        self.mm = mmap.mmap(fd, 4096, mmap.MAP_SHARED, mmap.PROT_READ | mmap.PROT_WRITE, offset=base)
        os.close(fd)

    def rd(self, off):
        # one 32-bit load: some registers advance an address when read
        return ctypes.c_uint32.from_buffer(self.mm, off).value

    def wr(self, off, v):
        ctypes.c_uint32.from_buffer(self.mm, off).value = v & 0xFFFFFFFF


def clock_mhz(b, seconds=0.5):
    t0, c0 = time.monotonic(), b.rd(0x1C)
    time.sleep(seconds)
    t1, c1 = time.monotonic(), b.rd(0x1C)
    return ((c1 - c0) & 0xFFFFFFFF) / (t1 - t0) / 1e6


def run(b, frames, prefix):
    b.wr(0x04, 2)                                 # stop: idle, chip in reset
    b.wr(0x10, 0)
    for w in frames:
        b.wr(0x14, w)
    if b.rd(0x10) != len(frames):
        sys.exit(f"frame memory: FRAME_ADDR {b.rd(0x10)} after {len(frames)} frames")
    b.wr(0x04, 1)
    t0 = time.monotonic()
    while b.rd(0x04) & 1:
        if time.monotonic() - t0 > 60:
            sys.exit("run did not finish in 60 s")
        time.sleep(0.001)
    status, played = b.rd(0x04), b.rd(0x18)
    with open(prefix + ".info", "w") as f:
        f.write(f"status {status}\nclocks {played}\n")
    n = b.rd(0x20)
    b.wr(0x24, 0)
    with open(prefix + ".samples", "w") as f:
        for _ in range(n):
            f.write(f"{b.rd(0x28) & 0xF:01x}\n")
    v = b.rd(0x2C)
    n = v & 0x7FFFFFFF
    b.wr(0x30, 0)
    with open(prefix + ".trace", "w") as f:
        for _ in range(n):
            w0, w1, w2 = b.rd(0x34), b.rd(0x38), b.rd(0x3C)
            f.write(f"{w0} {w1:08x} {w2:08x}\n")
    return status, played, n


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("frames")
    ap.add_argument("prefix")
    ap.add_argument("--base", type=lambda s: int(s, 0), default=0xA0000000)
    ap.add_argument("--repeat", type=int, default=1)
    a = ap.parse_args()
    frames = []
    for line in open(a.frames):
        w = int(line, 16)
        frames.append(w)
        if w == 0:
            break
    else:
        sys.exit("no end frame")
    b = Bench(a.base)
    if b.rd(0x00) != ID:
        sys.exit(f"identifier {b.rd(0x00):#010x} at {a.base:#x}, want {ID:#010x}: wrong --base, or the bitstream is not loaded")
    mhz = clock_mhz(b)
    print(f"chip clock: {mhz:.3f} MHz")
    if abs(mhz - 60) > 0.6:
        sys.exit("the chip clock is not 60 MHz: check pl_clk0 (it is set by the device tree overlay when the bitstream is loaded)")
    first = None
    for k in range(a.repeat):
        prefix = a.prefix if k == 0 else f"{a.prefix}.rep{k}"
        status, played, n = run(b, frames, prefix)
        print(f"run {k}: status {status}, {played} clocks, {n} trace entries -> {prefix}.*")
        files = [open(prefix + s).read() for s in (".info", ".samples", ".trace")]
        if first is None:
            first = files
        elif files != first:
            sys.exit(f"run {k} differs from run 0")
    if a.repeat > 1:
        print(f"all {a.repeat} runs identical")


if __name__ == "__main__":
    main()
