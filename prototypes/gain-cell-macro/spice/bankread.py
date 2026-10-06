# The bank's read path with its real standard cells (sg13cmos5l_stdcell transistor netlists),
# replacing the ideal precharge switch and the "RBL below 0.5 V" criterion of
# ../../gain-cell/retention/read.py.
#
# One column of N cells on RBL:
#   - precharge: sg13cmos5l_ebufn_2 with A tied high, enabled (TE_B low) for one clock cycle;
#   - sense: sg13cmos5l_inv_1 on RBL; a flop samples its output (modelled as the inverter output
#     at the sampling edge minus SETUP, read as 1 above VDD/2);
#   - the selected row's RWL: sg13cmos5l_buf_4 through the poly line (RRWL, CRWL lumped);
#   - N - 1 unselected cells, each storing a 1 at SN1 (their read transistors leak into RBL);
#   - CBL: the Metal2 bit line and its route to the sense cell (an estimate until extraction).
# Timing (bank controller, gc_bank.v): the previous read may have left RBL at 0 V; precharge runs
# from edge E0 to edge E1 = E0 + T; RWL is high from E1 to E1 + EVAL * T; the flop samples at
# E1 + EVAL * T. Control edges arrive DCTL after the clock edge (clk-to-q plus a driver).
# Measured: RBL at E1 (the precharge level), and RBL and the inverter output at the sample time.
# SNSWEEP=lo:hi:step sweeps the stored level of the selected cell, as read.py does.
import itertools, os, re, subprocess
VDD = float(os.environ.get("VDD", "1.2"))
N = int(os.environ.get("N", "32"))
T = float(os.environ.get("T", "16.667"))       # ns, the 60 MHz clock of architecture-v0 2.8
EVAL = int(os.environ.get("EVAL", "2"))         # cycles with RWL high
DCTL = float(os.environ.get("DCTL", "0.6"))     # ns from clock edge to control input of the drivers
SETUP = float(os.environ.get("SETUP", "0.3"))   # ns, flop setup plus clock skew allowance
CBL = os.environ.get("CBL", "30f")
RRWL, CRWL = os.environ.get("RRWL", "2.5k"), os.environ.get("CRWL", "15f")
SN1 = os.environ.get("SN1", "0.70")
# SENSE: inv_1 (default), or nand4_1 with all four inputs on RBL: four series NMOS against four
# parallel PMOS put its switching point well above VDD / 2, so a smaller discharge reads as a 1
SENSE = os.environ.get("SENSE", "inv_1")
STD = "/pdk/libs.ref/sg13cmos5l_stdcell/spice/sg13cmos5l_stdcell.spice"
E0 = 5.0
E1 = E0 + T
TS = E1 + EVAL * T - SETUP

def netlist(corner, temp, sn):
    cells = "\n".join(
        f"XMS{i} mid{i} sn{i} 0 0 sg13_lv_nmos w=0.30u l=0.13u\n"
        f"XMR{i} rbl 0 mid{i} 0 sg13_lv_nmos w=0.30u l=0.13u\n"
        f"XMW{i} 0 0 sn{i} 0 sg13_hv_nmos w=0.15u l=0.45u\n"
        f".ic v(sn{i})={SN1}" for i in range(1, N))
    c = DCTL
    return f"""* bank read {corner} {temp}C SN {sn}
.lib /pdk/libs.tech/ngspice/models/cornerMOSlv.lib {corner}
.lib /pdk/libs.tech/ngspice/models/cornerMOShv.lib {corner}
.include {STD}
.temp {temp}
.options reltol=1e-4 abstol=1e-15 vntol=1e-6 gmin=1e-18
vdd vdd 0 {VDD}
* control inputs (ideal edges of 100 ps, DCTL after the clock edges)
vpreb preb 0 pwl(0 {VDD} {E0 + c}n {VDD} {E0 + c + 0.1}n 0 {E1 + c}n 0 {E1 + c + 0.1}n {VDD})
vrwlin rwlin 0 pwl(0 0 {E1 + c}n 0 {E1 + c + 0.1}n {VDD} {E1 + EVAL * T + c}n {VDD} {E1 + EVAL * T + c + 0.1}n 0)
xtie hi vdd 0 sg13cmos5l_tiehi
xpre rbl hi preb vdd 0 sg13cmos5l_ebufn_2
{"xsense y rbl vdd 0 sg13cmos5l_inv_1" if SENSE == "inv_1" else "xsense y rbl rbl rbl rbl vdd 0 sg13cmos5l_nand4_1"}
xrwl rwld rwlin vdd 0 sg13cmos5l_buf_4
rrwl rwld rwl {RRWL}
crwl rwl 0 {CRWL}
cbl rbl 0 {CBL}
.ic v(rbl)=0
* the selected cell
XMS0 mid0 sn0 0 0 sg13_lv_nmos w=0.30u l=0.13u
XMR0 rbl rwl mid0 0 sg13_lv_nmos w=0.30u l=0.13u
XMW0 0 0 sn0 0 sg13_hv_nmos w=0.15u l=0.45u
.ic v(sn0)={sn}
{cells}
.control
pre_osdi /work/osdi/psp103.osdi
tran 10p {TS + 2}n
meas tran rbl_pre find v(rbl) at={E1 + c}n
meas tran rbl_s find v(rbl) at={TS}n
meas tran y_s find v(y) at={TS}n
meas tran sn_s find v(sn0) at={TS}n
.endc
.end
"""

def run(corner, temp, sn):
    open("/work/b.sp", "w").write(netlist(corner, temp, sn))
    out = subprocess.run(["ngspice", "-b", "/work/b.sp"], capture_output=True, text=True, timeout=1800).stdout
    g = lambda k: (lambda m: float(m.group(1)) if m else float("nan"))(
        re.search(rf"^{k}\s*=\s*([-+0-9.eE]+)", out, re.M))
    return g("rbl_pre"), g("rbl_s"), g("y_s"), g("sn_s")

lo, hi, step = (float(v) for v in os.environ.get("SNSWEEP", "0.0:0.60:0.025").split(":"))
corners = os.environ.get("CORNERS", "tt27,tt85,ff27,ff85,ss27,ss85").split(",")
print(f"bank read: N {N}, T {T} ns, EVAL {EVAL} cycles, DCTL {DCTL} ns, SETUP {SETUP} ns, CBL {CBL}, "
      f"RWL {RRWL}/{CRWL}, VDD {VDD}, unselected SN {SN1}, sense {SENSE}; sample at {TS:.3f} ns")
for cname in corners:
    corner, temp = "mos_" + cname[:2], int(cname[2:])
    v = lo
    while v <= hi + 1e-9:
        pre, rbl, y, sn = run(corner, temp, round(v, 4))
        print(f"{corner:7s} {temp:3d}C SN {v:6.3f}: RBL at E1 {pre:6.3f}  at sample {rbl:6.3f}  "
              f"sense out {y:6.3f}  reads {'1' if y > VDD / 2 else '0'}", flush=True)
        v += step
