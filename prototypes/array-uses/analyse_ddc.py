"""Independent check and rendering for the four-channel AM receiver (ddc.ml).

For each channel's demodulated output (50 kS/s, ddc-chN.txt) fit it against each station's
programme audio, as the stations transmit it, with the best delay (the host's filters delay the
audio by a fraction of a millisecond): gain, correlation and signal-to-residual. A channel
should carry exactly its own station. Channel 3 is tuned to an empty frequency whose third
multiple carries a station: its gain relative to a directly received station, corrected for the
carrier amplitudes, measures the square-wave LO's third-harmonic leak (theory: 1/3, -9.5 dB).
Writes a WAV per channel and a spectrogram.

Usage: uv run --with numpy --with matplotlib analyse_ddc.py out results/ddc_check.txt
"""
import sys
import wave
from pathlib import Path

import numpy as np

FS = 50_000
T0 = 240 / 60e6          # the first decimated frame
STATIONS = [("5.950 MHz, melody", 17.0), ("6.000 MHz, two tones", 17.0),
            ("6.055 MHz, chirp", 13.0), ("18.450 MHz, beeps", 24.0)]


def programme(k, t):
    if k == 0:
        notes = np.array([523.25, 659.25, 783.99, 1046.5])
        return np.sin(2 * np.pi * notes[(t / 0.25).astype(int) % 4] * t)
    if k == 1:
        return np.where((t / 0.3).astype(int) % 2 == 0, np.sin(2 * np.pi * 700 * t), np.sin(2 * np.pi * 1100 * t))
    if k == 2:
        return np.sin(2 * np.pi * (300 + 1500 * np.mod(t, 1.0)) * t)
    return np.where(np.mod(t, 0.2) < 0.1, np.sin(2 * np.pi * 400 * t), 0.0)


def fit(y, t, k):
    best = None
    skip = int(0.1 * FS)                       # let the filters and the DC tracker settle
    for lag in range(0, 60):
        a = programme(k, t - lag / FS)[skip:]
        yy = y[skip:]
        g = float(a @ yy / (a @ a))
        res = yy - g * a
        c = float(np.corrcoef(a, yy)[0, 1])
        snr = 10 * np.log10(np.sum((g * a) ** 2) / np.sum(res ** 2))
        if best is None or abs(c) > abs(best[1]):
            best = (g, c, snr, lag)
    return best


def main():
    d = Path(sys.argv[1]); out = Path(sys.argv[2])
    lines = []
    ys = []
    for ch in range(4):
        y = np.loadtxt(d / f"ddc-ch{ch}.txt")
        t = T0 + np.arange(len(y)) * 5 * 240 / 60e6
        ys.append(y)
        fits = [fit(y, t, k) for k in range(4)]
        lines.append(f"channel {ch}: " + "; ".join(
            f"{STATIONS[k][0]}: corr {f[1]:+.3f}, gain {f[0]:.0f}, S/R {f[2]:+.1f} dB, lag {f[3]}"
            for k, f in enumerate(fits)))
        with wave.open(str(d / f"ddc-ch{ch}.wav"), "wb") as w:
            w.setnchannels(1); w.setsampwidth(2); w.setframerate(FS)
            s = y / (np.max(np.abs(y[int(0.1 * FS):])) + 1e-9) * 20000
            w.writeframes(np.clip(s, -32767, 32767).astype("<i2").tobytes())
    # third-harmonic leak: ch3's gain on the beeps against ch0-2's gains on their own stations,
    # each divided by its carrier amplitude
    direct = [fit(ys[k], T0 + np.arange(len(ys[k])) * 5 * 240 / 60e6, k)[0] / STATIONS[k][1] for k in range(3)]
    img = fit(ys[3], T0 + np.arange(len(ys[3])) * 5 * 240 / 60e6, 3)[0] / STATIONS[3][1]
    ratio = img / np.mean(direct)
    lines.append(f"direct reception, gain per carrier count: " + " ".join(f"{x:.1f}" for x in direct))
    lines.append(f"image through the LO's third harmonic: {img:.1f} per count = {ratio:.3f} of direct "
                 f"({20*np.log10(abs(ratio)):.1f} dB; a square wave's third harmonic is 1/3, -9.5 dB)")
    if len(sys.argv) > 3 and sys.argv[3] == "--expect-fault":
        own = [fit(ys[k], T0 + np.arange(len(ys[k])) * 5 * 240 / 60e6, k)[1] for k in range(4)]
        ok = all(np.isfinite(c) and abs(c) < 0.1 for c in own)
        lines.append(f"fault control: own-station correlations {' '.join(f'{c:+.3f}' for c in own)}; "
                     + ("PASS (all below 0.1)" if ok else "FAIL"))
    else:
        own = [fit(ys[k], T0 + np.arange(len(ys[k])) * 5 * 240 / 60e6, k)[1] for k in range(4)]
        ok = all(c > 0.95 for c in own)
        lines.append(f"own-station correlations {' '.join(f'{c:+.3f}' for c in own)}: " + ("PASS (all above 0.95)" if ok else "FAIL"))
    out.write_text("\n".join(lines) + "\n")
    print("\n".join(lines))
    plot(ys, d)
    sys.exit(0 if ok else 1)


def plot(ys, d):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    names = ["channel 0 at 5.950 MHz: melody", "channel 1 at 6.000 MHz: two tones",
             "channel 2 at 6.055 MHz: chirp", "channel 3 at 6.150 MHz (empty): the 18.450 MHz station leaks in"]
    fig, axes = plt.subplots(4, 1, figsize=(9, 9), dpi=120, sharex=True)
    for ax, y, n in zip(axes, ys, names):
        ax.specgram(y, NFFT=2048, Fs=FS, noverlap=1536, cmap="magma", vmin=-20)
        ax.set_ylim(0, 3000); ax.set_ylabel("Hz"); ax.set_title(n, fontsize=10)
    axes[-1].set_xlabel("time (s)")
    fig.suptitle("Four AM channels from one 16-PE upe_v0 chain and an 8-bit ADC at 60 MS/s", fontsize=11)
    fig.tight_layout(); fig.savefig(d / "ddc-spectrogram.png"); plt.close(fig)


if __name__ == "__main__":
    main()
