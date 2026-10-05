"""CIFB with inter-stage gains c_k = 2^-m_k (needs the proposed A >>> m operand), integer, 16-bit
saturating. For each design: scale states to a common peak, report a_1 (input full scale), the
stable input range and the SQNR (input exact, so this is the modulator alone)."""
import numpy as np
from numba import njit
from explore_ntf import ntf_poles, cifb_coeffs, sqnr, FM

@njit(cache=True)
def run(u, a, m, sat):
    n = a.shape[0]
    s = np.zeros(n, dtype=np.int64)
    smax = np.zeros(n, dtype=np.int64)
    out = np.empty(u.shape[0], dtype=np.int8)
    y = 1
    for i in range(u.shape[0]):
        for k in range(n):
            if k == 0:
                t = u[i] - a[0] * y
            else:
                t = (s[k - 1] >> m[k]) - a[k] * y
            if sat:
                t = min(32767, max(-32768, t))
            v = s[k] + t
            if sat:
                v = min(32767, max(-32768, v))
            s[k] = v
            smax[k] = max(smax[k], abs(v))
        y = 1 if s[n - 1] >= 0 else -1
        out[i] = y
    return out, smax

nsteps = 1 << 20
f0 = FM * 37 / nsteps * 8
t = np.arange(nsteps)
for n, hinf in [(2, 4.0), (2, 2.0), (3, 1.5), (3, 1.7), (4, 1.5), (4, 1.4)]:
    alpha = np.array([1.0, 1.0]) if hinf == 4.0 else cifb_coeffs(n, ntf_poles(n, hinf))
    # float run, c = 1, to get peak X_k per unit alpha_1 at -3 dBFS (relative to alpha_1)
    big = 1 << 30
    af = np.round(alpha / alpha[0] * 2**20).astype(np.int64)
    u = np.round(0.5 * af[0] * np.sin(2 * np.pi * f0 * t / FM)).astype(np.int64)
    _, xpk = run(u, af, np.zeros(n, dtype=np.int64), False)
    # stage scale d_k = 2^(e_k): pick m_k = round(log2(xpk_k / xpk_{k-1})) (>= 0) to equalise
    rel = np.log2(xpk / xpk[0])
    m = np.zeros(n, dtype=np.int64)
    for k in range(1, n):
        m[k] = max(0, int(np.round(rel[k] - rel[k - 1])))
    # d_k / d_1 = prod 2^-m
    dk = np.cumprod(np.concatenate([[1.0], 2.0 ** -m[1:]]))
    best = None
    for e in np.arange(10, 15.5, 0.0625):
        a1 = 2**e
        a = np.round(alpha / alpha[0] * a1 * dk).astype(np.int64)  # a_k = d_k alpha_k (alpha_1 -> a1)
        if a.max() > 32767:
            break
        res = {}
        ok = True
        for amp_db in [-3.0]:
            amp = 10 ** (amp_db / 20)
            u = np.round(amp * 0.5 * a[0] * np.sin(2 * np.pi * f0 * t / FM)).astype(np.int64)  # -3 dB re half of a_1
            out, smax = run(u, a, m, True)
            if smax.max() >= 32767:
                ok = False
            res[amp_db] = (sqnr(out.astype(float), f0, 0, 0), smax)
        if ok:
            best = (a, res)
    if best is None:
        print(n, hinf, "none"); continue
    a, res = best
    # max stable amplitude relative to a_1 with saturation
    stab = 0
    for frac in np.arange(0.3, 1.0, 0.05):
        u = np.round(frac * a[0] * np.sin(2 * np.pi * f0 * t[:1<<18] / FM)).astype(np.int64)
        out, smax = run(u, a, m, True)
        q = sqnr(out.astype(float), f0 * 1, 0, 0) if False else None
        # instability shows as long runs of one value
        runs = np.max(np.diff(np.flatnonzero(np.diff(out) != 0))) if np.any(np.diff(out) != 0) else 1 << 18
        if runs < 200:
            stab = frac
    print(f"N={n} Hinf={hinf} m={m.tolist()} a={a.tolist()} SQNR(-3 dB re a1/2)={res[-3.0][0]:.1f} dB "
          f"smax={res[-3.0][1].tolist()} max stable ~{stab:.2f} a1")
