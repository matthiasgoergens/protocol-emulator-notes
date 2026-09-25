"""Static-latch variants that cut corners on the 6T cell: hold/read SNM, write, leakage, retention.

  ./run.sh RUN cellsim.py CELL [key=value ...] [mode=corners|mc:N:CORNER:TEMP|retention|vsweep]

CELL:
  6t   the usual cell (for the supply sweep); keys pd pg pu
  4tp  loadless 4T (Noda et al.): NMOS drivers, PMOS access transistors whose leakage from the
       precharged bit lines is the only load. Keys d (driver W), a (access W), ld, la, hvd/hva
       (1 = thick oxide). Word line active low; idle level wlidle (default VDD).
  4tn  4T without any PMOS: NMOS drivers, NMOS access transistors, the word line idling at
       wlidle (> 0) so that the access leakage holds the 1. Word line active high.
  5t   6T without the QB access transistor: one bit line. Keys pd pg pu.
  6n   all-NMOS static cell: 6T with each PMOS pull-up replaced by an NMOS "leakage load" from VDD
       to the node, its gate tied to the node (Vgs = 0 always, so it only ever leaks). Driver and
       load are the same device type, so their leakage ratio (k/d) holds across global corners.
       Keys d (driver W), a (access W), k (load W), lk (load L). No PMOS, no n-well.
Other keys: vcell (cell supply for hold, SNM and leakage; default 1.2), vbl (bit-line level during
read, default 1.2), wlon (active word-line level; default 0 for 4tp, 1.2 otherwise), corners
(comma list), temps (comma list).

Methods as in sram6t.py (Seevinck butterfly, DC 5 mV steps; transient write with a 400 ns bit-line
ramp; leakage = total current from the supply and both bit lines at the DC operating point).
Retention (mode=retention, for cells whose hold butterfly has lost a lobe): transient in hold from
the state a write leaves (Q = cell high level, QB = 0, set by .ic with the cell in hold, so the
operating point is computed with those nodes held, not charge-shared), reporting when Q - QB
falls below 0.2 V.
"""
import sys, os, math, statistics
from common import *

CELL = sys.argv[1]
K = dict(kv.split("=", 1) for kv in sys.argv[2:] if "=" in kv)
f = lambda k, d: float(K.get(k, d))
MODE = K.get("mode", "corners")
VCELL = f("vcell", VDD)
VBL = f("vbl", VDD)
CORN = K.get("corners", ",".join(CORNERS)).split(",")
TMPS = [int(t) for t in K.get("temps", ",".join(map(str, TEMPS))).split(",")]

if CELL in ("6t", "5t"):
    PD, PG, PU = f("pd", 0.15), f("pg", 0.15), f("pu", 0.15)
    WLIDLE, WLON = 0.0, f("wlon", VDD)
elif CELL == "4tp":
    D, A = f("d", 0.30), f("a", 0.15)
    LD, LA = f("ld", 0.13), f("la", 0.13)
    HVD, HVA = K.get("hvd") == "1", K.get("hva") == "1"
    WLIDLE, WLON = f("wlidle", VDD), f("wlon", 0.0)
elif CELL == "6n":
    D, A, KW = f("d", 0.30), f("a", 0.15), f("k", 0.60)
    LD, LA, LK = f("ld", 0.13), f("la", 0.13), f("lk", 0.13)
    HVD, HVA = K.get("hvd") == "1", False
    WLIDLE, WLON = 0.0, f("wlon", VDD)
elif CELL == "4tn":
    D, A = f("d", 0.30), f("a", 0.15)
    LD, LA = f("ld", 0.13), f("la", 0.13)
    HVD, HVA = K.get("hvd") == "1", K.get("hva") == "1"
    WLIDLE, WLON = f("wlidle", 0.4), f("wlon", VDD)
else:
    raise SystemExit(f"unknown cell {CELL}")
TAG = CELL + "_" + "_".join(f"{k}{v}" for k, v in sorted(K.items()) if k not in ("mode", "corners", "temps"))


def half(tag, inp, out, bl, wl, access=True):
    if CELL in ("6t", "5t"):
        s = pmos(f"PU{tag}", out, inp, "vcell", PU, b="vcell") + nmos(f"PD{tag}", out, inp, "0", PD)
        if access:
            s += nmos(f"PG{tag}", bl, wl, out, PG)
        return s
    s = nmos(f"D{tag}", out, inp, "0", D, max(LD, 0.45) if HVD else LD, hv=HVD)
    if CELL == "6n":
        s += nmos(f"K{tag}", "vcell", out, out, KW, LK)
        if access:
            s += nmos(f"A{tag}", bl, wl, out, A, LA)
        return s
    if CELL == "4tp":
        s += pmos(f"A{tag}", bl, wl, out, A, max(LA, 0.45) if HVA else LA, b="vdd", hv=HVA)
    else:
        s += nmos(f"A{tag}", bl, wl, out, A, max(LA, 0.45) if HVA else LA, hv=HVA)
    return s


def cell(q, qb):
    """The whole cell: half A drives Q (input QB) onto BL, half B drives QB (input Q) onto BLB."""
    return half("A", qb, q, "bl", "wl") + half("B", q, qb, "blb", "wl", access=CELL != "5t")


def head(corner, temp, mm, what):
    return (f"* {CELL} {what}\n" + libs(corner, mm) + f".temp {temp}\n"
            f"vdd vdd 0 {VDD}\nvcellsrc vcell 0 {VCELL}\n")


def go(name, ckt, body, seed):
    if seed is not None:
        open(f"/work/{name}.cir", "w").write(ckt + ".end\n")
        return run(name, f"* mc driver\n.control\nset rndseed={seed}\npre_osdi /osdi/psp103.osdi\n"
                         f"source /work/{name}.cir\n{body}\n.endc\n.end\n")
    return run(name, ckt + control(body))


def butterfly(corner, temp, mode, seed=None, mm=False):
    name = f"bf_{TAG}_{corner}_{temp}_{mode}_{seed}"
    wl = WLON if mode == "read" else WLIDLE
    blv = VBL if mode == "read" else VDD
    ckt = (head(corner, temp, mm, "butterfly " + mode) +
           f"vwl wl 0 {wl}\nvbl bl 0 {blv}\nvblb blb 0 {blv}\nvs s 0 0\n"
           + half("A", "s", "ya", "bl", "wl") + half("B", "s", "yb", "blb", "wl", access=CELL != "5t"))
    go(name, ckt, f"dc vs 0 {VCELL if CELL in ('6t', '5t') else VDD} 0.005\nset wr_singlescale\n"
                  f"set wr_vecnames\nwrdata /work/{name}.dat v(ya) v(yb)\n", seed)
    t = read_table(f"/work/{name}.dat")
    return snm(t[list(t)[0]], t["v(ya)"], t["v(yb)"])


def write(corner, temp, direction, seed=None, mm=False):
    """direction 0: Q starts at 1 and BL ramps VDD -> 0 (write a 0 into Q).
    direction 1: Q starts at 0 and BL ramps 0 -> VDD (write a 1 into Q; only meaningful for 5t,
    where there is no BLB to pull QB down). BLB stays at VDD. Returns V(BL) at the flip, or nan."""
    name = f"wr_{TAG}_{corner}_{temp}_{direction}_{seed}"
    a, b = (VDD, 0) if direction == 0 else (0, VDD)
    q0, qb0 = (VCELL, 0) if direction == 0 else (0, VCELL)
    ckt = (head(corner, temp, mm, "write") +
           f"vwl wl 0 pwl(0 {WLIDLE} 1n {WLIDLE} 1.1n {WLON})\n"
           f"vbl bl 0 pwl(0 {a} 2n {a} 402n {b})\nvblb blb 0 {VDD}\n" + cell("q", "qb") +
           f".ic v(q)={q0} v(qb)={qb0}\n")
    out = go(name, ckt, "tran 0.1n 410n\nmeas tran wm find v(bl) when v(q)=v(qb) cross=1\n", seed)
    return meas(out, "wm")


def leakage(corner, temp):
    name = f"lk_{TAG}_{corner}_{temp}"
    ckt = (head(corner, temp, False, "leakage") +
           f"vwl wl 0 {WLIDLE}\nvbl bl 0 {VDD}\nvblb blb 0 {VDD}\n" + cell("q", "qb") +
           f".nodeset v(q)={VCELL} v(qb)=0\n")
    out = run(name, ckt + control(
        "op\nprint v(q) v(qb)\nlet itot = -i(vdd)-i(vcellsrc)-i(vbl)-i(vblb)-i(vwl)\nprint itot"))
    return meas(out, "itot"), meas(out, "v\\(q\\)"), meas(out, "v\\(qb\\)")


def retention(corner, temp):
    """Hold transient from a written state; returns the time (s) at which Q - QB < 0.2 V, or inf."""
    name = f"rt_{TAG}_{corner}_{temp}"
    ckt = (head(corner, temp, False, "retention") +
           f"vwl wl 0 {WLIDLE}\nvbl bl 0 {VDD}\nvblb blb 0 {VDD}\n" + cell("q", "qb") +
           f".ic v(q)={VCELL if CELL in ('6t', '5t') else VDD} v(qb)=0\n")
    out = run(name, ckt + control(
        "tran 1u 100m\nmeas tran tfail when v(q)=v(qb)+0.2 cross=1\n"
        "meas tran q1u find v(q) at=1u\nmeas tran q1m find v(q) at=1m\nmeas tran q100m find v(q) at=99m\n"
        "meas tran qb100m find v(qb) at=99m"))
    t = meas(out, "tfail")
    return (t if not math.isnan(t) else math.inf), meas(out, "q1m"), meas(out, "q100m"), meas(out, "qb100m")


def kick(corner, temp, hold, wkick=10e-9, seed=None, mm=False):
    """Write a 1 into Q (from a stored 0, 20 ns word-line pulse, BLB driven to 0), hold for [hold]
    seconds with the word line idle and both bit lines at VDD, then 'kick': pulse the word line for
    [wkick] with both bit lines held at VDD (no data driven), idle again, and look 100 ns later.
    Returns (Q, QB just before the kick, Q, QB after it). A kick is a refresh that needs no read:
    the precharged bit lines recharge whichever node is high."""
    name = f"kk_{TAG}_{corner}_{temp}_{hold:.3g}_{seed}"
    t1 = 22e-9 + hold
    t2 = t1 + wkick
    idle, on = WLIDLE, WLON
    ckt = (head(corner, temp, mm, "write, hold, kick") +
           f"vwl wl 0 pwl(0 {idle} 1n {idle} 1.1n {on} 21n {on} 21.1n {idle} {t1:.15e} {idle} "
           f"{t1 + 0.1e-9:.15e} {on} {t2:.15e} {on} {t2 + 0.1e-9:.15e} {idle})\n"
           f"vbl bl 0 {VDD}\nvblb blb 0 pwl(0 0 21.5n 0 22n {VDD})\n" + cell("q", "qb") +
           f".ic v(q)=0 v(qb)={VCELL}\n")
    body = (f"tran {min(hold / 200, 1e-6):.3e} {t2 + 100e-9:.15e}\n"
            f"meas tran qw find v(q) at=21n\n"
            f"meas tran qa find v(q) at={t1 - 1e-12:.15e}\nmeas tran qba find v(qb) at={t1 - 1e-12:.15e}\n"
            f"meas tran qz find v(q) at={t2 + 99e-9:.15e}\nmeas tran qbz find v(qb) at={t2 + 99e-9:.15e}\n")
    out = go(name, ckt, body, seed)
    return meas(out, "qw"), meas(out, "qa"), meas(out, "qba"), meas(out, "qz"), meas(out, "qbz")


desc = " ".join(f"{k}={v}" for k, v in sorted(K.items()))
if MODE == "kick":
    holds = [float(h) for h in K.get("holds", "1e-6,1e-5,1e-4,1e-3,1e-2,1e-1").split(",")]
    print(f"{CELL} {desc}: write 1, hold, kick (WL {WLON} V for 10 ns, bit lines at VDD), check")
    jobs = [(c, t, h) for c in CORN for t in TMPS for h in holds]
    for (c, t, h), (qw, qa, qba, qz, qbz) in zip(jobs, pmap(lambda j: kick(*j), jobs)):
        ok = "ok" if qz > qbz + 0.3 else "LOST"
        print(f"{c:7s} {t:3d}  hold {h:8.1e} s  written Q {qw:.3f}  before kick Q/QB {qa:.3f}/{qba:.3f}  "
              f"after Q/QB {qz:.3f}/{qbz:.3f}  {ok}", flush=True)
    raise SystemExit
if MODE == "corners":
    print(f"{CELL} {desc}; WL idle {WLIDLE} V, active {WLON} V; cell supply {VCELL} V")
    print("corner   T   hold SNM(mV)  read SNM(mV)  write-0 BL(mV)  write-1 BL(mV)  leak(pA/bit)  Q/QB hold (V)")
    def one(ct):
        c, t = ct
        h = butterfly(c, t, "hold"); r = butterfly(c, t, "read")
        w0 = write(c, t, 0); w1 = write(c, t, 1) if CELL == "5t" else float("nan")
        lk, q, qb = leakage(c, t)
        return c, t, h, r, w0, w1, lk, q, qb
    for c, t, h, r, w0, w1, lk, q, qb in pmap(one, [(c, t) for c in CORN for t in TMPS]):
        print(f"{c:7s} {t:3d}  {1e3*h[2]:8.1f}     {1e3*r[2]:8.1f}      {1e3*w0:8.1f}        {1e3*w1:8.1f}     "
              f"{1e12*lk:10.2f}   {q:.3f}/{qb:.3f}", flush=True)
elif MODE == "retention":
    print(f"{CELL} {desc}: hold transient (100 ms) from Q=1, QB=0; WL idle {WLIDLE} V")
    for (c, t), (tf, q1m, q100m, qb100m) in zip([(c, t) for c in CORN for t in TMPS],
                                                 pmap(lambda ct: retention(*ct), [(c, t) for c in CORN for t in TMPS])):
        print(f"{c:7s} {t:3d}  fails at {tf*1e3 if tf != math.inf else math.inf:10.4g} ms   Q(1ms) {q1m:.3f}  "
              f"Q(99ms) {q100m:.3f}  QB(99ms) {qb100m:.3f}", flush=True)
elif MODE == "vsweep":
    # hold SNM against the cell supply: the data-retention voltage and the leakage it buys
    vs = [float(v) for v in K.get("vlist", "1.2,1.0,0.8,0.7,0.6,0.5,0.4,0.3,0.25,0.2").split(",")]
    print(f"{CELL} {desc}: hold SNM and leakage against the cell supply")
    jobs = [(c, t, v) for c in CORN for t in TMPS for v in vs]
    def one(ctv):
        global VCELL
        c, t, v = ctv
        return ctv
    # VCELL is global; run each supply in its own process-free loop by rewriting the global
    res = []
    for v in vs:
        VCELL = v
        TAG = CELL + f"_v{v}"
        r = pmap(lambda ct: (ct, butterfly(ct[0], ct[1], "hold"), leakage(ct[0], ct[1])),
                 [(c, t) for c in CORN for t in TMPS])
        for (c, t), h, lk in r:
            print(f"vcell {v:4.2f}  {c:7s} {t:3d}  hold SNM {1e3*h[2]:7.1f} mV  leakage {1e12*lk[0]:9.2f} pA/bit"
                  f"  (Q {lk[1]:.3f}, QB {lk[2]:.3f})", flush=True)
elif MODE.startswith("mc"):
    _, n, corner, temp = MODE.split(":")
    n, temp = int(n), int(temp)
    def one(seed):
        return seed, butterfly(corner, temp, "hold", seed, True), butterfly(corner, temp, "read", seed, True), \
            write(corner, temp, 0, seed, True)
    rows = pmap(one, range(1, n + 1))
    print(f"{CELL} {desc}, {corner} {temp} C, {n} mismatch samples")
    for s, h, r, w in rows:
        print(f"seed {s:4d}  hold {1e3*h[2]:7.1f}  read {1e3*r[2]:7.1f}  write-0 BL {1e3*w:7.1f} mV")
    for k, xs in (("hold SNM", [r[1][2] for r in rows]), ("read SNM", [r[2][2] for r in rows]),
                  ("write-0 BL", [r[3] for r in rows])):
        xs2 = [x for x in xs if not math.isnan(x)]
        if len(xs2) < 2:
            print(f"{k}: {len(xs) - len(xs2)} of {len(xs)} samples did not flip"); continue
        mu, sd = statistics.mean(xs2), statistics.stdev(xs2)
        print(f"{k:11s}: mean {1e3*mu:6.1f} mV  sigma {1e3*sd:5.1f} mV  min {1e3*min(xs2):6.1f}  "
              f"mean/sigma {mu/sd if sd else float('inf'):5.2f}  <=0: {sum(x <= 0 for x in xs2)}  "
              f"no flip: {len(xs) - len(xs2)}")
