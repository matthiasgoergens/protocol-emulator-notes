# A StrongARM latch sense amplifier in IHP SG13G2 thin-oxide devices, for the gain-cell read bit
# line (ngspice 44.2 + PSP 103). Modes:
#   offset  input-referred offset by Monte Carlo on the PDK's mismatch corner (mos_tt_mismatch,
#           which draws per-instance threshold and mobility deviations with agauss). Per seed,
#           INN sits at VCM and INP ramps by 1 mV per clock cycle (+-60 mV); the offset is the input
#           difference at the first cycle that resolves to OUTP high. SEEDS=a:b.
#   nominal the same ramp at the nominal corners (tt/ff/ss x 27/85), to check that it resolves
#           and how fast.
# Topology: tail NMOS (CLK); input pair INP/INN into nodes X/Y; cross-coupled NMOS on X/Y and PMOS
# to VDD; PMOS precharge of OUTP/OUTN and X/Y while CLK is low. OUTP high means INP > INN.
# Sizes by environment: WIN/LIN (input pair, default 2.0/0.50), WL/LL (latch, 1.0/0.13).
import os, re, subprocess, sys
E = os.environ.get
VDD = 1.2
WIN, LIN, WLT, LLT = E("WIN", "2.0"), E("LIN", "0.50"), E("WL", "1.0"), E("LL", "0.13")
VCM = float(E("VCM", "1.10"))
PER = 5.0          # ns
NCYC = 121
STEP = 1.0e-3

def sa(prefix=""):
    return f"""XT tail clk 0 0 sg13_lv_nmos w=2.0u l=0.13u
XIP x inp tail 0 sg13_lv_nmos w={WIN}u l={LIN}u
XIN y inn tail 0 sg13_lv_nmos w={WIN}u l={LIN}u
XLN1 outn outp x 0 sg13_lv_nmos w={WLT}u l={LLT}u
XLN2 outp outn y 0 sg13_lv_nmos w={WLT}u l={LLT}u
XLP1 outn outp vdd vdd sg13_lv_pmos w={WLT}u l={LLT}u
XLP2 outp outn vdd vdd sg13_lv_pmos w={WLT}u l={LLT}u
XP1 outn clk vdd vdd sg13_lv_pmos w=0.5u l=0.13u
XP2 outp clk vdd vdd sg13_lv_pmos w=0.5u l=0.13u
XP3 x clk vdd vdd sg13_lv_pmos w=0.5u l=0.13u
XP4 y clk vdd vdd sg13_lv_pmos w=0.5u l=0.13u
"""

def netlist(corner, temp, seed=None):
    lo = VCM - STEP * (NCYC - 1) / 2
    # INP steps at each cycle start, CLK rises 1 ns after
    pwl = " ".join(f"{k * PER}n {lo + k * STEP:.6f} {k * PER + 0.05}n {lo + (k + 1) * STEP:.6f}" for k in range(NCYC))
    meas = "\n".join(f"meas tran d{k} find v(outp) at={k * PER + 1 + 2.0}n" for k in range(NCYC))
    return f"""* strongarm offset {corner} {temp} seed {seed}
{f'.options seed={seed}' if seed is not None else ''}
.lib /pdk/libs.tech/ngspice/models/cornerMOSlv.lib {corner}
.temp {temp}
.options reltol=1e-4
vdd vdd 0 {VDD}
vinn inn 0 {VCM}
vinp inp 0 pwl({pwl})
vclk clk 0 pulse(0 {VDD} 1n 50p 50p {PER / 2 - 0.05}n {PER}n)
cl1 outp 0 5f
cl2 outn 0 5f
{sa()}
.control
pre_osdi /work/osdi/psp103.osdi
tran 5p {NCYC * PER}n
{meas}
.endc
.end
"""

def trip(corner, temp, seed=None):
    sp = f"/work/sa_{corner}_{temp}.sp"
    open(sp, "w").write(netlist(corner, temp, seed))
    out = subprocess.run(["ngspice", "-b", sp], capture_output=True, text=True, timeout=1800).stdout
    ds = []
    for k in range(NCYC):
        m = re.search(rf"^d{k}\s*=\s*([-+0-9.eE]+)", out, re.M)
        ds.append(float(m.group(1)) if m else None)
    first = next((k for k, d in enumerate(ds) if d is not None and d > 0.6), None)
    lo = -STEP * (NCYC - 1) / 2
    off = None if first is None else lo + (first - 0.5) * STEP
    return off, ds

mode = sys.argv[1]
if mode == "offset":
    a, b = (int(x) for x in E("SEEDS", "1:50").split(":"))
    corner = E("CORNER", "mos_tt_mismatch")
    print(f"StrongARM offset, {corner} 27C, input pair {WIN}/{LIN}, latch {WLT}/{LLT}, VCM {VCM} V")
    offs = []
    for s in range(a, b + 1):
        off, ds = trip(corner, 27, s)
        offs.append(off)
        print(f"seed {s:4d}: offset {'n/a' if off is None else f'{off * 1e3:+.2f} mV'}", flush=True)
    ok = [o for o in offs if o is not None]
    if ok:
        mu = sum(ok) / len(ok)
        sd = (sum((o - mu) ** 2 for o in ok) / max(1, len(ok) - 1)) ** 0.5
        print(f"n {len(ok)} (of {len(offs)}): mean {mu * 1e3:+.2f} mV, sigma {sd * 1e3:.2f} mV")
else:
    print(f"StrongARM nominal corners, input pair {WIN}/{LIN}, latch {WLT}/{LLT}, VCM {VCM} V")
    for corner in ("mos_tt", "mos_ff", "mos_ss"):
        for temp in (27, 85):
            off, ds = trip(corner, temp)
            print(f"{corner:7s} {temp:3d}C: trips at {'n/a' if off is None else f'{off * 1e3:+.2f} mV'};"
                  f" OUTP 2 ns after CLK at -30/0/+30 mV: "
                  + " ".join("nan" if ds[k] is None else f"{ds[k]:.2f}" for k in (0, (NCYC - 1) // 2, NCYC - 1)),
                  flush=True)
