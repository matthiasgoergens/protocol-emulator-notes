"""Demonstration (c): an I2C open-drain line. The chip (master) releases SDA at a known clock; the
pull-up (4.7 kohm) charges the bus (200 pF) along an RC curve; 3 us later a target pulls it low
through its driver. Reconstructed with the threshold sweep (acq.py T), which suits slow edges:
the pad decides quasi-statically once its overdrive grows, and the residual decision delay is
measured here on the fitted pad model (ramps at the edge's slope) and is a few ns.

Also: the questions a user asks of such an edge, answered from the reconstruction: rise time
(30-70 %, the I2C definition) against the fast-mode limit of 300 ns, tau and the bus capacitance
it implies for a known pull-up, and V_OL against the 0.4 V limit.

Output: results/i2c.txt, results/i2c.npz, plots/i2c.png.
Run: uv run --with numpy --with scipy --with matplotlib python demo_i2c.py
"""
import os
import numpy as np
from scipy.optimize import curve_fit
import scopemodel as sm
import acq
from padmodel import Pad, VT_SPICE

HERE = os.path.dirname(os.path.abspath(__file__))
rng = np.random.default_rng(5)
lines = []
def say(s=""):
    print(s, flush=True); lines.append(s)

R, C, VDD, VOL = 4.7e3, 200e-12, 3.3, 0.15
T_REL, T_FALL, FALL = 50e-9, 3.05e-6, 10e-9
tb = sm.TimeBase(mode="arch")
tb.calibrate_code_density(2_000_000, rng)
T = tb.T
noise = acq.Noise()
probe = sm.Probe(k_s=0.15, k_d=0.19, comp_err=0.0)     # a DC-accurate divider: the slow edge needs no compensation
dac = sm.Dac()
say("# demo_i2c.py (seed 5)")
say(f"bus: pull-up {R/1e3:.1f} kohm, {C*1e12:.0f} pF (tau {R*C*1e9:.0f} ns), V_OL {VOL} V, released at "
    f"{T_REL*1e9:.0f} ns, pulled low at {T_FALL*1e6:.2f} us with a {FALL*1e9:.0f} ns driver fall")

# decision delay of the pad on a slow ramp through its threshold (fitted pad model, 10 ps steps)
pad = Pad()
walk = {}
for slope in (0.1e6, 1e6, 10e6, 100e6):            # V/s at the pin
    t = np.arange(0, 400e-9, 10e-12)
    v = VT_SPICE + slope * (t - 200e-9)
    core = pad.run(v[None, :], 10e-12)[0]
    walk[slope] = t[np.argmax(core)] - 200e-9
say("pad decision delay on a ramp through the threshold (fitted model): " +
    ", ".join(f"{s/1e6:g} mV/ns: {d*1e9:.2f} ns" for s, d in walk.items()))
slopes = np.array(sorted(walk)); delays = np.array([walk[s] for s in slopes])

t_grid = np.arange(0, 3.4e-6, 1e-9)
sut = sm.i2c_release(t_grid, t0=T_REL, vdd=VDD, r_pull=R, c_bus=C, v_low=VOL, fall=FALL, t_fall=T_FALL)
pin_lin = probe.k_s * sut
dvdt = np.abs(np.gradient(pin_lin, t_grid))

# instants: every clock over 3.4 us, plus 130 ps steps (fine delay) around the fall
coarse = np.arange(0, 3.4e-6, T)
fine = np.arange(T_FALL - 30e-9, T_FALL + 60e-9, T / tb.n_taps)
want = np.unique(np.concatenate([coarse, fine]))
n_clk, k_bin = tb.nearest(want)
t_host = tb.estimate(n_clk, k_bin)
t_host, keep = np.unique(t_host, return_index=True)
n_clk, k_bin = n_clk[keep], k_bin[keep]
REPS = 8
lsb = dac.vio / 256
levels_code = np.arange(0, 256)
counts = np.zeros((len(levels_code), len(t_host)))
host_level = np.zeros(len(levels_code))
for i, code in enumerate(levels_code):
    o = probe.k_d * dac.volts(code)
    host_level[i] = (VT_SPICE - o - probe.k_d * 0.3 * lsb * rng.standard_normal()) / probe.k_s
    n = np.repeat(n_clk, REPS); k = np.repeat(k_bin, REPS)
    ts = tb.instant(np.zeros_like(n), k, rng) + n * T + tb.period_jitter * np.sqrt(n) * rng.standard_normal(len(n))
    p = np.interp(ts, t_grid, pin_lin)
    d = np.interp(np.interp(ts, t_grid, dvdt), slopes, delays)          # decision delay at this slope
    p_seen = np.interp(ts - d, t_grid, pin_lin)
    bits = (p_seen + o - noise.threshold(rng, len(ts))) > VT_SPICE
    counts[i] = bits.reshape(len(t_host), REPS).sum(axis=1)
order = np.argsort(host_level)
rec = acq.crossing_levels(counts[order], REPS, host_level[order])
m = np.isfinite(rec)
# walk correction: the pad decides late by a delay that depends on the slope at the pin; the host
# estimates the slope from this first reconstruction and moves each instant back by the delay
t_raw = t_host.copy()
o = np.argsort(t_host)
slope_est = np.zeros_like(rec)
slope_est[o[m[o]]] = np.abs(np.gradient(rec[o][m[o]], t_host[o][m[o]])) * probe.k_s
slope_est = np.maximum(slope_est, slopes[0])
t_host = t_host - np.interp(np.log(slope_est), np.log(slopes), delays)
truth = np.interp(t_host, t_grid, sut)
truth_raw = np.interp(t_raw, t_grid, sut)
err = rec - truth
say(f"acquisition: {len(t_host)} instants x 256 ladder levels x {REPS} = {len(t_host)*256*REPS} one-bit samples; "
    f"{lsb/probe.k_s*probe.k_d*1e3:.1f} mV at the target per ladder step")
say(f"walk correction moved instants by {np.median(t_raw - t_host)*1e9:.1f} ns (median), up to "
    f"{np.max(t_raw - t_host)*1e9:.1f} ns; rms error without it {np.sqrt(np.nanmean((rec - truth_raw)**2))*1e3:.1f} mV")
rr = m & (t_host > 60e-9) & (t_host < 2.9e-6)
say(f"reconstruction: {m.sum()}/{len(rec)} instants; rms error on the RC rise {np.sqrt(np.nanmean(err[rr]**2))*1e3:.1f} mV; on the flat "
    f"high part {np.sqrt(np.nanmean(err[(t_host > 2.0e-6) & (t_host < 3.0e-6)]**2))*1e3:.1f} mV; on the low part "
    f"{np.sqrt(np.nanmean(err[t_host < 40e-9]**2))*1e3:.1f} mV")

# the questions
def rc(t, v0, vinf, tau, t0):
    return np.where(t < t0, v0, vinf - (vinf - v0) * np.exp(-(t - t0) / tau))
sel = m & (t_host < 2.9e-6)
p, cov = curve_fit(rc, t_host[sel], rec[sel], p0=[0.2, 3.2, 1e-6, 40e-9])
tau = p[2]
def rise3070(tt, vv):
    lo, hi = 0.3 * VDD, 0.7 * VDD
    s = tt < 2.9e-6
    return np.interp(hi, vv[s], tt[s]) - np.interp(lo, vv[s], tt[s])
r_true = R * C * np.log(0.7 / 0.3) * 1.0
say(f"answers: V_OL {np.nanmean(rec[t_host < 40e-9])*1e3:.0f} mV (true {VOL*1e3:.0f}, limit 400); "
    f"RC fit tau {tau*1e9:.1f} ns +- {np.sqrt(cov[2,2])*1e9:.1f} (true {R*C*1e9:.1f}) -> bus capacitance "
    f"{tau/R*1e12:.1f} pF for the known 4.7 kohm; 30-70 % rise {rise3070(t_host[m], rec[m])*1e9:.0f} ns "
    f"(true {rise3070(t_grid, sut)*1e9:.0f} ns; fast-mode limit 300 ns: FAIL, standard-mode 1000 ns: pass)")
fz = m & (t_host > T_FALL - 30e-9) & (t_host < T_FALL + 60e-9)
def fall_time(tt, vv):
    s = np.argsort(tt); tt, vv = tt[s], vv[s]
    hi, lo = 0.7 * VDD, 0.3 * VDD
    i1 = np.nonzero(vv < hi)[0][0]; i2 = np.nonzero(vv < lo)[0][0]
    return np.interp(lo, vv[i2:i2-2:-1], tt[i2:i2-2:-1]) - np.interp(hi, vv[i1:i1-2:-1], tt[i1:i1-2:-1])
tg = (t_grid > T_FALL - 30e-9) & (t_grid < T_FALL + 60e-9)
say(f"fall (70-30 %) {fall_time(t_host[fz], rec[fz])*1e9:.1f} ns after walk correction, "
    f"{fall_time(t_raw[fz], rec[fz])*1e9:.1f} ns before (true {fall_time(t_grid[tg], sut[tg])*1e9:.1f} ns) from "
    f"130 ps steps around it")
t_chip = len(t_host) * 256 * REPS / 4 * 4 * T / 1  # one release per 4 clocks is impossible here: see below
t_period = 3.5e-6                                   # one release-and-fall per 3.5 us, 4 samplers per repetition
shots = 256 * REPS * np.ceil(len(t_host) / 4)
say(f"chip time: the bus repeats every {t_period*1e6:.1f} us; every repetition gives one sample to each of 4 lanes, "
    f"so {shots:.0f} repetitions = {shots*t_period:.1f} s. With the sampler's timed mode (one sample per clock for the "
    f"whole repetition, pin-sampler) it is 256 x {REPS} repetitions + the fine window: {256*REPS*t_period*1e3:.1f} ms "
    f"+ {256*REPS*len(fine)/4*t_period:.2f} s")
np.savez_compressed(os.path.join(HERE, "results", "i2c.npz"), t=t_host, rec=rec, truth=truth)
open(os.path.join(HERE, "results", "i2c.txt"), "w").write("\n".join(lines) + "\n")
import matplotlib; matplotlib.use("Agg")
import matplotlib.pyplot as plt
fig, ax = plt.subplots(1, 2, figsize=(11, 4), gridspec_kw=dict(width_ratios=[2.2, 1]))
ax[0].plot(t_grid * 1e6, sut, color="0.65", lw=2.5, label="bus (truth)")
ax[0].plot(t_host[m] * 1e6, rec[m], ".", ms=2, color="C3", label="threshold sweep, 256 levels x 8")
ax[0].axhline(0.3 * VDD, color="k", lw=0.5, ls=":"); ax[0].axhline(0.7 * VDD, color="k", lw=0.5, ls=":")
ax[0].set_xlabel("us"); ax[0].set_ylabel("V"); ax[0].legend(); ax[0].set_title("I2C SDA: release (RC) and pull-down")
ax[1].plot((t_grid[tg] - T_FALL) * 1e9, sut[tg], color="0.65", lw=2.5)
ax[1].plot((t_host[fz] - T_FALL) * 1e9, rec[fz], ".", ms=3, color="C3")
ax[1].set_xlabel("ns from the pull-down"); ax[1].set_title("the fall, 130 ps steps")
fig.tight_layout(); fig.savefig(os.path.join(HERE, "plots", "i2c.png"), dpi=110)
