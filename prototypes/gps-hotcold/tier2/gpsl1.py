"""GPS L1 C/A from the ICD (IS-GPS-200): Gold codes, navigation-message words with parity, the
user orbit algorithm, and a synthetic 1-bit IF generator modelled on a MAX2769-class front end.

Front end model (see README for which parameters are the part's and which are assumed):
  - reference and sample clock 16.368 MHz, IF 4.092 MHz (fs/4), one-bit sign output
  - IF filter: 6-pole Butterworth band-pass, 2.5 MHz wide, centred on the IF (assumed)
  - thermal noise white at the filter input; C/N0 is defined there
  - local-oscillator error: a common carrier offset for all satellites (the TCXO's ppm error)
  - the chip's pin sampler keeps every 5th sample: 3.2736 MS/s, where the IF aliases to
    4.092 - 3.2736 = 0.8184 MHz, i.e. fs/4 again (not inverted), 3.2 samples per chip

Signal physics: every satellite's contribution is built from its transmit time
t_tx(t) = t - tau(t), with tau from the orbit (light time, Earth rotation), so code phase, data
bits, carrier phase and Doppler are mutually consistent without approximation beyond a linear
interpolation of tau inside each millisecond.
"""
import math
import numpy as np
from scipy import signal as sps

C = 299_792_458.0
F_L1 = 1575.42e6
F_CHIP = 1.023e6
FS_FE = 16.368e6
F_IF = 4.092e6
DECIM = 5
FS = FS_FE / DECIM                 # 3.2736 MS/s at the chip
OMEGA_E = 7.2921151467e-5
MU = 3.986005e14

# G2 phase-selector taps, IS-GPS-200 Table 3-Ia, PRN 1..32
G2_TAPS = [(2, 6), (3, 7), (4, 8), (5, 9), (1, 9), (2, 10), (1, 8), (2, 9), (3, 10), (2, 3), (3, 4),
           (5, 6), (6, 7), (7, 8), (8, 9), (9, 10), (1, 4), (2, 5), (3, 6), (4, 7), (5, 8), (6, 9),
           (1, 3), (4, 6), (5, 7), (6, 8), (7, 9), (8, 10), (1, 6), (2, 7), (3, 8), (4, 9)]
# first 10 chips in octal, same table (independent check of the generator)
FIRST10_OCTAL = [0o1440, 0o1620, 0o1710, 0o1744, 0o1133, 0o1455, 0o1131, 0o1454, 0o1626, 0o1504,
                 0o1642, 0o1750, 0o1764, 0o1772, 0o1775, 0o1776, 0o1156, 0o1467, 0o1633, 0o1715,
                 0o1746, 0o1763, 0o1063, 0o1706, 0o1743, 0o1761, 0o1770, 0o1774, 0o1127, 0o1453,
                 0o1625, 0o1712]


def ca_code(prn):
    """1023 chips as 0/1 (1 = logic one, transmitted as -1 in the +-1 convention used below)"""
    g1 = [1] * 10
    g2 = [1] * 10
    t1, t2 = G2_TAPS[prn - 1]
    out = []
    for _ in range(1023):
        out.append(g1[9] ^ g2[t1 - 1] ^ g2[t2 - 1])
        f1 = g1[2] ^ g1[9]
        f2 = g2[1] ^ g2[2] ^ g2[5] ^ g2[7] ^ g2[8] ^ g2[9]
        g1 = [f1] + g1[:9]
        g2 = [f2] + g2[:9]
    return np.array(out, np.int8)


def pm(bits):
    """0/1 -> +1/-1"""
    return 1 - 2 * np.asarray(bits, np.int64)


# ---------------------------------------------------------------- navigation message

def parity(d24, d29s, d30s):
    """IS-GPS-200 Table 20-XIV. d24: 24 source bits (list of 0/1). Returns the 30 transmitted bits."""
    d = [None] + list(d24)
    D = [b ^ d30s for b in d24]
    def x(*idx):
        v = 0
        for i in idx:
            v ^= d[i]
        return v
    p25 = d29s ^ x(1, 2, 3, 5, 6, 10, 11, 12, 13, 14, 17, 18, 20, 23)
    p26 = d30s ^ x(2, 3, 4, 6, 7, 11, 12, 13, 14, 15, 18, 19, 21, 24)
    p27 = d29s ^ x(1, 3, 4, 5, 7, 8, 12, 13, 14, 15, 16, 19, 20, 22)
    p28 = d30s ^ x(2, 4, 5, 6, 8, 9, 13, 14, 15, 16, 17, 20, 21, 23)
    p29 = d30s ^ x(1, 3, 5, 6, 7, 9, 10, 14, 15, 16, 17, 18, 21, 22, 24)
    p30 = d29s ^ x(3, 5, 6, 8, 9, 10, 11, 13, 15, 19, 22, 23, 24)
    return D + [p25, p26, p27, p28, p29, p30]


def check_word(w30, d29s, d30s):
    """-> (ok, 24 data bits) for 30 received bits given the previous word's D29, D30"""
    d24 = [b ^ d30s for b in w30[:24]]
    return parity(d24, d29s, d30s) == list(w30), d24


PREAMBLE = [1, 0, 0, 0, 1, 0, 1, 1]


def subframe(tow_start, sf_id, rng):
    """300 bits of a subframe starting at GPS time-of-week tow_start (a multiple of 6 s).
    Words 3..10 carry random data (the receiver here is assisted with ephemeris; see README)."""
    bits = []
    d29s = d30s = 0
    for w in range(10):
        if w == 0:
            d = PREAMBLE + [int(b) for b in rng.integers(0, 2, 14)] + [0, 0]
        elif w == 1:
            tow_count = (tow_start // 6 + 1) % 100800
            d = [(tow_count >> (16 - i)) & 1 for i in range(17)] + [0, 0] + \
                [(sf_id >> (2 - i)) & 1 for i in range(3)] + [0, 0]
        else:
            d = [int(b) for b in rng.integers(0, 2, 24)]
        if w in (1, 9):
            # bits 23-24 chosen so that D29 = D30 = 0 (as the ICD does for HOW and word 10)
            for t in range(4):
                d[22], d[23] = t >> 1, t & 1
                word = parity(d, d29s, d30s)
                if word[28] == 0 and word[29] == 0:
                    break
        word = parity(d, d29s, d30s)
        bits += word
        d29s, d30s = word[28], word[29]
    return bits


class NavMessage:
    """bit(k) for k = floor(GPS time / 20 ms) since the start of the week"""

    def __init__(self, prn, t_first, t_last, seed=0):
        rng = np.random.default_rng(seed * 1000 + prn)
        self.first_sf = int(t_first // 6) - 1
        n_sf = int(t_last // 6) - self.first_sf + 2
        bits = []
        for s in range(n_sf):
            k = self.first_sf + s
            bits += subframe(k * 6, (k % 5) + 1, rng)
        self.bits = np.array(bits, np.int8)
        self.k0 = self.first_sf * 300

    def bits_at(self, k):
        return self.bits[np.asarray(k) - self.k0]


# ---------------------------------------------------------------- orbits (IS-GPS-200 20.3.3.4.3)

def sat_pos(eph, t):
    """ECEF position at GPS time t (seconds of week) from a Keplerian ephemeris dict
    (no harmonic corrections: the synthetic ephemerides have them zero)"""
    A = eph["sqrtA"] ** 2
    n0 = math.sqrt(MU / A ** 3)
    tk = t - eph["toe"]
    M = eph["M0"] + (n0 + eph["dn"]) * tk
    E = M
    for _ in range(10):
        E = M + eph["e"] * math.sin(E)
    nu = math.atan2(math.sqrt(1 - eph["e"] ** 2) * math.sin(E), math.cos(E) - eph["e"])
    phi = nu + eph["omega"]
    r = A * (1 - eph["e"] * math.cos(E))
    i = eph["i0"] + eph["idot"] * tk
    xp, yp = r * math.cos(phi), r * math.sin(phi)
    Om = eph["Omega0"] + (eph["Omegadot"] - OMEGA_E) * tk - OMEGA_E * eph["toe"]
    return np.array([xp * math.cos(Om) - yp * math.cos(i) * math.sin(Om),
                     xp * math.sin(Om) + yp * math.cos(i) * math.cos(Om),
                     yp * math.sin(i)])


def light_time(eph, rx, t_rx):
    """tau such that the signal received at rx at GPS time t_rx left at t_rx - tau, with the
    satellite position rotated into the ECEF frame of reception (Sagnac)"""
    tau = 0.075
    for _ in range(6):
        s = sat_pos(eph, t_rx - tau)
        th = OMEGA_E * tau
        sr = np.array([math.cos(th) * s[0] + math.sin(th) * s[1], -math.sin(th) * s[0] + math.cos(th) * s[1], s[2]])
        tau = np.linalg.norm(sr - rx) / C
    return tau


def geodetic_to_ecef(lat, lon, h):
    a, f = 6378137.0, 1 / 298.257223563
    e2 = f * (2 - f)
    p, l = math.radians(lat), math.radians(lon)
    N = a / math.sqrt(1 - e2 * math.sin(p) ** 2)
    return np.array([(N + h) * math.cos(p) * math.cos(l), (N + h) * math.cos(p) * math.sin(l),
                     (N * (1 - e2) + h) * math.sin(p)])


def elevation(rx, s):
    lat = math.atan2(rx[2], math.hypot(rx[0], rx[1]))
    lon = math.atan2(rx[1], rx[0])
    d = s - rx
    up = np.array([math.cos(lat) * math.cos(lon), math.cos(lat) * math.sin(lon), math.sin(lat)])
    return math.degrees(math.asin(d @ up / np.linalg.norm(d)))


def constellation(t, rx, seed=3):
    """a synthetic 24-satellite Walker-like constellation (6 planes, 55 deg, 26,560 km); returns
    the ephemerides of those above 15 degrees at t, PRN-numbered 1.."""
    rng = np.random.default_rng(seed)
    ephs = []
    prn = 1
    for plane in range(6):
        for k in range(4):
            ephs.append(dict(prn=prn, sqrtA=math.sqrt(26_559_700.0), e=float(rng.uniform(0.001, 0.015)),
                             i0=math.radians(55 + rng.uniform(-1, 1)), Omega0=math.radians(60 * plane + rng.uniform(-3, 3)),
                             omega=float(rng.uniform(0, 2 * math.pi)),
                             M0=math.radians(90 * k + 15 * plane + rng.uniform(-5, 5)),
                             dn=0.0, idot=0.0, Omegadot=-8.0e-9, toe=float(t - t % 7200)))
            prn += 1
    vis = [e for e in ephs if elevation(rx, sat_pos(e, t)) > 15]
    return vis


# ---------------------------------------------------------------- IF generator

class IFGen:
    """Streams one-bit samples at FS (after the pin sampler's 1-of-5), a millisecond at a time.
    sats: list of dicts with prn, cn0 (dB-Hz), and either eph (orbit-driven) or
    (code_phase_chips, doppler_hz) for a static test signal. t0: GPS time of sample 0."""

    def __init__(self, sats, t0, rx=None, lo_offset_hz=0.0, bw=2.5e6, seed=1, clock_bias_m=0.0,
                 quantise=True):
        self.rng = np.random.default_rng(seed)
        self.sats = sats
        self.t0 = t0
        self.rx = rx
        self.lo = lo_offset_hz
        self.n = 0                      # full-rate samples produced so far
        self.quantise = quantise
        self.b, self.a = sps.butter(3, [F_IF - bw / 2, F_IF + bw / 2], "bandpass", fs=FS_FE)
        self.zi = np.zeros(max(len(self.a), len(self.b)) - 1)
        self.codes = {s["prn"]: pm(ca_code(s["prn"])) for s in sats}
        for s in sats:
            s.setdefault("phase0", float(self.rng.uniform(0, 1)))
            if "eph" in s:
                s["nav"] = NavMessage(s["prn"], t0 - 1, t0 + 40, seed)
        self.sigma = 1.0

    def _tau(self, s, t):
        if "eph" in s:
            return light_time(s["eph"], self.rx, t)
        # static test: code phase and Doppler fixed; tau chosen to give them
        return s["code_phase_chips"] / F_CHIP - s["doppler_hz"] / F_L1 * (t - self.t0) + 0.07

    def chunk(self, n_full=16368):
        """next n_full front-end samples -> (1-bit samples after 1-of-5 as +-1 int8, and the
        full-rate analogue for tests)"""
        k = np.arange(self.n, self.n + n_full)
        t = self.t0 + k / FS_FE
        x = self.rng.normal(0, self.sigma, n_full)
        for s in self.sats:
            A = math.sqrt(4 * 10 ** (s["cn0"] / 10) * self.sigma ** 2 / FS_FE)
            ta, tb = t[0], t[-1] + 1 / FS_FE
            tau_a, tau_b = self._tau(s, ta), self._tau(s, tb)
            tau = tau_a + (tau_b - tau_a) * (t - ta) / (tb - ta)
            ttx = t - tau
            chip = np.floor(np.mod(ttx, 1e-3) * F_CHIP).astype(np.int64) % 1023
            code = self.codes[s["prn"]][chip]
            if "nav" in s:
                data = pm(s["nav"].bits_at(np.floor(ttx / 0.02).astype(np.int64)))
            else:
                data = 1
            ph = (F_IF + self.lo) * (k / FS_FE) - F_L1 * tau + s["phase0"]
            x += A * data * code * np.cos(2 * np.pi * np.mod(ph, 1.0))
        y, self.zi = sps.lfilter(self.b, self.a, x, zi=self.zi)
        self.n += n_full
        off = (-(self.n - n_full)) % DECIM
        ys = y[off::DECIM]
        if self.quantise:
            return np.where(ys >= 0, 1, -1).astype(np.int8), y
        return ys, y
