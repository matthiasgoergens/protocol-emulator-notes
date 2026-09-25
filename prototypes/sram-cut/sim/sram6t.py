"""6T SRAM cell: hold SNM, read SNM, write margin, leakage, over corners and with mismatch.

  ./run.sh RUN sram6t.py SIZES [MODE]
SIZES: pd,pg,pu widths in um, optionally :lpd,lpg,lpu lengths (default 0.13), e.g. 0.30,0.30,0.15
MODE:  corners (default): tt/ff/ss/sf/fs x 27/85 C, no mismatch
       mc:N:CORNER:TEMP   N Monte Carlo samples of the PDK mismatch model (mos_*_mismatch libs)
Environment: VWL (word-line high level for read SNM and write, default 1.2), VBL (bit-line
precharge level during read, default 1.2), HV=1 for thick-oxide devices everywhere.

Methods (stated, so the numbers can be compared):
- SNM: Seevinck's butterfly. The two half cells (inverter + access transistor) are separate
  instances driven by one swept input (DC, 5 mV steps). Hold: WL 0, bit lines at VDD. Read: WL at
  VWL, both bit lines clamped at VBL (the usual worst case: a precharged bit line that has not yet
  moved). Reported: the smaller lobe.
- Write margin: transient. The cell starts holding Q=1 (a DC-stable state, so .ic sets nothing
  that the cell would not hold anyway), WL rises to VWL at 1 ns, BLB stays at VDD, and BL ramps
  from VDD to 0 over 400 ns (3 mV/ns, quasi-static). The write margin is V(BL) when Q and QB
  cross; a larger margin is an easier write. No crossing = not writable.
- Leakage: DC operating point in hold (WL 0, BL = BLB = VDD), the sum of the currents drawn from
  VDD and both bit lines, per bit.
"""
import sys, os, math, statistics
from common import *

sizes = sys.argv[1]
w, _, l = sizes.partition(":")
PD, PG, PU = (float(x) for x in w.split(","))
LPD, LPG, LPU = (float(x) for x in l.split(",")) if l else (0.13, 0.13, 0.13)
HV = os.environ.get("HV") == "1"
if HV:
    LPD, LPG, LPU = (max(x, 0.45) for x in (LPD, LPG, LPU))
VWL = float(os.environ.get("VWL", VDD))
VBL = float(os.environ.get("VBL", VDD))
MODE = sys.argv[2] if len(sys.argv) > 2 else "corners"
TAG = f"6t_{PD}_{PG}_{PU}" + ("_hv" if HV else "")


def half(tag, inp, out, bl, wl):
    return (pmos(f"PU{tag}", out, inp, "vdd", PU, LPU, hv=HV) +
            nmos(f"PD{tag}", out, inp, "0", PD, LPD, hv=HV) +
            nmos(f"PG{tag}", bl, wl, out, PG, LPG, hv=HV))


def butterfly(corner, temp, mode, seed=None, mm=False):
    """Returns (snm_Qlow, snm_Qhigh, snm)."""
    name = f"bf_{TAG}_{corner}_{temp}_{mode}_{seed}"
    wl = VWL if mode == "read" else 0
    ckt = (f"* butterfly {mode}\n" + libs(corner, mm) + f".temp {temp}\n"
           f"vdd vdd 0 {VDD}\nvwl wl 0 {wl}\nvbl bl 0 {VBL}\nvblb blb 0 {VBL}\nvs s 0 0\n"
           # half A drives Q from QB (= s), half B drives QB from Q (= s)
           + half("A", "s", "ya", "bl", "wl") + half("B", "s", "yb", "blb", "wl"))
    body = (f"dc vs 0 {VDD} 0.005\nset wr_singlescale\nset wr_vecnames\n"
            f"wrdata /work/{name}.dat v(ya) v(yb)\n")
    if seed is not None:
        # the seed has to be set before the netlist is parsed, since agauss() is evaluated then
        open(f"/work/{name}.cir", "w").write(ckt + ".end\n")
        run(name, f"* mc driver\n.control\nset rndseed={seed}\npre_osdi /osdi/psp103.osdi\n"
                  f"source /work/{name}.cir\n{body}\n.endc\n.end\n")
    else:
        run(name, ckt + control(body))
    t = read_table(f"/work/{name}.dat")
    return snm(t["v-sweep"] if "v-sweep" in t else t[list(t)[0]], t["v(ya)"], t["v(yb)"])


def write_margin(corner, temp, seed=None, mm=False):
    name = f"wm_{TAG}_{corner}_{temp}_{seed}"
    ckt = (f"* write margin\n" + libs(corner, mm) + f".temp {temp}\n"
           f"vdd vdd 0 {VDD}\nvwl wl 0 pwl(0 0 1n 0 1.1n {VWL})\n"
           f"vbl bl 0 pwl(0 {VDD} 2n {VDD} 402n 0)\nvblb blb 0 {VDD}\n"
           + half("A", "qb", "q", "bl", "wl") + half("B", "q", "qb", "blb", "wl")
           + f".ic v(q)={VDD} v(qb)=0\n")
    body = ("tran 0.1n 410n\nmeas tran tflip when v(q)=v(qb) cross=1\n"
            "meas tran wm find v(bl) when v(q)=v(qb) cross=1\n")
    if seed is not None:
        open(f"/work/{name}.cir", "w").write(ckt + ".end\n")
        out = run(name, f"* mc driver\n.control\nset rndseed={seed}\npre_osdi /osdi/psp103.osdi\n"
                        f"source /work/{name}.cir\n{body}\n.endc\n.end\n")
    else:
        out = run(name, ckt + control(body))
    v = meas(out, "wm")
    return v if not math.isnan(v) else -1.0     # -1: never flipped


def leakage(corner, temp):
    name = f"lk_{TAG}_{corner}_{temp}"
    ckt = (f"* leakage\n" + libs(corner) + f".temp {temp}\n"
           f"vdd vdd 0 {VDD}\nvwl wl 0 0\nvbl bl 0 {VDD}\nvblb blb 0 {VDD}\n"
           + half("A", "qb", "q", "bl", "wl") + half("B", "q", "qb", "blb", "wl")
           + f".nodeset v(q)={VDD} v(qb)=0\n")
    out = run(name, ckt + control("op\nprint -i(vdd) -i(vbl) -i(vblb) v(q) v(qb)\n"
                                  "let itot = -i(vdd)-i(vbl)-i(vblb)\nprint itot"))
    return meas(out, "itot")


if MODE == "corners":
    print(f"6T PD {PD}/{LPD} PG {PG}/{LPG} PU {PU}/{LPU}{' thick oxide' if HV else ''}; "
          f"WL {VWL} V, read bit lines at {VBL} V")
    print("corner   T   hold SNM (mV)   read SNM (mV)   write margin (mV)   leakage (pA/bit)")
    jobs = [(c, t) for c in CORNERS for t in TEMPS]
    def one(ct):
        c, t = ct
        h = butterfly(c, t, "hold"); r = butterfly(c, t, "read")
        return c, t, h[2], r[2], write_margin(c, t), leakage(c, t)
    for c, t, h, r, wm, lk in pmap(one, jobs):
        print(f"{c:7s} {t:3d}   {1e3*h:8.1f}        {1e3*r:8.1f}        {1e3*wm:8.1f}          {1e12*lk:10.2f}",
              flush=True)
elif MODE.startswith("mc"):
    _, n, corner, temp = MODE.split(":")
    n, temp = int(n), int(temp)
    def one(seed):
        h = butterfly(corner, temp, "hold", seed, True)
        r = butterfly(corner, temp, "read", seed, True)
        return seed, h[2], r[2], write_margin(corner, temp, seed, True)
    rows = pmap(one, range(1, n + 1))
    print(f"6T PD {PD} PG {PG} PU {PU}{' hv' if HV else ''}, WL {VWL}, {corner} {temp} C, {n} mismatch samples")
    for s, h, r, wm in rows:
        print(f"seed {s:4d}  hold {1e3*h:7.1f}  read {1e3*r:7.1f}  wm {1e3*wm:7.1f} mV")
    for k, i in (("hold SNM", 1), ("read SNM", 2), ("write margin", 3)):
        xs = [row[i] for row in rows]
        mu, sd = statistics.mean(xs), statistics.stdev(xs)
        print(f"{k:13s}: mean {1e3*mu:6.1f} mV  sigma {1e3*sd:5.1f} mV  min {1e3*min(xs):6.1f} mV  "
              f"mean/sigma {mu/sd if sd else float('inf'):5.2f}  fails(<=0) {sum(x <= 0 for x in xs)}")
