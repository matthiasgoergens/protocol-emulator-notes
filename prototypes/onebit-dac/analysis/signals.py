"""Test signals and the host's processing.

- music(): a synthetic, music-like 16-bit stereo clip (piano-like notes with inharmonic partials
  and decays, a bass line, kick, snare and hi-hat, panned), generated here so that it is freely
  usable; TPDF-dithered to 16 bits like a CD master.
- host_mode_a(x, fs_word): what the host sends at 44.1 kHz: scale to the order's full scale and
  round with TPDF dither (the words are about 14 bits: the 16-bit PE datapath sets the scale).
- host_mode_b(x): 4x oversampling on the host (a 307-tap Kaiser FIR, 20 kHz passband, 24.1 kHz
  stopband, about 110 dB), then requantisation to the order's scale with third-order error
  feedback (NTF (1 - z^-1)^3) and TPDF dither, at 176.5 kHz.
"""
import numpy as np
from scipy import signal
import dac_common as dc


def tone(f, level_db, dur, fs, phase=0.0):
    t = np.arange(int(dur * fs)) / fs
    return 10 ** (level_db / 20) * np.sin(2 * np.pi * f * t + phase)


def to_cd(x, rng):
    """float in [-1, 1] -> 16-bit with TPDF dither (as a CD master), returned as float LSBs"""
    return np.clip(np.round(x * 32767 + rng.uniform(-0.5, 0.5, x.shape) + rng.uniform(-0.5, 0.5, x.shape)), -32768, 32767)


def music(dur=10.0, fs=dc.FS_A, seed=7):
    rng = np.random.default_rng(seed)
    n = int(dur * fs)
    t = np.arange(n) / fs
    L = np.zeros(n)
    R = np.zeros(n)

    def add(sig, start, pan):
        i0 = int(start * fs)
        m = min(len(sig), n - i0)
        if m <= 0:
            return
        gl, gr = np.cos(pan * np.pi / 2), np.sin(pan * np.pi / 2)
        L[i0 : i0 + m] += gl * sig[:m]
        R[i0 : i0 + m] += gr * sig[:m]

    def piano(f, dur_n, amp):
        tt = np.arange(int(dur_n * fs)) / fs
        s = np.zeros_like(tt)
        for h in range(1, 12):
            fh = f * h * np.sqrt(1 + 0.0004 * h * h)  # inharmonic partials
            if fh > 19000:
                break
            s += (1.0 / h ** 1.3) * np.exp(-tt * (1.5 + 0.8 * h)) * np.sin(2 * np.pi * fh * tt + rng.uniform(0, 6.28))
        s *= np.minimum(1, tt / 0.004)
        return amp * s

    beat = 0.5
    scale = [0, 2, 4, 5, 7, 9, 11, 12]
    chords = [[0, 4, 7], [9, 12, 16], [5, 9, 12], [7, 11, 14]]
    nb = int(dur / beat)
    for b in range(nb):
        root = 261.63 * 2 ** (-12 / 12)
        ch = chords[(b // 4) % 4]
        if b % 2 == 0:
            for k, iv in enumerate(ch):
                add(piano(root * 2 ** (iv / 12), 2.0, 0.08), b * beat + 0.01 * k, 0.35)
        # melody
        note = scale[rng.integers(0, 8)] + 12
        add(piano(root * 2 ** (note / 12), 1.0, 0.12), b * beat + (0.25 if rng.random() < 0.3 else 0), 0.6)
        # bass
        bf = root / 2 * 2 ** (ch[0] / 12)
        tt = np.arange(int(beat * fs)) / fs
        bass = sum((1 / h) * np.sin(2 * np.pi * bf * h * tt) for h in range(1, 6)) * np.exp(-tt * 3) * 0.18
        add(bass, b * beat, 0.5)
        # kick on every beat, snare on 2 and 4, hats on eighths
        tk = np.arange(int(0.3 * fs)) / fs
        kick = np.sin(2 * np.pi * (50 * tk + 60 * (1 - np.exp(-tk * 30)) / 30)) * np.exp(-tk * 12) * 0.35
        add(kick, b * beat, 0.5)
        if b % 2 == 1:
            sn = (rng.standard_normal(len(tk)) * 0.5 + np.sin(2 * np.pi * 190 * tk)) * np.exp(-tk * 18) * 0.15
            add(sn, b * beat, 0.45)
        for e in range(2):
            th = np.arange(int(0.06 * fs)) / fs
            hat = signal.lfilter(*signal.butter(2, 7000, "high", fs=fs), rng.standard_normal(len(th))) * np.exp(-th * 60) * 0.05
            add(hat, b * beat + e * beat / 2, 0.75)
    pk = max(np.max(np.abs(L)), np.max(np.abs(R)))
    L *= 10 ** (-1 / 20) / pk
    R *= 10 ** (-1 / 20) / pk
    return to_cd(L, rng), to_cd(R, rng)


def host_mode_a(x_cd, fs_word, seed=11):
    """CD words (LSB units) -> words at the modulator's scale, rounded with TPDF dither"""
    rng = np.random.default_rng(seed)
    v = x_cd / 32768.0 * fs_word
    return np.round(v + rng.uniform(-0.5, 0.5, v.shape) + rng.uniform(-0.5, 0.5, v.shape))


_FIR = None


def host_fir():
    global _FIR
    if _FIR is None:
        fs = dc.FS_B
        _FIR = signal.firwin(307, (20000 + 24100) / 2, window=("kaiser", 11.0), fs=fs) * 4
    return _FIR


def host_mode_b(x_cd, fs_word, seed=13):
    """CD words -> 4x oversampled words at the modulator's scale, third-order noise-shaped"""
    rng = np.random.default_rng(seed)
    up = np.zeros(4 * len(x_cd))
    up[::4] = x_cd / 32768.0 * fs_word
    v = signal.lfilter(host_fir(), [1.0], up)
    return _ef3(v, rng.uniform(-0.5, 0.5, v.shape) + rng.uniform(-0.5, 0.5, v.shape))


def _ef3(v, d):
    out = np.empty_like(v)
    e1 = e2 = e3 = 0.0
    for i in range(len(v)):
        w = v[i] - (3 * e1 - 3 * e2 + e3)   # y = v + (1 - z^-1)^3 e
        q = np.round(w + d[i])
        e = q - w
        out[i] = q
        e3, e2, e1 = e2, e1, e
    return out


try:
    from numba import njit
    _ef3 = njit(cache=True)(_ef3)
except Exception:
    pass
