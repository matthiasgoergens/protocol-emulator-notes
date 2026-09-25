# A boosted write word line from the 1.2 V supply alone (IHP SG13G2, ngspice 44.2 + PSP 103).
#
# VPP generator (one per array): a cross-coupled voltage doubler. Two flying capacitors, driven
# by complementary clocks CK/CKB (0/1.2 V, from the core), lift their top plates A/B between
# VDD and 2 VDD. Cross-coupled thick-oxide NMOS recharge A/B from VDD; cross-coupled thick-oxide
# PMOS (n-well at VPP) pass the high one to VPP. A reservoir capacitor holds VPP. By construction
# no node exceeds 2 VDD = 2.4 V, under the 3.3 V rating of the thick-oxide devices. The
# capacitors are thick-oxide NMOS capacitors (gate = top plate, source/drain = bottom plate).
#
# Row driver (per row): a thick-oxide level shifter (cross-coupled PMOS from VPP, NMOS pull-downs
# on the decoder output D and its complement) and a thick-oxide inverter from VPP onto WWL.
# Thin-oxide devices only ever see 0/1.2 V (the decoder).
#
# Load: the row's 32 write transistors, each writing a 1 into a 3T cell (thick-oxide storage
# transistor unless MS=lv) from WBL = 1.2 V, on a poly word line of RWIRE ohm and CWIRE in 4
# segments; the other 31 rows' drivers idle on VPP (one instance, m=31).
#
# WBL alternates: the even-numbered writes store a 1 over the previous 0, the odd ones a 0.
# Sequence: the pump starts at t = 0 from VPP = 0; writes (WWL high for TW ns) at the times in
# WRITES (us). Reports VPP before and after each write, the WWL level at the far end, its rise
# time, the written SN of the far-end cell 5 ns after WWL falls, and the peak voltage on VPP and
# on the flying-capacitor nodes.
import os, re, subprocess
E = os.environ.get
VDD = 1.2
FCK = float(E("FCK", "100"))            # MHz pump clock
CFLY = E("CFLY", "10x2")                # flying cap: hv nmos W L (um): 20 um2 ~ 90 fF
CRES = E("CRES", "10x10")               # reservoir: 100 um2 ~ 460 fF
# FLY=lv: thin-oxide flying capacitors and start-up diodes. In steady state a flying capacitor's
# gate (top plate) sits VDD above its inverted channel (bottom plate), so its oxide sees 1.2 V;
# the thick-oxide capacitor does not start (its top plate only reaches VDD - VT, too little to
# invert it once the clock lifts the bottom plate).
FLY = E("FLY", "lv")
STARTUP = E("STARTUP", FLY)            # oxide of the start-up diodes
NCOL = int(E("NCOL", "32"))
RWIRE, CWIRE = float(E("RWIRE", "500")), float(E("CWIRE", "4e-15"))
TW = float(E("TW", "20"))
WRITES = [float(x) for x in E("WRITES", "3,3.2,3.4,3.6").split(",")]
MS = E("MS", "hv")
MSL = "0.45" if MS == "hv" else "0.13"
TSTOP = max(WRITES) + 0.2

def netlist(corner, temp):
    fw, fl = re.split(r"[x_ ]", CFLY)
    rw, rl = re.split(r"[x_ ]", CRES)
    per = 1e3 / FCK
    # decoder: D high during each write window, DB its complement (thin-oxide levels)
    pts = ["0 0"]
    for w in WRITES:
        t0 = w * 1e3
        pts += [f"{t0}n 0", f"{t0 + 0.2}n {VDD}", f"{t0 + TW}n {VDD}", f"{t0 + TW + 0.2}n 0"]
    dpwl = " ".join(pts)
    # WBL: 1 for the even-numbered writes, 0 for the odd ones, so each write of a 1 starts from 0
    wp = [f"0 {VDD}"]
    for j, w in enumerate(WRITES):
        t0 = w * 1e3
        v = VDD if j % 2 == 0 else 0
        wp += [f"{t0 - 50}n {wp[-1].split()[1]}", f"{t0 - 49}n {v}"]
    wblpwl = " ".join(wp)
    dbpwl = " ".join(f"{p.split()[0]} {VDD - float(p.split()[1]):.3f}" for p in pts)
    seg = RWIRE / 4
    wire = "\n".join(f"rw{k} w{k} w{k + 1} {seg}\ncw{k} w{k + 1} 0 {CWIRE / 4}" for k in range(4))
    # cells hang off the four segment ends; 32 in all
    cells = []
    for i in range(NCOL):
        node = f"w{1 + (i * 4) // NCOL}"
        cells.append(f"XMW{i} wbl {node} sn{i} 0 sg13_hv_nmos w=0.15u l=0.45u\n"
                     f"XMS{i} mid{i} sn{i} 0 0 sg13_{MS}_nmos w=0.30u l={MSL}u\n"
                     f"XMR{i} vdd 0 mid{i} 0 sg13_lv_nmos w=0.30u l=0.13u\n.ic v(sn{i})=0")
    far = f"sn{NCOL - 1}"
    ms = []
    for j, w in enumerate(WRITES):
        t0 = w * 1e3
        ms += [f"meas tran vppb{j} find v(vpp) at={t0 - 0.5}n",
               f"meas tran vppa{j} find v(vpp) at={t0 + TW + 5}n",
               f"meas tran wwl{j} find v(w4) at={t0 + TW - 0.5}n",
               f"meas tran tr{j} trig v(d) val=0.6 rise=1 td={t0 - 1}n targ v(w4) val={0.9} rise=1 td={t0 - 1}n",
               f"meas tran wsf{j} find v({far}) at={t0 + TW + 5}n",
               f"meas tran wsn{j} find v(sn0) at={t0 + TW + 5}n"]
    return f"""* boosted WWL {corner} {temp}
.lib /pdk/libs.tech/ngspice/models/cornerMOSlv.lib {corner}
.lib /pdk/libs.tech/ngspice/models/cornerMOShv.lib {corner}
.temp {temp}
.options reltol=1e-3 abstol=1e-14 vntol=1e-6
vdd vdd 0 {VDD}
vck ck 0 pulse(0 {VDD} 0 0.2n 0.2n {per / 2 - 0.2}n {per}n)
vckb ckb 0 pulse({VDD} 0 0 0.2n 0.2n {per / 2 - 0.2}n {per}n)
* pump: flying caps (gate = top plate a/b, source/drain = clock), cross-coupled NMOS to VDD,
* cross-coupled PMOS to VPP (n-well at VPP)
XCA ck a ck 0 sg13_{FLY}_nmos w={fw}u l={fl}u
XCB ckb b ckb 0 sg13_{FLY}_nmos w={fw}u l={fl}u
XN1 vdd b a 0 sg13_hv_nmos w=1.0u l=0.45u
XN2 vdd a b 0 sg13_hv_nmos w=1.0u l=0.45u
* start-up: diode-connected NMOS charge A and B to VDD - VT (the cross-coupled pair cannot start from 0)
XSA vdd vdd a 0 sg13_{STARTUP}_nmos w=0.3u l={'0.13' if STARTUP == 'lv' else '0.45'}u
XSB vdd vdd b 0 sg13_{STARTUP}_nmos w=0.3u l={'0.13' if STARTUP == 'lv' else '0.45'}u
XP1 vpp b a vpp sg13_hv_pmos w=2.0u l=0.45u
XP2 vpp a b vpp sg13_hv_pmos w=2.0u l=0.45u
XCR 0 vpp 0 0 sg13_hv_nmos w={rw}u l={rl}u
* the selected row's driver: level shifter + inverter, all thick oxide
vd d 0 pwl({dpwl})
vdb db 0 pwl({dbpwl})
XLP1 ls lsb vpp vpp sg13_hv_pmos w=0.3u l=0.45u
XLP2 lsb ls vpp vpp sg13_hv_pmos w=0.3u l=0.45u
XLN1 ls d 0 0 sg13_hv_nmos w=1.0u l=0.45u
XLN2 lsb db 0 0 sg13_hv_nmos w=1.0u l=0.45u
* ls is low when selected (d high pulls it down), so the inverter output goes to VPP
XDP w0 ls vpp vpp sg13_hv_pmos w=3.0u l=0.45u
XDN w0 ls 0 0 sg13_hv_nmos w=1.0u l=0.45u
* 31 idle rows' drivers on VPP (their level shifters hold lsb low, ls high: output PMOS off)
XIP widle vpp vpp vpp sg13_hv_pmos w=3.0u l=0.45u m=31
XIN widle vpp 0 0 sg13_hv_nmos w=1.0u l=0.45u m=31
XILP lsbi vpp vpp vpp sg13_hv_pmos w=0.3u l=0.45u m=31
XILN lsbi vdd 0 0 sg13_hv_nmos w=1.0u l=0.45u m=31
XILN2 vpp 0 0 0 sg13_hv_nmos w=1.0u l=0.45u m=31
{wire}
vwbl wbl 0 pwl({wblpwl})
{chr(10).join(cells)}
.control
pre_osdi /work/osdi/psp103.osdi
tran 0.1n {TSTOP}u
meas tran vppmax max v(vpp)
meas tran amax max v(a)
meas tran bmax max v(b)
meas tran lsmax max v(ls)
let dca = v(a) - v(ck)
let dcb = v(b) - v(ckb)
meas tran dca max dca
meas tran dcb max dcb
meas tran tup when v(vpp)=2.0 rise=1
let psup = -(v(vdd)*i(vdd) + v(ck)*i(vck) + v(ckb)*i(vckb) + v(d)*i(vd) + v(db)*i(vdb))
meas tran pidle avg psup from=2.0u to=2.9u
meas tran pwr avg psup from=2.9u to={max(WRITES) + 0.2}u
{chr(10).join(ms)}
.endc
.end
"""

print(f"boosted WWL: pump {FCK} MHz, start-up diodes {STARTUP}, flying caps {FLY} {CFLY} um, reservoir hv {CRES} um; {NCOL} cells ({MS} storage),"
      f" wire {RWIRE} ohm / {CWIRE * 1e15:.1f} fF; writes of {TW} ns at {WRITES} us")
for corner in [c for c in E("CORNERS", "mos_tt,mos_ff,mos_ss").split(",")]:
    for temp in [int(t) for t in E("TEMPS", "27,85").split(",")]:
        sp = f"/work/wwl_{corner}_{temp}.sp"
        open(sp, "w").write(netlist(corner, temp))
        out = subprocess.run(["ngspice", "-b", sp], capture_output=True, text=True, timeout=7200).stdout
        g = lambda k: (lambda m: float(m.group(1)) if m else float("nan"))(re.search(rf"^{k}\s*=\s*([-+0-9.eE]+)", out, re.M))
        print(f"{corner:7s} {temp:3d}C  peak VPP {g('vppmax'):.3f}, A {g('amax'):.3f}, B {g('bmax'):.3f}, LS {g('lsmax'):.3f} V;"
              f" peak across the flying caps {g('dca'):.3f} / {g('dcb'):.3f} V; VPP reaches 2.0 V at {g('tup') * 1e6:.2f} us;"
              f" supply power idle {g('pidle') * 1e6:.1f} uW, with writes every {(WRITES[1] - WRITES[0]) * 1e3:.0f} ns {g('pwr') * 1e6:.1f} uW", flush=True)
        for j, w in enumerate(WRITES):
            print(f"    write at {w} us: VPP {g(f'vppb{j}'):.3f} -> {g(f'vppa{j}'):.3f} V; far-end WWL {g(f'wwl{j}'):.3f} V,"
                  f" D to WWL 0.9 V {g(f'tr{j}') * 1e9:.2f} ns; written SN far {g(f'wsf{j}'):.3f}, near {g(f'wsn{j}'):.3f} V", flush=True)
