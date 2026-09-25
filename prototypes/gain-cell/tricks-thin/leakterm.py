# Where does the write transistor's leakage floor go? One thin NMOS (W 0.15 L 0.13), drain = SN
# at VD, gate at VG, source (WBL) at VS, bulk 0; every terminal driven by its own source, so the
# current into each terminal is separated: drain (total SN loss), gate (gate-drain tunnelling),
# source (channel), bulk (junction + GIDL). Also gate current of thin NMOS and PMOS storage
# transistors (W 0.30 L 0.13) at equal |Vgs|: NMOS gate at V, rest at 0; PMOS gate at 1.2-V,
# rest at 1.2 (n-well).
import itertools, re, subprocess
def op(body, corner, temp, prints):
    sp = f"""* t
.lib /pdk/libs.tech/ngspice/models/cornerMOSlv.lib {corner}
.temp {temp}
.options abstol=1e-20 gmin=1e-20
{body}
.control
pre_osdi /work/osdi/psp103.osdi
op
print {' '.join(prints)}
.endc
.end
"""
    open("/work/t.sp", "w").write(sp)
    out = subprocess.run(["ngspice", "-b", "/work/t.sp"], capture_output=True, text=True).stdout
    return [-float(re.search(rf"{re.escape(p)}\s*=\s*([-+0-9.eE]+)", out).group(1)) for p in prints]
print("write transistor, SN (drain) at 0.7 V, gate 0: current out of each terminal source (A); "
      "positive at vd = SN loses charge")
for corner, temp in itertools.product(["mos_tt", "mos_ff", "mos_ss"], [27, 85]):
    for vs in (0.0, 0.2, 0.3, 0.4, 0.7):
        r = op(f"vd d 0 0.7\nvg g 0 0\nvs s 0 {vs}\nvb b 0 0\nXA d g s b sg13_lv_nmos w=0.15u l=0.13u",
               corner, temp, ["i(vd)", "i(vg)", "i(vs)", "i(vb)"])
        print(f"{corner} {temp:3d}C vs {vs:.1f}: drain {r[0]:10.3e} gate {r[1]:10.3e} source {r[2]:10.3e} bulk {r[3]:10.3e}", flush=True)
print("\ngate current, storage transistor W 0.30 L 0.13, |Vgs| = V (A, magnitude)")
for corner, temp in itertools.product(["mos_tt", "mos_ff", "mos_ss"], [27, 85]):
    row = []
    for v in (0.3, 0.5, 0.7, 0.9, 1.2):
        n = op(f"vg g 0 {v}\nXA 0 g 0 0 sg13_lv_nmos w=0.30u l=0.13u", corner, temp, ["i(vg)"])[0]
        p = op(f"vdd w 0 1.2\nvg g 0 {1.2 - v}\nXA w g w w sg13_lv_pmos w=0.30u l=0.13u", corner, temp, ["i(vg)"])[0]
        row.append(f"{v:.1f}V n {abs(n):9.2e} p {abs(p):9.2e}")
    print(f"{corner} {temp:3d}C  " + "   ".join(row), flush=True)
