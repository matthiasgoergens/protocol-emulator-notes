# Thin-oxide 3T gain cell and its variants, by SPICE (ngspice 44.2 + PSP 103 via OSDI).
# Two modes, chosen by MODE:
#   MODE=hold  write a 1 (from a stored 0) and a 0 (from a stored 1) for TWRITE ns, then hold;
#              reports the written level and the time SN crosses each level of a fine grid.
#   MODE=read  a column of N cells; the selected one holds a given SN (swept); reports RBL at
#              5/10/20 ns after the read word line rises. The unselected cells hold SN1.
# Pitfalls avoided (README, findings 5 and the uic artefact): the stored level comes from a
# simulated write starting at the opposite value (.ic on SN), never from the DC operating point,
# and no `uic`.
#
# Cell variants (environment):
#   MW    write device between WBL and SN, gates on WWL unless stated:
#         lv   thin NMOS W 0.15 L 0.13 (the drawn thin cell)
#         hv   thick NMOS W 0.15 L 0.45 (the drawn thick cell, for reference)
#         lv2  two thin NMOS in series (stack)
#         lvhv thin at SN, thick at WBL, in series;  hvlv the other way round
#         lv2g two thin NMOS in series, the WBL-side one gated by WEN (a column/bank write
#              enable, high during any write to the bank) instead of WWL
#         fb   Giterman-style internal feedback, NMOS version: MW1 WBL-X, MW2 X-SN (both WWL),
#              MF (thin NMOS, gate SN) from FBD to X, so X follows a stored 1 and MW2 sees a
#              raised source; FBD is VDD (a supply strap) unless FBD=rbl
#         plvw thin PMOS write transistor (W 0.15 L 0.13) in an n-well at VDD; WWL active low
#              (on at 0, idle at VDD, or VWWL if given); it writes a strong 1 and a weak 0
#   GD    1 adds a gated diode (Luk et al., 2T1D): a thin NMOS W 0.30 L GDL (default 0.30) with
#         its gate on SN and source and drain on RWL, which boosts a stored 1 during a read
#   MS    storage device: nlv (thin NMOS, source on the row bar), nhv (thick), plv (thin PMOS in
#         an n-well at VDD, source on a bar at VBAR, read into an RBL precharged low; MR is then
#         a thin PMOS gated by RWL active low)
#   VLO   the WBL level that writes a 0 (default 0; >0 shifts the stored 0 up, which puts every
#         unselected write transistor at Vgs <= -VLO without a negative rail)
#   VHI   the WBL level that writes a 1 (default VDD)
#   VBAR  the storage transistor's source bar during hold and read (default 0; VDD for plv)
#   RBAR  if set, the bar level during a read (the selected row's bar is pulled there)
#   WBLH  WBL level during hold: "opp" (default: the opposite data level, the worst case), or a
#         number (the bank parks WBL there when not writing)
#         or duty:D:P (a fraction D of every P us at VHI, the rest at VLO)
#   VWWL  the unselected write word line level (default 0)
#   VWEN  hold level of WEN for lv2g (default 0)
import os, re, subprocess, sys
VDD = 1.2
E = os.environ.get
MODE = E("MODE", "hold")
MW = E("MW", "lv")
MS = E("MS", "nlv")
PM = MS == "plv"
VLO = float(E("VLO", "0"))
VHI = float(E("VHI", str(VDD)))
VBAR = float(E("VBAR", str(VDD) if PM else "0"))
RBAR = E("RBAR")
WBLH = E("WBLH", "opp")
VWWL = float(E("VWWL", "0"))
VWEN = float(E("VWEN", "0"))
FBD = E("FBD", "vdd")
PW = MW.startswith("p")
GD = E("GD") == "1"
GDL = E("GDL", "0.30")
WMS = E("WMS", "0.30")
TWRITE = float(E("TWRITE", "20"))
TSTOP = E("TSTOP", "50m")
TMAX = E("TMAX", "10u")
MODELS = E("MODELS", "/pdk/libs.tech/ngspice/models")
CORNERS = E("CORNERS", "mos_tt,mos_ff,mos_ss").split(",")
TEMPS = [int(t) for t in E("TEMPS", "27,85").split(",")]
SEED = E("SEED")              # with a *_mismatch corner: the ngspice seed (.options seed)

LV = "w=0.15u l=0.13u"
HV = "w=0.15u l=0.45u"

def write_dev(i, wbl, wwl, sn):
    """the write path from wbl to sn for cell i"""
    b = "0"
    if MW == "lv":
        return f"XMW{i} {wbl} {wwl} {sn} {b} sg13_lv_nmos {LV}"
    if MW == "plvw":
        return f"XMW{i} {wbl} {wwl} {sn} vdd sg13_lv_pmos {LV}"
    if MW == "hv":
        return f"XMW{i} {wbl} {wwl} {sn} {b} sg13_hv_nmos {HV}"
    if MW == "lv2":
        return (f"XMWa{i} {wbl} {wwl} x{i} {b} sg13_lv_nmos {LV}\n"
                f"XMWb{i} x{i} {wwl} {sn} {b} sg13_lv_nmos {LV}")
    if MW == "lv2g":
        return (f"XMWa{i} {wbl} wen x{i} {b} sg13_lv_nmos {LV}\n"
                f"XMWb{i} x{i} {wwl} {sn} {b} sg13_lv_nmos {LV}")
    if MW == "lvhv":
        return (f"XMWa{i} {wbl} {wwl} x{i} {b} sg13_hv_nmos {HV}\n"
                f"XMWb{i} x{i} {wwl} {sn} {b} sg13_lv_nmos {LV}")
    if MW == "hvlv":
        return (f"XMWa{i} {wbl} {wwl} x{i} {b} sg13_lv_nmos {LV}\n"
                f"XMWb{i} x{i} {wwl} {sn} {b} sg13_hv_nmos {HV}")
    if MW == "fb":
        fbd = "rbl" if FBD == "rbl" else "vdd"
        return (f"XMWa{i} {wbl} {wwl} x{i} {b} sg13_lv_nmos {LV}\n"
                f"XMWb{i} x{i} {wwl} {sn} {b} sg13_lv_nmos {LV}\n"
                f"XMF{i} {fbd} {sn} x{i} {b} sg13_lv_nmos {LV}")
    raise SystemExit(f"unknown MW {MW}")

def read_devs(i, sn, bar, rwl):
    """storage and read transistors of cell i, onto rbl"""
    if PM:
        return (f"XMS{i} mid{i} {sn} {bar} vdd sg13_lv_pmos w={WMS}u l=0.13u\n"
                f"XMR{i} rbl {rwl} mid{i} vdd sg13_lv_pmos w=0.30u l=0.13u")
    ms = "sg13_hv_nmos" if MS == "nhv" else "sg13_lv_nmos"
    l = "0.45" if MS == "nhv" else "0.13"
    gd = f"\nXMD{i} {rwl} {sn} {rwl} 0 sg13_lv_nmos w=0.30u l={GDL}u" if GD else ""
    return (f"XMS{i} mid{i} {sn} {bar} 0 {ms} w={WMS}u l={l}u\n"
            f"XMR{i} rbl {rwl} mid{i} 0 sg13_lv_nmos w=0.30u l=0.13u" + gd)

def header(corner, temp):
    seed = f".options seed={SEED}\n" if SEED else ""
    return f"""* {MODE} MW={MW} MS={MS} VLO={VLO} VBAR={VBAR} WBLH={WBLH} {corner} {temp}C
.lib {MODELS}/cornerMOSlv.lib {corner}
.lib {MODELS}/cornerMOShv.lib {corner.replace('_mismatch', '')}
{seed}.temp {temp}
vdd vdd 0 {VDD}
vbar bar 0 {VBAR}
vwen wen 0 pwl(0 {VDD} {TWRITE}n {VDD} {TWRITE + 1}n {VWEN})
"""

L1GRID = [round(0.05 + 0.025 * k, 3) for k in range(40)]     # 0.05 .. 1.025

def hold_netlist(corner, temp, bit):
    vw = VHI if bit else VLO
    duty = None
    if WBLH == "opp":
        vh = VLO if bit else VHI
    elif WBLH.startswith("duty:"):
        # duty:D:P  after the write, WBL spends a fraction D of every period P (us) at VHI (writes
        # of 1s to other rows) and the rest parked at VLO
        _, d, per = WBLH.split(":")
        duty = (float(d), float(per))
        vh = VLO
    else:
        vh = float(WBLH)
    # the cell held the opposite value before the write
    ic = VLO if bit else 0.8
    if PW:
        idle = float(E("VWWL", str(VDD)))
        wwl_pwl = f"pwl(0 0 {TWRITE}n 0 {TWRITE + 1}n {idle})"
        ic = 0.4 if bit else VHI     # the opposite value: a weak 0 or a strong 1
    else:
        wwl_pwl = f"pwl(0 {VDD} {TWRITE}n {VDD} {TWRITE + 1}n {VWWL})"
    rwl_idle = VDD if PM else 0
    rbl_idle = 0 if PM else VDD
    # every level for a 0 as well: a read threshold can lie below VLO (a bug before 11:30 on
    # 2026-09-25 measured only levels above VLO and so missed a 0 creeping up to such a threshold)
    grid = [lv for lv in L1GRID if (lv < 1.0 if bit else True)]
    meas = "\n".join(f"meas tran t{int(round(lv * 1000))} when v(sn)={lv} {'fall' if bit else 'rise'}=1 from={TWRITE + 5}n"
                     for lv in grid)
    return header(corner, temp) + f"""
.options reltol=1e-4 abstol=1e-18 vntol=1e-7
{f"vwbl wbl 0 pwl(0 {vw} {TWRITE + 10}n {vw} {TWRITE + 11}n {vh})" if duty is None else
 f"vwp wp 0 pulse({VLO} {VHI} {TWRITE + 1000}n 10n 10n {duty[0] * duty[1] * 1000 - 10}n {duty[1] * 1000}n)\n"
 f"bwbl wbl 0 v = time < {TWRITE + 10}n ? {vw} : v(wp)"}
vwwl wwl 0 {wwl_pwl}
vrwl rwl 0 {rwl_idle}
vrbl rbl 0 {rbl_idle}
.ic v(sn)={ic}
{write_dev(0, 'wbl', 'wwl', 'sn')}
{read_devs(0, 'sn', 'bar', 'rwl')}
.control
pre_osdi /work/osdi/psp103.osdi
tran 1n {TSTOP} 0 {TMAX}
meas tran vw find v(sn) at={TWRITE + 5}n
meas tran vx find v(sn) at={TWRITE + 50}n
meas tran v1u find v(sn) at=1u
meas tran v10u find v(sn) at=10u
meas tran v100u find v(sn) at=100u
meas tran v1m find v(sn) at=1m
meas tran v10m find v(sn) at=10m
meas tran vend find v(sn) at={TSTOP}
{meas}
.endc
.end
"""

def run(sp, text):
    open(sp, "w").write(text)
    return subprocess.run(["ngspice", "-b", sp], capture_output=True, text=True, timeout=3600).stdout

def num(out, k):
    m = re.search(rf"^{k}\s*=\s*([-+0-9.eE]+)", out, re.M)
    return float(m.group(1)) if m else None

def hold():
    print(f"hold: MW={MW} MS={MS} VLO={VLO} VHI={VHI} VBAR={VBAR} WBLH={WBLH} VWWL={VWWL} "
          f"TWRITE={TWRITE}ns TSTOP={TSTOP}")
    for corner in CORNERS:
        for temp in TEMPS:
            for bit in (1, 0):
                out = run(f"/work/hold_{corner}_{temp}_{bit}.sp", hold_netlist(corner, temp, bit))
                f = lambda x: " n/a " if x is None else f"{x:6.3f}"
                vs = "  ".join(f"{k} {f(num(out, k))}" for k in ("vw", "v1u", "v10u", "v100u", "v1m", "v10m", "vend"))
                cr = []
                for lv in L1GRID:
                    t = num(out, f"t{int(round(lv * 1000))}")
                    if t is not None:
                        cr.append(f"{lv:.3f}@{t:.4g}")
                print(f"{corner:7s} {temp:3d}C stored {bit}  {vs}  crossings {' '.join(cr) or '-'}", flush=True)
                if num(out, "vw") is None:
                    print(out[-2000:], file=sys.stderr)

N = int(E("N", "32"))
CBL = E("CBL", "10f")
SN1 = E("SN1", "0.85")

def read_netlist(corner, temp, sn):
    wblh = VLO if WBLH == "opp" else float(WBLH)
    # read word line and bit line polarity
    if PM:
        rwl = f"pwl(0 {VDD} 40n {VDD} 40.1n 0 60n 0 60.1n {VDD})"
        unsel_rwl, pre_to, sn_unsel = "vdd", "0", VLO     # unselected: stored 0 is the conducting value
    else:
        rwl = f"pwl(0 0 40n 0 40.1n {VDD} 60n {VDD} 60.1n 0)"
        unsel_rwl, pre_to, sn_unsel = "0", "vdd", SN1
    bar = "bar"
    rbar = ""
    if RBAR is not None:
        bar = "rbar"
        rbar = f"vrbar rbar 0 pwl(0 {VBAR} 40n {VBAR} 40.1n {RBAR} 60n {RBAR} 60.1n {VBAR})"
    cells = "\n".join(
        f"{write_dev(i, 'wbl', 'vdd' if PW else '0', f'sn{i}')}\n{read_devs(i, f'sn{i}', 'bar', unsel_rwl)}\n.ic v(sn{i})={sn_unsel}"
        for i in range(1, N))
    if E("LUMP") == "1":
        # the N-1 unselected cells as one instance of each device with multiplicity N-1 (they all
        # hold the same level); about 10x faster, checked against the explicit column
        cells = "\n".join(l + f" m={N - 1}" if l.startswith("X") else l
                           for l in cells.split("\n") if not re.match(r"(X\w+|\.ic v\(sn)([2-9]|\d\d)", l.replace("XMWa", "XMW").replace("XMWb", "XMW")))
    return header(corner, temp) + f"""
.options reltol=1e-4 abstol=1e-15 vntol=1e-6
vwbl wbl 0 {wblh}
{rbar}
.ic v(sn0)={sn}
{write_dev(0, 'wbl', 'vdd' if PW else '0', 'sn0')}
{read_devs(0, 'sn0', bar, 'rwl')}
vrwl rwl 0 {rwl}
vpre pre 0 pwl(0 {VDD} 39n {VDD} 39.1n 0)
spre rbl {pre_to} pre 0 swm
.model swm sw vt=0.6 ron=100 roff=1e12
cbl rbl 0 {CBL}
{cells}
.control
pre_osdi /work/osdi/psp103.osdi
tran 10p 80n
meas tran sn_before find v(sn0) at=39n
meas tran sn_during find v(sn0) at=50n
meas tran sn_after find v(sn0) at=75n
meas tran bl5 find v(rbl) at=45n
meas tran bl10 find v(rbl) at=50n
meas tran bl20 find v(rbl) at=59.9n
.endc
.end
"""

def read():
    lo, hi, step = (float(v) for v in E("SNSWEEP", "0.0:1.0:0.025").split(":"))
    print(f"read: MW={MW} MS={MS} VLO={VLO} VBAR={VBAR} RBAR={RBAR} N={N} CBL={CBL} SN1={SN1}; "
          f"RBL at 5/10/20 ns after RWL {'falls' if PM else 'rises'}; SN before/during/after")
    for corner in CORNERS:
        for temp in TEMPS:
            v = lo
            while v <= hi + 1e-9:
                out = run(f"/work/read_{corner}_{temp}.sp", read_netlist(corner, temp, round(v, 3)))
                g = lambda k: (lambda x: float("nan") if x is None else x)(num(out, k))
                print(f"{corner:7s} {temp:3d}C SN {v:5.3f}: RBL {g('bl5'):6.3f} {g('bl10'):6.3f} {g('bl20'):6.3f}"
                      f"   SN {g('sn_before'):6.3f} {g('sn_during'):6.3f} {g('sn_after'):6.3f}", flush=True)
                v += step

if __name__ == "__main__":
    {"hold": hold, "read": read}[MODE]()
