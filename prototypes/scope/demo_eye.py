"""Demonstration (b): the eye of a 125 Mbaud MLT-3 line (100BASE-TX, one leg of the pair), built
by random equivalent-time sampling on a 60 MHz chip.

Pins (architecture v0: the fine-delay option on two pins, TDC half of each; a plain four-phase
output for the kick):
  trigger pin  the same leg through its own probe, fixed threshold between the 0 and +1 levels;
               its TDC timestamps every edge (clock index + bin + Vernier).
  signal pin   the leg through the probe, biased so the line sits below the pad threshold; kicked.
  kick         a four-phase output lane coupled to the signal pin through a small capacitor.
The systolic matcher watches the trigger pin's four-phase samples and fires on the pattern
"-1, 0, +1" (two rising steps; a second, lower-threshold input distinguishes -1 from 0); the
+1 crossing's timestamp is the reference.
Kicks follow on the clocks after the matcher's latency; each one's pin voltage is converted as in
demo_sck.py. Samples are folded modulo two symbols using the symbol period estimated from the
trigger edges. The link's clock is 50 ppm off the chip's and unrelated to it.

Output: results/eye.txt, results/eye.npz, plots/eye.png.
Run: uv run --with numpy --with scipy --with matplotlib python demo_eye.py
"""
import os, time
import numpy as np
from scipy.special import erf
import scopemodel as sm
import acq

HERE = os.path.dirname(os.path.abspath(__file__))
rng = np.random.default_rng(11)
lines = []
def say(s=""):
    print(s, flush=True); lines.append(s)

tb = sm.TimeBase(mode="arch")
inl = tb.calibrate_code_density(2_000_000, rng)
noise = acq.Noise()
kl = acq.KickLinear(rise_ps=500)
T = tb.T
UI = 8e-9 * (1 + 50e-6)             # 125 Mbaud, 50 ppm slow against the chip
N_SYM = 200000                      # symbols simulated (1.6 ms of line)
RISE = 3.5e-9                       # ASSUMPTION: 10-90 % edge, inside 100BASE-TX's 3-5 ns
RJ = 30e-12                         # ASSUMPTION: random jitter per edge on the line, rms
AMP = 0.5                           # one leg: +-0.5 V around its common mode (1 V differential)
CM = 1.2
say(f"# demo_eye.py (seed 11)")
say(f"line: MLT-3, {1/UI/1e6:.4f} Mbaud (50 ppm off the chip), one leg {CM} V +- {AMP} V, 10-90 % rise {RISE*1e9:.1f} ns, "
    f"random jitter {RJ*1e12:.0f} ps rms per edge; {N_SYM} symbols")
say(f"chip: {tb.n_taps} bins per clock, INL after code density {inl*1e12:.1f} ps, Vernier {tb.vernier*1e12:.0f} ps")

# ---------------------------------------------------------------- the line
bits = rng.integers(0, 2, N_SYM)                          # scrambled data: random
seq = [0, 1, 0, -1]
state = np.cumsum(bits) % 4
lvl = np.array(seq)[state] * AMP                          # MLT-3: advance one step on each 1
t_nom = np.arange(N_SYM) * UI + 100e-9
t_sym = t_nom + RJ * rng.standard_normal(N_SYM)            # boundary of symbol i (start)
s_sig = RISE / 2.563
def line_v(t):
    """Leg voltage at times t (any shape): sum of erf steps at the symbol boundaries near t."""
    t = np.asarray(t, dtype=float)
    i = np.clip(np.searchsorted(t_sym, t) - 1, 0, N_SYM - 1)
    v = CM + np.zeros_like(t)
    base = np.zeros_like(t)
    # levels before the window, then steps for boundaries within +-4 symbols
    j0 = np.clip(i - 4, 0, N_SYM - 1)
    v = CM + lvl[np.clip(j0 - 1, 0, N_SYM - 1)]
    for d in range(0, 9):
        j = np.clip(j0 + d, 0, N_SYM - 1)
        prev = lvl[np.clip(j - 1, 0, N_SYM - 1)]
        v = v + (lvl[j] - prev) * 0.5 * (1 + erf((t - t_sym[j]) / (s_sig * np.sqrt(2))))
    return v

# ---------------------------------------------------------------- trigger: pad crossings of CM + AMP/2
thr = CM + AMP / 2
rise_idx = np.nonzero((lvl[1:] == AMP) & (lvl[:-1] == 0))[0] + 1           # 0 -> +1 boundaries
# the matcher's pattern: the two symbols before the rise are <= 0 (it sees the thresholded stream)
pat = rise_idx[(rise_idx >= 3) & (lvl[rise_idx - 2] == -AMP)]      # -1, 0, +1: two rising steps
# crossing time of the threshold by the true waveform near each boundary (Newton on the erf sum)
tc = t_sym[pat].copy()
for _ in range(6):
    h = 1e-12
    f0 = line_v(tc) - thr
    f1 = (line_v(tc + h) - line_v(tc - h)) / (2 * h)
    tc -= f0 / f1
slope = (line_v(tc + 1e-12) - line_v(tc - 1e-12)) / 2e-12
# trigger pad: threshold noise becomes timing noise through the slope; its own delay is constant
# (with k_s = 1 on the trigger probe: its threshold sits at the pad's vt via the DAC)
tc_pad = tc + noise.threshold(rng, len(tc)) / slope + 0.6e-9
trig = tb.timestamp(tc_pad, rng)
say(f"trigger: {len(rise_idx)} rises to +1, {len(pat)} match the pattern -1, 0, +1 ({len(pat)/(N_SYM*UI)/1e6:.2f} M/s); "
    f"slope at the threshold {np.median(slope)/1e9:.2f} V/ns, so {noise.threshold(rng, 1).std() if False else np.sqrt((noise.dvt_dvdd*noise.vdd_noise)**2+noise.thermal**2)*1e3:.1f} mV of threshold noise "
    f"is {np.sqrt((noise.dvt_dvdd*noise.vdd_noise)**2+noise.thermal**2)/np.median(slope)*1e12:.1f} ps")
# the symbol period from the trigger timestamps: edges sit on the symbol grid
k_est = np.concatenate([[0], np.cumsum(np.round(np.diff(trig) / 8e-9))])
UI_est = np.polyfit(k_est, trig, 1)[0]
say(f"symbol period from {len(trig)} trigger timestamps: {UI_est*1e12:.4f} ps (true {UI*1e12:.4f} ps, "
    f"error {(UI_est/UI-1)*1e6:+.2f} ppm)")

# ---------------------------------------------------------------- kicks
K_S = 0.4
U_LO, U_HI = -0.14, 0.07
LAT = 4                          # clocks from the trigger edge to the first kick (matcher + pipeline)
KICKS = 8                        # kicks per trigger, every second clock
d_kout = 2.0e-9
centroid = float(np.sum(kl.w * kl.pos))
tiles = CM + np.array([-0.5, -0.1, 0.3, 0.7])  # four DAC settings cover the leg's 1 V (0.4 V at the pin)
# calibration table as in demo_sck.py (static pin, trim steps)
cal_d = np.linspace(kl.lo + 0.01, kl.hi - 0.01, 25); cal_m = []
for d in cal_d:
    n = rng.integers(10, 20, 64); k = rng.integers(0, tb.n_taps, 64)
    tl = tb.instant(np.zeros_like(n), k, rng) + n * T
    te = kl.shots(lambda t: np.zeros_like(t), tl + d_kout + noise.kick_launch_jitter * rng.standard_normal(64),
                  np.full(64, kl.base + d), rng, noise)
    cal_m.append(np.nanmean(tb.timestamp(te, rng) - tb.estimate(n, k)))
cal_m = np.array(cal_m); o = np.argsort(cal_m); cal_m, cal_d = cal_m[o], cal_d[o]

t0 = time.time()
phase_starts = np.array([np.searchsorted(tb.line[:tb.n_taps], p * T / 4 - 1e-10) for p in range(4)])
samples_t, samples_v, samples_truth = [], [], []
n_trig = len(trig)
for j, L in enumerate(tiles):
    mid = kl.base + 0.5 * (U_LO + U_HI)
    off = mid - K_S * L                                  # pin offset (DAC) for this tile, host-known
    use = np.arange(j, n_trig, len(tiles))               # alternate tiles over triggers (DAC settles between blocks)
    tr = trig[use]
    n0 = np.floor(tr / T).astype(int) + LAT
    n = (n0[:, None] + 2 * np.arange(KICKS)[None, :]).ravel()
    ph = rng.integers(0, 4, len(n))                      # a random lane (quarter) per kick, from the LFSR
    k = phase_starts[ph]
    tl = tb.instant(np.zeros_like(n), k, rng) + n * T    # launch on the chip's grid
    ta = tl + d_kout + noise.kick_launch_jitter * rng.standard_normal(len(tl))
    te = kl.shots(lambda t: K_S * line_v(t), ta, np.full(len(ta), off), rng, noise)
    m = tb.timestamp(te, rng) - tb.estimate(n, k)
    u = np.interp(m, cal_m, cal_d)
    ok = np.isfinite(m) & (m >= cal_m[0]) & (m <= cal_m[-1]) & (u > U_LO) & (u < U_HI)
    v_est = (kl.base + u - off) / K_S
    t_eff = tb.estimate(n, k) + d_kout + centroid - np.repeat(tr, KICKS)   # after the trigger edge
    t_true = ta + centroid - np.repeat(tc, KICKS)[:0] if False else ta + centroid
    samples_t.append(t_eff[ok]); samples_v.append(v_est[ok])
    samples_truth.append(line_v(t_true[ok]))
st = np.concatenate(samples_t); sv = np.concatenate(samples_v); tv = np.concatenate(samples_truth)
say(f"kicks: {len(tiles)} tiles, {KICKS} per trigger from clock {LAT} on, random lane; {len(st)} valid of "
    f"{n_trig*KICKS} ({time.time()-t0:.0f} s of simulation)")

# fold: phase within two symbols, referenced to the trigger edge (the +1 crossing sits at 0)
ph = np.mod(st, 2 * UI_est)
err = sv - tv
say(f"per-sample voltage error against the line at the sampled instant: rms {np.std(err)*1e3:.1f} mV, mean {np.mean(err)*1e3:+.1f} mV")

# truth eye: dense samples of the true line folded the same way (true times relative to true crossings)
tt_ref = rng.choice(tc, 20000) + rng.uniform(LAT * T, (LAT + 2 * KICKS) * T, 20000)
ph_true = np.mod(tt_ref - tc[0] * 0 - np.interp(tt_ref, tc, tc, left=np.nan) * 0, 1)  # placeholder, replaced below
idx = rng.integers(0, len(tc), 60000)
dt = rng.uniform(LAT * T, (LAT + 2 * KICKS) * T, 60000)
tt_ref = tc[idx] + dt
ph_true = np.mod(dt, 2 * UI)
v_true = line_v(tt_ref)

def eye_metrics(phase, v, ui, tag):
    """Upper eye (between 0 and +1): its opening at the best phase, and its width at the mid level."""
    mid_v = CM + AMP / 2
    bins = np.linspace(0, 2 * ui, 81)
    heights = []
    for a, b in zip(bins[:-1], bins[1:]):
        m = (phase >= a) & (phase < b)
        up = v[m & (v > mid_v)]; lo = v[m & (v <= mid_v)]
        if len(up) > 20 and len(lo) > 20:
            heights.append((0.5 * (a + b), np.percentile(up, 0.5) - np.percentile(lo, 99.5)))
    hb = max(heights, key=lambda x: x[1]) if heights else (np.nan, np.nan)
    # width: the phase range where the mid-level band (+-30 mV) is (nearly) empty
    band = np.abs(v - mid_v) < 0.03
    hist, _ = np.histogram(phase[band], bins=bins)
    dens, _ = np.histogram(phase, bins=bins)
    frac = hist / np.maximum(dens, 1)
    open_ = frac < 0.002
    # the longest run of open bins (cyclic)
    run, best = 0, 0
    for x in np.concatenate([open_, open_]):
        run = run + 1 if x else 0; best = max(best, run)
    width = min(best, len(open_)) * (bins[1] - bins[0])
    say(f"{tag}: upper eye height {hb[1]*1e3:.0f} mV at phase {hb[0]*1e9:.2f} ns; width at the mid level {width*1e9:.2f} ns "
        f"(of one symbol, {ui*1e9:.2f} ns)")
    return hb, width
eye_metrics(ph_true, v_true, UI, "truth (the line itself, 60000 samples)")
eye_metrics(ph, sv, UI_est, f"measured ({len(sv)} kicked samples)")

# acquisition time on the chip: triggers arrive at the pattern rate; one trigger's kicks take
# 2*KICKS clocks, during which later triggers are ignored
trig_rate = len(pat) / (N_SYM * UI)
busy = (LAT + 2 * KICKS) * T
eff_rate = trig_rate / (1 + trig_rate * busy)
t_acq = n_trig / eff_rate
say(f"chip time: {n_trig} triggers at {trig_rate/1e6:.2f} M/s pattern rate, busy {busy*1e9:.0f} ns each -> "
    f"{t_acq*1e3:.2f} ms for {n_trig*KICKS} kicks ({n_trig*KICKS/t_acq/1e6:.1f} M kicks/s)")
say(f"to the host: raw 4 bytes per kick (trigger fraction, lane, reading) = {n_trig*KICKS*4/1e6:.2f} MB, i.e. "
    f"{n_trig*KICKS*4/t_acq/1e6:.0f} MB/s against the host link's 7.5 MB/s (architecture v0 2.7); a PE histogram "
    f"(64 phases x 64 levels, 16-bit counts, 8 kB in a gain-cell bank) needs only the final 8 kB")

np.savez_compressed(os.path.join(HERE, "results", "eye.npz"), ph=ph, sv=sv, ph_true=ph_true, v_true=v_true, ui=UI_est)
open(os.path.join(HERE, "results", "eye.txt"), "w").write("\n".join(lines) + "\n")
import matplotlib; matplotlib.use("Agg")
import matplotlib.pyplot as plt
fig, ax = plt.subplots(1, 2, figsize=(11, 4.5), sharey=True)
for a, (p, v, title) in zip(ax, ((ph_true, v_true, "truth: the line at random instants"),
                                 (ph, sv, f"measured: {len(sv)} kicked samples, 60 MHz chip"))):
    a.hist2d(np.concatenate([p, p + 2 * UI]) * 1e9, np.concatenate([v, v]), bins=[160, 120],
             range=[[0, 32], [CM - 0.8, CM + 0.8]], cmap="magma", cmin=1)
    a.set_title(title); a.set_xlabel("ns after the triggering edge (mod 2 symbols), shown twice")
ax[0].set_ylabel("leg voltage (V)")
fig.suptitle("100BASE-TX MLT-3 eye, 125 Mbaud, equivalent-time: matcher trigger + TDC, kicked sampling")
fig.tight_layout(); fig.savefig(os.path.join(HERE, "plots", "eye.png"), dpi=110)
