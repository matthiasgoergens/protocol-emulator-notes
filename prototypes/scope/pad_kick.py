"""Kicked sampling, characterised on the fitted pad model (padmodel.Pad, checked against SPICE in
results/padmodel-validate.txt), and reduced to a fast linear model for the demonstrations:

    delay = D(u),   u = sum_tau w(tau) * dv(t_kick + tau)

dv is the pin's deviation from the kick base (vt - 0.25 V); D is the delay-versus-static-level
curve; w is the aperture (how much the pin voltage at each moment around the kick moves the
delay), normalised so that sum w = 1 for a static level. Measured for the SPICE kick (200 ps rise,
to compare with results/pad2-aper.txt) and for the kick the liberty predicts (500 ps: the 16 mA
output pad into 1 pF, rise_transition 0.51 ns).

Output: results/kick.txt, results/kick.npz. Run: uv run --with numpy --with scipy python pad_kick.py
"""
import os
import numpy as np
from padmodel import Pad, VT_SPICE

HERE = os.path.dirname(os.path.abspath(__file__))
DT = 2e-12
lines = []
def say(s):
    print(s, flush=True); lines.append(s)

pad = Pad()
t = np.arange(0, 8e-9, DT)
T_K = 3e-9
BASE = VT_SPICE - 0.25
AMP = 0.5
out = {}
for rise in (200e-12, 500e-12):
    kick = AMP * np.clip((t - T_K) / rise, 0, 1)
    deltas = np.arange(-0.15, 0.2201, 0.01)
    v = BASE + deltas[:, None] + kick[None, :]
    core = pad.run(v, DT)
    first = np.argmax(core[:, int(T_K / DT):], axis=1) * DT
    ok = core[:, int(T_K / DT) - 1] == 0
    d = np.where(ok, first, np.nan)
    say(f"kick {AMP} V, rise {rise*1e12:.0f} ps: delay vs static level (mV: ps) " +
        " ".join(f"{x*1e3:.0f}:{y*1e12:.0f}" for x, y in zip(deltas[::3], d[::3])))
    slope0 = np.interp(0.0, deltas, np.gradient(d, deltas))
    # aperture: a 5 mV, 20 ps box at each position
    pos = np.arange(-1.0e-9, 2.0e-9, 20e-12)
    bump = np.zeros((len(pos), len(t)))
    for i, p in enumerate(pos):
        bump[i, (t >= T_K + p) & (t < T_K + p + 20e-12)] = 5e-3
    vb = BASE + bump + kick[None, :]
    cb = pad.run(vb, DT)
    db = np.argmax(cb[:, int(T_K / DT):], axis=1) * DT
    # sub-sample timing: interpolate the crossing using the last low state is not available from
    # the boolean; use a finer grid instead: DT 2 ps against changes of a few ps is coarse, so
    # measure with a larger bump and divide
    bump *= 6
    vb = BASE + bump + kick[None, :]
    cb, va = pad.run(vb, DT, return_va=True)
    k0 = int(T_K / DT)
    # crossing of the internal node through v_lv, linearly interpolated
    def cross(vaa):
        res = []
        for row in vaa:
            r = row[k0:]
            j = int(np.argmax(r < pad.v_lv))
            res.append((j - 1 + (r[j - 1] - pad.v_lv) / (r[j - 1] - r[j])) * DT if j > 0 else np.nan)
        return np.array(res)
    _, va0 = pad.run((BASE + kick)[None, :], DT, return_va=True)
    d0 = cross(va0)[0]
    db = cross(va)
    w = (db - d0) / (slope0 * 30e-3 * 20e-12)          # per second of aperture
    area = np.sum(w) * 20e-12
    w_n = w / np.sum(w)
    mean = np.sum(w_n * pos); rms = np.sqrt(np.sum(w_n * (pos - mean) ** 2))
    H = np.abs(np.array([np.sum(w_n * np.exp(-2j * np.pi * f * pos)) for f in np.arange(0, 5e9, 10e6)]))
    f3 = np.arange(0, 5e9, 10e6)[np.argmax(H < 1 / np.sqrt(2))]
    say(f"  slope at the base {slope0*1e12/1e3:.2f} ps/mV; aperture: integral {area:.3f} (1 = linear), centroid "
        f"{mean*1e12:.0f} ps after the kick starts, rms width {rms*1e12:.0f} ps, -3 dB bandwidth {f3/1e9:.2f} GHz")
    out[f"r{int(rise*1e12)}_deltas"] = deltas
    out[f"r{int(rise*1e12)}_delay"] = d
    out[f"r{int(rise*1e12)}_pos"] = pos
    out[f"r{int(rise*1e12)}_w"] = w_n
    out[f"r{int(rise*1e12)}_d0"] = d0
np.savez_compressed(os.path.join(HERE, "results", "kick.npz"), **out)
say("SPICE comparison (results/pad2-aper.txt, 200 ps kick, 30 mV x 100 ps bumps): the delay moved by 5-25 ps "
    "for bumps from +100 to +700 ps, nothing outside; slope 4.0 ps/mV (pad2-kick.txt, -10..+10 mV)")
open(os.path.join(HERE, "results", "kick.txt"), "w").write("\n".join(lines) + "\n")
