# /// script
# requires-python = ">=3.10"
# dependencies = ["pyserial>=3.5"]
# ///
"""Host-side test runner for the ULX3S emulator test bench.

Loads each test's programme image over the host link, configures the core, runs it, dumps the
trace and the sampler capture, and hands them to the OCaml checker (ocaml/fpga_tests.exe), which
replays the trace through the ISA interpreter, compares it with the OCaml board model's
prediction, and decodes the protocols independently.

The same code drives the board (a serial port) and the Verilator model (a pipe), so the runner is
proven before the hardware arrives:

    uv run host/emu_runner.py --sim                       # every test, simulated board
    uv run host/emu_runner.py --port /dev/ttyUSB0         # every test the bare board can run
    uv run host/emu_runner.py --port /dev/ttyUSB0 --have jumper-0-7 --only uart_jumper
    uv run host/emu_runner.py --sim --controls            # negative controls must fail

Exit status 0 only if every selected test passed (and, with --controls, every control failed).
"""
from __future__ import annotations

import argparse
import datetime
import json
import os
import select
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
CHECKER = ROOT / "ocaml" / "_build" / "default" / "fpga_tests.exe"
CTRL_FLASH, CTRL_USB_ATTACH = 0x01, 0x10


class LinkError(RuntimeError):
    pass


class SimLink:
    """The Verilator model of emu_core, talking 8N1 on its uart pins via stdin/stdout."""

    def __init__(self, binary: Path, args: list[str], log: Path):
        self.log = open(log, "wb")
        self.p = subprocess.Popen([str(binary), *args], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                  stderr=self.log, bufsize=0)

    def write(self, data: bytes) -> None:
        assert self.p.stdin is not None
        self.p.stdin.write(data)
        self.p.stdin.flush()

    def read(self, n: int, timeout: float) -> bytes:
        assert self.p.stdout is not None
        out = bytearray()
        end = time.monotonic() + timeout
        while len(out) < n:
            left = end - time.monotonic()
            if left <= 0:
                break
            r, _, _ = select.select([self.p.stdout], [], [], left)
            if not r:
                break
            chunk = os.read(self.p.stdout.fileno(), n - len(out))
            if not chunk:
                break
            out += chunk
        return bytes(out)

    def close(self) -> None:
        if self.p.stdin:
            self.p.stdin.close()
        try:
            self.p.wait(timeout=10)
        except subprocess.TimeoutExpired:
            self.p.kill()
        self.log.close()


class SerialLink:
    """The ULX3S's FTDI FT231X serial port (US1), 8N1."""

    def __init__(self, port: str, baud: int):
        import serial  # pyserial; only needed on the board
        self.s = serial.Serial(port, baud, timeout=0.1)
        self.s.reset_input_buffer()

    def write(self, data: bytes) -> None:
        self.s.write(data)
        self.s.flush()

    def read(self, n: int, timeout: float) -> bytes:
        out = bytearray()
        end = time.monotonic() + timeout
        while len(out) < n and time.monotonic() < end:
            out += self.s.read(n - len(out))
        return bytes(out)

    def close(self) -> None:
        self.s.close()


class Emu:
    """The command protocol of rtl/emu_core.v."""

    def __init__(self, link, slow: float):
        self.link, self.slow = link, slow

    def expect(self, n: int, what: str, timeout: float = 5.0) -> bytes:
        b = self.link.read(n, timeout * self.slow)
        if len(b) != n:
            raise LinkError(f"{what}: wanted {n} bytes, got {len(b)}: {b.hex()}")
        return b

    def identify(self) -> dict:
        self.link.write(b"I")
        b = self.expect(8, "identify")
        if b[:4] != b"EMU1" or b[7:8] != b"k":
            raise LinkError(f"identify: unexpected reply {b!r}")
        return {"trace_aw": b[4], "ctrl": (b[5] << 8) | b[6]}

    def acks(self, n: int, what: str, timeout: float) -> None:
        b = self.expect(n, what, timeout)
        if b != b"k" * n:
            raise LinkError(f"{what}: bad acknowledgements {b!r}")

    def load_imem(self, words: list[int]) -> None:
        cmds = b"".join(bytes([ord("W"), 0, a, w >> 8, w & 0xFF]) for a, w in enumerate(words))
        self.link.write(cmds)
        self.acks(len(words), "imem write", 20.0)
        self.link.write(b"".join(bytes([ord("R"), 0, a]) for a in range(len(words))))
        back = self.expect(2 * len(words), "imem readback", 20.0)
        got = [(back[2 * i] << 8) | back[2 * i + 1] for i in range(len(words))]
        bad = [i for i, (x, y) in enumerate(zip(words, got)) if x != y]
        if bad:
            raise LinkError(f"imem readback differs at {len(bad)} words, first {bad[0]}: {got[bad[0]]:04x} != {words[bad[0]]:04x}")

    def cfg(self, regs: dict[int, int]) -> None:
        self.link.write(b"".join(bytes([ord("K"), r, v >> 8, v & 0xFF]) for r, v in sorted(regs.items())))
        self.acks(len(regs), "config", 5.0)

    def host_in(self, data: list[int]) -> None:
        for b in data:
            self.link.write(bytes([ord("H"), b]))
            self.acks(1, "host_in", 5.0)

    def stream(self, entries: list[list[int]]) -> None:
        self.link.write(b"".join(bytes([ord("B"), 0, a, c, w >> 8, w & 0xFF]) for a, (c, w) in enumerate(entries)))
        self.acks(len(entries), "stream buffer", 5.0)

    def run(self, cycles: int) -> None:
        self.link.write(b"G" + cycles.to_bytes(4, "big"))
        b = self.expect(1, "run", 30.0 + cycles * 2e-5)
        if b != b"g":
            raise LinkError(f"run: unexpected reply {b!r}")

    def trace(self) -> tuple[int, int, list[bytes]]:
        self.link.write(b"T")
        h = self.expect(7, "trace header")
        cnt, ovf, trunc = (h[0] << 8) | h[1], h[2], int.from_bytes(h[3:7], "big")
        body = self.expect(10 * cnt, "trace body", 30.0)
        return ovf, trunc, [body[10 * i:10 * i + 10] for i in range(cnt)]

    def capture(self) -> list[bytes]:
        self.link.write(b"S")
        h = self.expect(2, "capture header")
        cnt = (h[0] << 8) | h[1]
        body = self.expect(3 * cnt, "capture body", 10.0)
        return [body[3 * i:3 * i + 3] for i in range(cnt)]

    def status(self) -> dict:
        self.link.write(b"Z")
        b = self.expect(4, "status")
        return {"board_status": b[0], "sampler_overflows": b[1], "trace_overflow": b[2]}


def write_trace(path: Path, cycles: int, ovf: int, trunc: int, entries: list[bytes]) -> None:
    with open(path, "w") as f:
        f.write(f"{cycles} {ovf} {trunc}\n")
        for e in entries:
            c = int.from_bytes(e[0:4], "big")
            f.write(f"{c:x} " + " ".join(f"{x:02x}" for x in e[4:10]) + "\n")


def write_capture(path: Path, entries: list[bytes]) -> None:
    with open(path, "w") as f:
        for e in entries:
            f.write(f"{e[0]:x} {(e[1] << 8) | e[2]:04x}\n")


def sim_args(test: dict, cpb: int, flash_id: str | None) -> list[str]:
    a = ["--clks-per-bit", str(cpb)]
    if flash_id:
        a += ["--flash-id", flash_id]
    if test["wiring"]["jumper_0_7"]:
        a.append("--jumper-0-7")
    if test["wiring"]["header_i2c_slave"]:
        a.append("--header-i2c-slave")
        if test["wiring"]["header_slave_addr"] >= 0:
            a += ["--header-i2c-addr", f"{test['wiring']['header_slave_addr']:x}"]
    if test["wiring"]["header_flash"]:
        a.append("--header-flash")
    if "jumpers-streamer-to-sampler" in test["needs"]:
        a.append("--jumper-stream")
    a += ["--rtc-addr", f"{test['wiring']['rtc_addr']:x}"]
    return a


def flash_guard(test: dict, ctrl: int) -> None:
    """Refuse to route a programme to the configuration flash unless the OCaml model shows every
    command byte it sends is on the test's allow-list of read-only commands."""
    if not ctrl & CTRL_FLASH:
        return
    allowed = test.get("flash_allowed")
    cmds = test.get("flash_cmds_predicted", [])
    if allowed is None or not cmds or any(c not in allowed for c in cmds):
        raise LinkError(f"refusing flash-routed test {test['name']}: predicted commands {cmds}, allowed {allowed}")


def run_test(emu: Emu, test: dict, outdir: Path, mode: str, mutate: str | None = None) -> tuple[bool, str]:
    imem = list(test["imem"])
    if mutate == "imem":
        # control: the board runs a programme one bit different from the one the checker replays
        i = next(i for i, w in enumerate(imem) if (w >> 12) == 3 and (w & 0xFFF) > 1)   # first LDD n>1
        imem[i] ^= 0x001
    ctrl = test["ctrl"] | CTRL_USB_ATTACH
    flash_guard(test, ctrl)
    emu.load_imem(imem)
    regs = {r: 0 for r in range(1, 7)}
    regs.update({r: v for r, v in test["cfg"]})
    regs[0] = ctrl
    emu.cfg(regs)
    emu.host_in(test["host_in"])
    if test["stream"]:
        emu.stream(test["stream"])
    t0 = time.monotonic()
    emu.run(test["cycles"])
    ovf, trunc, entries = emu.trace()
    cap = emu.capture()
    st = emu.status()
    elapsed = time.monotonic() - t0
    if mutate == "trace" and len(entries) > 4:
        # control: one output bit flipped in one recorded entry
        e = bytearray(entries[len(entries) // 2])
        e[5] ^= 0x01
        entries[len(entries) // 2] = bytes(e)
    stem = test["name"] + (f".control-{mutate}" if mutate else "")
    tr, cp = outdir / f"{stem}.trace", outdir / f"{stem}.capture"
    write_trace(tr, test["cycles"], ovf, trunc, entries)
    write_capture(cp, cap)
    args = [str(CHECKER), "check", test["name"], "--trace", str(tr), "--capture", str(cp), "--mode", mode]
    r = subprocess.run(args, capture_output=True, text=True)
    report = r.stdout + r.stderr + f"  ({len(entries)} trace entries, {len(cap)} capture words, status {st}, {elapsed:.2f} s)\n"
    (outdir / f"{stem}.check.txt").write_text(report)
    return r.returncode == 0, report


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument("--sim", action="store_true", help="run against the Verilator model")
    g.add_argument("--port", help="serial port of the ULX3S (FTDI, usually /dev/ttyUSB0)")
    ap.add_argument("--baud", type=int, default=1_000_000)
    ap.add_argument("--cpb", type=int, default=8, help="simulation: clocks per UART bit the model was built with")
    ap.add_argument("--have", default="", help="comma-separated parts/wires present on the board (see BRINGUP.md)")
    ap.add_argument("--only", default="", help="comma-separated test names")
    ap.add_argument("--controls", action="store_true", help="also run negative controls, which must fail")
    ap.add_argument("--out", default=None, help="results directory (default results/<timestamp>-<mode>)")
    ap.add_argument("--judge", choices=["sim", "board"], default=None,
                    help="checker mode; default sim for --sim, board for --port. '--sim --judge board' rehearses "
                         "a board whose parts differ from the model (e.g. with --sim-flash-id)")
    ap.add_argument("--sim-flash-id", default=None, help="simulation: JEDEC ID of the configuration flash, 6 hex digits")
    a = ap.parse_args()

    if not CHECKER.exists():
        print(f"missing {CHECKER}; build it: cd {ROOT/'ocaml'} && opam exec --switch=5.3.0 -- dune build", file=sys.stderr)
        return 2
    tests = json.loads(subprocess.run([str(CHECKER), "manifest"], check=True, capture_output=True, text=True).stdout)
    if a.only:
        want = set(a.only.split(","))
        tests = [t for t in tests if t["name"] in want]
    mode = a.judge or ("sim" if a.sim else "board")
    stamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    outdir = Path(a.out) if a.out else ROOT / "results" / f"{stamp}-{mode}"
    outdir.mkdir(parents=True, exist_ok=True)
    have = set(filter(None, a.have.split(",")))
    sim_bin = ROOT / "sim" / f"obj_dir_cpb{a.cpb}" / "Vemu_sim"
    if a.sim and not sim_bin.exists():
        print(f"missing {sim_bin}; build it: sim/build.sh {a.cpb}", file=sys.stderr)
        return 2

    board = None
    if not a.sim:
        board = Emu(SerialLink(a.port, a.baud), slow=1.0)
        print("identify:", board.identify())

    summary = []
    plan = [(t, None) for t in tests]
    if a.controls:
        ctl = [t for t in tests if t["name"] == "uart_loop"] or tests[:1]
        plan += [(ctl[0], "trace"), (ctl[0], "imem")]
    for t, mutate in plan:
        missing = [n for n in t["needs"] if n not in have] if not a.sim else []
        label = t["name"] + (f" [control: {mutate}]" if mutate else "")
        if missing:
            print(f"SKIP {label}: needs {', '.join(missing)}")
            summary.append({"test": label, "result": "skip", "needs": missing})
            continue
        link = None
        try:
            if a.sim:
                link = SimLink(sim_bin, sim_args(t, a.cpb, a.sim_flash_id), outdir / f"{t['name']}.sim.log")
                emu = Emu(link, slow=20.0)
                emu.identify()
            else:
                emu = board
            ok, report = run_test(emu, t, outdir, mode, mutate)
        except LinkError as e:
            ok, report = False, f"link error: {e}\n"
        finally:
            if link is not None:
                link.close()
        expected_ok = mutate is None
        good = ok == expected_ok
        verdict = ("PASS" if ok else "FAIL") if mutate is None else ("control failed as it must" if not ok else "CONTROL PASSED: checker is blind")
        print(report, end="")
        print(f"{'OK  ' if good else 'BAD '} {label}: {verdict}\n")
        summary.append({"test": label, "result": "ok" if good else "bad", "checker_pass": ok})
    if board is not None:
        board.link.close()
    (outdir / "summary.json").write_text(json.dumps(summary, indent=1) + "\n")
    bad = [s for s in summary if s["result"] == "bad"]
    print(f"{len(summary) - len(bad)} of {len(summary)} as expected ({sum(s['result'] == 'skip' for s in summary)} skipped); results in {outdir}")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
