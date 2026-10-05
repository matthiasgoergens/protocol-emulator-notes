# /// script
# requires-python = ">=3.11"
# dependencies = ["numpy"]
# ///
"""FM on the third harmonic, judged on the four-phase stage's actual output.

Input: the stage's pins at quarter-clock resolution, written by fm.exe (pin 0 quarter grid, pin 1
half grid, pin 2 clock grid). The receiver and the SINAD metric are notes/fm-radio-2026-09-24/
fm_sim.py's own, imported unchanged, so the rows are comparable with that note.

fm_sim's metric has a 22 dB ceiling that it documents as an artefact (it drops the first 10 % of
the audio, so its brick-wall filter sees a window that is not a whole number of tone periods). The
4 ms window here holds whole numbers of tone and carrier periods, so a circular version of the same
receiver (circular discriminator, filters over the full window) has no edge effects; it is reported
alongside as "SINAD*" and has a much higher ceiling, which the lane-skew and delay-line experiments
need, because their effects are far below 22 dB.

Beyond the RTL rows, edges are re-rendered with sub-sample timing (box-filtered, so an edge can sit
anywhere, not just on the 64-per-clock simulation grid) to model: static per-lane timing offsets of
the four-phase stage (phase-clock skew and lane-to-pin delay mismatch), and a delay-line
digital-to-time converter (DTC) placing every edge at its exact time quantised to a tap, with tap
mismatch, jitter and calibration error.
"""
import sys, os, importlib.util
import numpy as np

here = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("fm_sim", os.path.join(here, "../../notes/fm-radio-2026-09-24/fm_sim.py"))
fm = importlib.util.module_from_spec(spec); spec.loader.exec_module(fm)

clk, fs, n, t, over = fm.clk, fm.fs, fm.n, fm.t, fm.over
q_per_clk = 4
up = over // q_per_clk                         # simulation samples per quarter


def circ_demod_sinad(x):
    """fm_sim's receiver and metric made circular: exact for a signal periodic over the window."""
    lo = np.exp(-2j * np.pi * fm.fc * t)
    X = np.fft.fft(x * lo)
    f = np.fft.fftfreq(n, 1 / fs)
    X[np.abs(f) > 200e3] = 0
    bb = np.fft.ifft(X)
    dec = int(fs / 2e6)
    bb = bb[::dec]
    fsd = fs / dec
    audio = np.angle(bb * np.conj(np.roll(bb, 1))) * fsd / (2 * np.pi)
    A = np.fft.rfft(audio); fa = np.fft.rfftfreq(len(audio), 1 / fsd); A[fa > 15e3] = 0
    a = np.fft.irfft(A, len(audio))
    k = np.arange(len(a)) / fsd
    M = np.stack([np.sin(2 * np.pi * fm.ftone * k), np.cos(2 * np.pi * fm.ftone * k), np.ones_like(k)], 1)
    coef, *_ = np.linalg.lstsq(M, a, rcond=None)
    fit = M @ coef
    tone = fit - coef[2]
    resid = a - fit
    return 10 * np.log10(np.mean(tone ** 2) / np.mean(resid ** 2)), np.sqrt(np.mean(tone ** 2))


def both(x):
    audio, fsd = fm.demodulate(x)
    s1, r1 = fm.sinad(audio, fsd)
    s2, r2 = circ_demod_sinad(x)
    return s1, r1, s2, r2


def render(times, deltas):
    """Box-filtered rendering: sample k is the average of the wave over [k/fs, (k+1)/fs). times in
    seconds (wrapped into the window: the signal is periodic), deltas +-2. The level before the
    first edge follows from the wave's range: it must reach -1 somewhere."""
    u = np.mod(times, n / fs) * fs
    i = np.floor(u).astype(np.int64); fr = u - i
    d = np.zeros(n + 1)
    np.add.at(d, i, deltas * (1 - fr))
    np.add.at(d, i + 1, deltas * fr)
    d[0] += d[n]
    c = np.cumsum(d[:n])
    return c - 1.0 - c.min()


def edges_of(levels, step):
    """edges of a +-1 sequence sampled every [step] seconds: times, deltas, lane (index mod 4)"""
    ch = np.nonzero(np.diff(np.concatenate([[levels[-1]], levels])))[0]
    return ch * step, (levels[ch] - levels[ch - 1]).astype(float), ch % 4


def main():
    wave = np.fromfile(sys.argv[1], dtype=np.uint8)
    assert len(wave) * up == n, (len(wave), n)
    out = []
    def pr(s=""):
        print(s); out.append(s)
    pr("FM on the third harmonic (99.75 MHz) through the four-phase stage RTL; receiver and metric from fm_sim.py")
    pr("SINAD: fm_sim.py's metric (22 dB ceiling, an artefact it documents); SINAD*: the same receiver made circular")
    pr(f"{'source':46s} {'SINAD':>7s} {'tone rms':>9s} {'SINAD*':>7s} {'tone rms':>9s}")
    def row(name, x):
        s1, r1, s2, r2 = both(x)
        pr(f"{name:46s} {s1:6.1f}dB {r1/1e3:6.1f}kHz {s2:6.1f}dB {r2/1e3:6.1f}kHz")
        return s2
    row("fm_sim ideal edges", fm.square_from_edges(fm.phase, None))
    row("fm_sim clock grid", fm.square_from_edges(fm.phase, clk))
    row("fm_sim clk/2 grid", fm.square_from_edges(fm.phase, clk * 2))
    row("fm_sim clk/4 grid", fm.square_from_edges(fm.phase, clk * 4))
    pins = {}
    for bit, name in [(2, "clock grid"), (1, "both clock edges"), (0, "four-phase stage")]:
        lv = np.where((wave >> bit) & 1, 1.0, -1.0)
        pins[bit] = lv
        row(f"RTL: NCO -> stage pin, {name}", np.repeat(lv, up))
    # agreement of the RTL quarter pin with fm_sim's clk/4 quantisation, best alignment
    ref = fm.square_from_edges(fm.phase, clk * 4)[::up]
    best = min(((int(np.sum(np.roll(pins[0], s) != ref)), s) for s in range(-32, 33)))
    pr(f"RTL quarter pin vs fm_sim clk/4 wave: {best[0]} of {len(ref)} quarters differ at the best shift ({best[1]} quarters)")

    # edge re-rendering: check it reproduces the RTL wave exactly before using it
    q = 1 / (clk * q_per_clk)
    et, ed, lane = edges_of(pins[0], q)
    base = render(et, ed)
    err = np.abs(base - np.repeat(pins[0], up))
    mism = int(np.sum(err > 1e-6))
    pr(f"edge re-rendering of the RTL quarter pin: {len(et)} edges, {mism} samples differ from the RTL wave by more than 1e-6 (max {err.max():.1e})")
    lane_counts = np.bincount(lane, minlength=4)
    pr(f"edges per lane: {', '.join(str(c) for c in lane_counts)}")

    def with_offsets(lane_off=(0, 0, 0, 0), rise=0.0, jitter=0.0, seed=0):
        rng = np.random.default_rng(seed)
        tt = et + np.array(lane_off)[lane] + np.where(ed > 0, rise, 0.0)
        if jitter:
            tt = tt + rng.normal(0, jitter, len(tt))
        return render(tt, ed)

    pr()
    pr("Four-phase stage: static per-lane timing offsets (phase-clock skew plus lane-to-pin delay mismatch)")
    for d in [0, 50e-12, 100e-12, 200e-12, 400e-12, 800e-12]:
        s_alt = row(f"  lanes 1 and 3 late by {d*1e12:4.0f} ps", with_offsets((0, d, 0, d)))
    for d in [100e-12, 200e-12, 400e-12]:
        worst = 99.0
        for seed in range(4):
            offs = np.random.default_rng(100 + seed).uniform(-d, d, 4)
            s1, r1, s2, r2 = both(with_offsets(tuple(offs)))
            worst = min(worst, s2)
        pr(f"  {'random lane offsets within +-%d ps, worst of 4' % round(d*1e12):46s} {'':>7s} {'':>9s} {worst:6.1f}dB")
    row("  rising edges 500 ps later than falling", with_offsets(rise=500e-12))
    for j in [20e-12, 50e-12, 100e-12]:
        row(f"  random edge jitter {j*1e12:.0f} ps rms", with_offsets(jitter=j, seed=1))

    # DTC: every edge at its exact ideal time, quantised to a delay-line tap
    pr()
    pr("Delay-line DTC: exact edge times quantised to the next tap (coarse part from the clock)")
    k = np.arange(int(2 * fm.phase[-1]) + 3)
    # exact crossing times of phase(t) = k/2 by Newton iteration from the carrier-only guess
    tk = (k / 2) / fm.f0
    for _ in range(6):
        ph = fm.f0 * tk + fm.dev0 * np.sin(2 * np.pi * fm.ftone * tk) / (2 * np.pi * fm.ftone)
        fr = fm.f0 + fm.dev0 * np.cos(2 * np.pi * fm.ftone * tk)
        tk = tk - (ph - k / 2) / fr
    tk = tk[(tk >= 0) & (tk < n / fs)]
    kk = np.round(2 * (fm.f0 * tk + fm.dev0 * np.sin(2 * np.pi * fm.ftone * tk) / (2 * np.pi * fm.ftone))).astype(int)
    dd = np.where(kk % 2 == 0, 2.0, -2.0)      # phase crosses an integer: level goes to +1
    def dtc(tap, inl_sigma=0.0, jitter=0.0, scale_err=0.0, seed=0):
        rng = np.random.default_rng(seed)
        period = 1 / clk
        coarse = np.floor(tk / period) * period
        fine = tk - coarse
        ntaps = int(np.ceil(period / tap)) + 1
        idx = np.ceil(fine / tap - 1e-9).astype(int)          # the next tap at or after the ideal time
        # tap i's actual delay: i * tap * (1 + scale error) + a random walk of per-stage mismatch
        walk = np.concatenate([[0.0], np.cumsum(rng.normal(0, inl_sigma, ntaps))]) if inl_sigma else np.zeros(ntaps + 1)
        actual = coarse + idx * tap * (1 + scale_err) + walk[idx]
        if jitter:
            actual = actual + rng.normal(0, jitter, len(actual))
        return render(actual, dd)
    pr(f"  {len(tk)} exact edges; sum of deltas {dd.sum():.0f} (must be 0 for a periodic wave)")
    row("  exact edges, no quantisation", render(tk, dd))
    for tap in [25e-12, 50e-12, 100e-12, 200e-12, 470e-12, 940e-12]:
        row(f"  tap {tap*1e12:4.0f} ps", dtc(tap))
    for tap, inl, jit, sc in [(50e-12, 5e-12, 0, 0), (50e-12, 10e-12, 0, 0), (50e-12, 0, 20e-12, 0),
                              (50e-12, 0, 0, 0.02), (50e-12, 0, 0, 0.10), (50e-12, 5e-12, 10e-12, 0.02)]:
        row(f"  tap 50 ps, INL walk {inl*1e12:.0f} ps/stage, jitter {jit*1e12:.0f} ps, scale error {sc*100:.0f}%",
            dtc(tap, inl, jit, sc, seed=3))
    with open(sys.argv[2], "w") as f:
        f.write("\n".join(out) + "\n")


if __name__ == "__main__":
    main()
