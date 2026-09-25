# Monte Carlo of the thin-oxide 3T cell's lifetime with the PDK's mismatch models
# (cornerMOSlv.lib mos_<corner>_mismatch: per-instance agauss on delvto, factuo, w, l).
# One ngspice session per sample, so every analysis in it sees the same mismatch draws:
#   1. hold run: write a 1 (from VLO), hold with WBL at VLO (the worst case for a 1); record the
#      time SN crosses each level of a 12.5 mV grid;
#   2. hold run: write a 0 (from 0.8 V), hold with WBL at VDD (the worst case for a 0), and
#      again with WBL parked at VLO (an idle column): life and lifepark in the output;
#   3. read runs: SN of the same cell forced to a level (a switch until 39 ns), then a read of the
#      32-cell column; RBL at the sense time for a scan of levels gives this cell's thresholds:
#      L1 (RBL falls below 0.5 V) and H0 (RBL stays above 0.7 V).
# Lifetime of the sample = min(time for its 1 to fall to its L1, time for its 0 to rise to H0).
# The seed goes in as `.options seed=N`; smoke-tested that different seeds give different
# draws and the same seed the same draws (results/seedcheck.txt).
# Environment: CORNER (mos_tt, mos_ff, ...), TEMP, VLO, VBAR, MW (lv only here), N0 (first
# seed), NS (samples), JOBS (parallel ngspice processes), TSTOP, SCAN "lo:hi:step" for reads,
# SENSE (ns after RWL rises, default 10), NOMISMATCH=1 runs the nominal corner as a check.
# A read run stops 2 ns after the sense time.
import math, os, re, subprocess, sys
from concurrent.futures import ThreadPoolExecutor
E = os.environ.get
VDD = 1.2
CORNER = E("CORNER", "mos_tt")
TEMP = int(E("TEMP", "85"))
VLO = float(E("VLO", "0"))
VBAR = float(E("VBAR", "0"))
N0, NS, JOBS = int(E("N0", "1")), int(E("NS", "200")), int(E("JOBS", "3"))
TSTOP = E("TSTOP", "50m")
TMAX = E("TMAX", "10u")
SENSE = float(E("SENSE", "10"))
lo, hi, st = (float(x) for x in E("SCAN", "0.10:0.60:0.05").split(":"))
SCAN = [round(lo + st * k, 4) for k in range(int(round((hi - lo) / st)) + 1)]
LIB = CORNER if E("NOMISMATCH") else CORNER + "_mismatch"
N = 32
GRID = [round(0.9 - 0.0125 * k, 4) for k in range(72) if 0.9 - 0.0125 * k > -0.0001]
LV = "w=0.15u l=0.13u"

def netlist(seed):
    # the 31 unselected cells of the column, lumped into one instance of multiplicity 31 (they all
    # hold the same worst-case 1 and only leak into RBL through their MR); the PDK scales their
    # mismatch by 1/sqrt(m), which is the spread of their summed leakage
    cells = (f"XMW1 wbl 0 sn1 0 sg13_lv_nmos {LV} m={N - 1}\n"
             f"XMS1 mid1 sn1 bar 0 sg13_lv_nmos w=0.30u l=0.13u m={N - 1}\n"
             f"XMR1 rbl 0 mid1 0 sg13_lv_nmos w=0.30u l=0.13u m={N - 1}\n.ic v(sn1)=0.85")
    m1 = "\n".join(f"meas tran a{k} when v(sn0)={lv} fall=1 from=25n" for k, lv in enumerate(GRID))
    m0 = "\n".join(f"meas tran b{k} when v(sn0)={lv} rise=1 from=25n" for k, lv in enumerate(GRID))
    mp = "\n".join(f"meas tran c{k} when v(sn0)={lv} rise=1 from=25n" for k, lv in enumerate(GRID))
    pp = " ".join(f"c{k}" for k in range(len(GRID)))
    p1 = " ".join(f"a{k}" for k in range(len(GRID)))
    p0 = " ".join(f"b{k}" for k in range(len(GRID)))
    reads = "\n".join(f"""alter vlev dc={lv}
tran 40p {42 + SENSE:g}n
meas tran r{k} find v(rbl) at={40 + SENSE}n
print r{k}""" for k, lv in enumerate(SCAN))
    return f"""* mc {CORNER} {TEMP} seed {seed}
.lib /pdk/libs.tech/ngspice/models/cornerMOSlv.lib {LIB}
.options seed={seed}
.temp {TEMP}
.options reltol=1e-4 abstol=1e-18 vntol=1e-7
* mode: 0 = hold (write, then hold), 1 = read of a forced level
vm m 0 dc 0
* bit written in a hold run (1 or 0)
vbit bit 0 dc 1
vlev lev 0 dc 0.5
vdd vdd 0 {VDD}
vbar bar 0 {VBAR}
vwwlp wwlp 0 pwl(0 {VDD} 20n {VDD} 21n 0)
bwwl wwl 0 v = v(wwlp) * (1 - v(m))
* WBL: hold run: the bit's level during the write, the opposite level after; read run: VLO
* after writing a 0, WBL goes to v(zw): VDD (a column written with 1s all the time) or VLO (parked)
vzw zw 0 dc {VDD}
bwbl wbl 0 v = (1 - v(m)) * (time < 30n ? (v(bit) > 0.5 ? {VDD} : {VLO}) : (v(bit) > 0.5 ? {VLO} : v(zw))) + v(m) * {VLO}
vrwlp rwlp 0 pwl(0 0 40n 0 40.1n {VDD})
brwl rwl 0 v = v(rwlp) * v(m)
vprep prep 0 pwl(0 {VDD} 39n {VDD} 39.1n 0)
bpre pre 0 v = v(m) * v(prep) + (1 - v(m)) * {VDD}
spre rbl vdd pre 0 swm
* force switch: in a read run, holds SN at the scanned level until 39 ns
* hold run of a 0: holds SN at 0.8 V (the opposite value) for the first 1 ns, then the write
vpre0 pre0 0 pwl(0 {VDD} 1n {VDD} 1.1n 0)
bfc fc 0 v = v(m) * v(prep) + (1 - v(m)) * (1 - v(bit)) * v(pre0)
sforce sn0 lev fc 0 swm
.model swm sw vt=0.6 ron=100 roff=1e15
cbl rbl 0 10f
XMW0 wbl wwl sn0 0 sg13_lv_nmos {LV}
XMS0 mid0 sn0 bar 0 sg13_lv_nmos w=0.30u l=0.13u
XMR0 rbl rwl mid0 0 sg13_lv_nmos w=0.30u l=0.13u
.ic v(sn0)={VLO}
{cells}
.control
pre_osdi /work/osdi/psp103.osdi
tran 1n {TSTOP} 0 {TMAX}
meas tran vw1 find v(sn0) at=25n
{m1}
print vw1 {p1}
alter vbit dc=0
alter vlev dc=0.8
tran 1n {TSTOP} 0 {TMAX}
meas tran vw0 find v(sn0) at=25n
{m0}
print vw0 {p0}
alter vzw dc={VLO}
tran 1n {TSTOP} 0 {TMAX}
meas tran vwp find v(sn0) at=25n
{mp}
print vwp {pp}
alter vm dc=1
{reads}
.endc
.end
"""

def num(out, k):
    m = re.search(rf"^{k}\s*=\s*([-+0-9.eE]+)", out, re.M)
    return float(m.group(1)) if m else None

def cross(pts, limit):
    """SN where RBL crosses limit (RBL falls as SN rises)"""
    for (s0, r0), (s1, r1) in zip(pts, pts[1:]):
        if r0 is None or r1 is None:
            continue
        if (r0 - limit) * (r1 - limit) <= 0 and r0 != r1:
            return s0 + (s1 - s0) * (r0 - limit) / (r0 - r1)
    return None

def t_at(vw, cr, level, falling):
    if (falling and vw <= level) or (not falling and vw >= level):
        return 0.0
    prev = (vw, 30e-9)
    for lv, t in cr:
        if t is None:
            continue
        if (falling and lv >= vw - 0.003) or (not falling and lv <= vw + 0.003):
            continue
        if (falling and lv <= level) or (not falling and lv >= level):
            (v0, t0), (v1, t1) = prev, (lv, t)
            f = (level - v0) / (v1 - v0)
            return math.exp(math.log(t0) + f * (math.log(max(t1, t0)) - math.log(t0)))
        prev = (lv, t)
    return math.inf

def sample(seed):
    wd = f"/work/s{seed}"
    os.makedirs(wd, exist_ok=True)
    sp = f"{wd}/mc.sp"
    open(sp, "w").write(netlist(seed))
    out = subprocess.run(["ngspice", "-b", sp], capture_output=True, text=True, timeout=7200).stdout
    vw1, vw0 = num(out, "vw1"), num(out, "vw0")
    c1 = [(lv, num(out, f"a{k}")) for k, lv in enumerate(GRID)]
    c0 = sorted([(lv, num(out, f"b{k}")) for k, lv in enumerate(GRID)])
    cp = sorted([(lv, num(out, f"c{k}")) for k, lv in enumerate(GRID)])
    vwp = num(out, "vwp")
    rd = [(lv, num(out, f"r{k}")) for k, lv in enumerate(SCAN)]
    l1, h0 = cross(rd, 0.5), cross(rd, 0.7)
    if vw1 is None or vw0 is None:
        return f"seed {seed} FAILED " + out[-300:].replace("\n", " | ")
    t1 = t_at(vw1, c1, l1, True) if l1 is not None else float("nan")
    t0 = t_at(vw0, c0, h0, False) if h0 is not None else float("nan")
    tp = t_at(vwp, cp, h0, False) if h0 is not None and vwp is not None else float("nan")
    life = min(t1, t0)
    return (f"seed {seed:5d} vw1 {vw1:.4f} vw0 {vw0:.4f} L1 {l1 if l1 is None else round(l1, 4)} "
            f"H0 {h0 if h0 is None else round(h0, 4)} t1 {t1:.4e} t0 {t0:.4e} life {life:.4e} "
            f"t0park {tp:.4e} lifepark {min(t1, tp):.4e}  "
            f"rbl {' '.join('-' if r is None else f'{r:.3f}' for _, r in rd)}")

print(f"mc: {LIB} {TEMP}C VLO={VLO} VBAR={VBAR} sense {SENSE} ns, seeds {N0}..{N0 + NS - 1}, "
      f"scan {SCAN}, TSTOP {TSTOP}", flush=True)
with ThreadPoolExecutor(JOBS) as ex:
    for line in ex.map(sample, range(N0, N0 + NS)):
        print(line, flush=True)
