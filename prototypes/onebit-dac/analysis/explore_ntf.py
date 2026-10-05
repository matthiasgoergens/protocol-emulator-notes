"""Design exploration for the CIFB modulators on 16-bit PEs (not the deliverable model).

For each order N and out-of-band gain Hinf: synthesise NTF = (1 - z^-1)^N / D(z) with
Butterworth poles, solve the non-delaying CIFB feedback coefficients a_k (unit inter-stage
gains, which is all the PE can do without extra PEs), then simulate the integer recurrence the
PEs implement, with 16-bit saturation, to find the largest a_1 (input full scale in LSB) for
which no state saturates at a given input level.

Recurrence (one modulator step, y = +-1 from the previous step):
  t_1 = u - a_1 y ;  S_k <- sat(S_k + t_k) ; t_{k+1} = S_k - a_{k+1} y ;  y' = sign(S_N)
"""
import sys
import numpy as np
from scipy import signal
from numba import njit

FM = 6_000_000
FB = 20_000


def ntf_poles(n, hinf):
    lo, hi = 1e-4, 0.999
    for _ in range(60):
        wn = (lo + hi) / 2
        _, p, _ = signal.butter(n, wn, btype="high", output="zpk")
        w = np.linspace(0, np.pi, 4096)
        z = np.exp(1j * w)
        h = np.prod([(z - 1) for _ in range(n)], axis=0) / np.prod([(z - pk) for pk in p], axis=0)
        m = np.max(np.abs(h))
        if m > hinf:
            hi = wn
        else:
            lo = wn
    return p


def cifb_coeffs(n, poles):
    # D(s) with s = z^-1: prod(1 - p s), coefficients in ascending powers of s
    d = np.array([1.0 + 0j])
    for pk in poles:
        d = np.convolve(d, [1.0, -pk])
    d = np.real(d)
    one_minus_s_n = np.array([1.0])
    for _ in range(n):
        one_minus_s_n = np.convolve(one_minus_s_n, [1.0, -1.0])
    p = (d - one_minus_s_n)[1:]  # divide by s (constant term is 0)
    # express P(s) in w = 1 - s: P(1 - w)
    pw = np.zeros(n)
    for j, c in enumerate(p):  # c * s^j = c * (1 - w)^j
        term = np.array([1.0])
        for _ in range(j):
            term = np.convolve(term, [1.0, -1.0])
        pw[: len(term)] += c * term
    return pw  # a_1 .. a_N


@njit(cache=True)
def run(u, a, sat):
    n = a.shape[0]
    s = np.zeros(n, dtype=np.int64)
    smax = np.zeros(n, dtype=np.int64)
    out = np.empty(u.shape[0], dtype=np.int8)
    y = 1
    nsat = 0
    for i in range(u.shape[0]):
        t = u[i] - a[0] * y
        for k in range(n):
            if k > 0:
                t = s[k - 1] - a[k] * y
                if sat:
                    if t > 32767:
                        t = 32767
                        nsat += 1
                    elif t < -32768:
                        t = -32768
                        nsat += 1
            v = s[k] + t
            if sat:
                if v > 32767:
                    v = 32767
                    nsat += 1
                elif v < -32768:
                    v = -32768
                    nsat += 1
            s[k] = v
            if abs(v) > smax[k]:
                smax[k] = abs(v)
        y = 1 if s[n - 1] >= 0 else -1
        out[i] = y
    return out, smax, nsat


def sqnr(out, f0, amp, a1):
    n = out.shape[0]
    win = signal.windows.blackmanharris(n)
    spec = np.abs(np.fft.rfft(out * win)) ** 2
    freqs = np.fft.rfftfreq(n, 1 / FM)
    k0 = int(round(f0 * n / FM))
    sig = spec[k0 - 4 : k0 + 5].sum()
    band = (freqs > 20) & (freqs < FB)
    band[k0 - 4 : k0 + 5] = False
    noise = spec[band].sum()
    return 10 * np.log10(sig / noise)


def main():
    nsteps = 1 << 20
    f0 = FM * 37 / nsteps * 8  # coherent-ish
    tgt_amp = float(sys.argv[1]) if len(sys.argv) > 1 else -3.0
    for n, hinf in [(2, 4.0), (2, 2.0), (3, 1.5), (3, 2.0), (4, 1.5), (5, 1.5)]:
        if n == 2 and hinf == 4.0:
            a = np.array([1.0, 1.0])
        else:
            a = cifb_coeffs(n, ntf_poles(n, hinf))
        # largest a_1 (power of two steps / fine) such that a tgt_amp sine does not saturate
        amp = 10 ** (tgt_amp / 20)
        best = None
        for a1 in [2 ** e for e in np.arange(8, 15.01, 0.125)]:
            ai = np.round(a / a[0] * a1).astype(np.int64)
            t = np.arange(nsteps)
            u = np.round(amp * ai[0] * np.sin(2 * np.pi * f0 * t / FM)).astype(np.int64)
            out, smax, nsat = run(u, ai, False)
            if smax.max() < 32000:
                best = (a1, ai, smax, sqnr(out.astype(float), f0, amp, ai[0]))
        if best is None:
            print(f"N={n} Hinf={hinf}: nothing fits")
            continue
        a1, ai, smax, q = best
        print(f"N={n} Hinf={hinf} a/a1={np.round(a / a[0], 4)} -> a_int={ai.tolist()} "
              f"a1=2^{np.log2(a1):.2f} smax={smax.tolist()} SQNR@{tgt_amp}dBFS={q:.1f} dB "
              f"input resolution {np.log2(2 * ai[0]):.1f} bits")


if __name__ == "__main__":
    main()
