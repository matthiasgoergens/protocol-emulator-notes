# Read of a gain cell in IHP SG13G2, by SPICE (ngspice 44.2 + PSP 103 via OSDI). TOPO=2T (default)
# or TOPO=3T.
#
# 3T: MS (gate SN) from GND to MID, MR (gate RWL) from MID to RBL. Idle: RWL low, every MR off.
# Read: the selected RWL rises; a stored 1 discharges RBL through MS and MR. Unselected cells
# (storing 1, the worst case for leakage) only leak through their MR.
#
# 2T:
# One column of N cells on a read bitline RBL. Each cell: write transistor MW (sg13_hv_nmos,
# WBL -> SN, gate WWL), storage transistor MS (sg13_lv_nmos, gate SN, between the row's RWL bar and
# RBL). Idle: every RWL bar at VDD, RBL precharged to VDD, so every MS is off whatever it stores.
# Read: the selected row's RWL falls to 0; a stored 1 turns its MS on and discharges RBL. The
# unselected cells all store a 1 (the worst case): once RBL falls below their SN minus a threshold
# they conduct from their RWL (VDD) into RBL and fight the read.
# Measured: RBL at 2, 5 and 10 ns after the word line falls, for a stored 1 and a stored 0, and
# the selected SN before and after the read (read disturb). An inverter trips near VDD/2, so a
# read works if RBL(stored 1) < 0.5 V and RBL(stored 0) > 0.7 V at the sense time.
import itertools, os, re, subprocess
VDD = 1.2
TOPO = os.environ.get("TOPO", "2T")
MS = os.environ.get("MS", "lv")    # storage transistor: lv (thin oxide, L 0.13) or hv (thick, L 0.45)
MSL = "0.13" if MS == "lv" else "0.45"
N = int(os.environ.get("N", "32"))
WMW, LMW, W = os.environ.get("WMW", "0.15"), os.environ.get("LMW", "0.60"), os.environ.get("W", "0.30")
CBL = os.environ.get("CBL", "10f")      # Metal2 wire, about 0.15 fF/um over N x 2.6 um

def netlist(corner, temp, bit, sn_unsel, sn_given=None):
    if TOPO == "2T":
        cells = "\n".join(
            f"XMW{i} 0 0 sn{i} 0 sg13_hv_nmos w={WMW}u l={LMW}u\n"
            f"XMS{i} rbl sn{i} vdd 0 sg13_lv_nmos w={W}u l=0.13u\n"
            f".ic v(sn{i})={sn_unsel}" for i in range(1, N))
        sel = f"XMS0 rbl sn0 rwl 0 sg13_lv_nmos w={W}u l=0.13u"
        rwl = f"pwl(0 {VDD} 40n {VDD} 40.1n 0 60n 0 60.1n {VDD})"
    else:
        cells = "\n".join(
            f"XMW{i} 0 0 sn{i} 0 sg13_hv_nmos w={WMW}u l={LMW}u\n"
            f"XMS{i} mid{i} sn{i} 0 0 sg13_{MS}_nmos w={W}u l={MSL}u\n"
            f"XMR{i} rbl 0 mid{i} 0 sg13_lv_nmos w={W}u l=0.13u\n"
            f".ic v(sn{i})={sn_unsel}" for i in range(1, N))
        sel = (f"XMS0 mid0 sn0 0 0 sg13_{MS}_nmos w={W}u l={MSL}u\n"
               f"XMR0 rbl rwl mid0 0 sg13_lv_nmos w={W}u l=0.13u")
        rwl = f"pwl(0 0 40n 0 40.1n {VDD} 60n {VDD} 60.1n 0)"
    return f"""* {TOPO} read {corner} {temp}C bit {bit}
.lib /pdk/libs.tech/ngspice/models/cornerMOSlv.lib {corner}
.lib /pdk/libs.tech/ngspice/models/cornerMOShv.lib {corner}
.temp {temp}
.options reltol=1e-4 abstol=1e-15 vntol=1e-6
vdd vdd 0 {VDD}
* the selected cell: written for 20 ns, then isolated
vwbl wbl 0 {VDD if bit else 0}
vwwl wwl 0 {"0" if sn_given is not None else f"pwl(0 {VDD} 20n {VDD} 21n 0)"}
XMW0 wbl wwl sn0 0 sg13_hv_nmos w={WMW}u l={LMW}u
* the cell held the opposite value before the write (without this the DC operating point, not the
* 20 ns write, sets the stored level)
.ic v(sn0)={sn_given if sn_given is not None else (0 if bit else 0.7)}
{sel}
* RWL of the selected row: active from 40 ns to 60 ns
vrwl rwl 0 {rwl}
* RBL precharge: an ideal switch to VDD until 39 ns, then RBL floats
vpre pre 0 pwl(0 {VDD} 39n {VDD} 39.1n 0)
spre rbl vdd pre 0 swm
.model swm sw vt=0.6 ron=100 roff=1e12
cbl rbl 0 {CBL}
{cells}
.control
pre_osdi /work/osdi/psp103.osdi
tran 10p 80n
meas tran sn_before find v(sn0) at=39n
meas tran bl2 find v(rbl) at=42n
meas tran bl5 find v(rbl) at=45n
meas tran bl10 find v(rbl) at=50n
meas tran sn_during find v(sn0) at=50n
meas tran sn_after find v(sn0) at=75n
.endc
.end
"""

SWEEP = os.environ.get("SNSWEEP")      # e.g. "0.10:0.60:0.05": SN given directly, no write
if SWEEP:
    lo, hi, step = (float(v) for v in SWEEP.split(":"))
    print(f"{TOPO}: SN sweep, N {N}, MS W {W}, wire {CBL}; RBL at 2/5/10/20 ns after the read starts")
    for corner, temp in itertools.product(["mos_tt", "mos_ff", "mos_ss"], [27, 85]):
        v = lo
        while v <= hi + 1e-9:
            sp = f"/work/sweep_{corner}_{temp}.sp"
            open(sp, "w").write(netlist(corner, temp, 0, os.environ.get("SN1", "0.70"), round(v, 3)).replace(
                "meas tran bl10 find v(rbl) at=50n", "meas tran bl10 find v(rbl) at=50n\nmeas tran bl20 find v(rbl) at=59n"))
            out = subprocess.run(["ngspice", "-b", sp], capture_output=True, text=True, timeout=900).stdout
            g = lambda k: (lambda m: float(m.group(1)) if m else float("nan"))(
                re.search(rf"^{k}\s*=\s*([-+0-9.eE]+)", out, re.M))
            print(f"{corner:7s} {temp:3d}C SN {v:5.2f}: RBL {g('bl2'):6.3f} {g('bl5'):6.3f} {g('bl10'):6.3f} {g('bl20'):6.3f}", flush=True)
            v += step
    raise SystemExit
print(f"{TOPO}: N {N} cells on the bitline, MW W {WMW} L {LMW}, MS W {W}, wire {CBL}")
for corner, temp in itertools.product(["mos_tt", "mos_ff", "mos_ss"], [27, 85]):
    for bit in (1, 0):
        sp = f"/work/read_{corner}_{temp}_{bit}.sp"
        # unselected cells hold a 1 at SN1 (default 0.70 V, about the written level; higher is worse)
        open(sp, "w").write(netlist(corner, temp, bit, os.environ.get("SN1", "0.70")))
        out = subprocess.run(["ngspice", "-b", sp], capture_output=True, text=True, timeout=900).stdout
        g = lambda k: (lambda m: float(m.group(1)) if m else float("nan"))(
            re.search(rf"^{k}\s*=\s*([-+0-9.eE]+)", out, re.M))
        print(f"{corner:7s} {temp:3d}C stored {bit}: SN {g('sn_before'):6.3f} -> during {g('sn_during'):6.3f}"
              f" -> after {g('sn_after'):6.3f} V   RBL at 2/5/10 ns {g('bl2'):6.3f} {g('bl5'):6.3f} {g('bl10'):6.3f} V",
              flush=True)
