#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
# SPDX-License-Identifier: Apache-2.0
"""Judge the example programmes' pin traces with sigrok's protocol decoders and a third-party UART.

The traces are the chip RTL's pins as tools/asm's runner recorded them (test/examples.ml writes
results/traces/<example>/deadline-sequencer.{bin,expected}: one byte per clock, bit k = net k).
Everything is tools/sigrok-judge's machinery, imported, not copied: sigrok-cli in its pinned
container, its judges for UART, SPI and I2C, and its teeth (planted faults each trace must fail).
The I2C read (a write, a repeated START, a read with ACK and NACK) has no case there, so it is
judged here against the annotation sequence sigrok prints, with the I2C teeth. The UART
transmitter's trace is also replayed into Alex Forencich's uart_rx (tools/peers, unmodified).

Usage: test/judge_examples.py   (from tools/asm; after examples.exe has written the traces)
"""
import datetime, subprocess, sys, tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
ASM = HERE.parent
ROOT = ASM.parent.parent
sys.path.insert(0, str(ROOT / "tools" / "sigrok-judge"))
sys.path.insert(0, str(ROOT / "tools" / "peers"))
import judge as J        # noqa: E402
import peers as P        # noqa: E402

TRACES = ASM / "results" / "traces"


def judge_i2c_read(samples, rate, exp):
    d = "i2c:scl=%s:sda=%s" % (exp["i2c_scl"], exp["i2c_sda"])
    cls = "start:repeat-start:stop:ack:nack:address-read:address-write:data-read:data-write"
    got = [g for g in J.sigrok(samples, 8, rate, d, ["i2c=" + cls]) if g not in ("Write", "Read")]
    warn = J.sigrok(samples, 8, rate, d, ["i2c=warnings"])
    want = ["Start", "Address write: 50", "ACK", "Data write: 10", "ACK", "Start repeat", "Address read: 50", "ACK",
            "Data read: 12", "ACK", "Data read: 7A", "NACK", "Stop"]
    problems = []
    if got != want:
        problems.append("decoded [%s], expected [%s]" % ("; ".join(got), "; ".join(want)))
    problems += ["decoder warning: " + w for w in warn]
    return J.Verdict(problems, "decoded [%s]" % "; ".join(got))


CASES = [
    ("uart_tx", J.judge_uart, J.uart_teeth),
    ("spi", J.judge_spi, J.spi_teeth),
    ("i2c_write", J.judge_i2c, J.i2c_teeth),
    ("i2c_read", judge_i2c_read, J.i2c_teeth),
    ("bridge", J.judge_spi, J.spi_teeth),
]


def main():
    J.ensure_image()
    print("# command: test/judge_examples.py")
    print("# commit: " + subprocess.run(["git", "-C", str(ROOT), "rev-parse", "HEAD"], capture_output=True, text=True).stdout.strip())
    for v in J.sigrok_version():
        print("# " + v.strip())
    print("# date: " + datetime.datetime.now().astimezone().isoformat(timespec="seconds"))
    failed = 0
    for name, judge, teeth in CASES:
        d = TRACES / name
        binf, expf = d / "deadline-sequencer.bin", d / "deadline-sequencer.expected"
        if not binf.exists():
            print(f"{name}: MISSING TRACE {binf} (run examples.exe first)")
            failed += 1
            continue
        exp = J.read_expected(expf)
        rate = int(exp["samplerate"])
        base = binf.read_bytes()
        v = judge(base, rate, exp)
        print(f"{name}: {'PASS' if v.ok else 'FAIL'}: {v.summary}")
        for p in v.problems:
            print(f"    {p}")
        failed += not v.ok
        for tname, mutated in teeth(base, exp):
            tv = judge(mutated, rate, exp)
            print(f"  tooth {name}: {tname}: {'CAUGHT' if not tv.ok else 'MISSED'}")
            failed += tv.ok
    # the third-party UART receiver on the UART transmitter's trace
    subprocess.run(["sha256sum", "--check", "--quiet", "SHA256SUMS"], cwd=P.VENDOR, check=True)
    exp = J.read_expected(TRACES / "uart_tx" / "deadline-sequencer.expected")
    base = (TRACES / "uart_tx" / "deadline-sequencer.bin").read_bytes()
    pin, bit = int(exp["uart_pin"]), int(exp["uart_bit_cycles"])
    want = J.ints(exp["uart_bytes"])
    with tempfile.TemporaryDirectory(dir="/var/tmp") as tmp:
        got, errs = P.run_peer([(b >> pin) & 1 for b in base], bit // 8, tmp)
        ok = got == want and not errs
        print(f"uart_tx into verilog-uart uart_rx: {'PASS' if ok else 'FAIL'}: received {' '.join('%02x' % x for x in got)}"
              + (f", flags {errs}" if errs else ""))
        failed += not ok
        bad = J.invert(base, [pin], J.edges(base, pin, "f")[0] + bit * 4 + bit // 4, J.edges(base, pin, "f")[0] + bit * 4 + 3 * bit // 4)
        got, errs = P.run_peer([(b >> pin) & 1 for b in bad], bit // 8, tmp)
        caught = got != want or bool(errs)
        print(f"  tooth uart_tx into uart_rx: data bit 3 of byte 0 inverted: {'CAUGHT' if caught else 'MISSED'}")
        failed += not caught
    print()
    print("ALL CHECKS PASS" if not failed else f"{failed} CHECK(S) FAILED")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
