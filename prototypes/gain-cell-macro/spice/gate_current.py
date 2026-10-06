# Gate current of one transistor with source, drain and bulk at 0 V and the gate at VG: the
# storage transistor's gate is the storage node, so this is the stored 1's leak through the
# storage gate (../../gain-cell/retention/leak.py found it to be the dominant path).
# Prints, per corner and temperature, the gate current of
#   lv: sg13_lv_nmos W 0.30 L 0.13 (the storage transistor), and
#   hv: sg13_hv_nmos W 0.15 L 0.45 (the write transistor, gate at VG, for comparison)
# at VG = 0.2, 0.4 and 0.6 V. Run under run.sh with PDK=cmos5l and PDK=g2old to compare the two
# PSP 103 builds on the same model cards.
import itertools, re, subprocess

def netlist(dev, corner, temp, vg):
    m = ("XM d g s b sg13_lv_nmos w=0.30u l=0.13u" if dev == "lv"
         else "XM d g s b sg13_hv_nmos w=0.15u l=0.45u")
    return f"""* gate current {dev} {corner} {temp} {vg}
.lib /pdk/libs.tech/ngspice/models/cornerMOSlv.lib {corner}
.lib /pdk/libs.tech/ngspice/models/cornerMOShv.lib {corner}
.temp {temp}
.options reltol=1e-6 abstol=1e-20
vg g 0 {vg}
vd d 0 0
vs s 0 0
vb b 0 0
{m}
.control
pre_osdi /work/osdi/psp103.osdi
op
print -i(vg)
.endc
.end
"""

print("gate current (A, into the gate) with S = D = B = 0 V")
for dev, corner, temp in itertools.product(["lv", "hv"], ["mos_tt", "mos_ff", "mos_ss"], [27, 85]):
    vals = []
    for vg in (0.2, 0.4, 0.6):
        open("/work/g.sp", "w").write(netlist(dev, corner, temp, vg))
        out = subprocess.run(["ngspice", "-b", "/work/g.sp"], capture_output=True, text=True).stdout
        m = re.search(r"-i\(vg\)\s*=\s*([-+0-9.eE]+)", out)
        vals.append(m.group(1) if m else "n/a")
    print(f"{dev} {corner:7s} {temp:3d}C  VG 0.2: {vals[0]:>12s}  0.4: {vals[1]:>12s}  0.6: {vals[2]:>12s}",
          flush=True)
