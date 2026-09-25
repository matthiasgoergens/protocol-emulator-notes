# Joins a read sweep (cell.py MODE=read) and hold runs (cell.py MODE=hold) into lifetimes.
#   read file: RBL at 5/10/20 ns against the selected cell's SN. At each corner, a 1 reads if
#     RBL falls below 0.5 V by the sense time (for plv: RBL rises above 0.7 V), a 0 if RBL stays
#     above 0.7 V (plv: below 0.5 V). L1 = lowest SN that reads as 1 (NMOS storage; for plv the
#     roles swap: the conducting value is a stored 0), H0 = highest SN that reads as 0;
#     interpolated linearly between sweep points.
#   hold file: crossing times of a fine level grid for a written 1 (falling) and 0 (rising).
# Lifetime = time for the written level to reach the threshold, interpolated in log time between
# grid levels; "> TSTOP" when it never gets there, "0" when the written level is already wrong.
# Usage: life.py READFILE HOLDFILE... [--sense 10|20|5] [--plv]
import math, re, sys
from collections import defaultdict

args = [a for a in sys.argv[1:] if not a.startswith("--")]
sense = {"5": 0, "10": 1, "20": 2}[next((a.split("=")[1] for a in sys.argv if a.startswith("--sense=")), "10")]
plv = "--plv" in sys.argv
# sense thresholds on RBL: a 1 (NMOS storage) needs RBL < TH1, a 0 needs RBL > TH0; the default
# is an inverter tripping at 0.6 V with 0.1 V margin each way; a latch sense amplifier with a
# reference would allow e.g. --th1=0.8 --th0=1.0
TH1 = float(next((a.split("=")[1] for a in sys.argv if a.startswith("--th1=")), "0.5"))
TH0 = float(next((a.split("=")[1] for a in sys.argv if a.startswith("--th0=")), "0.7"))
readf, holdfs = args[0], args[1:]

pts = defaultdict(list)
for line in open(readf):
    m = re.match(r"(mos_\w+)\s+(\d+)C SN\s+([-\d.]+): RBL\s+([-\d.na]+)\s+([-\d.na]+)\s+([-\d.na]+)", line)
    if m:
        pts[(m[1], int(m[2]))].append((float(m[3]), float(m[4 + sense])))

def thresholds(p):
    """(L1, H0): for NMOS storage RBL falls with SN; a 1 needs RBL < 0.5, a 0 RBL > 0.7.
    For plv RBL rises as SN falls: a stored 0 (conducting) needs RBL > 0.7, a 1 RBL < 0.5."""
    p = sorted(p)
    def cross(limit, above_is_high_sn):
        # the SN where RBL crosses [limit], scanning upwards in SN
        for (s0, r0), (s1, r1) in zip(p, p[1:]):
            if (r0 - limit) * (r1 - limit) <= 0 and r0 != r1:
                return s0 + (s1 - s0) * (r0 - limit) / (r0 - r1)
        return None
    if not plv:
        l1 = cross(TH1, True)       # SN above which RBL < TH1
        h0 = cross(TH0, True)       # SN below which RBL > TH0
        if l1 is None and p and p[0][1] < TH1: l1 = p[0][0]
        if h0 is None and p and p[-1][1] > TH0: h0 = p[-1][0]
        return l1, h0
    # plv: conducting value is a low SN. H0' = highest SN that still reads as a (conducting) 0:
    # RBL > 0.7; L1' = lowest SN that reads as 1: RBL < 0.5
    h0 = cross(TH0, False)
    l1 = cross(TH1, False)
    return l1, h0

def parse_hold(f):
    res = {}
    for line in open(f):
        m = re.match(r"(mos_\w+)\s+(\d+)C stored (\d)\s+vw\s+([-\d.]+).*?vend\s+([-\d.na/ ]+?)\s+crossings (.*)", line)
        if not m:
            continue
        cr = [(float(a), float(b)) for a, b in re.findall(r"([-\d.]+)@([-\d.eE+]+)", m[6])]
        vend = float(m[5]) if m[5].strip() not in ("n/a",) else None
        res[(m[1], int(m[2]), int(m[3]))] = (float(m[4]), cr, vend)
    tstop = re.search(r"TSTOP=(\S+)", open(f).read())
    return res, tstop[1] if tstop else "?"

def t_at(vw, cr, level, falling):
    """time the level is crossed, interpolated in log time between grid levels past vw"""
    c = sorted([(lv, t) for lv, t in cr if (lv < vw - 0.005 if falling else lv > vw + 0.005)],
               key=lambda x: -x[0] if falling else x[0])
    if (falling and vw < level) or (not falling and vw > level):
        return 0.0
    prev = (vw, 30e-9)
    for lv, t in c:
        if (falling and lv <= level) or (not falling and lv >= level):
            (v0, t0), (v1, t1) = prev, (lv, t)
            if v1 == v0:
                return t1
            f = (level - v0) / (v1 - v0)
            return math.exp(math.log(t0) + f * (math.log(max(t1, t0)) - math.log(t0)))
        prev = (lv, t)
    return None

def fmt(t, tstop):
    if t is None:
        return f">{tstop}"
    if t == 0:
        return "0 (written wrong)"
    for u, s in ((1e-3, "ms"), (1e-6, "us"), (1e-9, "ns")):
        if t >= u:
            return f"{t / u:.3g} {s}"
    return f"{t:.2g} s"

print(f"read thresholds from {readf}, sense at {['5', '10', '20'][sense]} ns, RBL < {TH1} reads 1, > {TH0} reads 0"
      f" ({'PMOS storage, a stored 0 conducts' if plv else 'NMOS storage'})")
th = {k: thresholds(v) for k, v in pts.items()}
for k in sorted(th):
    l1, h0 = th[k]
    print(f"  {k[0]:7s} {k[1]:3d}C  a 1 reads above {l1 if l1 is None else round(l1, 3)} V, "
          f"a 0 reads below {h0 if h0 is None else round(h0, 3)} V")
for hf in holdfs:
    res, tstop = parse_hold(hf)
    print(f"\n{hf}")
    worst = None
    for k in sorted(th):
        l1, h0 = th[k]
        r1, r0 = res.get((k[0], k[1], 1)), res.get((k[0], k[1], 0))
        if not r1 or not r0:
            continue
        if not plv:
            t1 = t_at(r1[0], r1[1], l1, True) if l1 is not None else 0.0
            t0 = t_at(r0[0], r0[1], h0, False) if h0 is not None else 0.0
        else:
            # plv: the stored 1 must stay above L1' (not conducting); the stored 0 below H0'
            t1 = t_at(r1[0], r1[1], l1, True) if l1 is not None else 0.0
            t0 = t_at(r0[0], r0[1], h0, False) if h0 is not None else 0.0
        both = [x for x in (t1, t0)]
        life = min((x if x is not None else math.inf) for x in both)
        worst = life if worst is None else min(worst, life)
        print(f"  {k[0]:7s} {k[1]:3d}C  1: written {r1[0]:.3f} end {r1[2]}  -> {fmt(t1, tstop):>18s}"
              f"   0: written {r0[0]:.3f} end {r0[2]} -> {fmt(t0, tstop):>18s}   lifetime {fmt(None if life == math.inf else life, tstop)}")
    print(f"  worst corner: {fmt(None if worst == math.inf else worst, tstop)}")
