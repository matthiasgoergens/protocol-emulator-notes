# Retention of a 3-transistor gain cell in IHP SG13G2, by SPICE (ngspice 44.2 + PSP 103 via OSDI).
# Cell: write transistor MW between the write bitline WBL and the storage node SN (gate WWL);
# storage transistor MS with its gate on SN; read-access transistor MR (off during hold).
# Sequence: write a 1 for 20 ns, then hold with the write transistor off and WBL driven to 0,
# the worst case for a stored 1. Retention = time until SN has lost half of its written level.
import itertools, re, subprocess, sys
VDD = 1.2
cases = []
only = sys.argv[1:] or ["lv_nmos", "lv_pmos", "hv_pmos", "hv_nmos"]
for wt, corner, temp in itertools.product(only, ["mos_tt", "mos_ff"], [27, 85]):
    cases.append((wt, corner, temp))

def netlist(wt, corner, temp):
    lib = "cornerMOShv.lib" if wt.startswith("hv") else "cornerMOSlv.lib"
    L = "0.45u" if wt.startswith("hv") else "0.13u"
    n = wt.endswith("nmos")
    # write: gate on for nmos = VDD, for pmos = 0; hold: the opposite
    won, woff = (VDD, 0.0) if n else (0.0, VDD)
    body = "0" if n else "vdd"
    return f"""* gain cell retention {wt} {corner} {temp}C
.lib /pdk/libs.tech/ngspice/models/cornerMOSlv.lib {corner}
{'.lib /pdk/libs.tech/ngspice/models/cornerMOShv.lib ' + corner if lib == 'cornerMOShv.lib' else ''}
.temp {temp}
.options reltol=1e-4 abstol=1e-18 vntol=1e-7
vdd vdd 0 {VDD}
* write bitline: 1 during the write, 0 afterwards (the worst case for a stored 1)
vwbl wbl 0 pwl(0 {VDD} 30n {VDD} 31n 0)
* write word line: on for the first 20 ns
vwwl wwl 0 pwl(0 {won} 20n {won} 21n {woff})
vrwl rwl 0 0
vrbl rbl 0 {VDD}
XMW wbl wwl sn {body} sg13_{wt} w=0.15u l={L}
XMS mid sn 0 0 sg13_lv_nmos w=0.15u l=0.13u
XMR rbl rwl mid 0 sg13_lv_nmos w=0.15u l=0.13u
.control
pre_osdi /work/osdi/psp103.osdi
tran 100n 20m 0 100n
let v0 = v(sn)[0]
meas tran vw find v(sn) at=25n
meas tran v1u find v(sn) at=1u
meas tran v10u find v(sn) at=10u
meas tran v100u find v(sn) at=100u
meas tran v1m find v(sn) at=1m
meas tran v10m find v(sn) at=10m
let half = vw / 2
meas tran thalf when v(sn)=half fall=1
.endc
.end
"""

rows = []
for wt, corner, temp in cases:
    sp = f"/work/cell_{wt}_{corner}_{temp}.sp"
    open(sp, "w").write(netlist(wt, corner, temp))
    out = subprocess.run(["ngspice", "-b", sp], capture_output=True, text=True, timeout=600).stdout
    def g(k):
        m = re.search(rf"^{k}\s*=\s*([-+0-9.eE]+)", out, re.M)
        return float(m.group(1)) if m else None
    rows.append((wt, corner, temp, g("vw"), g("v1u"), g("v100u"), g("v1m"), g("v10m"), g("thalf")))
    r = rows[-1]
    fmt = lambda x: "  n/a " if x is None else f"{x:6.3f}"
    t = "> 20 ms" if r[8] is None else (f"{r[8]*1e6:9.1f} us")
    print(f"{wt:8s} {corner:7s} {temp:3d}C  written {fmt(r[3])} V  after 1us {fmt(r[4])}  100us {fmt(r[5])}  1ms {fmt(r[6])}  10ms {fmt(r[7])}  half-level at {t}", flush=True)
    if r[3] is None:
        print(out[-1500:], file=sys.stderr)
