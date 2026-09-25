"""The scope's signal chain: target signals, probe network, pad comparator, DAC, time base.

Every number that is an assumption rather than a measurement or a SPICE/liberty result is marked
ASSUMPTION next to it. The pad comparator is padmodel.Pad (fitted to SPICE of sg13g2_IOPadIn).
"""
import math
import numpy as np
from dataclasses import dataclass, field

from padmodel import Pad, VT_SPICE

# ----------------------------------------------------------------------------------------------
# Target signals (functions of time in seconds, vectorised)

def erf_edge(t, t0, rise):
    """0 -> 1 edge with 10-90 % time `rise` (Gaussian-filtered step)."""
    from scipy.special import erf
    s = rise / 2.563
    return 0.5 * (1 + erf((t - t0) / (s * math.sqrt(2))))

def sck_edge(t, t0=0.0, rise=1e-9, vhi=3.3, ring_amp=0.40, ring_f=300e6, ring_tau=3e-9):
    """SPI SCK rising edge seen at a target: 1 ns rise, 300 MHz ringing decaying with 3 ns
    (the same waveform as spice/pad2.py sck)."""
    e = erf_edge(t, t0, rise)
    dt = np.maximum(t - t0, 0)
    r = ring_amp * np.sin(2 * np.pi * ring_f * dt) * np.exp(-dt / ring_tau) * (t > t0)
    return vhi * e + r * e

def i2c_release(t, t0=0.0, vdd=3.3, r_pull=4.7e3, c_bus=200e-12, v_low=0.15, fall=20e-9, t_fall=None):
    """Open-drain line: held low until t0, released (RC rise), pulled low again at t_fall."""
    tau = r_pull * c_bus
    v = np.where(t < t0, v_low, vdd - (vdd - v_low) * np.exp(-np.maximum(t - t0, 0) / tau))
    if t_fall is not None:
        # the driver pulls the line low: a fast exponential fall (driver on-resistance x C)
        vf = v_low + (np.interp(t_fall, t, v) - v_low) * np.exp(-np.maximum(t - t_fall, 0) / fall)
        v = np.where(t < t_fall, v, vf)
    return v

# ----------------------------------------------------------------------------------------------
# Probe network: target -> pin

@dataclass
class Probe:
    """Compensated resistive summing network: target through Rs||Cs, DAC through Rd||Cd, a
    resistor Rg to ground, all into the pin (pad 0.22 pF from the liberty + board/package C).

    DC gain from the target k_s = g_s / (g_s + g_d + g_g), from the DAC k_d = g_d / (...).
    With the capacitors in the same ratio as the conductances the divider is flat; a mismatch
    `comp_err` leaves a step response that starts at k_s(1 + comp_err) and relaxes to k_s with the
    network's time constant. The target's source resistance and the pin capacitance leave one pole.
    """
    k_s: float = 0.16          # target -> pin gain (sets the target range with a 0..3.3 V DAC)
    k_d: float = 0.18          # DAC -> pin gain
    comp_err: float = 0.05     # ASSUMPTION: 5 % capacitor trim error in the compensation
    tau_comp: float = 30e-9    # network RC (e.g. 10 kohm x 3 pF), where the comp error relaxes
    f_pin: float = 1.5e9       # ASSUMPTION: residual pole from source resistance x pin/board C
    def pin(self, t, v_target, v_offset):
        """v_target sampled on the uniform grid t (last axis). Returns the pin voltage."""
        dt = t[1] - t[0]
        v = np.asarray(v_target, dtype=np.float64)
        # compensation error: high-pass of the target with tau_comp, scaled by comp_err
        a = dt / (self.tau_comp + dt)
        lp = np.empty_like(v); acc = v[..., 0].copy()
        for k in range(v.shape[-1]):
            acc = acc + a * (v[..., k] - acc); lp[..., k] = acc
        v = v + self.comp_err * (v - lp)
        # residual pole
        b = dt / (1 / (2 * np.pi * self.f_pin) + dt)
        out = np.empty_like(v); acc = v[..., 0].copy()
        for k in range(v.shape[-1]):
            acc = acc + b * (v[..., k] - acc); out[..., k] = acc
        return self.k_s * out + v_offset

    def offset_for_level(self, level, vt=VT_SPICE):
        """Pin offset that puts the pad threshold at target level `level`."""
        return vt - self.k_s * level

# ----------------------------------------------------------------------------------------------
# DAC: an R-2R ladder on output pins, plus one sigma-delta trim pin

@dataclass
class Dac:
    bits: int = 8
    r: float = 10e3
    r_tol: float = 0.01        # ASSUMPTION: 1 % resistors
    r_on: float = 80.0         # ASSUMPTION: output pad on-resistance, 4 mA cell
    r_on_tol: float = 0.2      # ASSUMPTION: +-20 % between pins
    vio: float = 3.3
    trim_bits: int = 6         # sigma-delta pin through 2^trim x the ladder's LSB resistance
    seed: int = 1
    def __post_init__(self):
        rng = np.random.default_rng(self.seed)
        n = self.bits
        self.r_leg = 2 * self.r * (1 + self.r_tol * rng.standard_normal(n)) + \
            self.r_on * (1 + self.r_on_tol * rng.standard_normal(n))
        self.r_ser = self.r * (1 + self.r_tol * rng.standard_normal(n))
        self.r_term = 2 * self.r * (1 + self.r_tol * rng.standard_normal())
        self.codes_v = np.array([self._ladder(c) for c in range(2 ** n)])
    def _ladder(self, code):
        # nodal solution of the ladder: node i has leg i (pin at vio or 0), series resistor to i+1
        n = self.bits
        G = np.zeros((n, n)); I = np.zeros(n)
        for i in range(n):
            bit = (code >> i) & 1
            G[i, i] += 1 / self.r_leg[i]; I[i] += bit * self.vio / self.r_leg[i]
            if i == 0:
                G[i, i] += 1 / self.r_term
            if i + 1 < n:
                g = 1 / self.r_ser[i]
                G[i, i] += g; G[i + 1, i + 1] += g; G[i, i + 1] -= g; G[i + 1, i] -= g
        return np.linalg.solve(G, I)[n - 1]
    def volts(self, code, trim=0.0):
        """Ladder code plus a trim fraction in [0, 1) of one ideal LSB from the sigma-delta pin
        (its duty cycle is exact in time; ASSUMPTION: 1 % gain error from edge asymmetry)."""
        lsb = self.vio / 2 ** self.bits
        return self.codes_v[code] + trim * lsb * 1.01

# ----------------------------------------------------------------------------------------------
# Time base: clock, delay line, TDC, calibration

@dataclass
class TimeBase:
    """Sampling and launch instants within a clock, and the TDC on the same structure.

    mode "arch": architecture v0's fine-delay option (notes/architecture-v0.md 2.2, the
    "cheap point" of ../multiphase): four clock phases plus a quarter-period line of
    sg13g2_dlygate4sd1 (134.3 ps typ, ../multiphase/sta/liberty_delays.txt). The phases carry a
    static skew each (unknown, calibrated with everything else by code density).
    mode "full": one full-period line of sg13g2_buf_1 (63.2 ps typ).
    In both, the positions of all bins within one clock form `line` (seconds from the clock edge).
    """
    f_clk: float = 60e6
    mode: str = "arch"
    mismatch: float = 0.03         # ASSUMPTION: 3 % per-stage random (as ../multiphase/shmoo.ml)
    bow: float = 20e-12            # ASSUMPTION: systematic INL of a line (placement), half-sine amplitude
    phase_skew: float = 50e-12     # ASSUMPTION: rms static skew of phases 1..3 (no CTS run)
    period_jitter: float = 10e-12  # ASSUMPTION: clock period jitter, rms, white per period
    vdd_noise: float = 5e-3        # ASSUMPTION: core supply noise, rms, slow against a traversal
    delay_sens: float = 1.08       # d ln(delay) / d vdd, from (1.2/vdd)^1.3 (../multiphase/shmoo.ml)
    vernier: float = 15e-12        # Vernier interpolator step inside a TDC bin (0: none)
    vernier_inl: float = 2e-12     # ASSUMPTION: residual INL of the interpolator after code density
    seed: int = 2
    def __post_init__(self):
        rng = np.random.default_rng(self.seed)
        self.T = 1 / self.f_clk
        self.v_inl = self.vernier_inl * rng.standard_normal(64)
        if self.mode == "arch":
            self.tap = 134.3e-12
            q = self.T / 4
            n = int(math.ceil(q / self.tap)) + 2
            d = self.tap * (1 + self.mismatch * rng.standard_normal(n))
            seg = np.concatenate([[0], np.cumsum(d)])
            seg += self.bow * np.sin(np.pi * np.clip(seg / q, 0, 1))
            seg = seg[seg < q]
            self.seg = seg
            skew = np.concatenate([[0], self.phase_skew * rng.standard_normal(3)])
            self.skew = skew
            pos = np.concatenate([p * q + skew[p] + seg for p in range(4)])
            self.line_delay = np.concatenate([seg for p in range(4)])   # the part that is a delay line
        else:
            self.tap = 63.2e-12
            n = int(math.ceil(self.T / (self.tap * 0.7))) + 8
            d = self.tap * (1 + self.mismatch * rng.standard_normal(n))
            pos = np.concatenate([[0], np.cumsum(d)])
            pos += self.bow * np.sin(np.pi * np.clip(pos / self.T, 0, 1))
            pos = pos[pos < self.T]
            self.line_delay = pos.copy()
        self.line = np.sort(pos)
        order = np.argsort(pos)
        self.line_delay = self.line_delay[order]
        self.n_taps = len(self.line)
        self.line = np.concatenate([self.line, [self.T]])     # bin edges, last = next clock
        self.est = None

    def calibrate_code_density(self, n_hits, rng):
        """Code-density calibration: n_hits edges at uniformly random times within a clock (from
        an asynchronous source, e.g. a ring oscillator) land in the bins; widths ~ hit counts."""
        u = rng.uniform(0, self.T, n_hits)
        idx = np.searchsorted(self.line, u, side="right") - 1
        counts = np.bincount(idx, minlength=self.n_taps)[: self.n_taps]
        w = counts / n_hits * self.T
        self.est = np.concatenate([[0], np.cumsum(w)])
        return self.inl()

    def inl(self):
        return np.max(np.abs(self.est[: self.n_taps] - self.line[: self.n_taps]))

    def jitter(self, n_clk, k, rng):
        """Timing error of an instant n_clk clocks after the reference, bin k: clock jitter
        accumulated over n_clk periods, and supply noise scaling the delay-line part."""
        n_clk = np.asarray(n_clk); k = np.asarray(k)
        e = self.period_jitter * np.sqrt(np.maximum(n_clk, 0)) * rng.standard_normal(np.shape(k))
        e += self.delay_sens * self.vdd_noise * rng.standard_normal(np.shape(k)) * self.line_delay[k]
        return e

    def instant(self, n_clk, k, rng):
        return np.asarray(n_clk) * self.T + self.line[np.asarray(k)] + self.jitter(n_clk, k, rng)

    def estimate(self, n_clk, k):
        return np.asarray(n_clk) * self.T + self.est[np.asarray(k)]

    def nearest(self, t):
        """Clock and bin whose calibrated position is nearest to the wanted time t (host side)."""
        t = np.asarray(t, dtype=float)
        n = np.floor(t / self.T).astype(int)
        f = t - n * self.T
        k = np.clip(np.searchsorted(self.est[: self.n_taps], f), 1, self.n_taps - 1)
        k = np.where(np.abs(self.est[k - 1] - f) < np.abs(self.est[k] - f), k - 1, k)
        return n, k

    def timestamp(self, t_edge, rng):
        """TDC in timestamp mode: clock index plus the calibrated centre of the bin the edge falls
        in; the line runs fast or slow with the supply during the shot."""
        t_edge = np.asarray(t_edge, dtype=float)
        n = np.floor(t_edge / self.T)
        f = t_edge - n * self.T
        k = np.clip(np.searchsorted(self.line, f, side="right") - 1, 0, self.n_taps - 1)
        f = f - self.delay_sens * self.vdd_noise * rng.standard_normal(np.shape(f)) * self.line_delay[k]
        f = np.clip(f, 0, self.T - 1e-15)
        k = np.clip(np.searchsorted(self.line, f, side="right") - 1, 0, self.n_taps - 1)
        if self.vernier:
            # interpolator: the residual from the bin's start, quantised to the Vernier step
            j = np.clip(np.floor(np.nan_to_num((f - self.line[k]) / self.vernier)).astype(int), 0, 63)
            fine = self.est[k] + (j + 0.5) * self.vernier + self.v_inl[j]
        else:
            fine = 0.5 * (self.est[k] + self.est[k + 1])
        return np.where(np.isfinite(t_edge), n * self.T + fine, np.nan)
