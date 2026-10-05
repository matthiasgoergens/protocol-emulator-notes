"""Acquisition engines: how the chip turns pad decisions into (time, voltage) samples.

Two ways to get voltage out of a digital input pad (see README "Two ways to read a voltage"):

T  threshold sweep. The DAC shifts the pin so the pad's threshold sits at a chosen target level;
   the sampling flip-flop records the pad's output at a programmed instant. One bit per shot; the
   level where the probability of a 1 crosses 1/2 is the waveform's value. Limited by the pad's
   small-overdrive speed (spice/pad.py: 150 mV of sine is needed at 100 MHz).
K  kicked sampling. The pin idles below threshold; at the sampling instant an output pin kicks it
   up through a small capacitor. The pad's delay from the kick to its output edge falls with the
   pin voltage at that moment (spice: about 4 ps per mV) and the TDC measures it. Many bits per
   shot, and an aperture of a few hundred ps set by the kick's rise and the pad's decision.

Both use padmodel.Pad (fitted to SPICE) for the pad, scopemodel.TimeBase for instants and the TDC.
"""
import numpy as np
from padmodel import Pad, VT_SPICE

DT = 2e-12

class Noise:
    """Per-shot noise sources (all ASSUMPTIONS except where marked)."""
    def __init__(self, vdd_noise=5e-3, thermal=0.7e-3, dvt_dvdd=0.43, kick_launch_jitter=10e-12,
                 iovdd_noise=5e-3):
        self.vdd_noise = vdd_noise            # core supply, rms, quasi-static during a shot
        self.thermal = thermal                # pad input-referred, rms to 1 GHz (results/pad-noise.txt)
        self.dvt_dvdd = dvt_dvdd              # threshold vs core supply (results/pad-dc.txt)
        self.kick_launch_jitter = kick_launch_jitter   # output pad delay jitter, rms
        self.iovdd_noise = iovdd_noise        # I/O supply, rms: scales the kick amplitude
    def threshold(self, rng, n):
        return np.sqrt((self.dvt_dvdd * self.vdd_noise) ** 2 + self.thermal ** 2) * rng.standard_normal(n)

# ----------------------------------------------------------------------------------------------
# T: threshold sweep

def comparator_table(pad, pin0, offsets):
    """Pad output for the pin waveform pin0 (no offset, on the DT grid) plus each offset."""
    v = pin0[None, :] + offsets[:, None]
    return pad.run(v, DT)

def threshold_shots(table, offsets, t0, level_idx, t_true, thr_noise):
    """One bit per shot: pad output at the true instant, with the offset perturbed by the
    threshold noise (a threshold shift of +n is an offset shift of -n)."""
    do = offsets[1] - offsets[0]
    j = np.clip(np.round(level_idx - thr_noise / do).astype(int), 0, len(offsets) - 1)
    i = np.clip(np.round((t_true - t0) / DT).astype(int), 0, table.shape[1] - 1)
    return table[j, i]

def crossing_levels(counts, n, levels):
    """For each time column: the level where the fraction of 1s crosses 1/2 (linear
    interpolation between the two levels around it). counts: (n_levels, n_times), ones counted
    as 'pin above threshold'. Levels ascending in target volts, so the fraction falls with level."""
    p = counts / n
    out = np.full(p.shape[1], np.nan)
    for c in range(p.shape[1]):
        col = p[:, c]
        idx = np.nonzero((col[:-1] >= 0.5) & (col[1:] < 0.5))[0]
        if len(idx) == 0:
            continue
        k = idx[-1]
        a, b = col[k], col[k + 1]
        out[c] = levels[k] + (a - 0.5) / (a - b) * (levels[k + 1] - levels[k])
    return out

# ----------------------------------------------------------------------------------------------
# K: kicked sampling

class Kick:
    def __init__(self, amp=0.5, rise=500e-12, base_below_vt=0.25):
        self.amp = amp                  # volts at the pin (C_k / (C_k + C_pin) x 3.3 V)
        self.rise = rise                # ASSUMPTION: 0.5 ns, the 16 mA output pad into ~1 pF (liberty)
        self.base_below_vt = base_below_vt
    def shape(self, t):
        return np.clip(t / self.rise, 0.0, 1.0)

def kicked_shots(pad, pin_fn, t_kick, offsets, kick, rng, noise, pre=3e-9, post=2.5e-9, batch=3000):
    """Simulate shots: pin(t) = pin_fn(t) + offset + kick(t - t_kick) with per-shot noise.
    Returns the pad's rising-edge time after the kick (nan if none: the pad was already high,
    or never flipped). pin_fn takes an array of absolute times."""
    n = len(t_kick)
    out = np.full(n, np.nan)
    rel = np.arange(-pre, post, DT)
    for s in range(0, n, batch):
        tk = t_kick[s:s + batch]
        m = len(tk)
        t = tk[:, None] + rel[None, :]
        thr = noise.threshold(rng, m)
        amp = kick.amp * (1 + noise.iovdd_noise / 3.3 * rng.standard_normal(m))
        v = pin_fn(t) + offsets[s:s + batch][:, None] - thr[:, None] + amp[:, None] * kick.shape(rel[None, :])
        core = pad.run(v, DT)
        k0 = int(round(pre / DT))
        before = core[:, k0 - 1]
        after = core[:, k0:]
        first = np.argmax(after, axis=1)
        ok = (~before) & after.any(axis=1)
        out[s:s + batch] = np.where(ok, tk + first * DT, np.nan)
    return out

class KickLinear:
    """Fast kicked-sampling model from pad_kick.py (results/kick.npz): the delay from the kick to
    the pad's output edge is D(u), u the aperture-weighted pin deviation from the kick base."""
    def __init__(self, rise_ps=500, base_below_vt=0.25):
        z = np.load(__import__("os").path.join(__import__("os").path.dirname(__file__), "results", "kick.npz"))
        self.deltas = z[f"r{rise_ps}_deltas"]; self.delay = z[f"r{rise_ps}_delay"]
        self.pos = z[f"r{rise_ps}_pos"]; self.w = z[f"r{rise_ps}_w"]
        ok = np.isfinite(self.delay)
        self.deltas, self.delay = self.deltas[ok], self.delay[ok]
        self.base = VT_SPICE - base_below_vt
        self.lo, self.hi = self.deltas[0], self.deltas[-1]
    def shots(self, pin_fn, t_kick, offsets, rng, noise):
        """Pad output edge times (nan where the pin was out of the kick's range)."""
        t = t_kick[:, None] + self.pos[None, :]
        u = (pin_fn(t) * self.w[None, :]).sum(axis=1) + offsets - self.base - noise.threshold(rng, len(t_kick))
        u -= noise.iovdd_noise / 3.3 * 0.5 * rng.standard_normal(len(t_kick))   # kick amplitude
        d = np.interp(u, self.deltas, self.delay, left=np.nan, right=np.nan)
        return t_kick + d

def tdc_read(tb, t_edge, rng, clock_origin=0.0):
    """Thermometer TDC on the same kind of line: the edge's clock index plus the calibrated
    position of the tap bin it lands in (bin centre), with supply noise scaling the line."""
    rel = t_edge - clock_origin
    n = np.floor(rel / tb.T)
    frac = rel - n * tb.T
    eps = tb.delay_sens * tb.vdd_noise * rng.standard_normal(np.shape(frac))
    frac_line = frac / (1 + eps)                    # the line runs slow or fast during this shot
    k = np.clip(np.searchsorted(tb.line, frac_line, side="right") - 1, 0, tb.n_taps - 1)
    centre = 0.5 * (tb.est[k] + tb.est[k + 1])
    return clock_origin + n * tb.T + centre

def start_stop(tb, interval, rng):
    """Start-stop TDC: the kick's launch edge (on chip, at the output pad's input) starts a
    delay line, the pad's output edge samples its thermometer. Reads the calibrated centre of the
    tap bin reached; the line runs fast or slow with the core supply during the shot."""
    eps = tb.delay_sens * tb.vdd_noise * rng.standard_normal(np.shape(interval))
    x = np.asarray(interval) / (1 + eps)
    k = np.clip(np.searchsorted(tb.line, x, side="right") - 1, 0, len(tb.line) - 2)
    return np.where(np.isfinite(interval), 0.5 * (tb.est[k] + tb.est[k + 1]), np.nan)

def launch_to_arrival(t_launch, d_kout, noise, rng):
    return t_launch + d_kout + noise.kick_launch_jitter * rng.standard_normal(np.shape(t_launch))

def calibrate_kick(pad, kick, tb, noise, rng, deltas, shots_per=32, d_kout=2.0e-9):
    """V-to-T curve with a static input: the DAC trim steps the pin by known amounts (deltas,
    relative to vt - base_below_vt); fit delta as a polynomial in the start-stop reading.
    Returns the fit, the per-shot residual (rms, volts at the pin) and the calibrated range of
    readings (outside it a reading is rejected, never extrapolated)."""
    base = VT_SPICE - kick.base_below_vt
    d_all, m_all = [], []
    for d in deltas:
        n = shots_per
        t_launch = rng.uniform(10e-9, 40e-9, n)
        t_arr = launch_to_arrival(t_launch, d_kout, noise, rng)
        te = kicked_shots(pad, lambda t: np.zeros_like(t), t_arr, np.full(n, base + d), kick, rng, noise)
        d_all.append(np.full(n, d)); m_all.append(start_stop(tb, te - t_launch, rng))
    d_all = np.concatenate(d_all); m_all = np.concatenate(m_all)
    ok = np.isfinite(m_all)
    coef = np.polyfit(m_all[ok] * 1e9, d_all[ok], 4)
    resid = d_all[ok] - np.polyval(coef, m_all[ok] * 1e9)
    rng_ok = (np.min(m_all[ok]), np.max(m_all[ok]))
    return coef, float(np.std(resid)), rng_ok, (d_all, m_all)

def kick_to_delta(coef, delay):
    return np.polyval(coef, delay * 1e9)
