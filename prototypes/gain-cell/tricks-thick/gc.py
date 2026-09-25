# Gain-cell tricks on the thick-oxide side (IHP SG13G2, ngspice 44.2 + PSP 103 via OSDI).
# One script, three modes, so that every trick is measured by the same method:
#   ret    write a bit from the opposite value, then hold; report when SN crosses each level
#   read   SN sweep: the selected cell starts at a given SN (.ic, no write), a read runs, and RBL
#          is reported at several times after RWL rises (N cells on the column, the unselected
#          ones storing SN1); also reports the stored-0 case at the levels in ZEROS
#   csn    small-signal capacitance of SN (AC, 10 MHz), biased at 0.5 V through 1 Tohm
# The write: WWL starts low (so the operating point at t = 0 has MW off and SN at its .ic, the
# opposite value), rises in 1 ns, stays high for TWRITE, and falls in 1 ns.
# The cell (3T): MW (hv nmos, WBL -> SN, gate WWL), MS (gate SN, source GND, drain MID),
# MR (gate RWL, MID -> RBL). Options, all by environment variable:
#   MS=lv|hv  MSW (0.30)  MSL (0.13 lv / 0.45 hv)     storage transistor
#   MR=lv|hv  MRW (0.30)  MRL (0.13 lv / 0.45 hv)     read transistor
#   WMW (0.15) LMW (0.45)                              write transistor (always thick oxide)
#   CSN  extra ideal capacitance SN-GND (e.g. 1f): stacked metal, no leakage
#   CC   ideal coupling capacitance RWL-SN (e.g. 0.5f): metal fingers, no leakage
#   VWWL the write word line's high level (1.2 = no boost)
#   WBLIDLE opp|<volts>: WBL after the write (opp = the opposite value, the worst case)
#   TWRITE (20) ns; TSTOP (1) s; TMAX (5u) max step in ret
#   CORNERS (tt,ff,ss) TEMPS (27,85) BITS (1,0)
#   read: N (32), CBL (10f), SN1 (unselected level, 0.7), SWEEP lo:hi:step, ZEROS (-0.06,0.0,0.05,0.10)
#         VRWL (1.2) read word line level; TREAD (40) ns RWL pulse
import itertools, os, re, subprocess, sys
VDD = 1.2
E = os.environ.get
MS, MR = E("MS", "hv"), E("MR", "lv")
MSW, MRW = E("MSW", "0.30"), E("MRW", "0.30")
MSL = E("MSL", "0.13" if MS == "lv" else "0.45")
MRL = E("MRL", "0.13" if MR == "lv" else "0.45")
WMW, LMW = E("WMW", "0.15"), E("LMW", "0.45")
CSN, CC = E("CSN", "0"), E("CC", "0")
VWWL = float(E("VWWL", "1.2"))
WBLIDLE = E("WBLIDLE", "opp")
TWRITE = float(E("TWRITE", "20"))
CORNERS = ["mos_" + c for c in E("CORNERS", "tt,ff,ss").split(",")]
TEMPS = [int(t) for t in E("TEMPS", "27,85").split(",")]
# DVTMW / DVTMS shift the write / storage transistor's threshold (volts, negative = leakier), for
# mismatch sensitivity; they need MODELS=/work/models-dvt, a copy made by retention/mkmodels.sh
# (run.sh copies it into each run directory)
MODELS = E("MODELS", "/pdk/libs.tech/ngspice/models")
DVTMW, DVTMS = E("DVTMW"), E("DVTMS")

def cellnet(i, wbl, wwl, sn, rwl, rbl):
    s = (f"XMW{i} {wbl} {wwl} {sn} 0 sg13_hv_nmos w={WMW}u l={LMW}u{f' dvt={DVTMW}' if DVTMW else ''}\n"
         f"XMS{i} mid{i} {sn} 0 0 sg13_{MS}_nmos w={MSW}u l={MSL}u{f' dvt={DVTMS}' if DVTMS else ''}\n"
         f"XMR{i} {rbl} {rwl} mid{i} 0 sg13_{MR}_nmos w={MRW}u l={MRL}u\n")
    if float(CSN.rstrip("f") or 0):
        s += f"CSN{i} {sn} 0 {CSN}\n"
    if float(CC.rstrip("f") or 0):
        s += f"CC{i} {rwl} {sn} {CC}\n"
    return s

def head(title, corner, temp):
    return f"""* {title}
.lib {MODELS}/cornerMOSlv.lib {corner}
.lib {MODELS}/cornerMOShv.lib {corner}
.temp {temp}
vdd vdd 0 {VDD}
"""

def run(sp, text, timeout=3600):
    open(sp, "w").write(text)
    out = subprocess.run(["ngspice", "-b", sp], capture_output=True, text=True, timeout=timeout).stdout
    def g(k):
        m = re.search(rf"^{k}\s*=\s*([-+0-9.eE]+)", out, re.M)
        return float(m.group(1)) if m else None
    return out, g

def desc():
    return (f"MS {MS} {MSW}/{MSL}, MR {MR} {MRW}/{MRL}, MW hv {WMW}/{LMW}, CSN {CSN}, CC {CC}, "
            f"VWWL {VWWL}, WBL idle {WBLIDLE}, write {TWRITE} ns"
            + (f", MW dVT {DVTMW}" if DVTMW else "") + (f", MS dVT {DVTMS}" if DVTMS else ""))

def ret():
    tstop, tmax = E("TSTOP", "1"), E("TMAX", "5u")
    lv1 = [round(1.15 - 0.05 * k, 2) for k in range(23)]       # 1.15 .. 0.05
    lv0 = [round(0.05 * k, 2) for k in range(1, 17)]           # 0.05 .. 0.80
    print(f"ret: {desc()}; hold {tstop} s")
    for corner, temp, bit in itertools.product(CORNERS, TEMPS, [int(b) for b in E("BITS", "1,0").split(",")]):
        idle = (0 if bit else VDD) if WBLIDLE == "opp" else float(WBLIDLE)
        pre = 0 if bit else float(E("PRE0", "0.7"))
        levels = lv1 if bit else lv0
        meas = "\n".join(f"meas tran t{int(round(lv * 100))} when v(sn)={lv} {'fall' if bit else 'rise'}=1"
                         for lv in levels)
        text = head(f"ret {corner} {temp} {bit}", corner, temp) + f""".options reltol=1e-4 abstol=1e-18 vntol=1e-7
vwbl wbl 0 pwl(0 {VDD if bit else 0} {TWRITE + 11}n {VDD if bit else 0} {TWRITE + 12}n {idle})
vwwl wwl 0 pwl(0 0 1n {VWWL} {TWRITE + 1}n {VWWL} {TWRITE + 2}n 0)
vrwl rwl 0 0
vrbl rbl 0 {VDD}
.ic v(sn)={pre}
{cellnet(0, 'wbl', 'wwl', 'sn', 'rwl', 'rbl')}
.control
pre_osdi /work/osdi/psp103.osdi
tran 1u {tstop} 0 {tmax}
meas tran vw find v(sn) at={TWRITE + 6}n
meas tran v1u find v(sn) at=1u
meas tran v1m find v(sn) at=1m
meas tran v10m find v(sn) at=10m
meas tran v100m find v(sn) at=100m
meas tran vend find v(sn) at={float(tstop) * 0.999}
{meas}
.endc
.end
"""
        out, g = run(f"/work/ret_{corner}_{temp}_{bit}.sp", text)
        f = lambda x: "  n/a " if x is None else f"{x:6.3f}"
        cr = "  ".join(f"{lv:.2f}V@" + ("-" if g(f"t{int(round(lv * 100))}") is None
                                        else f"{g(f't{int(round(lv * 100))}') * 1e3:.3f}ms") for lv in levels)
        print(f"{corner:7s} {temp:3d}C stored {bit} written {f(g('vw'))} V  1us {f(g('v1u'))} 1ms {f(g('v1m'))}"
              f" 10ms {f(g('v10m'))} 100ms {f(g('v100m'))} end {f(g('vend'))}  crossings {cr}", flush=True)
        if g("vw") is None:
            print(out[-2000:], file=sys.stderr)

def read():
    N, CBL, SN1 = int(E("N", "32")), E("CBL", "10f"), E("SN1", "0.7")
    VRWL, TREAD = float(E("VRWL", "1.2")), float(E("TREAD", "40"))
    lo, hi, step = (float(v) for v in E("SWEEP", "0.20:1.20:0.05").split(":"))
    zeros = [float(z) for z in E("ZEROS", "-0.06,0.0,0.05,0.10").split(",")]
    times = [2, 5, 10, 20, 40]
    print(f"read: {desc()}; N {N}, wire {CBL}, unselected at {SN1} V, RWL {VRWL} V for {TREAD} ns;"
          f" RBL at {'/'.join(map(str, times))} ns after RWL rises; SN before -> during")
    for corner, temp in itertools.product(CORNERS, TEMPS):
        levels, v = list(zeros), lo
        while v <= hi + 1e-9:
            levels.append(round(v, 3)); v += step
        for v in levels:
            unsel = "".join(cellnet(i, "0", "0", f"sn{i}", "0", "rbl") + f".ic v(sn{i})={SN1}\n"
                            for i in range(1, N))
            ms = "\n".join(f"meas tran bl{t} find v(rbl) at={40 + t}n" for t in times)
            text = head(f"read {corner} {temp} {v}", corner, temp) + f""".options reltol=1e-4 abstol=1e-15 vntol=1e-6
vrwl rwl 0 pwl(0 0 40n 0 40.1n {VRWL} {40 + TREAD}n {VRWL} {40.1 + TREAD}n 0)
vpre pre 0 pwl(0 {VDD} 39n {VDD} 39.1n 0)
spre rbl vdd pre 0 swm
.model swm sw vt=0.6 ron=100 roff=1e12
cbl rbl 0 {CBL}
.ic v(sn0)={v}
{cellnet(0, '0', '0', 'sn0', 'rwl', 'rbl')}
{unsel}
.control
pre_osdi /work/osdi/psp103.osdi
tran 10p {50 + TREAD}n
meas tran snb find v(sn0) at=39n
meas tran snd find v(sn0) at={40 + min(TREAD, 20) - 1}n
{ms}
.endc
.end
"""
            out, g = run(f"/work/read_{corner}_{temp}.sp", text, 1800)
            f = lambda x: "  nan " if x is None else f"{x:6.3f}"
            print(f"{corner:7s} {temp:3d}C SN {v:5.2f}: {f(g('snb'))} -> {f(g('snd'))}  RBL "
                  + " ".join(f(g(f"bl{t}")) for t in times), flush=True)

def csn():
    print(f"csn: {desc()}; C(SN) at 10 MHz, SN biased through 1 Tohm")
    for corner, temp in itertools.product(CORNERS, TEMPS):
        for bias in [float(b) for b in E("BIAS", "0.0,0.3,0.5,0.8,1.2").split(",")]:
            text = head(f"csn {corner} {temp}", corner, temp) + f"""
vwbl wbl 0 0
vwwl wwl 0 0
vrwl rwl 0 0
vrbl rbl 0 {VDD}
vb b 0 {bias}
rb b sn 1e12
iac 0 sn dc 0 ac 1
{cellnet(0, 'wbl', 'wwl', 'sn', 'rwl', 'rbl')}
.control
pre_osdi /work/osdi/psp103.osdi
ac lin 1 10meg 10meg
let c = 1/(2*3.14159265*10e6*mag(v(sn)))
print c
.endc
.end
"""
            out, g = run(f"/work/csn_{corner}_{temp}.sp", text)
            m = re.search(r"^c\s*=\s*([-+0-9.eE]+)", out, re.M)
            print(f"{corner:7s} {temp:3d}C SN {bias:4.2f} V: C = {float(m.group(1)) * 1e15 if m else float('nan'):.3f} fF",
                  flush=True)

{"ret": ret, "read": read, "csn": csn}[sys.argv[1]]()
