"""Checks of gpsl1.py: C/A codes against the ICD's first-10-chips octal table and the Gold-code
three-valued cross-correlation; navigation-word parity round trip and a single-bit-error
control; generator sanity (a strong static satellite is found at the planted code phase and
Doppler by a float correlation). Writes results/tier2/test_gpsl1.txt."""
import sys, math
import numpy as np
import gpsl1 as g

out = []
bad = 0
for prn in range(1, 33):
    c = g.ca_code(prn)
    v = int("".join(map(str, c[:10])), 2)
    if v != g.FIRST10_OCTAL[prn - 1]:
        bad += 1
out.append(f"C/A first 10 chips vs ICD octal table: {32 - bad}/32 match")
codes = [g.pm(g.ca_code(p)) for p in range(1, 33)]
vals = set()
for i in range(32):
    for j in range(32):
        cc = np.round(np.fft.ifft(np.fft.fft(codes[i]) * np.conj(np.fft.fft(codes[j]))).real).astype(int)
        if i == j:
            cc = cc[1:]
            assert np.fft.ifft(np.fft.fft(codes[i]) * np.conj(np.fft.fft(codes[i]))).real[0].round() == 1023
        vals |= set(cc.tolist())
out.append(f"periodic auto (off-peak) and cross-correlation values over all 32x32 pairs: {sorted(vals)} (Gold: -65, -1, 63)")
bal = sorted(set(int((g.ca_code(p) == 1).sum()) for p in range(1, 33)))
out.append(f"ones per code: {bal} (balanced Gold codes have 512)")
rng = np.random.default_rng(0)
ok = 0; caught = 0
for trial in range(200):
    bits = g.subframe(6 * trial, trial % 5 + 1, rng)
    d29s = d30s = 0
    good = True
    for w in range(10):
        wd = bits[30 * w:30 * w + 30]
        r, _ = g.check_word(wd, d29s, d30s)
        good &= r
        d29s, d30s = wd[28], wd[29]
    ok += good
    wd = list(bits[30:60]); wd[rng.integers(0, 30)] ^= 1
    r, _ = g.check_word(wd, bits[28], bits[29])
    caught += not r
out.append(f"parity: {ok}/200 generated subframes pass; single-bit errors caught {caught}/200")
# generator sanity: one satellite at 60 dB-Hz, static, float correlation
gen = g.IFGen([dict(prn=7, cn0=60, code_phase_chips=300.25, doppler_hz=1500.0)], t0=100.0, quantise=False)
x, _ = gen.chunk()
n = np.arange(len(x))
best = (0, None)
ca = codes[6]
for fd in np.arange(-5000, 5001, 250):
    ph = 2 * np.pi * (g.FS_FE / g.DECIM * 0 + (g.F_IF - g.FS) + fd) * n / g.FS
    bb = x * np.exp(-1j * ph)
    for p in range(0, 3274):
        pass
    # correlation over all code offsets via FFT on a long code
    m = np.arange(len(x) + 3274)
    code = ca[(np.floor(m * g.F_CHIP / g.FS).astype(int)) % 1023]
    L = 1 << 14
    r = np.fft.ifft(np.conj(np.fft.fft(bb, L)) * np.fft.fft(code, L))[:3274]
    k = np.argmax(np.abs(r))
    if abs(r[k]) > best[0]:
        best = (abs(r[k]), (fd, k))
fd, k = best[1]
# received chip at sample 0: tau(t0) = cp/Fchip + 0.07 -> ttx = t0 - 0.07 - cp/Fchip
chip0 = ((100.0 - 0.07 - 300.25 / g.F_CHIP) % 1e-3) * g.F_CHIP
k_true = (chip0 / 0.3125) % (1023 / 0.3125)
out.append(f"generator: static PRN 7 at 60 dB-Hz, Doppler 1500 Hz, planted code phase -> found Doppler {fd} Hz, "
           f"code offset {k} samples (expected {k_true:.2f})")
txt = "\n".join(out)
print(txt)
open(sys.argv[1], "w").write(txt + "\n")
