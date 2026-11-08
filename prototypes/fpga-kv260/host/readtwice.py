#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Read the bench's stored trace three times, without a new run, and compare (8 Nov 2026).
Tells a readout fault (the readouts differ) from a recording fault (they agree). Read-only
except TRACE_ADDR. Run through ../kria/guard.py (sudo python3 guard.py -- readtwice.py)."""
import ctypes, mmap, os
fd = os.open("/dev/mem", os.O_RDWR | os.O_SYNC)
mm = mmap.mmap(fd, 4096, mmap.MAP_SHARED, mmap.PROT_READ | mmap.PROT_WRITE, offset=0xA0000000)
os.close(fd)
rd = lambda o: ctypes.c_uint32.from_buffer(mm, o).value
def wr(o, v): ctypes.c_uint32.from_buffer(mm, o).value = v
assert rd(0x00) == 0x46423031, hex(rd(0x00))
n = rd(0x2C) & 0x7FFFFFFF
print("status", rd(0x04), "clocks", rd(0x18), "entries", n)
def dump():
    wr(0x30, 0)
    out, skips = [], []
    for i in range(n):
        e = (rd(0x34), rd(0x38), rd(0x3C))
        a = rd(0x30)
        if a != i + 1: skips.append((i, a))
        out.append(e)
    return out, skips
reads = [dump() for _ in range(3)]
for k, (d, s) in enumerate(reads):
    zeros = [i for i, e in enumerate(d) if e == (0, 0, 0)]
    nonmono = [i for i in range(1, n) if d[i][0] <= d[i - 1][0]]
    print(f"readout {k}: zero entries at {zeros[:8]}, clock not increasing at {nonmono[:8]}, TRACE_ADDR off at {s[:5]}")
for k in (1, 2):
    diff = [i for i in range(n) if reads[k][0][i] != reads[0][0][i]]
    print(f"readout {k} vs 0: {len(diff)} entries differ, first {diff[:8]}")
