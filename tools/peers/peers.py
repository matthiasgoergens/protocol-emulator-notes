#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
# SPDX-License-Identifier: Apache-2.0
"""Third-party protocol peers on our pins (method after TeslaCoilerOW, ttihp-protocol-emulator,
docs/independent-peers.md): alexforencich/verilog-uart (MIT), unmodified, vendored at a pinned commit with
SHA256SUMS, receives the byte stream our deadline-sequencer RTL puts on its UART pin.  The trace the
RTL produced (tools/sigrok-judge/traces/deadline-sequencer.bin, made by run.sh there) is replayed into
the peer's `uart_rx` in Icarus Verilog; the bytes it reports must equal the bytes sent and it must raise
no error flag.  Teeth: a flipped data bit and a slow transmitter must each be flagged.

Usage:  peers.py [--traces DIR]
"""
import argparse, datetime, re, subprocess, sys, tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "sigrok-judge"))
from judge import edges, invert, stretch, read_expected, ints   # noqa: E402  (our own helpers, no sigrok involved)

VENDOR = HERE / "vendor" / "verilog-uart"


def run_peer(uart_samples, prescale, tmp):
    trace = Path(tmp) / "trace.txt"
    trace.write_text("".join("%d\n" % (b & 1) for b in uart_samples))
    exe = Path(tmp) / "sim"
    subprocess.run(["iverilog", "-g2005", "-o", str(exe), f"-Puart_rx_replay.PRESCALE={prescale}",
                    str(VENDOR / "uart_rx.v"), str(HERE / "uart_rx_replay.v")], check=True)
    out = subprocess.run(["nice", "ionice", "vvp", str(exe), f"+TRACE={trace}"], capture_output=True, text=True, check=True).stdout
    got = [int(m.group(1), 16) for m in re.finditer(r"^RX ([0-9a-f]{2})$", out, re.M)]
    errs = sorted(set(re.findall(r"^(FRAME_ERROR|OVERRUN_ERROR)$", out, re.M)))
    return got, errs


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--traces", default=str(HERE.parent / "sigrok-judge" / "traces"))
    a = ap.parse_args()
    subprocess.run(["sha256sum", "--check", "--quiet", "SHA256SUMS"], cwd=VENDOR, check=True)
    exp = read_expected(Path(a.traces) / "deadline-sequencer.expected")
    base = (Path(a.traces) / "deadline-sequencer.bin").read_bytes()
    pin, bit = int(exp["uart_pin"]), int(exp["uart_bit_cycles"])
    assert bit % 8 == 0
    prescale = bit // 8
    want = ints(exp["uart_bytes"])
    print("# command: peers.py")
    print("# commit: " + subprocess.run(["git", "-C", str(HERE), "rev-parse", "HEAD"], capture_output=True, text=True).stdout.strip())
    print("# peer: " + (VENDOR / "PINNED").read_text().splitlines()[1])
    print("# " + subprocess.run(["iverilog", "-V"], capture_output=True, text=True).stdout.splitlines()[0])
    print("# date: " + datetime.datetime.now().astimezone().isoformat(timespec="seconds"))
    failed = 0
    with tempfile.TemporaryDirectory(dir="/var/tmp") as tmp:
        got, errs = run_peer(base, prescale, tmp)
        ok = got == want and not errs
        print(f"verilog-uart uart_rx on the sequencer's UART pin (prescale {prescale}): {'PASS' if ok else 'FAIL'}: "
              f"received {' '.join('%02x' % b for b in got) or 'nothing'}, sent {' '.join('%02x' % b for b in want)}, "
              f"errors {errs or 'none'}")
        failed += not ok
        s = edges(base, pin, "f")[0]
        teeth = [("bit 3 of byte 0 inverted for half a bit", invert(base, [pin], s + bit * 4 + bit // 4, s + bit * 4 + 3 * bit // 4)),
                 ("bit time 10 % long (receiver fixed)", stretch(base, 1.10)),
                 ("bit time 30 % long (receiver fixed)", stretch(base, 1.30))]
        for name, t in teeth:
            g, e = run_peer(t, prescale, tmp)
            caught = g != want or bool(e)
            print(f"  tooth: {name}: {'CAUGHT' if caught else 'MISSED'}: received {' '.join('%02x' % b for b in g) or 'nothing'}, errors {e or 'none'}")
            failed += not caught
    print("ALL CHECKS PASS" if not failed else f"{failed} CHECK(S) FAILED")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
