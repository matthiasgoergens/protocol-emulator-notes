# Retention of a 3-transistor gain cell in IHP SG13G2, by SPICE (ngspice 44.2 + PSP 103 via OSDI).
# Cell: write transistor MW between the write bitline WBL and the storage node SN (gate WWL);
# storage transistor MS with its gate on SN; read-access transistor MR (off during hold).
# Sequence: write the bit for 20 ns, then hold with the write transistor off and WBL driven to
# the opposite value, the worst case for either. Retention = time until SN crosses the read
# threshold: a stored 1 falls below 0.45 V, a stored 0 rises above 0.35 V.
# Environment:
#   MS_SOURCE=wbl ties the storage transistor's source to WBL instead of ground (a rejected
#     layout variant: the storage gate couples to WBL through its channel and loses the bit);
#   TOPO=2T drops MR and holds the storage transistor's source (the row's RWL bar) and drain (RBL)
#     at VDD, the 2T cell's idle state;
#   W sets every transistor's width in um (default 0.15); WMW and LMW override the write
#     transistor's width and length.
import itertools, os, re, subprocess, sys
VDD = 1.2
MS_SOURCE = os.environ.get("MS_SOURCE", "0")
W = os.environ.get("W", "0.15")
WMW = os.environ.get("WMW", W)
LMW = os.environ.get("LMW")
TOPO = os.environ.get("TOPO", "3T")
MS = os.environ.get("MS", "lv")    # storage transistor: lv (thin oxide, L 0.13) or hv (thick, L 0.45)
MSL = "0.13" if MS == "lv" else "0.45"
TWRITE = float(os.environ.get("TWRITE", "20"))    # ns
# DVT shifts the write transistor's threshold (volts, negative = leakier), to place it n sigma
# out in the mismatch distribution. It needs a model copy whose subcircuits take a dvt parameter
# (the stock ones hardcode delvto=0): MODELS=/models, see mkmodels.sh.
MODELS = os.environ.get("MODELS", "/pdk/libs.tech/ngspice/models")
DVT = os.environ.get("DVT")
TSTOP = os.environ.get("TSTOP", "50m")             # simulated hold time
TSTEP = os.environ.get("TSTEP", "100n")            # maximum time step
LEVELS1 = [0.45, 0.40, 0.35, 0.30, 0.25]          # a stored 1 is reported falling past each
LEVELS0 = [0.25, 0.30, 0.35, 0.40]                # a stored 0 rising past each
cases = []
only = sys.argv[1:] or ["lv_nmos", "lv_pmos", "hv_pmos", "hv_nmos"]
for wt, corner, temp, bit in itertools.product(only, ["mos_tt", "mos_ff", "mos_ss"], [27, 85], [1, 0]):
    if os.environ.get("CASES") and f"{corner[4:]}{temp}{bit}" not in os.environ["CASES"].split(","):
        continue           # CASES=tt851,ss270 runs only those (corner, temperature, stored bit)
    cases.append((wt, corner, temp, bit))

def netlist(wt, corner, temp, bit):
    lib = "cornerMOShv.lib" if wt.startswith("hv") or MS == "hv" else "cornerMOSlv.lib"
    L = "0.45u" if wt.startswith("hv") else "0.13u"
    if LMW:
        L = LMW + "u"
    n = wt.endswith("nmos")
    # write: gate on for nmos = VDD, for pmos = 0; hold: the opposite
    won, woff = (VDD, 0.0) if n else (0.0, VDD)
    body = "0" if n else "vdd"
    if TOPO == "2T":
        ms_lines = f"XMS rbl sn vdd 0 sg13_lv_nmos w={W}u l=0.13u"
    else:
        ms_lines = (f"XMS mid sn {MS_SOURCE} 0 sg13_{MS}_nmos w={W}u l={MSL}u\n"
                    f"XMR rbl rwl mid 0 sg13_lv_nmos w={W}u l=0.13u")
    return f"""* gain cell retention {wt} {corner} {temp}C
.lib {MODELS}/cornerMOSlv.lib {corner}
{f'.lib {MODELS}/cornerMOShv.lib ' + corner if lib == 'cornerMOShv.lib' else ''}
.temp {temp}
.options reltol=1e-4 abstol=1e-18 vntol=1e-7
vdd vdd 0 {VDD}
* write bitline: 1 during the write, 0 afterwards (the worst case for a stored 1)
vwbl wbl 0 pwl(0 {VDD if bit else 0} {TWRITE + 10}n {VDD if bit else 0} {TWRITE + 11}n {0 if bit else VDD})
* the cell held the opposite value before the write; without this the DC operating point, not the
* write, sets the stored level (an artefact that inflated every stored-1 result before v4)
.ic v(sn)={0 if bit else 0.7}
* write word line: on for the first 20 ns
vwwl wwl 0 pwl(0 {won} {TWRITE}n {won} {TWRITE + 1}n {woff})
vrwl rwl 0 0
vrbl rbl 0 {VDD}
XMW wbl wwl sn {body} sg13_{wt} w={WMW}u l={L}{f" dvt={DVT}" if DVT else ""}
{ms_lines}
.control
pre_osdi /work/osdi/psp103.osdi
tran {TSTEP} {TSTOP} 0 {TSTEP}
let v0 = v(sn)[0]
meas tran vw find v(sn) at={TWRITE + 5}n
meas tran v1u find v(sn) at=1u
meas tran v10u find v(sn) at=10u
meas tran v100u find v(sn) at=100u
meas tran v1m find v(sn) at=1m
meas tran v10m find v(sn) at=10m
{chr(10).join(f"meas tran t{int(lv * 100)} when v(sn)={lv} {'fall' if bit else 'rise'}=1" for lv in (LEVELS1 if bit else LEVELS0))}
.endc
.end
"""

rows = []
for wt, corner, temp, bit in cases:
    sp = f"/work/cell_{wt}_{corner}_{temp}_{bit}.sp"
    open(sp, "w").write(netlist(wt, corner, temp, bit))
    out = subprocess.run(["ngspice", "-b", sp], capture_output=True, text=True, timeout=600).stdout
    def g(k):
        m = re.search(rf"^{k}\s*=\s*([-+0-9.eE]+)", out, re.M)
        return float(m.group(1)) if m else None
    rows.append((wt, corner, temp, g("vw"), g("v1u"), g("v100u"), g("v1m"), g("v10m")))
    r = rows[-1]
    fmt = lambda x: "  n/a " if x is None else f"{x:6.3f}"
    ts = "  ".join(f"{lv:.2f}V@" + ("-" if g(f"t{int(lv * 100)}") is None else f"{g(f't{int(lv * 100)}') * 1e6:.1f}us")
                   for lv in (LEVELS1 if bit else LEVELS0))
    print(f"{wt:8s} {corner:7s} {temp:3d}C  stored {bit}  written {fmt(r[3])} V  after 1us {fmt(r[4])}  100us {fmt(r[5])}  1ms {fmt(r[6])}  10ms {fmt(r[7])}  crossings {ts}", flush=True)
    if r[3] is None:
        print(out[-1500:], file=sys.stderr)
