"""Behavioural model of the IHP input pad (sg13g2_IOPadIn) as a comparator, fitted to SPICE.

The pad's receiver is a thick-oxide inverter on the 1.2 V core supply followed by a thin-oxide
inverter (spice/pad.py). Its threshold is about 0.59 V and, at the threshold, both thick-oxide
devices are weak, so the first stage is a slow, nonlinear integrator:

    C_a dVa/dt = I(v_in, Va) + C_m d(v_in)/dt ,      p2c = (Va < V_lv) delayed by d_lv

I(v_in, Va) is the thick-oxide inverter's output current, tabulated by SPICE (spice/pad2.py iv),
v_in is the pad voltage after the secondary-protection RC (tau_in). C_a, C_m and tau_in are fitted
to SPICE step responses (fit()). The model is then checked against SPICE waveforms it was not
fitted to (validate()).

Run: uv run --with numpy --with scipy python padmodel.py fit|validate
"""
import os, sys, glob
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
SPICE_DIR = "/var/tmp/scope/spice2"
IV_NPZ = os.path.join(HERE, "results", "pad-iv.npz")
FIT_TXT = os.path.join(HERE, "results", "padmodel-fit.txt")
VDD = 1.2
VT_SPICE = 0.5887           # tt 25 C, results/pad-dc.txt

def pack_iv():
    out = {}
    for c in ("tt", "ss", "ff"):
        a = np.loadtxt(os.path.join(SPICE_DIR, "iv", f"iv_{c}.txt"))
        vin = a[:241, 0]
        i = a[:, 1].reshape(121, 241)          # outer va 0..1.2 step 0.01, inner vin
        out[c] = i.astype(np.float64)
    np.savez_compressed(IV_NPZ, vin=vin, va=np.linspace(0, 1.2, 121), **out)

class Pad:
    """Vectorised comparator: simulate many input waveforms at once on a uniform time grid."""
    def __init__(self, corner="tt", C_a=None, C_m=None, tau_in=None, v_lv=0.6, d_lv=20e-12):
        z = np.load(IV_NPZ)
        self.vin_g, self.va_g, self.I = z["vin"], z["va"], z[corner]
        p = self.params()
        self.C_a = C_a if C_a is not None else p.get("C_a", 15e-15)
        self.C_m = C_m if C_m is not None else p.get("C_m", 1e-15)
        self.tau_in = tau_in if tau_in is not None else p.get("tau_in", 12e-12)
        self.v_lv, self.d_lv = v_lv, d_lv

    @staticmethod
    def params():
        p = {}
        if os.path.exists(FIT_TXT):
            for line in open(FIT_TXT):
                if line.startswith("param "):
                    _, k, v = line.split()
                    p[k] = float(v)
        return p

    def current(self, vin, va):
        # bilinear interpolation in the (va, vin) table; clamp to the table
        x = np.clip((vin - self.vin_g[0]) / (self.vin_g[1] - self.vin_g[0]), 0, len(self.vin_g) - 1.001)
        y = np.clip((va - self.va_g[0]) / (self.va_g[1] - self.va_g[0]), 0, len(self.va_g) - 1.001)
        xi, yi = x.astype(int), y.astype(int)
        fx, fy = x - xi, y - yi
        I = self.I
        return ((1 - fy) * ((1 - fx) * I[yi, xi] + fx * I[yi, xi + 1]) +
                fy * ((1 - fx) * I[yi + 1, xi] + fx * I[yi + 1, xi + 1]))

    def run(self, v_pad, dt, va0=None, return_va=False):
        """v_pad: array (..., n) of pad voltages on a grid of step dt. Returns p2c as bool (..., n)."""
        v_pad = np.asarray(v_pad, dtype=np.float64)
        n = v_pad.shape[-1]
        vin = v_pad[..., 0].copy()
        if va0 is None:
            va = np.where(vin > VT_SPICE, 0.0, VDD) + 0 * vin
            # settle the DC point (100 steps of the ODE with a frozen input)
            for _ in range(400):
                va = np.clip(va + dt * self.current(vin, va) / self.C_a, 0, VDD)
        else:
            va = va0 + 0 * vin
        out_va = np.empty(v_pad.shape, dtype=np.float32) if return_va else None
        core = np.empty(v_pad.shape, dtype=bool)
        a_in = dt / (self.tau_in + dt)
        for k in range(n):
            vin_new = vin + a_in * (v_pad[..., k] - vin)
            dv = vin_new - vin
            vin = vin_new
            va = np.clip(va + (dt * self.current(vin, va) + self.C_m * dv) / self.C_a, 0, VDD)
            core[..., k] = va < self.v_lv
            if return_va:
                out_va[..., k] = va
        sh = int(round(self.d_lv / dt))
        if sh:
            core = np.concatenate([np.repeat(core[..., :1], sh, axis=-1), core[..., :-sh]], axis=-1)
        return (core, out_va) if return_va else core

def load_wave(path):
    a = np.loadtxt(path)
    # columns: t v(pad) t v(padres_n) t v(core)
    return a[:, 0], a[:, 1], a[:, 3], a[:, 5]

def crossing(t, y, level, rising, t_from=4e-9):
    m = t >= t_from
    t, y = t[m], y[m]
    s = (y[:-1] < level) & (y[1:] >= level) if rising else (y[:-1] > level) & (y[1:] <= level)
    idx = np.nonzero(s)[0]
    if len(idx) == 0:
        return np.nan
    i = idx[0]
    return t[i] + (level - y[i]) / (y[i + 1] - y[i]) * (t[i + 1] - t[i])

def fit():
    from scipy.optimize import minimize
    if not os.path.exists(IV_NPZ):
        pack_iv()
    files = sorted(glob.glob(os.path.join(SPICE_DIR, "step", "w_step_*.txt")))
    waves = [load_wave(f) for f in files]
    dt = waves[0][0][1] - waves[0][0][0]
    n = min(len(w[0]) for w in waves)
    vp = np.stack([w[1][:n] for w in waves])
    va_ref = np.stack([w[2][:n] for w in waves])
    def cost(x):
        C_a, C_m, tau = np.exp(x)
        pad = Pad(C_a=C_a, C_m=C_m, tau_in=tau)
        _, va = pad.run(vp[:, ::2], 2 * dt, return_va=True)
        return float(np.mean((va - va_ref[:, ::2]) ** 2))
    x0 = np.log([15e-15, 1e-15, 12e-12])
    r = minimize(cost, x0, method="Nelder-Mead", options=dict(maxiter=150, xatol=1e-3, fatol=1e-9))
    C_a, C_m, tau = np.exp(r.x)
    with open(FIT_TXT, "w") as f:
        f.write("# padmodel.py fit: C_a, C_m, tau_in fitted to SPICE Va(t) of 10 step responses "
                "(results/pad2-step.txt), tt 25 C\n")
        f.write(f"# rms Va error {np.sqrt(r.fun)*1e3:.1f} mV over {len(files)} waveforms, {r.nit} iterations\n")
        f.write(f"param C_a {C_a:.4e}\nparam C_m {C_m:.4e}\nparam tau_in {tau:.4e}\n")
    print(open(FIT_TXT).read())

def validate():
    """Compare model p2c edges with SPICE on waveforms not used in the fit."""
    pad = Pad()
    lines = ["# padmodel.py validate: model p2c edge times against SPICE (tt 25 C); "
             "none of these waveforms was used in the fit",
             f"# params C_a={pad.C_a:.3e} C_m={pad.C_m:.3e} tau_in={pad.tau_in:.3e}"]
    errs = []
    for group in ("step", "sck", "kick", "aper"):
        for f in sorted(glob.glob(os.path.join(SPICE_DIR, group, "w_*.txt"))):
            t, vp, va, vc = load_wave(f)
            dt = t[1] - t[0]
            core = pad.run(vp[::2], 2 * dt).astype(float)
            tm = t[::2]
            ref_edges = edges(t, vc > VDD / 2)
            mod_edges = edges(tm, core > 0.5)
            name = os.path.basename(f)[2:-4]
            pairs = match(ref_edges, mod_edges)
            e = [m - r for r, m in pairs]
            errs += [x for x in e if group != "step"]
            lines.append(f"{group:5s} {name:14s} spice edges {len(ref_edges):2d} model {len(mod_edges):2d}  "
                         f"errors ps: {' '.join(f'{x*1e12:+.0f}' for x in e[:8])}")
    if errs:
        a = np.abs(np.array(errs))
        lines.append(f"# over the non-step waveforms: {len(a)} matched edges, median |error| "
                     f"{np.median(a)*1e12:.1f} ps, max {a.max()*1e12:.1f} ps")
    txt = "\n".join(lines)
    open(os.path.join(HERE, "results", "padmodel-validate.txt"), "w").write(txt + "\n")
    print(txt)

def edges(t, b):
    d = np.nonzero(b[1:] != b[:-1])[0]
    return [(t[i + 1], bool(b[i + 1])) for i in d if t[i + 1] > 4e-9]

def match(ref, mod):
    pairs, used = [], set()
    for tr, pol in ref:
        best = None
        for j, (tm, pm) in enumerate(mod):
            if pm == pol and j not in used and (best is None or abs(tm - tr) < abs(mod[best][0] - tr)):
                best = j
        if best is not None and abs(mod[best][0] - tr) < 2e-9:
            used.add(best)
            pairs.append((tr, mod[best][0]))
    return pairs

if __name__ == "__main__":
    {"fit": fit, "validate": validate, "pack": pack_iv}[sys.argv[1]]()
