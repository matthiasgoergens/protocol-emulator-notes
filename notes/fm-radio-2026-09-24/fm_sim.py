# /// script
# requires-python = ">=3.11"
# dependencies = ["numpy"]
# ///
"""Can the chip bit-bang FM broadcast? A square wave at f0 has a third harmonic at 3 f0, so a
33.25 MHz pin gives 99.75 MHz. Question: how well does FM survive when the pin's edges are
quantised in time? Three cases, each demodulated by a software FM receiver tuned to 99.75 MHz:
  ideal    edges exactly where an ideal FM square wave puts them
  grid     edges on the 66.5 MHz clock grid (an NCO driving a pin: what the chip can do today)
  subclk   edges on a grid of clock / 32 (a tapped delay line, 0.47 ns)
Audio: a 1 kHz tone, broadcast deviation 75 kHz at the carrier, so 25 kHz at the fundamental.
Figure of merit: the tone's power against everything else in 0-15 kHz after demodulation (SINAD)."""
import numpy as np

clk = 66.5e6
f0 = clk / 2                 # fundamental; third harmonic 99.75 MHz
fc = 3 * f0
dev0 = 75e3 / 3              # deviation at the fundamental
ftone = 1e3
over = 64                    # simulation samples per chip clock
fs = clk * over
T = 4e-3
n = int(T * fs)
t = np.arange(n) / fs

# instantaneous phase of the fundamental, in cycles
phase = f0 * t + (dev0 / ftone) * np.sin(2 * np.pi * ftone * t) / (2 * np.pi) * 0 + 0.0
# integrate frequency properly: f(t) = f0 + dev0 cos(2 pi ftone t)
phase = f0 * t + dev0 * np.sin(2 * np.pi * ftone * t) / (2 * np.pi * ftone)

def square_from_edges(phase, grid):
    """Square wave whose transitions happen at the first grid point at or after the ideal time."""
    if grid is None:
        return np.where((phase % 1.0) < 0.5, 1.0, -1.0)
    # sample the ideal wave only at grid points, then hold: an edge moves to the next grid point
    step = int(round(fs / grid))
    held = np.where((phase[::step] % 1.0) < 0.5, 1.0, -1.0)
    return np.repeat(held, step)[: len(phase)]

def demodulate(x):
    # mix down to baseband around fc, low-pass to 200 kHz, decimate, FM discriminator
    lo = np.exp(-2j * np.pi * fc * t)
    bb = x * lo
    X = np.fft.fft(bb)
    f = np.fft.fftfreq(len(bb), 1 / fs)
    X[np.abs(f) > 200e3] = 0
    bb = np.fft.ifft(X)
    dec = int(fs / 2e6)
    bb = bb[::dec]
    fsd = fs / dec
    audio = np.angle(bb[1:] * np.conj(bb[:-1])) * fsd / (2 * np.pi)
    return audio, fsd

def sinad(audio, fsd):
    """Least-squares fit of the 1 kHz tone (sine, cosine, offset); SINAD = tone power / residual
    power after a 15 kHz low-pass. No window, so no leakage counted as noise (the first version
    used an FFT window and reported 13 dB even for the ideal signal)."""
    a = audio[len(audio) // 10:]
    A = np.fft.rfft(a); f = np.fft.rfftfreq(len(a), 1 / fsd); A[f > 15e3] = 0; a = np.fft.irfft(A, len(a))
    k = np.arange(len(a)) / fsd
    M = np.stack([np.sin(2 * np.pi * ftone * k), np.cos(2 * np.pi * ftone * k), np.ones_like(k)], 1)
    coef, *_ = np.linalg.lstsq(M, a, rcond=None)
    fit = M @ coef
    tone = fit - coef[2]
    resid = a - fit
    return 10 * np.log10(np.mean(tone ** 2) / np.mean(resid ** 2)), np.sqrt(np.mean(tone ** 2))

if __name__ == "__main__":   # guard added so prototypes/multiphase/fm_eval.py can reuse the functions
  for name, grid in [("ideal", None), ("grid", clk)] + [(f"clk/{k}", clk * k) for k in (2, 4, 8, 16, 32)]:
    x = square_from_edges(phase, grid)
    # carrier level at 99.75 MHz relative to the fundamental, before demodulation
    audio, fsd = demodulate(x)
    s, rms = sinad(audio, fsd)
    print(f"{name:7s} SINAD {s:6.1f} dB, fitted tone deviation rms {rms/1e3:6.1f} kHz (ideal tone: {75/np.sqrt(2):.1f} kHz)")
