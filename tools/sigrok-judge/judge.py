#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
# SPDX-License-Identifier: Apache-2.0
"""sigrok judge: decode the pin traces our prototypes produce with an external sigrok-cli and compare
the decoded frames with the payloads that were meant to be sent, then plant a fault in each trace and
require the judge to notice.

Method after MarcosAsh (demo/decode.py, test/traces/sigrok/*.trace, Apache-2.0): a protocol decoder
written by other people judges the pins, any decoder warning fails, and every trace comes with "teeth",
waveform changes the judge must refuse.  libsigrokdecode is GPL-3.0, so sigrok-cli is only ever run as
a program inside a container (see Containerfile); none of its code is copied or translated here.

A trace is a file of one byte per sample (bit p = channel p) plus a `.expected` file of `key value`
lines.  Usage:  judge.py [--rate HZ] [--traces DIR] [--only NAME[,NAME]] [--no-teeth]
"""
import argparse, datetime, os, re, statistics, subprocess, sys, tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
IMAGE = "localhost/sigrok-judge:0.7.2-1"


# ----------------------------------------------------------------------------- sigrok, as a program
def ensure_image():
    if subprocess.run(["podman", "image", "exists", IMAGE]).returncode == 0:
        return
    print(f"building {IMAGE}", file=sys.stderr)
    subprocess.run(["nice", "ionice", "podman", "build", "--tag", IMAGE, "--file", str(HERE / "Containerfile"),
                    str(HERE)], check=True, stdout=sys.stderr)


def sigrok_version():
    out = subprocess.run(["podman", "run", "--rm", IMAGE, "sigrok-cli", "--version"], capture_output=True,
                         text=True, check=True).stdout
    return [l for l in out.splitlines() if l.startswith("sigrok-cli") or "libsigrokdecode" in l and "Libs" not in l][:2]


WORK = HERE / "work"


def sigrok(samples, nchan, rate, decoders, annotations):
    """Run sigrok-cli on [samples] (bytes, one per sample); returns the lines of the annotation output."""
    WORK.mkdir(exist_ok=True)
    with tempfile.NamedTemporaryFile(dir=WORK, suffix=".bin", delete=False) as f:
        f.write(samples)
        name = os.path.basename(f.name)
    try:
        cmd = ["nice", "ionice", "podman", "run", "--rm", "--volume", f"{WORK}:/w:Z", IMAGE, "sigrok-cli",
               "--input-format", f"binary:numchannels={nchan}:samplerate={int(rate)}", "--input-file", f"/w/{name}",
               "--protocol-decoders", decoders]
        for a in annotations:
            cmd += ["--protocol-decoder-annotations", a]
        r = subprocess.run(cmd, capture_output=True, text=True)
        if r.returncode != 0:
            raise RuntimeError(f"sigrok-cli failed ({r.returncode}): {r.stderr.strip()}")
        return [l.split(": ", 1)[1] if ": " in l else l for l in r.stdout.splitlines()]
    finally:
        os.unlink(WORK / name)


# ----------------------------------------------------------------------------- waveform operations
def ch(trace, p):
    return [(b >> p) & 1 for b in trace]


def edges(trace, p, kind):
    """Sample indices where channel p falls ('f') or rises ('r') relative to the previous sample."""
    v = ch(trace, p)
    want = (1, 0) if kind == "f" else (0, 1)
    return [i for i in range(1, len(v)) if (v[i - 1], v[i]) == want]


def invert(trace, chans, a, b):
    t = bytearray(trace)
    mask = sum(1 << p for p in chans)
    for i in range(max(a, 0), min(b, len(t))):
        t[i] ^= mask
    return bytes(t)


def delay(trace, p, n):
    """Channel p arrives n samples late, the other channels untouched."""
    t = bytearray(trace)
    v = ch(trace, p)
    for i in range(len(t)):
        bit = v[max(i - n, 0)]
        t[i] = (t[i] & ~(1 << p)) | (bit << p)
    return bytes(t)


def stretch(trace, factor):
    return bytes(trace[min(int(i / factor), len(trace) - 1)] for i in range(int(len(trace) * factor)))


def delete(trace, a, n):
    return trace[:a] + trace[a + n:]


def resample(trace, src, dst):
    """What a logic analyser running at [dst] Hz records of a signal known at [src] Hz (sample and hold)."""
    n = int(len(trace) * dst / src)
    return bytes(trace[min(int(i * src / dst), len(trace) - 1)] for i in range(n))


# ----------------------------------------------------------------------------- expected files
def read_expected(path):
    kv = {}
    lines = []
    for l in Path(path).read_text().splitlines():
        if not l.strip():
            continue
        if l.startswith("#"):
            m = re.match(r"# samplerate(?:_hz_assumed)? (\d+)", l)
            if m:
                kv["samplerate"] = m.group(1)
            continue
        k, _, v = l.partition(" ")
        lines.append((k, v))
        kv.setdefault(k, v)
    kv["_lines"] = lines
    return kv


def ints(s):
    return [int(x) for x in s.split(",") if x != ""]


# ----------------------------------------------------------------------------- judges: decode, compare
class Verdict:
    def __init__(self, problems, summary):
        self.ok = not problems
        self.problems = problems
        self.summary = summary


def judge_uart(samples, rate, exp):
    pin, bit = int(exp["uart_pin"]), int(exp["uart_bit_cycles"])
    baud = int(exp["samplerate"]) / bit   # the baud rate is the transmitter's, whatever the analyser rate
    base = ["rx=%d" % pin, "baudrate=%d" % round(baud)]
    got = sigrok(samples, 8, rate, "uart:" + ":".join(base), ["uart=rx-data"])
    warn = sigrok(samples, 8, rate, "uart:" + ":".join(base), ["uart=rx-warnings:rx-break"])
    want = ["%02X" % b for b in ints(exp["uart_bytes"])]
    return compare_bytes(got, want, warn)


def judge_spi(samples, rate, exp):
    d = "spi:clk=%s:mosi=%s:cs=%s" % (exp["spi_sclk"], exp["spi_mosi"], exp["spi_cs"])
    got = sigrok(samples, 8, rate, d, ["spi=mosi-data"])
    warn = sigrok(samples, 8, rate, d, ["spi=warnings"])
    return compare_bytes(got, ["%02X" % b for b in ints(exp["spi_bytes"])], warn)


def compare_bytes(got, want, warn):
    problems = []
    if got != want:
        problems.append("decoded %s, sent %s" % (" ".join(got) or "nothing", " ".join(want)))
    problems += ["decoder warning: " + w for w in warn]
    return Verdict(problems, "decoded " + (" ".join(got) or "nothing"))


def judge_i2c(samples, rate, exp):
    d = "i2c:scl=%s:sda=%s" % (exp["i2c_scl"], exp["i2c_sda"])
    cls = "start:repeat-start:stop:ack:nack:address-read:address-write:data-read:data-write"
    got = [g for g in sigrok(samples, 8, rate, d, ["i2c=" + cls]) if g not in ("Write", "Read")]   # the R/W flag is in "Address write"
    warn = sigrok(samples, 8, rate, d, ["i2c=warnings"])
    b = ints(exp["i2c_bytes"])
    addr, rw = b[0] >> 1, b[0] & 1
    want = ["Start", "Address %s: %02X" % ("read" if rw else "write", addr), "ACK"]
    for x in b[1:]:
        want += ["Data %s: %02X" % ("read" if rw else "write", x), "ACK"]
    want.append("Stop")
    problems = []
    if got != want:
        problems.append("decoded [%s], sent [%s]" % ("; ".join(got), "; ".join(want)))
    problems += ["decoder warning: " + w for w in warn]
    return Verdict(problems, "decoded [%s]" % "; ".join(got))


def ps2_shim(samples, rate):
    """The installed ps2 decoder (libsigrokdecode 0.5.3) collects 12 falling clock edges per 11-bit frame
    and so emits a frame only when the next frame's start bit arrives, which then misaligns every later
    frame.  Measured with a synthetic ideal trace (results/ps2-decoder-quirk.txt).  The shim appends one
    idle clock pulse (DATA high) after every 11th falling edge, which is what that decoder needs and
    which a real line never shows as a data bit."""
    f = edges(samples, 0, "f")
    r = edges(samples, 0, "r")
    if not f:
        return samples
    gaps = [b - a for a, b in zip(f, f[1:]) if b - a < 4 * (f[1] - f[0])]
    cell = int(statistics.median(gaps)) if gaps else 80
    half = max(cell // 2, 1)
    out, last = bytearray(), 0
    for k in range(11, len(f) + 1, 11):
        after = next((x for x in r if x > f[k - 1]), len(samples))
        out += samples[last:after]
        out += bytes([0b11] * half + [0b10] * half + [0b11] * half)
        last = after
    out += samples[last:]
    return bytes(out)


def judge_ps2(samples, rate, exp):
    samples = ps2_shim(samples, rate)
    got = sigrok(samples, 2, rate, "ps2:clk=0:data=1", ["ps2=word:parity-ok:parity-err"])
    words = [int(g.split(": ")[1], 16) for g in got if g.startswith("Data: ")]
    bad = [g for g in got if g.startswith("Parity error")]
    want = ints(exp["ps2_bytes"])
    problems = []
    if words != want:
        problems.append("decoded %s, sent %s" % (" ".join("%02x" % w for w in words) or "nothing", " ".join("%02x" % w for w in want)))
    if bad:
        problems.append("%d parity errors reported" % len(bad))
    return Verdict(problems, "decoded " + (" ".join("%02x" % w for w in words) or "nothing"))


CAN_ALLOWED_WARNINGS = {
    # The reference node's remote frame uses identifier 0x7FF, the largest, which the CAN specification
    # forbids (its seven most significant bits may not all be recessive).  That is the prototype's test
    # choice, not a fault of the chip; every other warning fails the judge.
    "Identifier bits 10..4 must not be all recessive",
}


def judge_can(samples, rate, exp):
    d = "can:can_rx=%s:nominal_bitrate=%s:sample_point=77" % (exp["can_rx"], exp["can_bitrate"])
    got = sigrok(samples, 1, rate, d, ["can=sof:eof:id:rtr:dlc:data:ack-slot"])
    warn = sigrok(samples, 1, rate, d, ["can=warnings"])
    frames, cur, acks = [], None, []
    for g in got:
        if g == "Start of frame":
            cur = {"data": []}
        elif cur is None:
            continue
        elif g.startswith("Identifier: "):
            cur["id"] = int(g.split(": ")[1].split()[0])
        elif g.startswith("Remote transmission request: "):
            cur["rtr"] = int(g.endswith("remote frame"))
        elif g.startswith("Data length code: "):
            cur["dlc"] = int(g.split(": ")[1])
        elif g.startswith("Data byte "):
            cur["data"].append(int(g.split(": ")[1], 16))
        elif g.startswith("ACK slot: "):
            acks.append(g.split(": ")[1])
        elif g == "End of frame":
            frames.append(cur)
            cur = None
    if cur is not None:
        frames.append(dict(cur, incomplete=True))
    want = []
    for k, v in exp["_lines"]:
        if k == "can_frame":
            kv = dict(x.split("=") for x in v.split())
            want.append({"id": int(kv["id"]), "rtr": int(kv["rtr"]), "dlc": int(kv["dlc"]), "data": ints(kv["data"])})
    problems = []
    norm = lambda f: (f.get("id"), f.get("rtr"), f.get("dlc"), tuple([] if f.get("rtr") else f["data"]), f.get("incomplete", False))
    if [norm(f) for f in frames] != [norm(dict(w, data=w["data"])) for w in want]:
        # (the decoder reads data bytes for remote frames too; they are not compared)
        problems.append("decoded %s, sent %s" % (_pp_can(frames), _pp_can(want)))
    for w in warn:
        if w not in CAN_ALLOWED_WARNINGS:
            problems.append("decoder warning: " + w)
    return Verdict(problems, "decoded %s; ACK slots %s; allowed warnings seen: %d"
                   % (_pp_can(frames), ",".join(acks), sum(1 for w in warn if w in CAN_ALLOWED_WARNINGS)))


def _pp_can(fs):
    return "[" + "; ".join("id=0x%x rtr=%s dlc=%s data=%s" % (f.get("id", -1), f.get("rtr"), f.get("dlc"),
                           ",".join("%02x" % x for x in ([] if f.get("rtr") else f["data"]))) for f in fs) + "]"


def judge_usb(samples, rate, exp):
    d = "usb_signalling:dp=%s:dm=%s:signalling=low-speed,usb_packet:signalling=low-speed" % (exp["usb_dp"], exp["usb_dm"])
    pk = ["setup", "in", "out", "data0", "data1", "ack", "nak", "stall", "sof", "pre", "err", "invalid", "reserved"]
    got = sigrok(samples, 2, rate, d, ["usb_packet=" + ":".join("packet-" + p for p in pk)])
    bad = sigrok(samples, 2, rate, d, ["usb_packet=sync-err:crc5-err:crc16-err:packet-err:packet-invalid:packet-reserved"])
    bad += sigrok(samples, 2, rate, d, ["usb_signalling=error"])
    setup, device, last, pkts = None, [], None, []
    for g in got:
        m = re.match(r"(SETUP|IN|OUT) ADDR (\d+) EP (\d+)", g)
        if m:
            last = m.group(1)
            pkts.append(g)
            if last == "SETUP" and int(m.group(2)) != int(exp["usb_addr"]):
                bad.append("token for address " + m.group(2))
            continue
        m = re.match(r"DATA[01] \[ ?(.*?) ?\]$", g)
        if m:
            data = [int(x, 16) for x in m.group(1).split()]
            if last == "SETUP":
                setup = data
            elif last == "IN":
                device += data
            pkts.append(g)
            last = None
        else:
            pkts.append(g)
    problems = []
    if setup != ints(exp["usb_setup"]):
        problems.append("SETUP data %s, sent %s" % (setup, ints(exp["usb_setup"])))
    want = ints(exp["usb_device_data"])
    if device != want:
        problems.append("device sent %s, expected %s" % (" ".join("%02x" % x for x in device), " ".join("%02x" % x for x in want)))
    problems += ["decoder error: " + b for b in bad]
    return Verdict(problems, "%d packets; setup %s; device data %s" % (len(pkts), setup, " ".join("%02x" % x for x in device)))


def judge_spdif(samples, rate, exp):
    got = sigrok(samples, 1, rate, "spdif:data=0", ["spdif=preamble:samples:validity:subcode:chan_stat:parity"])
    subs, cur, unknown = [], None, 0
    for g in got:
        w = g.split()
        if len(w) == 2 and w[0] == "Preamble":
            cur = [w[1], 0, 0, 0, 0, None]
        elif g == "Unknown Preamble":
            unknown += 1
            cur = None
        elif cur is None:
            continue
        elif len(w) == 2 and w[0] == "Audio":
            cur[1] = int(w[1], 16)
        elif g == "E":
            cur[2] = 1
        elif len(w) == 2 and w[0] == "S:":
            cur[3] = int(w[1])
        elif len(w) == 2 and w[0] == "C:":
            cur[4] = int(w[1])
        elif len(w) == 2 and w[0] == "P:":
            cur[5] = int(w[1])
            subs.append("%s %06x %d %d %d %d" % tuple(cur))
            cur = None
    sent = ["%s %s" % (k, v) for k, v in exp["_lines"]]
    # the capture starts mid-stream, so align on the first four decoded subframes, as the chip's own check does
    off = -1
    for j in range(0, len(sent) - 3):
        if len(subs) >= 4 and subs[:4] == sent[j:j + 4]:
            off = j
            break
    problems = []
    cmp_ = eq = 0
    if off < 0:
        problems.append("the first four decoded subframes appear nowhere in the sent stream (%d decoded)" % len(subs))
    else:
        for k, s in enumerate(subs):
            if off + k < len(sent):
                cmp_ += 1
                eq += s == sent[off + k]
        if eq != cmp_:
            problems.append("%d of %d decoded subframes differ from the sent" % (cmp_ - eq, cmp_))
        if off > 2:
            problems.append("alignment at sent subframe %d, expected at most 2" % off)
        if cmp_ < len(sent) - 6:
            problems.append("only %d of %d sent subframes decoded" % (cmp_, len(sent)))
    if unknown:
        problems.append("%d unknown preambles" % unknown)
    return Verdict(problems, "%d subframes decoded, aligned at sent subframe %d, %d of %d equal (preamble, 24-bit audio, V, U, C, P)"
                   % (len(subs), off, eq, cmp_))


# ----------------------------------------------------------------------------- the teeth
def uart_teeth(t, exp):
    pin, bit = int(exp["uart_pin"]), int(exp["uart_bit_cycles"])
    s = edges(t, pin, "f")[0]
    return [("bit 3 of byte 0 inverted for half a bit", invert(t, [pin], s + bit * 4 + bit // 4, s + bit * 4 + 3 * bit // 4)),
            ("bit time 10 % long (receiver fixed)", stretch(t, 1.10))]


def spi_teeth(t, exp):
    clk, mosi = int(exp["spi_sclk"]), int(exp["spi_mosi"])
    r = edges(t, clk, "r")
    return [("MOSI inverted around the third clock rising edge", invert(t, [mosi], r[2] - 16, r[2] + 16)),
            ("MOSI 40 samples late against SCLK (period 64)", delay(t, mosi, 40))]


def i2c_teeth(t, exp):
    scl, sda = int(exp["i2c_scl"]), int(exp["i2c_sda"])
    r = edges(t, scl, "r")
    f = edges(t, scl, "f")
    k = 2
    end = next(x for x in f if x > r[k])
    return [("SDA inverted over the high phase of the third SCL pulse", invert(t, [sda], r[k] - 20, end)),
            ("SDA 24 samples late against SCL", delay(t, sda, 24))]


def ps2_teeth(t, exp):
    f = edges(t, 0, "f")
    r = edges(t, 0, "r")
    k = f[4]
    end = next(x for x in r if x > k)
    return [("DATA inverted over the fifth falling clock edge", invert(t, [1], k - 1, end)),
            ("DATA 45 samples late against CLK (half period about 40)", delay(t, 1, 45))]


def can_teeth(t, exp):
    bit = int(int(exp["samplerate"]) / int(exp["can_bitrate"]))
    s = edges(t, 0, "f")[0]
    return [("bit 30 of the first frame inverted", invert(t, [0], s + 30 * bit, s + 31 * bit)),
            ("bit time 25 % long (decoder fixed at 500 kbit/s)", stretch(t, 1.25))]


def usb_teeth(t, exp):
    idle = t[0]
    s = next(i for i, b in enumerate(t) if b != idle)
    return [("one bit of the first packet inverted (D+ and D-)", invert(t, [0, 1], s + 10 * 20, s + 10 * 21)),
            ("bit time 25 % long (decoder fixed at 1.5 Mbit/s)", stretch(t, 1.25))]


def spdif_teeth(t, exp):
    n = len(t)
    return [("30 samples (0.7 cell) inverted mid-stream", invert(t, [0], n // 2, n // 2 + 30)),
            ("300 samples stretched 1.6 times mid-stream (cells of the wrong length)", t[:n // 2] + stretch(t[n // 2:n // 2 + 300], 1.6) + t[n // 2 + 300:])]


def spdif_probes(t, exp):
    """Changes that are not faults for a decoder that re-locks on every edge; reported, never failing."""
    n = len(t)
    return [("20 samples deleted mid-stream (a phase step of half a cell)", delete(t, n // 2, 20))]


# ----------------------------------------------------------------------------- the cases
CASES = [
    # name, protocol, trace stem, channels, judge, teeth, trim (samples dropped at the start)
    dict(name="uart", stem="deadline-sequencer", judge=judge_uart, teeth=uart_teeth),
    dict(name="spi", stem="deadline-sequencer", judge=judge_spi, teeth=spi_teeth),
    dict(name="i2c", stem="deadline-sequencer", judge=judge_i2c, teeth=i2c_teeth),
    dict(name="ps2", stem="ps2", judge=judge_ps2, teeth=ps2_teeth),
    dict(name="can", stem="can", judge=judge_can, teeth=can_teeth, trim=200),
    dict(name="usb-ls", stem="usb-ls", judge=judge_usb, teeth=usb_teeth),
    dict(name="spdif", stem="spdif/tx-44k1-60000", judge=judge_spdif, teeth=spdif_teeth, probes=spdif_probes),
    dict(name="spdif-chip-fault", stem="spdif/control-44k1-60000", judge=judge_spdif, teeth=None, expect_fail=True,
         expected="spdif/control-44k1-60000"),
]

NO_DECODER = [
    ("10BASE-T (ethernet-10base-t, eth10-node, pin-sampler, sequencer-ethernet, multi-proto Ethernet)",
     "libsigrokdecode 0.5.3 has no decoder for Manchester-coded 10BASE-T or an Ethernet MAC frame "
     "(see results/sigrok-decoders.txt); the Ethernet prototypes keep their scapy-based oracles."),
]


def ps2_quirk():
    """An ideal synthetic PS/2 trace (clock 80 samples per bit, data valid at each falling edge) of four
    device-to-host bytes, decoded without and with the shim."""
    def frame(b):
        bits = [0] + [(b >> i) & 1 for i in range(8)] + [1 - (bin(b).count("1") & 1), 1]
        return [(c, x) for x in bits for c in [1] * 40 + [0] * 40]
    sent = [0x1C, 0xF0, 0x1C, 0x32]
    s = [(1, 1)] * 500
    for b in sent:
        s += frame(b) + [(1, 1)] * 300
    t = bytes(c | (d << 1) for c, d in s)
    print("# command: judge.py --ps2-quirk")
    print("# ideal trace, 1 MHz, bytes sent: " + " ".join("%02x" % b for b in sent))
    for label, tr in (("without the shim", t), ("with the shim", ps2_shim(t, 1e6))):
        got = sigrok(tr, 2, 1e6, "ps2:clk=0:data=1", ["ps2=word:parity-ok:parity-err"])
        print(f"{label}: " + "; ".join(got))
    return 0


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--traces", default=str(HERE / "traces"))
    ap.add_argument("--rate", type=float, help="resample every trace to this rate, as a logic analyser would")
    ap.add_argument("--only", help="comma-separated case names")
    ap.add_argument("--no-teeth", action="store_true")
    ap.add_argument("--ps2-quirk", action="store_true", help="show the ps2 decoder's 12-edge frames on an ideal synthetic trace")
    a = ap.parse_args()
    ensure_image()
    if a.ps2_quirk:
        return ps2_quirk()
    tr = Path(a.traces)
    only = set(a.only.split(",")) if a.only else None
    print("# command: judge.py " + " ".join(sys.argv[1:]))
    print("# commit: " + subprocess.run(["git", "-C", str(ROOT), "rev-parse", "HEAD"], capture_output=True, text=True).stdout.strip())
    for v in sigrok_version():
        print("# " + v.strip())
    print("# image: %s (base and packages pinned in Containerfile)" % IMAGE)
    print("# date: " + datetime.datetime.now().astimezone().isoformat(timespec="seconds"))
    print("# analyser rate: " + (f"{a.rate:g} Hz (resampled)" if a.rate else "as simulated"))
    failed = 0
    rows = []
    for c in CASES:
        if only and c["name"] not in only:
            continue
        stem = c["stem"]
        binf, expf = tr / (stem + ".bin"), tr / ((c.get("expected") or stem) + ".expected")
        if not binf.exists() or not expf.exists():
            print(f"{c['name']}: MISSING TRACE {binf}")
            failed += 1
            rows.append((c["name"], "MISSING", "-"))
            continue
        exp = read_expected(expf)
        src = int(exp["samplerate"])
        base = binf.read_bytes()[c.get("trim", 0):]

        def run(trace):
            rate = src
            if a.rate and a.rate < src:
                trace, rate = resample(trace, src, a.rate), a.rate
            return c["judge"](trace, rate, exp)

        v = run(base)
        if c.get("expect_fail"):
            status = "FLAGGED (as planted in the chip)" if not v.ok else "NOT FLAGGED"
            ok = not v.ok
        else:
            status = "PASS" if v.ok else "FAIL"
            ok = v.ok
        print(f"{c['name']}: {status}: {v.summary}")
        for p in v.problems:
            print(f"    {p}")
        failed += not ok
        tooth_rows = []
        if c.get("teeth") and not a.no_teeth:
            for tname, mutated in c["teeth"](base, exp):
                tv = run(mutated)
                caught = not tv.ok
                print(f"  tooth {c['name']}: {tname}: {'CAUGHT' if caught else 'MISSED'}")
                for p in tv.problems[:3]:
                    print(f"      {p}")
                failed += not caught
                tooth_rows.append((tname, caught))
        if c.get("probes") and not a.no_teeth:
            for pname, mutated in c["probes"](base, exp):
                pv = run(mutated)
                print(f"  probe {c['name']}: {pname}: {'flagged' if not pv.ok else 'NOT flagged'} (informational, not a fault for this decoder)")
                for p in pv.problems[:3]:
                    print(f"      {p}")
        rows.append((c["name"], status, tooth_rows))
    print()
    print("protocols with no sigrok decoder:")
    for n, why in NO_DECODER:
        print(f"  {n}: {why}")
    print()
    print("ALL CHECKS PASS" if not failed else f"{failed} CHECK(S) FAILED")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
