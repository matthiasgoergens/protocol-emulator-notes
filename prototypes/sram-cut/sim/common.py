"""Shared helpers for the SRAM corner-cutting simulations (ngspice 44.2 + PSP 103 via OSDI, IHP
SG13G2 models). Runs inside the spice-retention container; see run.sh.

Conventions: VDD 1.2 V, the only rail. Devices are the PDK subcircuits (X d g s b model w= l=).
Every analysis writes its netlist and raw vectors into the container's /work (on the host
/var/tmp/spice-sram-cut/RUN), so each number can be traced to its netlist."""
import math, os, re, subprocess
from concurrent.futures import ThreadPoolExecutor

VDD = 1.2
CORNERS = ["mos_tt", "mos_ff", "mos_ss", "mos_sf", "mos_fs"]
TEMPS = [27, 85]
JOBS = int(os.environ.get("JOBS", "4"))


def libs(corner, mismatch=False):
    c = corner + ("_mismatch" if mismatch else "")
    return (f".lib /pdk/libs.tech/ngspice/models/cornerMOSlv.lib {c}\n"
            f".lib /pdk/libs.tech/ngspice/models/cornerMOShv.lib {c}\n")


def nmos(name, d, g, s, w, l=0.13, b="0", hv=False):
    return f"X{name} {d} {g} {s} {b} sg13_{'hv' if hv else 'lv'}_nmos w={w}u l={l}u\n"


def pmos(name, d, g, s, w, l=0.13, b="vdd", hv=False):
    return f"X{name} {d} {g} {s} {b} sg13_{'hv' if hv else 'lv'}_pmos w={w}u l={l}u\n"


def run(name, text, timeout=1800):
    """Write /work/NAME.sp, run ngspice in batch mode, return stdout+stderr."""
    sp = f"/work/{name}.sp"
    with open(sp, "w") as f:
        f.write(text)
    p = subprocess.run(["ngspice", "-b", sp], capture_output=True, text=True, timeout=timeout)
    out = p.stdout + p.stderr
    with open(f"/work/{name}.log", "w") as f:
        f.write(out)
    return out


def control(body, seed=None):
    s = f"set rndseed={seed}\n" if seed is not None else ""
    return f".control\n{s}pre_osdi /osdi/psp103.osdi\n{body}\n.endc\n.end\n"


def meas(out, key):
    m = re.search(rf"^{key}\s*=\s*([-+0-9.eE]+)", out, re.M)
    return float(m.group(1)) if m else float("nan")


def read_table(path):
    """Read a wrdata file written with wr_singlescale and wr_vecnames: returns dict name -> list."""
    with open(path) as f:
        lines = [l.split() for l in f if l.strip()]
    names = lines[0]
    cols = {n: [] for n in names}
    for row in lines[1:]:
        for n, v in zip(names, row):
            cols[n].append(float(v))
    return cols


def pmap(fn, items):
    with ThreadPoolExecutor(max_workers=JOBS) as ex:
        return list(ex.map(fn, items))


# ---------------------------------------------------------------- static noise margin
def _interp(xs, ys, x):
    """Linear interpolation on increasing xs; None outside."""
    if x < xs[0] or x > xs[-1]:
        return None
    lo, hi = 0, len(xs) - 1
    while hi - lo > 1:
        mid = (lo + hi) // 2
        if xs[mid] <= x:
            lo = mid
        else:
            hi = mid
    if xs[hi] == xs[lo]:
        return ys[lo]
    t = (x - xs[lo]) / (xs[hi] - xs[lo])
    return ys[lo] + t * (ys[hi] - ys[lo])


def snm(s, ya, yb):
    """Seevinck's method. The loop is broken into two half cells driven by the same swept input s:
    half B gives curve 1, QB = fB(Q), the points (s, yb); half A gives curve 2, Q = fA(QB), the
    points (ya, s). Rotating by 45 degrees (u = (x-y)/sqrt2, v = (x+y)/sqrt2), the largest square
    in a lobe has its diagonal along v, so its side is max |v1 - v2| / sqrt2 within the lobe.
    Returns (lobe with Q low, lobe with Q high, min of the two); a lobe that has closed gives a
    value <= 0 (the cell is monostable there)."""
    r = 1 / math.sqrt(2)
    c1 = sorted(((x - y) * r, (x + y) * r) for x, y in zip(s, yb))
    c2 = sorted(((x - y) * r, (x + y) * r) for x, y in zip(ya, s))
    u1, v1 = [p[0] for p in c1], [p[1] for p in c1]
    u2, v2 = [p[0] for p in c2], [p[1] for p in c2]
    lo = max(u1[0], u2[0]); hi = min(u1[-1], u2[-1])
    n = 2000
    best_neg, best_pos = -1e9, -1e9
    for i in range(n + 1):
        u = lo + (hi - lo) * i / n
        a = _interp(u1, v1, u); b = _interp(u2, v2, u)
        if a is None or b is None:
            continue
        d = a - b
        if u < 0:
            best_neg = max(best_neg, d)
        else:
            best_pos = max(best_pos, -d)
    return best_neg * r, best_pos * r, min(best_neg, best_pos) * r
