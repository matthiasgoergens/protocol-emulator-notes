# Joins the two measurements into a lifetime per corner:
#   sweep file (read.py SNSWEEP): RBL after 10 and 20 ns against the stored SN; the lowest SN that
#     still reads as a 1 (RBL below 0.5 V, an inverter's trip point with margin) is interpolated;
#   retention files (run.py): the times at which a freshly written 1 falls past 0.45 .. 0.25 V.
# Lifetime of a 1 = time until SN reaches the lowest readable level, interpolated linearly
# between the reported crossings; a 0 is reported separately (it must stay below the highest
# level that still reads as a 0, where RBL stays above 0.7 V).
import re, sys
from collections import defaultdict

sweep_file, *ret_files = sys.argv[1:]
rbl = defaultdict(list)      # (corner, temp) -> [(sn, rbl10, rbl20)]
for line in open(sweep_file):
    m = re.match(r"(mos_\w+)\s+(\d+)C SN\s+([\d.]+): RBL\s+([-\d.]+)\s+([-\d.]+)\s+([-\d.]+)\s+([-\d.]+)", line)
    if m:
        rbl[(m[1], int(m[2]))].append((float(m[3]), float(m[6]), float(m[7])))

def lowest_readable(pts, col, limit=0.5):
    """lowest SN with RBL < limit, interpolated; None if even the highest SN fails"""
    pts = sorted(pts)
    for (s0, *a), (s1, *b) in zip(pts, pts[1:]):
        r0, r1 = a[col], b[col]
        if r0 >= limit > r1:
            return s0 + (s1 - s0) * (r0 - limit) / (r0 - r1)
    return pts[0][0] if pts and pts[0][1 + col] < limit else None

def highest_zero(pts, col, limit=0.7):
    pts = sorted(pts)
    ok = [s for s, *r in pts if r[col] > limit]
    return max(ok) if ok else None

print("lowest readable 1 (RBL < 0.5 V) and highest readable 0 (RBL > 0.7 V), by sense time")
for k in sorted(rbl):
    lo10, lo20 = lowest_readable(rbl[k], 0), lowest_readable(rbl[k], 1)
    f = lambda v: "  -  " if v is None else f"{v:.3f}"
    print(f"  {k[0]:7s} {k[1]:3d}C  1 needs >= {f(lo10)} V at 10 ns, {f(lo20)} V at 20 ns; "
          f"0 reads up to {f(highest_zero(rbl[k], 0))} V at 10 ns (sweep floor {min(p[0] for p in rbl[k]):.2f})")

for rf in ret_files:
    print(f"\n{rf}")
    for line in open(rf):
        m = re.match(r"\w+\s+(mos_\w+)\s+(\d+)C\s+stored (\d)\s+written\s+([-\d.]+) V.*crossings (.*)", line)
        if not m or m[3] != "1":
            continue
        k = (m[1], int(m[2]))
        cross = [(float(a), None if b == "-" else float(b)) for a, b in re.findall(r"([\d.]+)V@([-\d.]+)(?:us)?", m[5])]
        written = float(m[4])
        out = []
        for col, label in ((0, "10 ns"), (1, "20 ns")):
            need = lowest_readable(rbl[k], col) if k in rbl else None
            if need is None:
                out.append(f"{label}: no sweep"); continue
            if written < need:
                out.append(f"{label}: unreadable at once (written {written:.3f} < {need:.3f})"); continue
            # interpolate the crossing time at level [need] from the reported levels (falling)
            pts = [(written, 0.0)] + [(lv, t) for lv, t in cross if t is not None and lv < written]
            t = None
            for (v0, t0), (v1, t1) in zip(pts, pts[1:]):
                if v0 >= need >= v1:
                    t = t0 + (t1 - t0) * (v0 - need) / (v0 - v1); break
            if t is None:
                if any(lv <= need and tc is None for lv, tc in cross) or len(pts) == 1:
                    txt = "> 50 ms"            # a level at or below [need] was never reached
                else:                          # [need] is below the lowest reported level
                    txt = f"> {pts[-1][1] / 1000:.2f} ms (needs a level below {pts[-1][0]} V)"
            else:
                txt = f"{t / 1000:.2f} ms"
            out.append(f"{label}: {txt} (to {need:.3f} V)")
        print(f"  {k[0]:7s} {k[1]:3d}C  written {written:.3f} V   lifetime of a 1 read at " + ";  ".join(out))
