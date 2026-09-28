# /// script
# requires-python = ">=3.11"
# dependencies = ["numpy", "scipy", "pillow", "numba"]
# ///
"""Demo B front end: a first-order delta-sigma ADC made of one input pin, one output pin and an RC
network (the FPGA trick), for composite video and for audio.

Circuit (all values at the node N, which has capacitor C to ground):
    video (0..1 V, from a 75-ohm termination) --Rin--> N
    output pin (0 or VDDIO, through its own ~50 ohm) --Rf--> N
    VDDIO --Rb--> N                  (bias: centres the video range on the pin threshold)
    input pin samples N against its threshold Vth = VDDIO/2 + offset + noise (per sample)
    next output = NOT(sample): negative feedback, one clock of loop delay
The node obeys C dV/dt = sum of currents; between clock edges the output and (to first order)
the input are constant, so the update per sample is exact: V <- Vinf + (V - Vinf) exp(-T/tau).

Measured here (results/dsadc.txt, results/dsadc.json):
  1. sine SNR against bandwidth at 60 MS/s (one sample per clock) and 240 MS/s (four-phase input
     and output stage), for a few capacitor values, with pin threshold noise;
  2. a PAL test card through the ADC: the software TV's picture (out/dsadc_*.png) and the error
     of the per-cell luma averages the chip would compute (boxcar counts of ones);
  3. sync separation from the bit stream: a 0.53 us boxcar sliced into a sync bit, pulse widths
     classified the way a sequencer thread would (wait for a level with a deadline);
  4. audio: a 1 kHz tone, SNR in 15 kHz.
"""
import json, math, pathlib, sys, time
import numpy as np
import scipy.signal as sg
from numba import njit

HERE = pathlib.Path(__file__).parent
RES = HERE / "results"
OUT = HERE / "out"
sys.path.insert(0, str(HERE.parent / "composite-video"))

VDD = 3.3
RIN, RF, RB = 1000.0, 2640.0, 1430.0      # maps 0..1 V onto duty 0.9..0.1 (see solve_duty)
RPIN = 50.0                               # output driver resistance, in series with RF


@njit(cache=True)
def _loop(vin, T, C, rin, rf, rb, vdd, vth, noise, seed, delay):
    np.random.seed(seed)
    n = len(vin)
    bits = np.empty(n, np.uint8)
    g = 1.0 / rin + 1.0 / rf + 1.0 / rb
    tau = C / g
    a = math.exp(-T / tau)
    v = vth
    for i in range(n):
        # the output during sample i is the complement of the sample taken `delay` samples earlier
        out = 1 - bits[i - delay] if i >= delay else (i & 1)
        vo = vdd if out else 0.0
        vinf = (vin[i] / rin + vo / rf + vdd / rb) / g
        v = vinf + (v - vinf) * a
        bits[i] = 1 if v > vth + noise * np.random.standard_normal() else 0
    return bits


def adc(vin, fs, C=470e-12, vth_off=0.0, noise=1e-3, seed=0, delay=1):
    """Returns the pin samples: 1 = node above threshold = input high (so ones ~ video level).
    delay: loop delay in samples from a sample to the output level it sets (1 = next sample)."""
    bits = _loop(np.ascontiguousarray(vin, dtype=np.float64), 1.0 / fs, C, RIN, RF + RPIN, RB, VDD,
                 VDD / 2 + vth_off, noise, seed, delay)
    return bits


def solve_duty(v):
    """Steady-state fraction of samples reading 1 for input v (for scaling the output)."""
    a, b = RIN / (RF + RPIN), RIN / RB
    vth = VDD / 2
    # (v - vth) + a (VDD * (1 - d) - vth) + b (VDD - vth) = 0, d = fraction of ones (output = NOT)
    return 1 - (vth * a + vth - v - b * (VDD - vth)) / (VDD * a)


def recon(bits, fs, bw):
    """Brick-wall low-pass in the frequency domain, scaled back to volts via the duty mapping."""
    d = bits.astype(float)
    D = np.fft.rfft(d)
    f = np.fft.rfftfreq(len(d), 1 / fs)
    D[f > bw] = 0
    d = np.fft.irfft(D, len(d))
    d0, d1 = solve_duty(0.0), solve_duty(1.0)
    return (d - d0) / (d1 - d0)


def sine_snr(fs, C, noise, f0=200e3, amp=0.4, bws=(0.5e6, 1e6, 2e6, 4.2e6, 5e6), T=2e-3, seed=0, delay=1):
    n = int(T * fs)
    t = np.arange(n) / fs
    f0 = round(f0 * T) / T                       # whole number of periods in the window
    vin = 0.5 + amp * np.sin(2 * np.pi * f0 * t)
    bits = adc(vin, fs, C=C, noise=noise, seed=seed, delay=delay)
    out = {}
    for bw in bws:
        r = recon(bits, fs, bw)[n // 10: -n // 10]
        tt = t[n // 10: -n // 10]
        M = np.stack([np.sin(2 * np.pi * f0 * tt), np.cos(2 * np.pi * f0 * tt), np.ones_like(tt)], 1)
        coef, *_ = np.linalg.lstsq(M, r, rcond=None)
        res = r - M @ coef
        sig = np.hypot(coef[0], coef[1]) ** 2 / 2
        out[f"{bw/1e6:g}MHz"] = round(10 * math.log10(sig / np.mean(res ** 2)), 1)
    out["gain"] = round(float(np.hypot(coef[0], coef[1]) / amp), 4)
    return out


def main():
    RES.mkdir(exist_ok=True)
    OUT.mkdir(exist_ok=True)
    res = {"circuit": dict(VDD=VDD, Rin=RIN, Rf=RF, Rpin=RPIN, Rb=RB,
                           duty_at_0V=round(solve_duty(0.0), 3), duty_at_1V=round(solve_duty(1.0), 3))}
    lines = ["Demo B: one-pin delta-sigma ADC (dsadc.py). Circuit: Rin %.0f, Rf %.0f + %.0f pin, Rb %.0f to %.1f V;"
             % (RIN, RF, RPIN, RB, VDD),
             "duty 0 V -> %.3f, 1 V -> %.3f. Sine 0.5 +- 0.4 V at 200 kHz, SNR in dB against bandwidth."
             % (solve_duty(0.0), solve_duty(1.0)), ""]
    # 1. sine SNR
    tab = []
    for fs in (60e6, 240e6):
        for C in (100e-12, 470e-12, 2.2e-9):
            for noise in (0.0, 1e-3, 5e-3):
                o = sine_snr(fs, C, noise)
                tab.append(dict(fs=fs, C=C, noise=noise, **o))
                lines.append(f"fs {fs/1e6:5.0f} MS/s  C {C*1e12:6.0f} pF  threshold noise {noise*1e3:3.0f} mV rms  "
                             + "  ".join(f"{k}: {v}" for k, v in o.items()))
                print(lines[-1], flush=True)
    res["sine"] = tab
    # 1b. loop delay: the input path's synchroniser and the four-phase stage's retiming put
    # clocks, not samples, between a sample and the output it drives
    lines.append("")
    lines.append("Loop delay (samples from a pin sample to the output level it sets), C 470 pF, 1 mV noise:")
    tabd = []
    for fs, delays in ((60e6, (1, 2, 3)), (240e6, (1, 4, 8, 12))):
        for dl in delays:
            o = sine_snr(fs, 470e-12, 1e-3, delay=dl)
            tabd.append(dict(fs=fs, delay=dl, **o))
            lines.append(f"fs {fs/1e6:5.0f} MS/s  delay {dl:2d} samples ({dl * 1e9 / fs:5.1f} ns)  "
                         + "  ".join(f"{k}: {v}" for k, v in o.items()))
            print(lines[-1], flush=True)
    res["sine_delay"] = tabd
    # 2. PAL test card through the ADC
    import tv
    lines.append("")
    pics = {}
    for fs, dl in ((60e6, 1), (60e6, 2), (240e6, 4), (240e6, 8)):
        tv.FS = fs
        s = tv.STD["PAL"]
        src = tv.test_picture()
        comp = tv.encode(src, s)                       # 0 = sync tip ... 1 = white, in volts
        ideal = tv.decode(tv.lowpass(comp, s["recon"], 401), s)
        t0 = time.time()
        bits = adc(comp, fs, C=470e-12, noise=1e-3, delay=dl)
        rec = recon(bits, fs, 5e6)
        dec = tv.decode(rec, s)
        tv.save(dec, OUT / f"dsadc_PAL_{int(fs/1e6)}MSps_d{dl}.png", 480)
        p = tv.psnr(dec, ideal)
        # per-cell luma as the chip computes it: count of ones over a cell (boxcar), per line,
        # for a 32 x 24 grid of the active picture, compared with the same average of the composite
        n_act = int(round(s["active_len"] * fs))
        lt = int(round(s["line"] * fs))
        errs = []
        for li in range(s["first_active"], s["first_active"] + s["n_active"]):
            a0 = int(round(li * s["line"] * fs + s["active_start"] * fs))
            seg_b = bits[a0:a0 + n_act].astype(float)
            seg_c = comp[a0:a0 + n_act]
            w = n_act // 32
            cb = seg_b[:w * 32].reshape(32, w).mean(axis=1)
            cc = seg_c[:w * 32].reshape(32, w).mean(axis=1)
            d0, d1 = solve_duty(0.0), solve_duty(1.0)
            errs.append((cb - d0) / (d1 - d0) - cc)
        errs = np.array(errs)                          # line-level cell errors, volts
        # cells of 12 lines x (active / 32): the 32 x 24 grid
        g = errs[: 24 * 12].reshape(24, 12, 32).mean(axis=1)
        # 3. sync separation from the bit stream
        nbox = int(round(0.53e-6 * fs))                 # a 0.53 us boxcar (32 samples at 60 MS/s)
        box = np.convolve(bits.astype(float), np.ones(nbox) / nbox, mode="same")
        low = box < 0.5 * (solve_duty(0.0) + solve_duty(s["blank"]))   # near the sync tip level
        edges = np.flatnonzero(low[1:] & ~low[:-1]) + 1
        rises = np.flatnonzero(~low[1:] & low[:-1]) + 1
        widths = []
        for e in edges:
            r = rises[rises > e]
            if len(r):
                widths.append((r[0] - e) / fs * 1e6)
        widths = np.array(widths)
        hs = widths[(widths > 3.5) & (widths < 6.0)]
        broad = widths[widths > 20]
        starts = edges[[i for i, wdt in enumerate(widths) if 3.5 < wdt < 6.0]]
        per = np.diff(starts) / fs * 1e6
        per = per[(per > 60) & (per < 68)]
        o = dict(fs=fs, delay=dl, picture_psnr_vs_ideal_db=round(p, 1), seconds=round(time.time() - t0, 1),
                 cell_err_line_rms_mV=round(float(errs.std() * 1e3), 2),
                 cell_err_grid_rms_mV=round(float(g.std() * 1e3), 2),
                 cell_err_grid_max_mV=round(float(np.abs(g).max() * 1e3), 2),
                 hsync_found=int(len(hs)), hsync_width_us_mean=round(float(hs.mean()), 3) if len(hs) else None,
                 hsync_width_us_sd=round(float(hs.std()), 3) if len(hs) else None,
                 line_period_us_sd=round(float(per.std()), 4) if len(per) else None,
                 broad_pulses=int(len(broad)), other_pulses=int(len(widths) - len(hs) - len(broad)))
        pics[f"{int(fs/1e6)}_d{dl}"] = o
        lines.append(f"PAL test card at {fs/1e6:.0f} MS/s, loop delay {dl}: " + ", ".join(f"{k} {v}" for k, v in o.items() if k not in ("fs", "delay")))
        print(lines[-1], flush=True)
    res["pal"] = pics
    # 4. audio: 1 kHz tone
    lines.append("")
    fs = 60e6
    T = 20e-3
    n = int(T * fs)
    t = np.arange(n) / fs
    vin = 0.5 + 0.4 * np.sin(2 * np.pi * 1000 * t)
    bits = adc(vin, fs, C=2.2e-9, noise=1e-3)
    # decimate as the chip would: CIC-like boxcar to 48 kHz (1250 samples), then measure in 15 kHz
    d = bits[: n // 1250 * 1250].reshape(-1, 1250).mean(axis=1)
    fa = fs / 1250
    tt = np.arange(len(d)) / fa
    A = np.fft.rfft(d); f = np.fft.rfftfreq(len(d), 1 / fa); A[f > 15e3] = 0; d = np.fft.irfft(A, len(d))
    M = np.stack([np.sin(2 * np.pi * 1000 * tt), np.cos(2 * np.pi * 1000 * tt), np.ones_like(tt)], 1)
    coef, *_ = np.linalg.lstsq(M, d, rcond=None)
    r = d - M @ coef
    snr = 10 * math.log10(np.hypot(coef[0], coef[1]) ** 2 / 2 / np.mean(r ** 2))
    res["audio"] = dict(fs=fs, C=2.2e-9, snr_15k_db=round(snr, 1))
    lines.append(f"Audio: 1 kHz, 0.4 V peak, 60 MS/s, C 2.2 nF, boxcar decimation to 48 kS/s: SNR in 15 kHz {snr:.1f} dB")
    print(lines[-1])
    (RES / "dsadc.json").write_text(json.dumps(res, indent=1))
    (RES / "dsadc.txt").write_text("\n".join(lines) + "\n")


if __name__ == "__main__":
    main()
