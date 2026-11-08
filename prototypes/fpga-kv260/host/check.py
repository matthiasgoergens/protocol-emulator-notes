#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Judge a run of the UART, SPI and I2C demo on the FPGA test bench from its recorded files.

    check.py META PREFIX [--i2c-device]

META is ds.meta from ../chip-top/bin/fpga_ops.exe; PREFIX.info, .trace and .samples come from
kv260_run.py on the board or from sim/tb_bench.v. The trace is decoded on its own (it does not
need a simulation to compare with): the UART bytes on uo_out[0] and their bit timing, the SPI
bytes on uo_out[3:1], the I2C bytes and acknowledges on uio[7:6], and the bytes the host drained
from HOSTOUT. Without --i2c-device nothing answers on the I2C bus, so every byte must be
unacknowledged and the controller reports 0x01 per byte; with it, a device at address 0x50 (for
example a 24C-series EEPROM) must acknowledge both bytes and the controller reports 0x00.
"""
import sys


def read_meta(path):
    meta = {}
    for line in open(path):
        if line.startswith("#") or not line.strip():
            continue
        k, v = line.split(None, 1)
        v = v.strip()
        meta[k] = [int(x) for x in v.split(",")] if "," in v else int(v)
    return meta


def read_trace(path, total):
    """Per clock, for the [total] clocks played: (uo 1st half, uo 2nd half, uio_in)."""
    entries = []
    for line in open(path):
        c, w1, w2 = line.split()
        entries.append((int(c), int(w1, 16), int(w2, 16)))
    clocks = []
    for (c, w1, w2), nxt in zip(entries, entries[1:] + [None]):
        end = nxt[0] if nxt else total
        for _ in range(c, end):
            clocks.append((w1 & 0xFF, (w1 >> 8) & 0xFF, (w2 >> 16) & 0xFF))
    return clocks


def bit(v, i):
    return (v >> i) & 1


def uart(clocks, start, bit_clocks):
    """8N1 bytes on uo_out[0]; returns (byte, clock of start bit, framing ok). A start bit whose
    frame does not fit before the end of the run is returned with byte None and framing not ok,
    so that a truncated extra byte fails the check instead of going unseen."""
    out, c = [], max(start, 1)
    lv = [bit(h2, 0) for _, h2, _ in clocks]
    while c < len(lv):
        if lv[c - 1] == 1 and lv[c] == 0:
            mid = c + bit_clocks // 2
            if mid + 9 * bit_clocks >= len(lv):
                out.append((None, c, False))
                break
            bits = [lv[mid + k * bit_clocks] for k in range(1, 9)]
            stop = lv[mid + 9 * bit_clocks]
            out.append((sum(b << k for k, b in enumerate(bits)), c, stop == 1 and lv[mid] == 0))
            c = mid + 9 * bit_clocks
        c += 1
    return out


def spi(clocks, start):
    """Mode 0, msb first: MOSI uo_out[2] at each rise of SCLK uo_out[1] while CS uo_out[3] is low."""
    out, cur, n = [], 0, 0
    for c in range(max(start, 1), len(clocks)):
        p, q = clocks[c - 1][1], clocks[c][1]
        if bit(q, 3) == 1:
            cur, n = 0, 0
            continue
        if bit(p, 1) == 0 and bit(q, 1) == 1:
            cur = (cur << 1) | bit(q, 2)
            n += 1
            if n == 8:
                out.append(cur)
                cur, n = 0, 0
    return out


def i2c(clocks, start):
    """Bytes with their acknowledge bit (0 = acknowledged), and whether a STOP followed."""
    sda = [bit(u, 6) for _, _, u in clocks]
    scl = [bit(u, 7) for _, _, u in clocks]
    out, bits, active, stopped = [], [], False, False
    for c in range(max(start, 1), len(clocks)):
        if scl[c] and scl[c - 1] and sda[c - 1] and not sda[c]:
            active, bits, stopped = True, [], False
        elif scl[c] and scl[c - 1] and not sda[c - 1] and sda[c]:
            active, stopped = False, True
        elif active and not scl[c - 1] and scl[c]:
            bits.append(sda[c])
            if len(bits) == 9:
                out.append((sum(b << (7 - k) for k, b in enumerate(bits[:8])), bits[8]))
                bits = []
    return out, stopped


def hostout(samples):
    """HOSTOUT entries {valid, tag} then the byte: the valid entries' bytes, and whether every
    valid entry comes before every empty one (an empty entry is 0x00 0x00)."""
    nib = [int(x, 16) for x in samples]
    by = [(nib[i] << 4) | nib[i + 1] for i in range(0, len(nib) - 1, 2)]
    pairs = list(zip(by[0::2], by[1::2]))
    valid = [d for t, d in pairs if t & 0x80]
    k = len(valid)
    well_formed = all(t & 0x80 for t, _ in pairs[:k]) and all(p == (0, 0) for p in pairs[k:])
    return valid, well_formed


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    device = "--i2c-device" in sys.argv
    if len(args) != 2:
        sys.exit(__doc__)
    meta = read_meta(args[0])
    info = read_meta(args[1] + ".info")
    clocks = read_trace(args[1] + ".trace", info["clocks"])
    samples = open(args[1] + ".samples").read().split()
    run = meta["run_clock"]
    ok = True

    def judge(name, good, detail):
        nonlocal ok
        ok &= good
        print(f"  {name}: {'ok' if good else 'WRONG'}: {detail}")

    print(f"{len(clocks)} clocks in the trace (expected {meta['clocks']}), run set at clock {run}")
    judge("run", info["status"] == 2 and len(clocks) == meta["clocks"],
          f"status {info['status']} (2: done, nothing dropped), {len(clocks)} clocks played")
    u = uart(clocks, run, meta["uart_bit_clocks"])
    judge("uart bytes", [b for b, _, f in u if f] == meta["uart_bytes"] and all(f for _, _, f in u),
          " ".join(f"{'?' if b is None else f'0x{b:02x}'}@{c}{'' if f else '(framing)'}" for b, c, f in u))
    lv = [bit(h2, 0) for _, h2, _ in clocks]
    edges = [c for c in range(run, len(lv)) if lv[c] != lv[c - 1]]
    off = [(e - edges[0]) % meta["uart_bit_clocks"] for e in edges] if edges else []
    judge("uart edge spacing", bool(edges) and not any(off), f"{len(edges)} edges, all on the {meta['uart_bit_clocks']}-clock grid: {not any(off)}")
    s = spi(clocks, run)
    judge("spi bytes", s == meta["spi_bytes"], " ".join(f"0x{b:02x}" for b in s))
    i, stopped = i2c(clocks, run)
    want_ack = 0 if device else 1
    judge("i2c bytes", [b for b, _ in i] == meta["i2c_bytes"] and all(a == want_ack for _, a in i) and stopped,
          " ".join(f"0x{b:02x}{'+ack' if a == 0 else '-nak'}" for b, a in i) + f" stop={stopped}")
    h, well_formed = hostout(samples)
    want = [want_ack] * len(meta["i2c_bytes"])
    judge("host drained", len(samples) == meta["samples"] and well_formed and h == want,
          f"{len(samples)} samples (want {meta['samples']}), " + " ".join(f"0x{b:02x}" for b in h)
          + f" (want {' '.join(f'0x{b:02x}' for b in want)})" + ("" if well_formed else ", malformed entries"))
    print("PASS" if ok else "FAIL")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
