# Lifetime of a stored 1 in the bank, joining two simulations per corner:
#   the bank read sweep (bankread.py): the sense inverter's output at the sampling edge against
#     the stored level; the lowest level that still reads 1 is interpolated where the output
#     crosses VDD / 2;
#   a retention run (../../gain-cell/retention/run.py): the times at which a written 1 falls past
#     a list of levels.
# Lifetime = time until the written 1 falls to that lowest readable level, interpolated linearly
# between the reported crossings. Also printed: the highest stored level that still reads 0 (a
# stored 0 must stay below it; in this cell it stays below 0.03 V, findings 6).
# Usage: python3 banklife.py SWEEP RETENTION
import re, sys

sweep, ret = sys.argv[1:3]
vdd = 1.2
pts = {}
for line in open(sweep):
    m = re.search(r"VDD ([\d.]+)", line)
    if m and line.startswith("bank read"):
        vdd = float(m.group(1))
    m = re.match(r"(mos_\w+)\s+(\d+)C SN\s+([-\d.]+): RBL at E1\s+([-\d.]+)\s+at sample\s+([-\d.]+)\s+sense out\s+([-\d.]+)", line)
    if m:
        pts.setdefault((m[1], int(m[2])), []).append((float(m[3]), float(m[6]), float(m[4])))

def lowest_one(p):
    p = sorted(p)
    for (s0, y0, _), (s1, y1, _) in zip(p, p[1:]):
        if y0 <= vdd / 2 < y1:
            return s0 + (s1 - s0) * (vdd / 2 - y0) / (y1 - y0)
    return None

print(f"# banklife.py {sweep} {ret}  (VDD {vdd}; read as 1 when the sense output exceeds VDD/2 at the sample edge)")
for line in open(ret):
    m = re.match(r"\w+\s+(mos_\w+)\s+(\d+)C\s+stored 1\s+written\s+([-\d.]+) V.*crossings (.*)", line)
    if not m:
        continue
    k = (m[1], int(m[2]))
    written = float(m[3])
    cross = [(float(a), None if b == "-" else float(b)) for a, b in re.findall(r"([\d.]+)V@([-\d.]+)(?:us)?", m[4])]
    p = pts.get(k)
    if not p:
        print(f"{k[0]} {k[1]}C: no read sweep"); continue
    need = lowest_one(p)
    pre = min(x[2] for x in p)
    zero_ok = max((s for s, y, _ in p if y < vdd / 2 and s <= (need or 9)), default=None)
    if need is None:
        print(f"{k[0]:7s} {k[1]:3d}C  written {written:.3f} V; no stored level in the sweep reads 1"); continue
    if written < need:
        txt = f"unreadable at once (written {written:.3f} V < {need:.3f} V)"
    else:
        seq = [(written, 0.0)] + [(lv, t) for lv, t in cross if t is not None and lv < written]
        t = None
        for (v0, t0), (v1, t1) in zip(seq, seq[1:]):
            if v0 >= need >= v1:
                t = t0 + (t1 - t0) * (v0 - need) / (v0 - v1); break
        if t is None:
            last = seq[-1]
            txt = (f"> {last[1] / 1000:.2f} ms (not yet at {need:.3f} V; lowest level reported {last[0]} V)")
        else:
            txt = f"{t / 1000:.2f} ms"
    print(f"{k[0]:7s} {k[1]:3d}C  written {written:.3f} V, reads 1 down to {need:.3f} V, 0 up to "
          f"{zero_ok:.3f} V, precharge reaches {pre:.3f} V: lifetime of a 1 {txt}")
