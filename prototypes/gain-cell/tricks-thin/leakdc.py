# DC leakage map for the thin-oxide gain cell, by SPICE (ngspice 44.2 + PSP 103 via OSDI).
# Each case is one DC operating point with every terminal driven, so the currents are the leak
# a storage node would see at that bias. Printed in amperes, per corner and temperature:
#   ch_*:   channel (subthreshold) current of the write transistor, drain at SN, source at WBL,
#           gate at 0 V: Vgs = -Vs, Vds = Vd - Vs. Single thin NMOS (W 0.15 L 0.13), a stack of
#           two, a thin + thick stack, a thick one (W 0.15 L 0.45) for reference.
#   gate_*: gate current of a storage transistor (W 0.30), gate at SN, the rest at the given
#           level: thin NMOS with source/drain/bulk at 0 and at a raised bar; thin PMOS with
#           source/drain/bulk (n-well) at VDD and at lower levels; thick NMOS for reference.
import itertools, re, subprocess
VDD = 1.2
CASES = {
    # name: (netlist body, current source to read); 'sn' node driven by vsn
    "ch_lv_vs0_vd0.7":   ("XA sn 0 w 0 sg13_lv_nmos w=0.15u l=0.13u", 0.7, 0.0),
    "ch_lv_vs0.1_vd0.7": ("XA sn 0 w 0 sg13_lv_nmos w=0.15u l=0.13u", 0.7, 0.1),
    "ch_lv_vs0.2_vd0.7": ("XA sn 0 w 0 sg13_lv_nmos w=0.15u l=0.13u", 0.7, 0.2),
    "ch_lv_vs0.3_vd0.7": ("XA sn 0 w 0 sg13_lv_nmos w=0.15u l=0.13u", 0.7, 0.3),
    "ch_lv_vs0.4_vd0.7": ("XA sn 0 w 0 sg13_lv_nmos w=0.15u l=0.13u", 0.7, 0.4),
    "ch_lv2_vs0_vd0.7":  ("XA sn 0 x 0 sg13_lv_nmos w=0.15u l=0.13u\nXB x 0 w 0 sg13_lv_nmos w=0.15u l=0.13u", 0.7, 0.0),
    "ch_lvhv_vs0_vd0.7": ("XA sn 0 x 0 sg13_lv_nmos w=0.15u l=0.13u\nXB x 0 w 0 sg13_hv_nmos w=0.15u l=0.45u", 0.7, 0.0),
    "ch_hv_vs0_vd0.7":   ("XA sn 0 w 0 sg13_hv_nmos w=0.15u l=0.45u", 0.7, 0.0),
    "gate_nlv_b0_g0.7":  ("XA 0 sn 0 0 sg13_lv_nmos w=0.30u l=0.13u", 0.7, 0.0),
    "gate_nlv_b0.3_g0.7": ("XA w sn w 0 sg13_lv_nmos w=0.30u l=0.13u", 0.7, 0.3),
    "gate_nlv_b0_g0.3":  ("XA 0 sn 0 0 sg13_lv_nmos w=0.30u l=0.13u", 0.3, 0.0),
    "gate_nhv_b0_g0.7":  ("XA 0 sn 0 0 sg13_hv_nmos w=0.30u l=0.45u", 0.7, 0.0),
    "gate_plv_b1.2_g0.7": ("XA w sn w w sg13_lv_pmos w=0.30u l=0.13u", 0.7, 1.2),
    "gate_plv_b1.2_g0.0": ("XA w sn w w sg13_lv_pmos w=0.30u l=0.13u", 0.0, 1.2),
    "gate_plv_b1.2_g1.2": ("XA w sn w w sg13_lv_pmos w=0.30u l=0.13u", 1.2, 1.2),
    "gate_plv_b0.9_g0.3": ("XA w sn w w sg13_lv_pmos w=0.30u l=0.13u", 0.3, 0.9),
    "junc_n_sn0.7":      ("XA sn 0 0 0 sg13_lv_nmos w=0.15u l=0.13u\n", 0.7, 0.0),
}

def netlist(body, vsn, vw, corner, temp):
    return f"""* leak dc
.lib /pdk/libs.tech/ngspice/models/cornerMOSlv.lib {corner}
.lib /pdk/libs.tech/ngspice/models/cornerMOShv.lib {corner}
.temp {temp}
.options abstol=1e-20 gmin=1e-20
vsn sn 0 {vsn}
vw w 0 {vw}
{body}
.control
pre_osdi /work/osdi/psp103.osdi
op
print i(vsn)
.endc
.end
"""

print("current out of the storage node (A, positive = SN loses charge), by bias case")
names = list(CASES)
print("corner  temp  " + "  ".join(f"{n:>18s}" for n in names))
for corner, temp in itertools.product(["mos_tt", "mos_ff", "mos_ss"], [27, 85]):
    row = []
    for n in names:
        body, vsn, vw = CASES[n]
        open("/work/l.sp", "w").write(netlist(body, vsn, vw, corner, temp))
        out = subprocess.run(["ngspice", "-b", "/work/l.sp"], capture_output=True, text=True).stdout
        m = re.search(r"i\(vsn\)\s*=\s*([-+0-9.eE]+)", out)
        # i(vsn) is the current into the source's + terminal, i.e. minus the current it delivers
        row.append(-float(m.group(1)) if m else float("nan"))
    print(f"{corner:7s} {temp:3d}  " + "  ".join(f"{x:18.3e}" for x in row), flush=True)
