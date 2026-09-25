# Which path drains the storage node? Holds a stored level on SN and compares the droop over
# 1 ms with each leakage path present on its own:
#   full:    the 3T cell as in run.py (MW, MS, MR)
#   mw_only: MW, with MS and MR replaced by an ideal capacitor (no gate leakage)
#   ms_only: MS and MR, with MW absent (SN touches nothing but the storage gate)
#   ms_hv:   full cell with a thick-oxide storage transistor instead
#   mwlv_only: a thin-oxide write transistor (W 0.15, L 0.13) with the ideal capacitor
# All start from the same SN (.ic), so the droop compares leakage currents directly; the ideal
# capacitor matches the storage gate's capacitance (CSN, estimated from full's coupling).
# No `uic`: with it every other node, the models' internal nodes included, starts at 0 V and
# the stored charge is shared out at t = 0 (a 0.43 V droop in every variant, an artefact).
import itertools, os, re, subprocess
VDD = 1.2
SN0 = float(os.environ.get("SN0", "0.55"))
CSN = os.environ.get("CSN", "1.5f")

def netlist(variant, corner, temp):
    mw = "XMW wbl 0 sn 0 sg13_hv_nmos w=0.15u l=0.45u"
    ms = "XMS mid sn 0 0 sg13_lv_nmos w=0.30u l=0.13u\nXMR rbl 0 mid 0 sg13_lv_nmos w=0.30u l=0.13u"
    body = {"full": f"{mw}\n{ms}",
            "mw_only": f"{mw}\ncsn sn 0 {CSN}",
            "ms_only": f"{ms}",
            "mwlv_only": f"XMW wbl 0 sn 0 sg13_lv_nmos w=0.15u l=0.13u\ncsn sn 0 {CSN}",
            "ms_hv": f"{mw}\nXMS mid sn 0 0 sg13_hv_nmos w=0.30u l=0.45u\nXMR rbl 0 mid 0 sg13_lv_nmos w=0.30u l=0.13u"}[variant]
    return f"""* leak {variant} {corner} {temp}
.lib /pdk/libs.tech/ngspice/models/cornerMOSlv.lib {corner}
.lib /pdk/libs.tech/ngspice/models/cornerMOShv.lib {corner}
.temp {temp}
.options reltol=1e-4 abstol=1e-18 vntol=1e-7
vwbl wbl 0 0
vrbl rbl 0 {VDD}
{body}
.ic v(sn)={SN0}
.control
pre_osdi /work/osdi/psp103.osdi
tran 1u 1m 0 1u
meas tran v100u find v(sn) at=100u
meas tran v1m find v(sn) at=1m
.endc
.end
"""

for corner, temp in itertools.product(["mos_tt", "mos_ff", "mos_ss"], [27, 85]):
    row = []
    for variant in (os.environ.get("VARIANTS", "full,mw_only,ms_only,ms_hv,mwlv_only").split(",")):
        sp = f"/work/leak_{variant}_{corner}_{temp}.sp"
        open(sp, "w").write(netlist(variant, corner, temp))
        out = subprocess.run(["ngspice", "-b", sp], capture_output=True, text=True, timeout=600).stdout
        m = re.search(r"^v1m\s*=\s*([-+0-9.eE]+)", out, re.M)
        row.append(f"{variant} {SN0 - float(m.group(1)) if m else float('nan'):+.3f}")
    print(f"{corner:7s} {temp:3d}C  droop over 1 ms from {SN0} V:  " + "   ".join(row), flush=True)
