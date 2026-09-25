"""Demonstration (a): an SPI SCK rising edge (1 ns 10-90 % rise, 400 mV of 300 MHz ringing
decaying with 3 ns) reconstructed by equivalent-time sampling, with both voltage methods:

K  kicked sampling (acq.KickLinear, from pad_kick.py): the kick pin's DTC places the kick, the
   input pin's TDC (with a Vernier interpolator) times the pad's edge, the V-to-T curve is
   calibrated with the DAC trim on a static pin. Multi-bit per shot.
T  threshold sweep (padmodel.Pad run on the probed waveform): the DAC sets the threshold, the
   input sampler takes one bit at a DTC-placed instant.

The chip launches SCK itself (clock 2 of every shot), so the trigger is the chip's own clock.
Output: results/sck.txt, results/sck.npz, plots/sck.png.
Run: uv run --with numpy --with scipy --with matplotlib python demo_sck.py   (FAST=1: fewer shots)
"""
import os, time
import numpy as np
from scipy.optimize import curve_fit
import scopemodel as sm
import acq
from padmodel import Pad, VT_SPICE

HERE = os.path.dirname(os.path.abspath(__file__))
FAST = os.environ.get("FAST") == "1"
rng = np.random.default_rng(7)
lines = []
def say(s=""):
    print(s, flush=True); lines.append(s)

tb = sm.TimeBase(mode="arch")
inl = tb.calibrate_code_density(2_000_000, rng)
noise = acq.Noise()
probe = sm.Probe(k_s=0.10, k_d=0.19)
dac = sm.Dac()
kl = acq.KickLinear(rise_ps=500)
T = tb.T
say(f"# demo_sck.py (seed 7{', FAST' if FAST else ''})")
say(f"time base (architecture v0 fine delay): 4 phases x {len(tb.seg)} dlygate taps, {tb.n_taps} bins per "
    f"{T*1e9:.2f} ns clock (mean {T/tb.n_taps*1e12:.0f} ps); phase skews {', '.join(f'{x*1e12:+.0f}' for x in tb.skew)} ps; "
    f"INL after code density with 2e6 hits {inl*1e12:.1f} ps; TDC Vernier step {tb.vernier*1e12:.0f} ps")
say(f"probe: target->pin {probe.k_s}, DAC->pin {probe.k_d}, compensation error {probe.comp_err*100:.0f} %, "
    f"residual pole {probe.f_pin/1e9:.1f} GHz; pad threshold {VT_SPICE} V (SPICE, tt)")
say(f"noise: core supply {noise.vdd_noise*1e3:.0f} mV rms (threshold {noise.dvt_dvdd*noise.vdd_noise*1e3:.1f} mV, "
    f"delay line {tb.delay_sens*tb.vdd_noise*100:.2f} % of its delay), pad thermal {noise.thermal*1e3:.1f} mV, clock period "
    f"jitter {tb.period_jitter*1e12:.0f} ps, output pad launch jitter {noise.kick_launch_jitter*1e12:.0f} ps")

# target at a fine grid; the probe's output (what the pin sees, without the DAC's offset)
t_launch = 2 * T
d_sck = 2.0e-9                         # SCK output pad + trace to the target and back (constant)
t_edge = t_launch + d_sck
t_grid = np.arange(t_launch - 1e-9, t_launch + 26e-9, acq.DT)
sut = sm.sck_edge(t_grid, t0=t_edge)
pin_lin = probe.pin(t_grid, sut, 0.0)
filt = pin_lin / probe.k_s
pin_fn = lambda t: np.interp(t, t_grid, pin_lin)

# wanted effective instants: -2 .. +16 ns around the edge, every 50 ps (the host picks the
# nearest reachable bin; several wanted instants may map to the same bin, which is fine)
want = t_edge + np.arange(-2e-9, 16e-9, 50e-12)
d_kout = 2.0e-9                        # kick pin output pad + coupling (constant, calibrated)
centroid = float(np.sum(kl.w * kl.pos))
n_clk, k_bin = tb.nearest(want - d_kout - centroid)
t_eff = tb.estimate(n_clk, k_bin) + d_kout + centroid      # host's time axis
keep = np.unique(t_eff, return_index=True)[1]
n_clk, k_bin, t_eff = n_clk[keep], k_bin[keep], t_eff[keep]
rel = t_eff - t_edge
say(f"instants: {len(rel)} distinct bins over {rel[0]*1e9:.1f}..{rel[-1]*1e9:.1f} ns (mean spacing {np.mean(np.diff(rel))*1e12:.0f} ps)")

def launches(reps):
    """Launch times of the kick (or the sampler clock) on the chip's clock grid, reps per instant:
    the line's supply noise only. The target moves instead: its per-shot shift is SCK's output
    pad jitter plus the clock jitter accumulated from clock 2 to the launch clock."""
    n = np.repeat(n_clk, reps); k = np.repeat(k_bin, reps)
    tl = tb.instant(np.zeros_like(n), k, rng) + n * T
    shift = noise.kick_launch_jitter * rng.standard_normal(len(n)) + \
        tb.period_jitter * np.sqrt(np.maximum(n - 2, 0)) * rng.standard_normal(len(n))
    return tl, n, k, shift

def shifted(shift):
    return lambda t: np.interp(t - shift.reshape((-1,) + (1,) * (np.ndim(t) - 1)), t_grid, pin_lin)

# ---------------------------------------------------------------- K: calibration
cal_deltas = np.linspace(kl.lo + 0.01, kl.hi - 0.01, 25)
cal_shots = 16 if FAST else 64
dm, mm = [], []
for d in cal_deltas:
    n = rng.integers(10, 20, cal_shots); k = rng.integers(0, tb.n_taps, cal_shots)
    tl = tb.instant(np.zeros_like(n), k, rng) + n * T
    ta = tl + d_kout + noise.kick_launch_jitter * rng.standard_normal(cal_shots)
    te = kl.shots(lambda t: np.zeros_like(t), ta, np.full(cal_shots, kl.base + d), rng, noise)
    dm.append(d); mm.append(np.nanmean(tb.timestamp(te, rng) - tb.estimate(n, k)))
dm = np.array(dm); mm = np.array(mm)
order = np.argsort(mm); cal_m, cal_d = mm[order], dm[order]       # V-to-T table, inverted by interpolation
m_lo, m_hi = cal_m[0], cal_m[-1]
# per-shot scatter at the base level, in volts at the pin
kk = rng.integers(0, tb.n_taps, 400)
tl = tb.instant(np.zeros(400, int), kk, rng) + 12 * T
te = kl.shots(lambda t: np.zeros_like(t), tl + d_kout + noise.kick_launch_jitter * rng.standard_normal(400),
              np.full(400, kl.base), rng, noise)
cal_rms = np.nanstd(np.interp(tb.timestamp(te, rng) - tb.estimate(np.full(400, 12), kk), cal_m, cal_d))
say(f"K calibration: {len(cal_deltas)} trim levels x {cal_shots} kicks on a static pin, averaged into a V-to-T table; "
    f"single-kick scatter {cal_rms*1e3:.2f} mV rms at the pin ({cal_rms/probe.k_s*1e3:.0f} mV at the target)")

# ---------------------------------------------------------------- K: acquisition
t0 = time.time()
reps = 4 if FAST else 16
tiles = np.array([0.5, 1.6, 2.7, 3.6])             # target level at each tile's centre (four DAC settings)
U_LO, U_HI = -0.14, 0.07                            # use the kick's steep part only (>2.5 ps/mV, results/kick.txt)
lsb = dac.vio / 256
vals = np.full((len(tiles), len(rel)), np.nan); nval = np.zeros((len(tiles), len(rel)), int)
shots_k = 0
for j, L in enumerate(tiles):
    want_off = kl.base + 0.5 * (U_LO + U_HI) - probe.k_s * L
    code = int(np.clip(round(want_off / probe.k_d / lsb), 0, 255))
    o_true = probe.k_d * dac.volts(code)
    o_host = o_true + probe.k_d * 0.3 * lsb * rng.standard_normal()   # ladder calibrated against the trim pin to 0.3 LSB
    tl, n, k, shift = launches(reps)
    ta = tl + d_kout + noise.kick_launch_jitter * rng.standard_normal(len(tl))
    te = kl.shots(shifted(shift), ta, np.full(len(tl), o_true), rng, noise)
    shots_k += len(tl)
    m = tb.timestamp(te, rng) - tb.estimate(n, k)
    u_est = np.interp(m, cal_m, cal_d)
    ok = np.isfinite(m) & (m >= m_lo) & (m <= m_hi) & (u_est > U_LO) & (u_est < U_HI)
    pin_est = kl.base + u_est
    tgt = np.where(ok, (pin_est - o_host) / probe.k_s, np.nan).reshape(len(rel), reps)
    nval[j] = np.isfinite(tgt).sum(axis=1)
    with np.errstate(invalid="ignore"):
        vals[j] = np.nanmean(tgt, axis=1)
# per instant: the tile whose readings sit nearest the middle of the steep part
mid = kl.base + 0.5 * (U_LO + U_HI)
score = nval * 1.0 - 0.01 * np.abs(np.nan_to_num(vals, nan=1e3) * probe.k_s + np.array(
    [probe.k_d * dac.volts(int(np.clip(round((mid - probe.k_s * L) / probe.k_d / lsb), 0, 255))) for L in tiles])[:, None] - mid) * 1e3
best = np.argmax(score, axis=0)
rec_k = vals[best, np.arange(len(rel))]
rec_k[nval[best, np.arange(len(rel))] < reps // 2] = np.nan
anchor_k = np.nanmean(rec_k[rel < -1.2e-9]); rec_k -= anchor_k
say(f"K acquisition: {len(tiles)} DAC tiles x {len(rel)} instants x {reps} kicks = {shots_k} kicks; "
    f"offset removed by the idle-low anchor {anchor_k*1e3:+.0f} mV; {time.time()-t0:.0f} s of simulation")

# ---------------------------------------------------------------- T: threshold sweep
t0 = time.time()
reps_t = 4 if FAST else 8
lsb_t = lsb * probe.k_d / probe.k_s                # target volts per ladder step
levels = np.arange(-0.4, 3.9, lsb_t)
off_fine = np.arange(VT_SPICE - probe.k_s * 4.1, VT_SPICE + probe.k_s * 0.6, 0.5e-3)
table = acq.comparator_table(Pad(), pin_lin, off_fine)       # pad output for every fine offset
counts = np.zeros((len(levels), len(rel)))
host_levels = np.zeros(len(levels))
t_eff_t = tb.estimate(n_clk, k_bin)                         # the sampler's instant (no kick path)
for li, L in enumerate(levels):
    code = int(np.clip(round((VT_SPICE - probe.k_s * L) / probe.k_d / lsb), 0, 255))
    o_real = probe.k_d * dac.volts(code)
    host_levels[li] = (VT_SPICE - o_real - probe.k_d * 0.3 * lsb * rng.standard_normal()) / probe.k_s
    tl, n, k, shift = launches(reps_t)
    tt = tl + d_kout + centroid - shift                     # same instants as K, in the target's frame
    bits = acq.threshold_shots(table, off_fine, t_grid[0], (o_real - off_fine[0]) / (off_fine[1] - off_fine[0]),
                               tt, noise.threshold(rng, len(tt)))
    counts[li] = bits.reshape(len(rel), reps_t).sum(axis=1)
order = np.argsort(host_levels)
rec_t = acq.crossing_levels(counts[order], reps_t, host_levels[order])
anchor_t = np.nanmean(rec_t[rel < -1.2e-9]); rec_t -= anchor_t
shots_t = len(levels) * len(rel) * reps_t
say(f"T acquisition: {len(levels)} levels ({lsb_t*1e3:.0f} mV steps at the target) x {len(rel)} instants x {reps_t} = "
    f"{shots_t} one-bit samples; {time.time()-t0:.0f} s of simulation")

# ---------------------------------------------------------------- evaluation
truth = np.interp(t_eff, t_grid, sut)
truth_f = np.interp(t_eff, t_grid, filt)
# the probed target seen through the kick's aperture (what K can at best deliver without deconvolution)
truth_a = np.array([np.sum(kl.w * np.interp(t + kl.pos - centroid, t_grid, filt)) for t in t_eff])
def ringfit(r, y):
    f = lambda t, a, fr, tau, ph, c: c + a * np.sin(2 * np.pi * fr * t + ph) * np.exp(-t / tau)
    p, _ = curve_fit(f, r, y, p0=[0.3, 300e6, 3e-9, 0.5, 3.3], maxfev=40000)
    a, ph = p[0], p[3]
    if a < 0: a, ph = -a, ph + np.pi
    return a, p[1], p[2], (ph + np.pi) % (2 * np.pi) - np.pi
def rise(r, y):
    m = np.isfinite(y); r, y = r[m], y[m]
    i1 = np.nonzero(y > 0.33)[0][0]; i2 = np.nonzero(y > 2.97)[0][0]
    return np.interp(2.97, y[i2-1:i2+1], r[i2-1:i2+1]) - np.interp(0.33, y[i1-1:i1+1], r[i1-1:i1+1])
res = {}
ring = rel > 1.5e-9
a0, f0, tau0, ph0 = ringfit(rel[ring], truth[ring])
aa = ringfit(rel[ring], truth_a[ring])
say(f"through probe and aperture: ringing {aa[0]*1e3:.0f} mV, {aa[1]/1e6:.0f} MHz, tau {aa[2]*1e9:.2f} ns")
say(f"truth at these instants: 10-90 % rise {rise(rel, truth)*1e12:.0f} ps (through probe and aperture {rise(rel, truth_a)*1e12:.0f} ps); ringing fit {a0*1e3:.0f} mV, "
    f"{f0/1e6:.0f} MHz, tau {tau0*1e9:.2f} ns")
for name, rec in (("K kicked", rec_k), ("T threshold", rec_t)):
    m = np.isfinite(rec)
    e = rec[m] - truth[m]; ef = rec[m] - truth_f[m]; ea = rec[m] - truth_a[m]
    flat = m & (rel < -0.8e-9)
    ok = m & ring
    try:
        a, fr, tau, ph = ringfit(rel[ok], rec[ok]); rs = f"ringing {a*1e3:.0f} mV, {fr/1e6:.1f} MHz, tau {tau*1e9:.2f} ns"
    except Exception as ex:
        rs = f"ringing fit failed ({type(ex).__name__})"
    try:
        rr = f"10-90 % rise {rise(rel, rec)*1e12:.0f} ps"
    except Exception:
        rr = "rise n/a"
    # time shift of the 50 % crossing against the truth
    try:
        c = lambda y: np.interp(1.65, y[m & (rel > -1e-9) & (rel < 1e-9)], rel[m & (rel > -1e-9) & (rel < 1e-9)])
        sh = f"50 % crossing {(c(rec) - c(truth))*1e12:+.0f} ps from the truth"
    except Exception:
        sh = ""
    # a constant time offset is invisible to the user (no absolute time reference): align, then compare
    shifts = np.arange(-300e-12, 300e-12, 5e-12)
    errs = [np.sqrt(np.mean((rec[m] - np.interp(rel[m] + d, rel, truth_a)) ** 2)) for d in shifts]
    ib = int(np.argmin(errs))
    say(f"{name}: after aligning the time axis by {shifts[ib]*1e12:+.0f} ps, rms error {errs[ib]*1e3:.0f} mV against "
        f"the probed target through the aperture")
    say(f"{name}: {m.sum()}/{len(rec)} instants; rms error {np.sqrt(np.mean(e**2))*1e3:.0f} mV against the target, "
        f"{np.sqrt(np.mean(ef**2))*1e3:.0f} mV against the probed target, {np.sqrt(np.mean(ea**2))*1e3:.0f} mV against "
        f"the probed target through the kick aperture; noise on the flat part "
        f"{np.std(rec[flat])*1e3:.1f} mV rms; {rr}; {sh}; {rs}")
    res[name] = rec

# acquisition time on the chip: one shot per 4 clocks (SCK period 66.7 ns) for K; T uses the
# four lanes' samplers per shot; DAC settling 60 us per setting (ASSUMPTION: 10 kohm ladder into 1 nF)
shot = 4 * T
acq_k = shots_k * shot + len(tiles) * 60e-6 + len(cal_deltas) * cal_shots * shot
acq_t = shots_t / 4 * shot + len(levels) * 60e-6
say(f"chip time: K {acq_k*1e3:.2f} ms including calibration ({shots_k + len(cal_deltas)*cal_shots} kicks); "
    f"T {acq_t*1e3:.2f} ms ({shots_t//4} shots of 4 samples, {len(levels)} DAC settles)")
say(f"to the host: K {shots_k*2/1e3:.0f} kB of 16-bit TDC readings (or {len(rel)*len(tiles)*4/1e3:.1f} kB if a PE sums "
    f"per instant); T {len(levels)*len(rel)/1e3:.0f} kB of counts")

np.savez_compressed(os.path.join(HERE, "results", "sck.npz"), rel=rel, truth=truth, truth_f=truth_f, truth_a=truth_a,
                    rec_k=rec_k, rec_t=rec_t)
open(os.path.join(HERE, "results", "sck.txt"), "w").write("\n".join(lines) + "\n")
import matplotlib; matplotlib.use("Agg")
import matplotlib.pyplot as plt
fig, ax = plt.subplots(2, 1, figsize=(9, 7), sharex=True, gridspec_kw=dict(height_ratios=[3, 1.3]))
ax[0].plot((t_grid - t_edge) * 1e9, sut, color="0.65", lw=2.5, label="target (truth)")
ax[0].plot(rel * 1e9, truth_a, color="k", lw=0.8, ls="--", label="target through probe (5 % compensation error) and kick aperture")
ax[0].plot(rel * 1e9, rec_k, lw=1, color="C0", label="K: kicked sampling, 16 kicks per point")
ax[0].plot(rel * 1e9, rec_t, lw=1, color="C3", label="T: threshold sweep, 8 bits per level and point")
ax[0].set_ylabel("target (V)"); ax[0].legend(loc="lower right", fontsize=8); ax[0].set_xlim(-2, 16)
ax[0].set_title("SPI SCK edge: equivalent-time reconstruction, 60 MHz chip, architecture-v0 fine delay")
ax[1].plot(rel * 1e9, (rec_k - truth_a) * 1e3, lw=0.8, color="C0")
ax[1].plot(rel * 1e9, (rec_t - truth_a) * 1e3, lw=0.8, color="C3")
ax[1].set_ylim(-300, 300); ax[1].set_ylabel("error vs dashed (mV)"); ax[1].set_xlabel("ns from the edge")
fig.tight_layout(); fig.savefig(os.path.join(HERE, "plots", "sck.png"), dpi=110)
