"""Shared pieces of the one-bit DAC analysis: rates, the OCaml renderer, the analogue model of
the pin and the reconstruction filter, and the audio-band metrics.

Rates: chip clock 60 MHz; modulator step 10 clocks (6 MHz); one 44.1 kHz host sample is 1360
clocks = 136 steps (fs = 44,117.6 Hz); with 4x host oversampling (mode B) one host sample is 340
clocks = 34 steps (176,470.6 Hz).
"""
import os
import subprocess
import numpy as np
from numba import njit
from scipy import signal

HERE = os.path.dirname(os.path.abspath(__file__))
SIM = os.path.join(HERE, "..", "sim", "_build", "default", "main.exe")
SCRATCH = os.environ.get("ONEBIT_SCRATCH", "/var/tmp/onebit-dac")

F_CLK = 60_000_000
STEP_CLOCKS = 10
FM = F_CLK / STEP_CLOCKS               # 6 MHz modulator rate
FS_A = F_CLK / 1360                    # 44,117.6 Hz
FS_B = F_CLK / 340                     # 176,470.6 Hz
STEPS_A = 136
STEPS_B = 34

A1 = {"o2": 15689, "o3": 11094, "o4": 6597}


def write_words(path, l, r):
    """host words, int16 LE, stereo interleaved"""
    x = np.empty(2 * len(l), dtype="<i2")
    x[0::2] = np.clip(np.round(l), -32768, 32767)
    x[1::2] = np.clip(np.round(r), -32768, 32767)
    x.tofile(path)


def render(order, words_path, prefix, steps, shift0=0):
    out = subprocess.run(["nice", "ionice", SIM, "render", order, words_path, prefix, str(steps), str(shift0)],
                         check=True, capture_output=True, text=True)
    return out.stdout.strip()


def read_bits(path, n=None):
    b = np.unpackbits(np.fromfile(path, dtype=np.uint8))
    return b if n is None else b[:n]


# ---------------- analogue model ----------------
# The pin output per modulator step is represented by its area (volt-seconds) over the step;
# for audio-band results only the area matters, and every impairment below is an area error.
#  - level: the pin is high (V_hi) or low (0). The stored bit F is 1 for y = -1, so the pin
#    drives NOT F (the pin stage's invert, or the host negates the words).
#  - supply: V_hi = V0 + n_s, n_s low-pass noise (one pole at 100 kHz) given by its rms in
#    20 Hz-20 kHz (the IO rail of the audio pins).
#  - rise/fall asymmetry: a rising edge loses V*tr_eff of area, a falling edge gains V*tf_eff;
#    with tr_eff = t0 - delta/2 and tf_eff = t0 + delta/2 the t0 parts cancel per pulse and
#    every edge adds V*delta/2: an error proportional to the number of transitions.
#  - jitter: an edge displaced by dt changes the area by -/+ V*dt (rising/falling), dt ~ N(0, sj).
#  - aggressor bounce: k_pads pads on the same rail switching with random data at the audio
#    pin's edges move each edge by kd * (bounce voltage), the bounce being bmax * (number
#    switching - k/2)/(k/2) (zero mean); kd in s per volt.


@njit(cache=True)
def _edge_dt(sj, kpads, bmax, kd):
    dt = 0.0
    if sj > 0:
        dt += sj * np.random.standard_normal()
    if kpads > 0:
        ns = 0
        for _ in range(kpads):
            if np.random.random() < 0.5:
                ns += 1
        dt += kd * bmax * (ns - kpads / 2) / (kpads / 2)
    return dt


@njit(cache=True)
def _areas(bits, T, V0, delta, sj, sv_step, kpads, bmax, kd, seed, mode):
    """mode 0: NRZ on one pin; 1: NRZ differential (pin and its complement, same clock edge,
    output = difference / 2); 2: RZ on one pin (a 1 is high for the first half step)."""
    np.random.seed(seed)
    n = bits.shape[0]
    a = np.empty(n, dtype=np.float64)
    prev = 1 - bits[0]
    # supply noise: white noise through one pole at 100 kHz (regulator noise and hum are
    # low-frequency; sv_step is the rms of this process)
    al = np.exp(-2 * np.pi * 100e3 * T)
    ns = 0.0
    for i in range(n):
        b = 1 - bits[i]
        if sv_step > 0:
            ns = al * ns + np.sqrt(1 - al * al) * sv_step * np.random.standard_normal()
        vhi = V0 + ns
        if mode == 2:
            area = 0.0
            if b == 1:
                dt1 = _edge_dt(sj, kpads, bmax, kd)
                dt2 = _edge_dt(sj, kpads, bmax, kd)
                # every edge adds V*delta/2 (rise/fall asymmetry); a late rise loses, a late fall gains
                area = vhi * T / 2 + V0 * (delta + dt2 - dt1)
            a[i] = area
            prev = b
            continue
        d = b - prev
        dt = _edge_dt(sj, kpads, bmax, kd) if d != 0 else 0.0
        e = 0.0
        if d != 0:
            e = V0 * (0.5 * delta - d * dt)
        if mode == 0:
            a[i] = T * vhi * b + e
        else:
            # complement pin: same supply sample, opposite edge, same asymmetry contribution
            ec = 0.0
            if d != 0:
                ec = V0 * (0.5 * delta + d * dt)
            a[i] = 0.5 * ((T * vhi * b + e) - (T * vhi * (1 - b) + ec)) + 0.5 * T * V0
        prev = b
    return a


class Impair:
    def __init__(self, V0=3.3, delta=0.0, sj=0.0, sv_inband=0.0, kpads=0, bmax=0.0, kd=0.0, seed=1, mode=0):
        self.V0, self.delta, self.sj, self.sv_inband, self.mode = V0, delta, sj, sv_inband, mode
        self.kpads, self.bmax, self.kd, self.seed = kpads, bmax, kd, seed

    def label(self):
        p = [["", "differential", "RZ"][self.mode]] if self.mode else []
        if self.delta: p.append(f"asym {self.delta*1e12:.0f} ps")
        if self.sj: p.append(f"jitter {self.sj*1e12:.0f} ps rms")
        if self.sv_inband: p.append(f"supply {self.sv_inband*1e6:.0f} uV in-band")
        if self.kpads: p.append(f"{self.kpads} pads x {self.bmax:.2f} V bounce, {self.kd*1e12/1e3:.1f} ps/mV")
        return ", ".join(p) if p else "ideal"

    def areas(self, bits):
        T = 1.0 / FM
        # one-pole noise at 100 kHz: the fraction of its power below 20 kHz is (2/pi) atan(0.2)
        sv_step = self.sv_inband / np.sqrt(2 / np.pi * np.arctan(20e3 / 100e3))
        return _areas(bits.astype(np.int8), T, self.V0, self.delta, self.sj, sv_step, self.kpads,
                      self.bmax, self.kd, self.seed, self.mode)


# Reconstruction filter: pin -> R1 1 kohm -> C1 2.2 nF (72 kHz pole), buffered, then a
# unity-gain Sallen-Key Butterworth at 40 kHz (R 10 kohm, 10 kohm; C 560 pF feedback,
# 270 pF to ground). Ideal op-amp, the RC unloaded (see README for the loading).
R1, C1 = 1e3, 2.2e-9
RS, CA, CB = 10e3, 560e-12, 270e-12


def filter_sos():
    w1 = 1 / (R1 * C1)
    w0 = 1 / (RS * np.sqrt(CA * CB))
    q = np.sqrt(CA * CB) / (2 * CB)
    num = [w1 * w0 ** 2]
    den = np.polymul([1, w1], [1, w0 / q, w0 ** 2])
    b, a = signal.bilinear(num, den, fs=FM)
    return signal.tf2sos(b, a)


def analogue(bits, imp, dec=64):
    """pin areas -> filter (output in volts, as the pin's average) -> decimated by dec"""
    sos = filter_sos()
    x = imp.areas(bits) * FM          # volts, step average
    y = signal.sosfilt(sos, x)
    # decimate to FM/dec with an FIR well below the new Nyquist
    yd = signal.resample_poly(y, 1, dec, window=("kaiser", 14.0))
    return y, yd, FM / dec


# ---------------- metrics ----------------
def a_weight(f):
    f2 = f ** 2
    ra = (12194 ** 2 * f2 ** 2) / ((f2 + 20.6 ** 2) * np.sqrt((f2 + 107.7 ** 2) * (f2 + 737.9 ** 2)) * (f2 + 12194 ** 2))
    return ra / ((12194 ** 2 * 1000 ** 4) / ((1000 ** 2 + 20.6 ** 2) * np.sqrt((1000 ** 2 + 107.7 ** 2) * (1000 ** 2 + 737.9 ** 2)) * (1000 ** 2 + 12194 ** 2)))


def spectrum(x, fs):
    x = x - np.mean(x)
    w = signal.windows.kaiser(len(x), 38)
    X = np.fft.rfft(x * w)
    # Parseval: summed over the bins of a component, p gives its mean square (A^2/2 for a sine)
    p = 2 * np.abs(X) ** 2 / (len(x) * np.sum(w ** 2))
    f = np.fft.rfftfreq(len(x), 1 / fs)
    return f, p, None


def tone_metrics(x, fs, f0, nb=40, weight=False):
    """returns (signal rms^2, THD+N rms^2 in 20 Hz-20 kHz, list of harmonic levels in dB re signal)"""
    f, p, _ = spectrum(x, fs)
    df = f[1] - f[0]
    k0 = int(round(f0 / df))
    sig = p[k0 - nb : k0 + nb + 1].sum()
    band = (f >= 20) & (f <= 20000)
    mask = band.copy()
    mask[k0 - nb : k0 + nb + 1] = False
    pw = p * (a_weight(np.maximum(f, 1)) ** 2 if weight else 1.0)
    noise = pw[mask].sum()
    harms = []
    for h in range(2, 6):
        kh = int(round(h * f0 / df))
        if h * f0 <= 20000:
            harms.append(10 * np.log10(p[kh - nb : kh + nb + 1].sum() / sig))
    return sig, noise, harms


def band_noise(x, fs, weight=False):
    f, p, _ = spectrum(x, fs)
    band = (f >= 20) & (f <= 20000)
    pw = p * (a_weight(np.maximum(f, 1)) ** 2 if weight else 1.0)
    return pw[band].sum()


def write_wav(path, l, r, fs):
    from scipy.io import wavfile
    x = np.stack([l, r], axis=1)
    x = x - x.mean(axis=0)
    peak = np.max(np.abs(x))
    # 16-bit with TPDF dither, normalised to -1 dBFS peak (for listening; the numbers in
    # results/ come from the floating-point signal, not from these files)
    rng = np.random.default_rng(0)
    v = x / max(peak, 1e-9) * 0.89 * 32767
    v = v + rng.uniform(-0.5, 0.5, v.shape) + rng.uniform(-0.5, 0.5, v.shape)
    wavfile.write(path, int(round(fs)), np.clip(np.round(v), -32768, 32767).astype(np.int16))
