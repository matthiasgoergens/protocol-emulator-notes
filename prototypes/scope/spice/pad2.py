# Reference data for the behavioural pad model (sg13g2_IOPadIn, flattened as in pad.py):
#   iv    the thick-oxide inverter's output current into padres_n as a function of
#         (v(padres), v(padres_n)), with padres_n forced; corners tt/ss/ff
#   step  steps from vt -/+ 0.2 V to vt +/- delta (the walk data, as waveforms)
#   sck   an SPI SCK edge (1 ns rise, 300 MHz ringing) scaled by K and offset so that the
#         threshold sits at a given level of the SUT waveform
#   kick  a fast step ("kick") of KICK volts added at 5 ns to a DC level vt - 0.25 + delta: the
#         pad's delay as a function of delta (a voltage-to-time converter)
#   aper  the kick with a narrow bump on the input at various times around the kick: how the
#         delay weights the input over time (the aperture)
# Waveforms go to /work/w_<name>.txt (time, v(pad), v(padres_n), v(core)) for the host to read.
import os, subprocess, sys, math
sys.path.insert(0, "/work")
from pad import header, vt, meas, run

VDD = 1.2
DT = "2p"

def pwl(points):
    return "pwl(" + " ".join(f"{t:.4e} {v:.5f}" for t, v in points) + ")"

def tran(name, spec, tstop, extra=""):
    t = header("tt", 25, VDD, spec) + f"""
.options method=gear
.control
pre_osdi /work/osdi/psp103.osdi
tran 1p {tstop} 0 {DT}
linearize
wrdata /work/w_{name}.txt v(pad) v(padres_n) v(core)
{extra}
.endc
.end
"""
    return run(name, t)

def sut_sck(t, t0=5e-9, rise=1e-9, ring_amp=0.40, ring_f=300e6, ring_tau=3e-9, vhi=3.3):
    # erf edge with 10-90 % time `rise`, plus decaying ringing starting at the edge centre
    s = rise / 2.563
    e = 0.5 * (1 + math.erf((t - t0) / (s * math.sqrt(2))))
    r = 0.0
    if t > t0:
        r = ring_amp * math.sin(2 * math.pi * ring_f * (t - t0)) * math.exp(-(t - t0) / ring_tau)
    return vhi * e + r * e

def main():
    part = sys.argv[1]
    v0 = vt("tt", 25, VDD)
    print(f"# tt 25C vdd {VDD}: vt = {v0:.4f} V")
    if part == "iv":
        for c, tmp in (("tt", 25), ("ss", 125), ("ff", -40)):
            t = header(c, tmp, VDD, "dc 0").replace("Xn_lv core padres_n", "Xn_lv core padres_nx").replace(
                "Xp_lv core padres_n", "Xp_lv core padres_nx") + f"""
va padres_n 0 dc 0
vax padres_nx 0 dc 0.6
.control
pre_osdi /work/osdi/psp103.osdi
dc vsrc 0 1.2 0.005 va 0 1.2 0.01
wrdata /work/iv_{c}.txt i(va)
.endc
.end
"""
            run("iv", t)
            print(f"iv table written: {c} {tmp}")
    elif part == "step":
        for rising in (True, False):
            for d in (0.05, 0.1, 0.2, 0.3, 0.5):
                lo, hi = (v0 - 0.2, v0 + d) if rising else (v0 + 0.2, v0 - d)
                name = f"step_{'r' if rising else 'f'}{int(d*1000)}"
                tran(name, pwl([(0, lo), (5e-9, lo), (5.01e-9, hi)]), "25n")
                print("wrote", name, flush=True)
    elif part == "sck":
        k = float(os.environ.get("K", "0.25"))
        for level in (0.5, 1.65, 2.8, 3.3, 3.5, 3.6):
            off = v0 - k * level
            pts = [(i * 5e-12, off + k * sut_sck(i * 5e-12)) for i in range(0, 4001)]
            name = f"sck_L{int(level*1000)}"
            tran(name, pwl(pts), "20n")
            print("wrote", name, f"k={k} offset={off:.4f}", flush=True)
    elif part == "kick":
        kick = float(os.environ.get("KICK", "0.5"))
        tr = float(os.environ.get("KRISE", "200e-12"))
        for dmv in range(-60, 61, 10):
            d = dmv / 1000
            base = v0 - 0.25 + d
            name = f"kick_{dmv}"
            out = tran(name, pwl([(0, base), (5e-9, base), (5e-9 + tr, base + kick)]), "12n",
                       f"meas tran tc when v(core)={VDD/2} rise=1 from=4n")
            tc = meas(out, "tc")
            print(f"kick {kick} V rise {tr*1e12:.0f} ps: delta={dmv} mV delay={(tc - 5e-9)*1e12 if tc else float('nan'):.1f} ps", flush=True)
    elif part == "aper":
        kick = float(os.environ.get("KICK", "0.5"))
        tr = float(os.environ.get("KRISE", "200e-12"))
        base = v0 - 0.25
        for pos_ps in [None] + list(range(-800, 801, 100)):
            pts = []
            for i in range(0, 2401):
                t = i * 5e-12
                v = base + (kick * min(1.0, max(0.0, (t - 5e-9) / tr)))
                if pos_ps is not None:
                    v += 0.03 * math.exp(-0.5 * ((t - 5e-9 - pos_ps * 1e-12) / 42e-12) ** 2)
                pts.append((t, v))
            name = f"aper_{'none' if pos_ps is None else pos_ps}"
            out = tran(name, pwl(pts), "12n", f"meas tran tc when v(core)={VDD/2} rise=1 from=4n")
            tc = meas(out, "tc")
            print(f"aperture: 30 mV bump (100 ps FWHM) at {pos_ps} ps from kick start: delay={(tc - 5e-9)*1e12 if tc else float('nan'):.2f} ps", flush=True)

main()
