# The IHP input pad (sg13g2_IOPadIn) as a comparator: threshold, its supply sensitivity, input
# capacitance, input-referred noise, overdrive-dependent delay and sine sensitivity.
# ngspice 44.2 + PSP 103 (OSDI), run in the spice-retention container by run.sh.
#
# The netlist is sg13g2_IOPadIn from libs.ref/sg13g2_io/spice/sg13g2_io.spi, flattened:
#   primary diodes DCNDiode / DCPDiode (2 x dantenna / dpantenna, l 1.26 w 27.78 each),
#   secondary protection: rppd l 2 w 1 (replaced by an ideal 590 ohm: 2/1.006 sq x 260 ohm/sq
#   from cornerRES.lib plus 2 x 35 ohm head resistance), dantenna l 3.1 w 0.64, dpantenna
#   l 0.64 w 4.98,
#   LevelDown: a thick-oxide inverter (hv nmos w 2.65 l 0.45, hv pmos w 4.65 l 0.45) on the CORE
#   supply vdd, then a thin-oxide inverter (lv nmos w 2.75, pmos w 4.75, l 0.13) driving p2c.
# p2c is loaded with 10 fF (the Tiny Tapeout input mux, an assumption). The source is ideal
# through RSRC (50 ohm unless set).
import os, re, subprocess, sys, math

MODELS = "/pdk/libs.tech/ngspice/models"
RSRC = float(os.environ.get("RSRC", "50"))
CL = os.environ.get("CL", "10f")

def header(corner, temp, vdd, vsrc_spec):
    return f"""* sg13g2_IOPadIn, flattened; {corner} {temp}C vdd={vdd}
.lib {MODELS}/cornerMOSlv.lib mos_{corner}
.lib {MODELS}/cornerMOShv.lib mos_{corner}
.lib {MODELS}/cornerDIO.lib dio_{corner if corner in ('tt','ss','ff') else 'tt'}
.temp {temp}
vdd vdd 0 {vdd}
viovdd iovdd 0 3.3
vsrc src 0 {vsrc_spec}
rsrc src pad {RSRC}
Xdn1 0 pad dantenna l=1.26u w=27.78u
Xdn2 0 pad dantenna l=1.26u w=27.78u
Xdp1 pad iovdd dpantenna l=1.26u w=27.78u
Xdp2 pad iovdd dpantenna l=1.26u w=27.78u
rsec pad padres 590
Xdn3 0 padres dantenna l=3.1u w=0.64u
Xdp3 padres iovdd dpantenna l=0.64u w=4.98u
Xn_hv 0 padres padres_n 0 sg13_hv_nmos l=0.45u w=2.65u
Xp_hv vdd padres padres_n vdd sg13_hv_pmos l=0.45u w=4.65u
Xn_lv core padres_n 0 0 sg13_lv_nmos l=0.13u w=2.75u
Xp_lv core padres_n vdd vdd sg13_lv_pmos l=0.13u w=4.75u
cl core 0 {CL}
"""

def run(name, text):
    sp = f"/work/{name}.sp"
    open(sp, "w").write(text)
    out = subprocess.run(["ngspice", "-b", sp], capture_output=True, text=True, timeout=1200).stdout
    return out

def meas(out, key):
    m = re.search(rf"^{key}\s*=\s*([-+0-9.eE]+)", out, re.M)
    return float(m.group(1)) if m else None

def vt(corner, temp, vdd):
    t = header(corner, temp, vdd, "dc 0") + f"""
.control
pre_osdi /work/osdi/psp103.osdi
dc vsrc 0 1.2 0.0005
meas dc vtr find v(src) when v(core)={vdd/2} rise=1
.endc
.end
"""
    return meas(run("vt", t), "vtr")

def cap_noise(corner, temp, vdd, v0):
    t = header(corner, temp, vdd, f"dc {v0} ac 1") + f"""
.control
pre_osdi /work/osdi/psp103.osdi
op
print v(core)
ac lin 1 100e6 100e6
let cin = -imag(i(vsrc))/(2*pi*100e6)
print cin
ac dec 20 1e5 2e10
let gmag = abs(v(core))
meas ac g0 find gmag at=1e6
let g3 = g0/sqrt(2)
meas ac f3db when gmag=g3 fall=1
let gbw = g0*f3db
print gbw
noise v(core) vsrc dec 20 1e5 2e10
print all
setplot previous
wrdata /work/inoise.txt inoise_spectrum
.endc
.end
"""
    out = run("capnoise", t)
    vc = re.search(r"v\(core\)\s*=\s*([-+0-9.eE]+)", out)
    cin = re.search(r"cin\s*=\s*([-+0-9.eE]+)", out)
    inz = re.search(r"inoise_total\s*=\s*([-+0-9.eE]+)", out)
    onz = re.search(r"onoise_total\s*=\s*([-+0-9.eE]+)", out)
    g0, f3 = meas(out, "g0"), meas(out, "f3db")
    band = {}
    try:
        rows = [tuple(map(float, l.split()[:2])) for l in open("/work/inoise.txt") if l.strip()]
        for fmax in (1e8, 3e8, 1e9, 3e9):
            acc = 0.0
            for (f1, d1), (f2, d2) in zip(rows, rows[1:]):
                if f2 <= fmax: acc += 0.5 * (d1 * d1 + d2 * d2) * (f2 - f1)
            band[fmax] = math.sqrt(acc)
    except OSError:
        pass
    return (float(vc.group(1)) if vc else None, float(cin.group(1)) if cin else None,
            float(inz.group(1)) if inz else None, float(onz.group(1)) if onz else None, g0, f3, band)

def walk(corner, temp, vdd, v0, delta, rising):
    # settle 5 ns at v0 -/+ 0.2 V, 10 ps step to v0 +/- delta at 5 ns
    lo, hi = (v0 - 0.2, v0 + delta) if rising else (v0 + 0.2, v0 - delta)
    t = header(corner, temp, vdd, f"pwl(0 {lo} 5n {lo} 5.01n {hi})") + f"""
.control
pre_osdi /work/osdi/psp103.osdi
tran 1p 12n 0 1p
meas tran tc when v(core)={vdd/2} {'rise' if rising else 'fall'}=1 from=4n
.endc
.end
"""
    tc = meas(run("walk", t), "tc")
    return None if tc is None else tc - 5.005e-9

def sine_toggles(corner, temp, vdd, v0, f, amp, off):
    per = 1.0 / f
    tstop = 2e-9 + 12 * per
    t = header(corner, temp, vdd, f"sin({v0 + off} {amp} {f} 2n)") + f"""
.control
pre_osdi /work/osdi/psp103.osdi
tran {per/200} {tstop} 0 {per/200}
meas tran vmin min v(core) from={2e-9 + 6*per} to={tstop}
.endc
.end
"""
    vmin = meas(run("sine", t), "vmin")
    return vmin is not None and vmin < vdd / 2

def main():
    what = sys.argv[1] if len(sys.argv) > 1 else "all"
    print(f"# RSRC={RSRC} ohm, p2c load {CL}")
    corners = [("tt", 25), ("ss", 125), ("ff", -40)]
    vts = {}
    if what in ("all", "dc"):
        print("## threshold: v(pad) where p2c crosses vdd/2 (DC sweep, rising)")
        print("corner temp vdd vt_V")
        for c, tmp in corners:
            for vdd in (1.08, 1.14, 1.2, 1.26, 1.32):
                v = vt(c, tmp, vdd); vts[(c, tmp, vdd)] = v
                print(f"{c} {tmp} {vdd:.2f} {v:.4f}", flush=True)
        for c, tmp in corners:
            s = (vts[(c, tmp, 1.26)] - vts[(c, tmp, 1.14)]) / 0.12
            print(f"dvt/dvdd {c} {tmp}: {s:.3f} V/V", flush=True)
    else:
        for c, tmp in corners:
            vts[(c, tmp, 1.2)] = vt(c, tmp, 1.2)
    if what in ("all", "noise"):
        print("## at the threshold: input capacitance at 100 MHz, input-referred noise 100 kHz..20 GHz")
        for c, tmp in corners:
            v0 = vts[(c, tmp, 1.2)]
            vc, cin, inz, onz, g0, f3, band = cap_noise(c, tmp, 1.2, v0)
            print(f"{c} {tmp}: input-referred noise integrated 100 kHz..fmax: " + ", ".join(f"{k/1e9:g} GHz {v*1e3:.3f} mV" for k, v in band.items()), flush=True)
            print(f"{c} {tmp}: v0={v0:.4f} v(core)={vc} cin={cin} F small-signal gain={g0} f3dB={f3} Hz "
                  f"onoise_total={onz} V_rms -> input-referred onoise/gain={onz/g0 if (onz and g0) else None} V_rms "
                  f"(ngspice inoise_total over 100k..20G, inflated beyond the bandwidth: {inz})", flush=True)
    if what in ("all", "walk"):
        print("## overdrive-dependent delay: 10 ps step from vt -/+ 0.2 V to vt +/- delta; delay to p2c = vdd/2")
        for c, tmp in corners:
            v0 = vts[(c, tmp, 1.2)]
            for rising in (True, False):
                for d in (0.001, 0.003, 0.01, 0.03, 0.1, 0.3):
                    w = walk(c, tmp, 1.2, v0, d, rising)
                    print(f"{c} {tmp} {'rise' if rising else 'fall'} delta={d*1e3:.0f}mV delay={w*1e12 if w else float('nan'):.1f}ps", flush=True)
    if what in ("all", "sine"):
        print("## sine sensitivity: input vt + 20 mV + A sin(2 pi f t); smallest A (bisection, 7 steps) that toggles p2c")
        c, tmp = "tt", 25
        v0 = vts[(c, tmp, 1.2)]
        for f in (0.1e9, 0.5e9, 1e9, 2e9, 4e9):
            lo, hi = 0.0, 0.5
            for _ in range(7):
                mid = 0.5 * (lo + hi)
                if sine_toggles(c, tmp, 1.2, v0, f, mid, 0.02): hi = mid
                else: lo = mid
            print(f"{c} f={f/1e9:.1f}GHz Amin={hi*1e3:.1f}mV (bracket {lo*1e3:.1f}..{hi*1e3:.1f}) -> |H|~{0.02/hi:.3f}", flush=True)

if __name__ == "__main__":
    main()
