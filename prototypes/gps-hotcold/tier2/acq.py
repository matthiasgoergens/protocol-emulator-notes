"""GPS L1 C/A acquisition as the chip would run it, bit-exact, plus Monte Carlo detection vs C/N0,
implementation loss, and acquisition time and area for several array sizes.

Hardware arithmetic (per 1 ms block of 3274 one-bit samples replayed from a sample bank):
  wiped_I(n) = x(n) * sgn cos(phase(n)),  wiped_Q(n) = x(n) * sgn sin(phase(n))
  phase(n) = 16-bit NCO, k = round((818.4 kHz + f_bin) * 65536 / FS), continuous in absolute
             sample count (the host loads the start phase for each block)
  code(m)  = C/A chip floor(m * 20480 / 65536) mod 1023 at absolute sample m (exact 5/16 chip)
  I(p) = sum_n wiped_I(n) * code(s + n + p), Q likewise, p = 0..3273 (one-sample code steps)
The host (RP2350) squares and sums I^2 + Q^2 over N blocks and takes the peak.

`acq.py verify` checks the vectorised correlation against the clock-by-clock PE row (pe_array.py)
`acq.py loss`   implementation loss against an unquantised receiver
`acq.py mc`     detection probability vs C/N0 for N = 1, 2, 5, 10 ms
`acq.py timing` acquisition time and area for several array sizes
Outputs go to results/tier2/.
"""
import json, math, sys, time
import numpy as np
import gpsl1 as g
import pe_array as pa

FS = g.FS
BLK = 3274                      # samples per block (1.00012 ms)
F_ALIAS = g.F_IF - FS           # 818.4 kHz
CODE_K = 20480
CODE_MOD = 1023 * 65536
BINS = np.arange(-5000, 5001, 500)
L_FFT = 8192
OUT = "../results/tier2"


def carrier_k(fd):
    return int(round((F_ALIAS + fd) * 65536 / FS))


def code_pm_abs(ca_pm, start, n):
    m = start + np.arange(n, dtype=np.int64)
    return ca_pm[((m * CODE_K) % CODE_MOD) >> 16]


def block_corr(x, s_abs, fd, ca_pm, code_fft=None):
    """integer I(p), Q(p) for p = 0..BLK-1 for block x (+-1) starting at absolute sample s_abs"""
    k = carrier_k(fd)
    ph0 = (s_abs * k) & 0xFFFF
    n = len(x)
    ci = pa.carrier_sign(ph0, k, n, 16384)          # cos sign: phase + quarter turn, MSB
    sq = pa.carrier_sign(ph0, k, n, 0)              # sin sign
    wiped = x.astype(np.float64) * ci - 1j * (x.astype(np.float64) * sq)
    if code_fft is None:
        code_fft = np.fft.fft(code_pm_abs(ca_pm, s_abs, n + BLK), L_FFT)
    r = np.fft.ifft(np.conj(np.fft.fft(wiped, L_FFT)) * code_fft)[:BLK]
    # r[p] = sum_n conj(wiped(n)) code(n + p) -> conj back to get sum wiped * code
    r = np.conj(r)
    return np.rint(r.real).astype(np.int64), np.rint(r.imag).astype(np.int64)


def float_corr(xf, s_abs, fd, ca_pm, true_phase=None):
    """unquantised reference: float samples, exact complex carrier at fd"""
    n = len(xf)
    t = (s_abs + np.arange(n)) / FS
    wiped = xf * np.exp(-2j * np.pi * (F_ALIAS + fd) * t)
    code_fft = np.fft.fft(code_pm_abs(ca_pm, s_abs, n + BLK), L_FFT)
    r = np.conj(np.fft.ifft(np.conj(np.fft.fft(wiped, L_FFT)) * code_fft)[:BLK])
    return r


# ---------------------------------------------------------------- verify

def verify():
    rng = np.random.default_rng(5)
    ca = g.pm(g.ca_code(12))
    lines = []
    total_bad = 0
    for trial in range(6):
        K = 16
        n = 300 if trial < 5 else BLK
        x = rng.choice([-1, 1], n)
        fd = float(rng.choice(BINS))
        s_abs = int(rng.integers(0, 10 ** 6))
        p0 = int(rng.integers(0, BLK))
        k = carrier_k(fd)
        ph0 = (s_abs * k) & 0xFFFF
        for arm, quarter in (("I", 16384), ("Q", 0)):
            # the hardware sees the code on the broadcast line at clock t = code(s + t - 2 + p0);
            # correlator j then integrates wiped(n) * code(s + n + p0 + j)
            clocks = n + K + 3
            code_line = code_pm_abs(ca, s_abs + p0 - 2, clocks + 2)
            bits = (1 - code_line) // 2
            # NCO: the mixer applies phase after n+1 updates to sample n; start one step back
            hw = pa.pe_row_pass(x, k, (ph0 - k) & 0xFFFF, quarter, bits, K)
            ref = pa.reference_pass(x, k, ph0, quarter, code_line, K, lag=2)
            I, Q = block_corr(x, s_abs, fd, ca)
            vec = [int(I[p0 + j]) if arm == "I" else int(-Q[p0 + j]) for j in range(K)] if n == BLK else None
            bad = sum(a != b for a, b in zip(hw, ref))
            if vec is not None:
                bad += sum(a != b for a, b in zip(hw, vec))
            total_bad += bad
            lines.append(f"  trial {trial} arm {arm}: {n} samples, K={K}, f_bin {fd:+.0f} Hz, pass offset {p0}: "
                         f"PE row vs closed form {'and vs FFT search ' if vec else ''}mismatches {bad}; first sums {hw[:4]}")
    # control: the same row with the tag negation disconnected on the correlators
    x = rng.choice([-1, 1], 300)
    k = carrier_k(0.0)
    code_line = code_pm_abs(ca, 1000 - 2, 330)
    bits = (1 - code_line) // 2
    good = pa.pe_row_pass(x, k, (-k) & 0xFFFF, 16384, bits, 8)
    orig = pa.PE.clock
    def clock_notag(self, nbr, tag_in):
        return orig(self, nbr, 0 if self.tag_src == "broadcast" else tag_in)
    pa.PE.clock = clock_notag
    broken = pa.pe_row_pass(x, k, (-k) & 0xFFFF, 16384, bits, 8)
    pa.PE.clock = orig
    diff = sum(a != b for a, b in zip(good, broken))
    lines.append(f"  control: correlator tag negation disconnected -> {diff}/8 sums differ")
    txt = f"PE row (clock by clock) vs closed form vs FFT search: {total_bad} mismatches in total\n" + "\n".join(lines)
    print(txt)
    open(f"{OUT}/acq_verify.txt", "w").write(txt + "\n")


# ---------------------------------------------------------------- Monte Carlo

def trial(rng, cn0, n_ms, noise_only=False, seed=None):
    prn = int(rng.integers(1, 33))
    fd = float(rng.uniform(-4500, 4500))
    cp = float(rng.uniform(0, 1023))
    sats = [] if noise_only else [dict(prn=prn, cn0=cn0, code_phase_chips=cp, doppler_hz=fd)]
    gen = g.IFGen(sats, t0=100.0, seed=int(rng.integers(0, 2 ** 31)))
    if noise_only:
        gen.codes = {}
    xs = []
    for _ in range(n_ms + 1):
        q, _ = gen.chunk()
        xs.append(q)
    x = np.concatenate(xs)
    ca = g.pm(g.ca_code(prn))
    acc = {N: None for N in (1, 2, 5, 10) if N <= n_ms}
    power = np.zeros((len(BINS), BLK))
    for m in range(n_ms):
        s = m * BLK
        blk = x[s:s + BLK]
        code_fft = np.fft.fft(code_pm_abs(ca, s, BLK + BLK), L_FFT)
        for bi, fb in enumerate(BINS):
            I, Q = block_corr(blk, s, fb, ca, code_fft)
            power[bi] += I.astype(np.float64) ** 2 + Q.astype(np.float64) ** 2
        if (m + 1) in acc:
            acc[m + 1] = power.copy()
    res = {}
    chip0 = ((100.0 - 0.07 - cp / g.F_CHIP) % 1e-3) * g.F_CHIP
    p_true = (chip0 / 0.3125) % (1023 / 0.3125)
    for N, pw in acc.items():
        bi, p = np.unravel_index(np.argmax(pw), pw.shape)
        stat = pw[bi, p] / pw.mean()
        dp = abs((p - p_true + 1636.8) % 3273.6 - 1636.8)
        correct = dp <= 2.0 and abs(BINS[bi] - fd) <= 500
        res[N] = (stat, bool(correct))
    return res


def mc(n_trials=60, n_noise=150):
    rng = np.random.default_rng(11)
    t0 = time.time()
    noise = [trial(rng, 0, 10, noise_only=True) for _ in range(n_noise)]
    thr = {N: float(np.max([r[N][0] for r in noise])) for N in (1, 2, 5, 10)}
    cn0s = [30, 32, 34, 36, 38, 40, 42, 44, 46]
    table = {}
    for cn0 in cn0s:
        rs = [trial(rng, cn0, 10) for _ in range(n_trials)]
        table[cn0] = {N: sum(1 for r in rs if r[N][1] and r[N][0] > thr[N]) / n_trials for N in (1, 2, 5, 10)}
        print(cn0, table[cn0], f"{time.time() - t0:.0f} s", flush=True)
    lines = [f"acquisition Monte Carlo: {n_trials} trials per C/N0, random PRN, Doppler U(-4.5, 4.5) kHz, code phase U(0, 1023);",
             f"search 21 bins x 500 Hz, 3274 code offsets (0.3125 chip); threshold per N = the largest peak/mean",
             f"over {n_noise} noise-only searches (false-alarm rate per search below about 1/{n_noise});",
             f"detection = peak within 2 samples and one bin of the truth AND above threshold.",
             "thresholds: " + ", ".join(f"N={N}: {v:.2f}" for N, v in thr.items()),
             f"{'C/N0 dB-Hz':>11} " + " ".join(f"{'Pd N=' + str(N):>9}" for N in (1, 2, 5, 10))]
    for cn0 in cn0s:
        lines.append(f"{cn0:>11} " + " ".join(f"{table[cn0][N]:>9.2f}" for N in (1, 2, 5, 10)))
    txt = "\n".join(lines)
    print(txt)
    open(f"{OUT}/acq_mc.txt", "w").write(txt + "\n")
    json.dump(dict(thr=thr, table={str(k): v for k, v in table.items()}), open(f"{OUT}/acq_mc.json", "w"), indent=1)
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    fig, ax = plt.subplots(figsize=(7, 4.5))
    for N in (1, 2, 5, 10):
        ax.plot(cn0s, [table[c][N] for c in cn0s], marker="o", label=f"N = {N} ms non-coherent")
    ax.set_xlabel("C/N0 (dB-Hz)"); ax.set_ylabel("probability of detection")
    ax.set_title("acquisition on the chip's arithmetic (1-bit samples, 1-bit carrier)")
    ax.grid(alpha=0.3); ax.legend()
    fig.tight_layout(); fig.savefig(f"{OUT}/acq_pd.png", dpi=110)


# ---------------------------------------------------------------- implementation loss

def loss(n_ms=200, cn0=45.0):
    """coherent 1-ms SNR at the true cell: float receiver vs 1-bit samples + exact carrier vs
    the chip (1-bit samples, 1-bit carrier from the 16-bit NCO), at the exact Doppler"""
    rng = np.random.default_rng(3)
    prn, fd, cp = 9, 1234.0, 511.3
    gen = g.IFGen([dict(prn=prn, cn0=cn0, code_phase_chips=cp, doppler_hz=fd)], t0=100.0, seed=4, quantise=False)
    ca = g.pm(g.ca_code(prn))
    xs = []
    for _ in range(n_ms + 1):
        v, _ = gen.chunk()
        xs.append(v)
    xf = np.concatenate(xs)
    x1 = np.where(xf >= 0, 1, -1)
    chip0 = ((100.0 - 0.07 - cp / g.F_CHIP) % 1e-3) * g.F_CHIP
    p_true = int(round((chip0 / 0.3125) % 3273.6))
    res = {}
    for name in ("float", "1-bit samples, float carrier", "chip: 1-bit samples, 1-bit NCO carrier"):
        peak, noise = [], []
        for m in range(n_ms):
            s = m * BLK
            if name == "float":
                r = float_corr(xf[s:s + BLK], s, fd, ca)
            elif name.startswith("1-bit samples"):
                r = float_corr(x1[s:s + BLK].astype(float), s, fd, ca)
            else:
                # the chip's NCO at the exact Doppler (not a bin centre) for a like-for-like loss
                I, Q = block_corr(x1[s:s + BLK], s, fd, ca)
                r = I + 1j * Q
            pk = np.argmax(np.abs(r[max(0, p_true - 3):p_true + 4])) + max(0, p_true - 3)
            peak.append(abs(r[pk]) ** 2)
            mask = np.ones(BLK, bool); mask[max(0, pk - 20):pk + 21] = False
            noise.append(np.mean(np.abs(r[mask]) ** 2))
        # SNR = (E|peak|^2 - noise) / noise: coherent post-correlation SNR
        nz = np.mean(noise)
        res[name] = 10 * math.log10((np.mean(peak) - nz) / nz)
    ideal = 10 * math.log10(10 ** (cn0 / 10) * BLK / FS)
    lines = [f"implementation loss, coherent 1 ms, C/N0 {cn0} dB-Hz, {n_ms} blocks, exact Doppler, IF filter 2.5 MHz:",
             f"  ideal C/N0 * T = {ideal:.2f} dB"]
    for k, v in res.items():
        lines.append(f"  {k:42s} SNR {v:6.2f} dB, loss vs ideal {ideal - v:5.2f} dB, vs float {res['float'] - v:5.2f} dB")
    txt = "\n".join(lines)
    print(txt)
    open(f"{OUT}/acq_loss.txt", "w").write(txt + "\n")


# ---------------------------------------------------------------- timing and area

def timing():
    f_clk = 65.472e6
    pe_synth, pe_placed = 6_559, 9_852          # ../pe-synth results/areas.txt, results/pnr.txt
    ext = 510                                    # tag-lane extension, estimate (README)
    lfsr = 3_500                                 # generic LFSR/CRC assist, estimate
    bank = 28_127                                # 4 kbit of sample bank, placed (../systolic-storage)
    lines = ["acquisition time and area (per 1 ms block; FS = 3.2736 MS/s, 3274 samples, 21 Doppler bins x 500 Hz)",
             "pass = 3274 + K + 3 clocks of replay + K readout + 3(K+2) configuration clocks; two rows (I, Q) of K correlators",
             f"{'K':>4} {'PEs':>4} {'passes/bin':>10} {'ms/PRN/block':>13} {'32 PRNs, N=1':>13} {'32 PRNs, N=5':>13} {'8 PRNs warm, N=5':>16} "
             f"{'PE area synth':>14} {'placed':>9}"]
    rows = []
    for K in (4, 8, 16, 32, 64):
        pes = 2 * K + 5
        passes = math.ceil(BLK / K)
        clocks = BLK + K + 3 + K + 3 * (K + 2)
        per_blk = passes * len(BINS) * clocks / f_clk          # seconds of chip time per PRN per block
        # each block of data arrives in real time (1 ms); processing overlaps with capture into
        # the other bank, so a PRN costs max(per_blk, 1 ms) per block
        t_prn = max(per_blk, 1e-3)
        warm_bins = 9                                         # +-2 kHz with a known TCXO offset
        per_blk_warm = passes * warm_bins * clocks / f_clk
        rows.append(dict(K=K, pes=pes, per_blk_ms=per_blk * 1e3, all32_n1=32 * t_prn, all32_n5=32 * 5 * t_prn,
                         warm8_n5=8 * 5 * max(per_blk_warm, 1e-3),
                         area_synth=pes * (pe_synth + ext) + lfsr, area_placed=pes * (pe_placed + ext * 1.5) + lfsr))
        r = rows[-1]
        lines.append(f"{K:>4} {pes:>4} {passes:>10} {r['per_blk_ms']:>13.1f} {r['all32_n1']:>11.1f} s {r['all32_n5']:>11.1f} s "
                     f"{r['warm8_n5']:>14.2f} s {r['area_synth']:>12,.0f} {r['area_placed']:>9,.0f}")
    lines.append(f"plus two 4 kbit sample banks (double buffer): {2 * bank:,} um2 placed (SRAM 1P_256x16 equivalent)")
    tpass = BLK + 3 + 3 + 3 * 8
    lines.append("tracking: one channel = E, P, L on both arms (6 PEs) + a mixer per arm (2) + 32-bit carrier NCO per arm "
                 f"(2 x 2 PEs) + 32-bit code NCO (2 PEs) = 14 PEs, one pass of about {tpass} clocks per code period; "
                 f"{int(f_clk * 1e-3 // tpass)} passes fit in 1 ms, so 12 channels use "
                 f"{12 * tpass / (f_clk * 1e-3) * 100:.0f} % of a 14-PE array's time")
    txt = "\n".join(lines)
    print(txt)
    open(f"{OUT}/acq_timing.txt", "w").write(txt + "\n")
    json.dump(rows, open(f"{OUT}/acq_timing.json", "w"), indent=1)


if __name__ == "__main__":
    {"verify": verify, "mc": mc, "loss": loss, "timing": timing}[sys.argv[1]]()
