# Lifetime of a gain cell from two measurements made by gc.py (the method of retention/analyse.py,
# extended to both stored values and to a sense amplifier):
#   read sweep (gc.py read): RBL at 2/5/10/20/40 ns after RWL rises, against the stored SN
#   retention  (gc.py ret):  the written level and when SN crosses each level, for a 1 and a 0
# Read criteria at sense time T:
#   inv       an inverter: a 1 reads if RBL < 0.5 V, a 0 if RBL > 0.7 V
#   sa        a latch comparing RBL with a reference column whose dummy cell has its gate held at
#             VREF (a fixed voltage, the same in every corner); a 1 reads if RBL <= RBLref - VM, a
#             0 if RBL >= RBLref + VM, where VM covers the latch's offset. VREF is scanned and the
#             value with the longest worst-case lifetime reported.
#   sa-fixed  the same latch against a fixed reference voltage VRBL on its other input (from a
#             divider, the same in every corner), scanned likewise.
# Lifetime in a corner = min(time for a written 1 to fall to the lowest readable 1, time for a
# written 0 to rise to the highest readable 0). A value that never crosses in the simulated hold
# gives a lower bound (">").
# Usage: python3 life.py READ_FILE RET_FILE [T_ns] [VM]
import re, sys
from collections import defaultdict

TIMES = [2, 5, 10, 20, 40]
read_file, ret_file = sys.argv[1], sys.argv[2]
T = int(sys.argv[3]) if len(sys.argv) > 3 else 20
VM = float(sys.argv[4]) if len(sys.argv) > 4 else 0.03
col = TIMES.index(T)

rbl = defaultdict(dict)
for line in open(read_file):
    m = re.match(r"(mos_\w+)\s+(\d+)C SN\s+([-\d.]+):\s+\S+\s+->\s+\S+\s+RBL\s+(.*)", line)
    if m:
        vals = [float(x) for x in m[4].split()]
        rbl[(m[1], int(m[2]))][float(m[3])] = vals[col]
ret = {}
tstop = None
for line in open(ret_file):
    m = re.search(r"hold ([\d.e-]+) s", line)
    if m:
        tstop = float(m[1]) * 1e3
    m = re.match(r"(mos_\w+)\s+(\d+)C stored (\d) written\s+([-\d.]+) V.*crossings (.*)", line)
    if m:
        cr = [(float(a), None if b == "-" else float(b)) for a, b in re.findall(r"([\d.]+)V@([-\d.]+)(?:ms)?", m[5])]
        ret[(m[1], int(m[2]), int(m[3]))] = (float(m[4]), cr)

def curve(k):
    return sorted(rbl[k].items())

def rbl_at(k, sn):
    pts = curve(k)
    for (s0, r0), (s1, r1) in zip(pts, pts[1:]):
        if s0 <= sn <= s1:
            return r0 + (r1 - r0) * (sn - s0) / (s1 - s0)
    return None

def sn_for(k, target):
    """lowest SN at which RBL falls to [target] (RBL decreases with SN); None if outside"""
    pts = curve(k)
    if pts[0][1] <= target:
        return pts[0][0]            # even the lowest SN swept reaches it
    for (s0, r0), (s1, r1) in zip(pts, pts[1:]):
        if r0 > target >= r1:
            return s0 + (s1 - s0) * (r0 - target) / (r0 - r1)
    return None                     # never: not even the highest SN swept

def time_to(k, bit, level):
    """ms for a written [bit] to reach [level]; 0 if it starts past it; inf-ish bound if never"""
    written, cr = ret[(*k, bit)]
    if (bit and written <= level) or (not bit and written >= level):
        return 0.0, ""
    pts = [(written, 0.0)] + [(lv, t) for lv, t in cr if t is not None and (lv < written if bit else lv > written)]
    for (v0, t0), (v1, t1) in zip(pts, pts[1:]):
        if (bit and v0 >= level >= v1) or (not bit and v0 <= level <= v1):
            return t0 + (t1 - t0) * (level - v0) / (v1 - v0), ""
    # not bracketed: either SN never got that far in the hold (> the hold time), or the level lies
    # beyond the last level the run reports (> the time of the last crossing, a weaker bound)
    reported = [lv for lv, t in cr]
    beyond = (level < min(reported)) if bit else (level > max(reported))
    if beyond and pts[-1][0] == (min(reported) if bit else max(reported)):
        return pts[-1][1], ">"
    return (tstop or pts[-1][1]), ">"

def lifetime(k, s1, s0):
    if s1 is None or s0 is None or s0 >= s1:
        return 0.0, "", s1, s0
    t1, b1 = time_to(k, 1, s1)
    t0, b0 = time_to(k, 0, s0)
    return (t1, b1, s1, s0) if t1 <= t0 else (t0, b0, s1, s0)

keys = sorted(k for k in rbl if (*k, 1) in ret)
def report(label, crit):
    worst = None
    lines = []
    for k in keys:
        s1, s0 = crit(k)
        t, b, _, _ = lifetime(k, s1, s0)
        w1, w0 = ret[(*k, 1)][0], ret[(*k, 0)][0]
        t1, b1 = time_to(k, 1, s1) if s1 is not None else (0.0, "")
        t0, b0 = time_to(k, 0, s0) if s0 is not None else (0.0, "")
        f = lambda v: "  -  " if v is None else f"{v:5.3f}"
        lines.append(f"  {k[0]:7s} {k[1]:3d}C  written 1 {w1:5.3f} / 0 {w0:6.3f}; reads 1 down to {f(s1)}, 0 up to {f(s0)};"
                     f" 1 lasts {b1}{t1:.3f} ms, 0 lasts {b0}{t0:.3f} ms -> {b}{t:.3f} ms")
        if worst is None or t < worst[0]:
            worst = (t, b, k)
    return worst, lines

print(f"{read_file} + {ret_file}: sense at {T} ns")
w, lines = report("inv", lambda k: (sn_for(k, 0.5), (lambda s: None if s is None else s)(sn_for(k, 0.7))))
print(f"inverter (1: RBL < 0.5 V, 0: RBL > 0.7 V): worst {w[1]}{w[0]:.3f} ms at {w[2][0]} {w[2][1]}C")
print("\n".join(lines))
best = None
for i in range(0, 121):
    vref = round(i * 0.01, 2)
    def crit(k, vref=vref):
        rr = rbl_at(k, vref)
        if rr is None:
            return None, None
        return sn_for(k, rr - VM), sn_for(k, rr + VM)
    w, lines = report("sa", crit)
    if best is None or w[0] > best[0][0]:
        best = (w, lines, vref)
w, lines, vref = best
wd = w
print(f"sense amplifier, dummy-cell reference at VREF {vref:.2f} V (best fixed value), margin {VM * 1e3:.0f} mV each side:"
      f" worst {w[1]}{w[0]:.3f} ms at {w[2][0]} {w[2][1]}C")
print("\n".join(lines))
best = None
for i in range(700, 1201):
    vr = round(i * 0.001, 3)
    w, lines = report("saf", lambda k, vr=vr: (sn_for(k, vr - VM), sn_for(k, vr + VM)))
    if best is None or w[0] > best[0][0]:
        best = (w, lines, vr)
w, lines, vr = best
print(f"sense amplifier, fixed reference {vr:.3f} V (best fixed value), margin {VM * 1e3:.0f} mV each side:"
      f" worst {w[1]}{w[0]:.3f} ms at {w[2][0]} {w[2][1]}C")
print("\n".join(lines))
