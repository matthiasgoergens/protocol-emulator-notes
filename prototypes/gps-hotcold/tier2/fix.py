"""End to end: synthetic sky -> 1-bit IF -> the chip's acquisition -> tracking with the chip's
correlators and host loop filters -> bit sync, subframe and TOW decode -> pseudoranges ->
least-squares position on the host.

Scenario: receiver at the tier-1 cache (1.3441 N, 103.8200 E, 20 m), a synthetic constellation
(gpsl1.constellation), satellites above 15 degrees with C/N0 40-47 dB-Hz, a -1.8 kHz common
carrier offset (TCXO error), 9.5 s of signal starting at a random GPS time.

Correlators are bit-exact chip arithmetic: 1-bit samples, 16-bit carrier NCO signs, a Q16 code
NCO, integer sums for early/prompt/late on both arms (E and L one sample, 0.3125 chip, either
side of P). The host (RP2350) runs the loops in floating point once per code period:
FLL-assisted Costas PLL, carrier-aided second-order DLL, bit sync by histogram, parity-checked
subframe sync. Ephemerides are given to the host (assisted start; see README).

Usage: fix.py [--regen]   (samples cached in /var/tmp/gps-hotcold/sky.npz)
Outputs: results/tier2/fix.txt, fix.json, fix.png
"""
import json, math, os, sys, time
import numpy as np
import gpsl1 as g
import acq
import pe_array as pa

OUT = "../results/tier2"
CACHE = "/var/tmp/gps-hotcold/sky.npz"
FS = g.FS
DUR_MS = 9500
LO = -1800.0
RX_LLH = (1.344100, 103.820000, 20.0)


def make_sky(seed=21):
    rng = np.random.default_rng(seed)
    t0 = 345_600.0 + float(rng.uniform(0, 80_000))       # a random GPS time of week
    rx = g.geodetic_to_ecef(*RX_LLH)
    vis = g.constellation(t0, rx)
    vis = sorted(vis, key=lambda e: -g.elevation(rx, g.sat_pos(e, t0)))[:9]
    sats = [dict(prn=e["prn"], cn0=float(rng.uniform(40, 47)), eph=e) for e in vis]
    gen = g.IFGen(sats, t0=t0, rx=rx, lo_offset_hz=LO, seed=seed)
    xs = []
    t = time.time()
    for ms in range(DUR_MS):
        q, _ = gen.chunk()
        xs.append(q)
        if ms % 1000 == 0:
            print(f"  generated {ms} ms, {time.time() - t:.0f} s", flush=True)
    x = np.concatenate(xs)
    truth = dict(t0=t0, rx=rx.tolist(), sats=[dict(prn=s["prn"], cn0=s["cn0"], eph=s["eph"],
                  elev=g.elevation(rx, g.sat_pos(s["eph"], t0))) for s in sats])
    np.savez(CACHE, x=x, truth=json.dumps(truth))
    return x, truth


# ---------------------------------------------------------------- acquisition (chip arithmetic)

def acquire(x, n_ms=5, thr=None):
    found = []
    for prn in range(1, 33):
        ca = g.pm(g.ca_code(prn))
        power = np.zeros((len(acq.BINS), acq.BLK))
        for m in range(n_ms):
            s = m * acq.BLK
            code_fft = np.fft.fft(acq.code_pm_abs(ca, s, 2 * acq.BLK), acq.L_FFT)
            for bi, fb in enumerate(acq.BINS):
                I, Q = acq.block_corr(x[s:s + acq.BLK], s, fb, ca, code_fft)
                power[bi] += I.astype(float) ** 2 + Q.astype(float) ** 2
        bi, p = np.unravel_index(np.argmax(power), power.shape)
        stat = power[bi, p] / power.mean()
        if stat > thr:
            # refine Doppler to 100 Hz on the same blocks (the host re-runs 11 bins around the peak)
            best = (0, 0)
            for fr in np.arange(-500, 501, 100) + acq.BINS[bi]:
                pw = 0
                for m in range(n_ms):
                    s = m * acq.BLK
                    code = acq.code_pm_abs(ca, s + p, acq.BLK)
                    k = acq.carrier_k(fr)
                    ph0 = (s * k) & 0xFFFF
                    ci = pa.carrier_sign(ph0, k, acq.BLK, 16384); sq = pa.carrier_sign(ph0, k, acq.BLK, 0)
                    blk = x[s:s + acq.BLK]
                    pw += float(np.sum(blk * ci * code)) ** 2 + float(np.sum(blk * sq * code)) ** 2
                if pw > best[0]:
                    best = (pw, fr)
            found.append(dict(prn=prn, code_offset=int(p), f_bin=float(acq.BINS[bi]), f_fine=float(best[1]), stat=float(stat)))
    return found


# ---------------------------------------------------------------- tracking

class Channel:
    def __init__(self, prn, code_offset, f0, x):
        self.prn = prn
        self.ca = g.pm(g.ca_code(prn))
        self.x = x
        # code phase (chips) at absolute sample 0 from the acquisition offset
        cp0 = ((code_offset) * 0.3125) % 1023
        # advance to the first code epoch after sample 0
        k_nom = 1.023e6 / FS
        n_to_epoch = math.ceil((1023 - cp0) / k_nom)
        self.S = n_to_epoch                                   # start sample of the current epoch
        self.cp = cp0 + n_to_epoch * k_nom - 1023             # chips at sample S (just past 0)
        self.f = f0                                           # carrier Doppler estimate (Hz, incl. LO)
        self.f_int = f0
        self.phase_q = 0                                      # 32-bit carrier NCO phase at S
        self.code_rate = 1.023e6
        self.dll_int = 0.0
        self.epoch = 0
        self.prev = None
        self.log = []                                         # per epoch: S, cp, I_P, Q_P, E, L, f, code_rate

    def step(self):
        # 32-bit NCOs: two PEs each, the low word's carry into the high word through the tag lane
        kc = int(round(self.code_rate / FS * 2 ** 32))
        cp_q = int(round(self.cp * 2 ** 32))
        n = int(-(-(1023 * 2 ** 32 - cp_q) // kc))               # samples to the next epoch
        S = self.S
        if S + n + 2 > len(self.x):
            return False
        x = self.x[S - 1:S + n + 1].astype(np.int64)
        idx = np.arange(-1, n + 1, dtype=np.int64)
        chips = ((cp_q + idx * kc) >> 32) % 1023                  # int64 is exact here (< 2^44)
        code = self.ca[chips]                                   # code for sample S-1 .. S+n
        k = int(round((acq.F_ALIAS + self.f) * 2 ** 32 / FS))
        ph0 = self.phase_q
        phs = (ph0 + k * np.arange(n, dtype=np.int64)) & 0xFFFFFFFF
        ci = 1 - 2 * (((phs + (1 << 30)) & 0xFFFFFFFF) >> 31)    # cos sign: a quarter turn ahead
        sq = 1 - 2 * (phs >> 31)
        xs = x[1:n + 1]
        # x * (cos - j sin): Q takes the negated sine arm, so arg(I + jQ) = received - local phase
        wi, wq = xs * ci, -(xs * sq)
        # prompt: code(n); early: code(n+1); late: code(n-1)
        cP, cE, cL = code[1:n + 1], code[2:n + 2], code[0:n]
        IP, QP = int(wi @ cP), int(wq @ cP)
        IE, QE = int(wi @ cE), int(wq @ cE)
        IL, QL = int(wi @ cL), int(wq @ cL)
        T = n / FS
        # ---- carrier loop (host, float): FLL for the first 300 ms, then Costas PLL
        e_ph = math.atan(QP / IP) / (2 * math.pi) if IP != 0 else 0.0
        if self.prev is not None:
            pI, pQ = self.prev
            cross, dot = pI * QP - pQ * IP, pI * IP + pQ * QP
            e_f = math.atan(cross / dot) / (2 * math.pi * T) if dot != 0 else 0.0
        else:
            e_f = 0.0
        self.prev = (IP, QP)
        if self.epoch < 300:
            self.f_int += 0.1 * e_f
            f_nco = self.f_int
        else:
            bw = 15.0
            w0 = bw / 0.53
            self.f_int += w0 * w0 * T * e_ph
            f_nco = self.f_int + 1.414 * w0 * e_ph
        # ---- code loop: normalised early-minus-late envelope, carrier aided, 2nd order, 2 Hz
        E, L = math.hypot(IE, QE), math.hypot(IL, QL)
        e_c = (1 - 0.3125) * (E - L) / (E + L) if E + L > 0 else 0.0
        w0c = 2.0 / 0.53
        self.dll_int += w0c * w0c * T * e_c
        aid = 1.023e6 * (self.f - LO_EST) / g.F_L1
        self.log.append((S, self.cp, IP, QP, E, L, self.f, self.code_rate, e_ph))
        # ---- advance to the next epoch
        self.phase_q = (ph0 + k * n) & 0xFFFFFFFF                          # exactly the NCO's phase
        self.cp = (cp_q + n * kc - 1023 * 2 ** 32) / 2 ** 32
        self.S = S + n
        self.f = f_nco
        self.code_rate = 1.023e6 + aid + self.dll_int + 1.414 * w0c * e_c
        self.epoch += 1
        return True


LO_EST = 0.0      # the receiver does not know the LO error; carrier aiding includes it and the DLL
                  # integrator absorbs the difference (a common-mode code-rate error)


def bit_sync(ch, start=400, n=1000):
    ip = np.array([r[2] for r in ch.log])
    s = np.sign(ip[start:start + n])
    flips = np.flatnonzero(s[1:] != s[:-1]) + 1 + start
    hist = np.bincount(flips % 20, minlength=20)
    return int(np.argmax(hist)), hist


def decode(ch, edge):
    ip = np.array([r[2] for r in ch.log], float)
    first = edge if edge >= 0 else 0
    while first < 300:
        first += 20
    nb = (len(ip) - first) // 20
    bits = [(0 if ip[first + 20 * i:first + 20 * i + 20].sum() > 0 else 1) for i in range(nb)]
    # try both polarities (Costas ambiguity); preamble + TLM and HOW parity
    for inv in (0, 1):
        b = [v ^ inv for v in bits]
        for i in range(2, len(b) - 60):
            if b[i:i + 8] != g.PREAMBLE:
                continue
            d29s, d30s = b[i - 2], b[i - 1]
            ok1, d1 = g.check_word(b[i:i + 30], d29s, d30s)
            ok2, d2 = g.check_word(b[i + 30:i + 60], b[i + 28], b[i + 29])
            if ok1 and ok2:
                tow_count = int("".join(map(str, d2[:17])), 2)
                sf_id = int("".join(map(str, d2[19:22])), 2)
                t_sf = (tow_count - 1) * 6.0
                return dict(epoch_sf=first + 20 * i, t_sf=t_sf, sf_id=sf_id, inverted=inv, n_bits=nb)
    return None


def t_tx_at(ch, nav, S_meas):
    """transmit time of the sample S_meas from the channel's epoch log"""
    for e in range(len(ch.log) - 1):
        S, cp = ch.log[e][0], ch.log[e][1]
        S2 = ch.log[e + 1][0]
        if S <= S_meas < S2:
            kc = int(round(ch.log[e][7] / FS * 2 ** 32))
            chips = cp + (S_meas - S) * kc / 2 ** 32
            return nav["t_sf"] + (e - nav["epoch_sf"]) * 1e-3 + chips / 1.023e6
    return None


def solve(sats, t_tx, rx_guess=np.zeros(3)):
    """least squares for position and clock (metres); pseudoranges relative to t_rx = max t_tx + 70 ms"""
    t_rx = max(t_tx) + 0.070
    pr = [g.C * (t_rx - t) for t in t_tx]
    p = np.array(rx_guess, float)
    b = 0.0
    for it in range(10):
        H, r = [], []
        for eph, tt, rho in zip(sats, t_tx, pr):
            s = g.sat_pos(eph, tt)
            tau = (rho - b) / g.C
            th = g.OMEGA_E * tau
            s = np.array([math.cos(th) * s[0] + math.sin(th) * s[1], -math.sin(th) * s[0] + math.cos(th) * s[1], s[2]])
            d = np.linalg.norm(s - p)
            H.append(np.r_[(p - s) / d, 1.0])
            r.append(rho - (d + b))
        H, r = np.array(H), np.array(r)
        dx = np.linalg.lstsq(H, r, rcond=None)[0]
        p += dx[:3]; b += dx[3]
        if np.linalg.norm(dx[:3]) < 1e-4:
            break
    Q = np.linalg.inv(H.T @ H)
    return p, b, r, Q


def enu(rx, p):
    lat = math.atan2(rx[2], math.hypot(rx[0], rx[1])); lon = math.atan2(rx[1], rx[0])
    R = np.array([[-math.sin(lon), math.cos(lon), 0],
                  [-math.sin(lat) * math.cos(lon), -math.sin(lat) * math.sin(lon), math.cos(lat)],
                  [math.cos(lat) * math.cos(lon), math.cos(lat) * math.sin(lon), math.sin(lat)]])
    return R @ (p - rx), R


def main():
    t_start = time.time()
    if "--regen" in sys.argv or not os.path.exists(CACHE):
        x, truth = make_sky()
    else:
        z = np.load(CACHE)
        x, truth = z["x"], json.loads(str(z["truth"]))
    rx = np.array(truth["rx"])
    lines = [f"scenario: GPS time {truth['t0']:.3f} s of week, receiver {RX_LLH}, LO offset {LO:+.0f} Hz, "
             f"{len(x)} one-bit samples ({len(x) / FS:.2f} s at {FS / 1e6:.4f} MS/s)"]
    for s in truth["sats"]:
        lines.append(f"  PRN {s['prn']:2d}  elevation {s['elev']:5.1f} deg  C/N0 {s['cn0']:.1f} dB-Hz")
    thr = json.load(open(f"{OUT}/acq_mc.json"))["thr"]["5"] if os.path.exists(f"{OUT}/acq_mc.json") else 3.0
    found = acquire(x, 5, thr)
    true_prns = {s["prn"] for s in truth["sats"]}
    lines.append(f"acquisition (chip arithmetic, N = 5 ms, threshold {thr:.2f} from the Monte Carlo noise runs): "
                 f"found {sorted(f['prn'] for f in found)}; visible {sorted(true_prns)}; "
                 f"false {sorted(f['prn'] for f in found if f['prn'] not in true_prns)}")
    chans = [Channel(f["prn"], f["code_offset"], f["f_fine"], x) for f in found if f["prn"] in true_prns]
    for ch in chans:
        while ch.step():
            pass
    navs = {}
    for ch in chans:
        edge, hist = bit_sync(ch)
        nav = decode(ch, edge)
        ph = np.array([r[8] for r in ch.log[1000:]])
        lines.append(f"  PRN {ch.prn:2d}: {len(ch.log)} epochs tracked, bit edge at epoch mod 20 = {edge} "
                     f"(histogram peak {hist.max()} of {hist.sum()} sign changes), PLL phase error rms {np.sqrt((ph ** 2).mean()) * 360:.1f} deg, "
                     + (f"subframe {nav['sf_id']} found, TOW of its start {nav['t_sf']:.0f} s" if nav else "no subframe decoded"))
        if nav:
            navs[ch.prn] = (ch, nav)
    ephs = {s["prn"]: s["eph"] for s in truth["sats"]}
    # position fixes every 100 ms over the last 1.5 s, all channels with a decoded subframe
    errs, fixes = [], []
    S_end = min((ch.log[-2][0] for ch, _ in navs.values()), default=0)
    for S_meas in range(S_end - int(1.5 * FS), S_end, int(0.1 * FS)):
        prns = [p for p, (ch, nav) in navs.items() if nav["epoch_sf"] < len(ch.log)]
        tt = [t_tx_at(navs[p][0], navs[p][1], S_meas) for p in prns]
        if len(prns) < 4 or any(v is None for v in tt):
            continue
        p, b, res, Q = solve([ephs[q] for q in prns], tt)
        d, R = enu(rx, p)
        # true receive time of this sample for the clock check
        errs.append(d)
        Qe = R @ Q[:3, :3] @ R.T
        fixes.append(dict(S=S_meas, prns=prns, east=d[0], north=d[1], up=d[2], clock_m=b,
                          hdop=float(math.sqrt(Qe[0, 0] + Qe[1, 1])), vdop=float(math.sqrt(Qe[2, 2])),
                          res_rms=float(np.sqrt((res ** 2).mean()))))
    # ranging accuracy against the truth: transmit-time error per satellite, common mode removed
    rerr = {p: [] for p in navs}
    for S_meas in range(S_end - int(1.5 * FS), S_end, int(0.1 * FS)):
        t_true = truth["t0"] + S_meas / FS
        e = {p: g.C * (t_tx_at(navs[p][0], navs[p][1], S_meas) - (t_true - g.light_time(ephs[p], rx, t_true))) for p in navs}
        cm = np.mean(list(e.values()))
        for p in navs:
            rerr[p].append(e[p] - cm)
    for p, v in rerr.items():
        v = np.array(v)
        lines.append(f"  PRN {p:2d} range error (common mode removed): mean {v.mean():+.2f} m, sd {v.std():.2f} m")
    E = np.array(errs)
    if len(E):
        h = np.hypot(E[:, 0], E[:, 1])
        lines.append(f"position: {len(E)} fixes (every 100 ms over the last 1.5 s) from {len(fixes[0]['prns'])} satellites "
                     f"{fixes[0]['prns']}, HDOP {fixes[0]['hdop']:.2f}, VDOP {fixes[0]['vdop']:.2f}")
        lines.append(f"  horizontal error: mean {h.mean():.2f} m, max {h.max():.2f} m; vertical error mean {E[:, 2].mean():+.2f} m, "
                     f"rms {np.sqrt((E[:, 2] ** 2).mean()):.2f} m; mean east/north bias {E[:, 0].mean():+.2f} / {E[:, 1].mean():+.2f} m; "
                     f"range residual rms {np.mean([f['res_rms'] for f in fixes]):.2f} m")
    else:
        lines.append("position: no fix")
    lines.append(f"wall time {time.time() - t_start:.0f} s")
    txt = "\n".join(lines)
    print(txt)
    open(f"{OUT}/fix.txt", "w").write(txt + "\n")
    json.dump(dict(found=found, fixes=fixes), open(f"{OUT}/fix.json", "w"), indent=1, default=float)
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    fig, ax = plt.subplots(3, 1, figsize=(10, 10))
    for ch in chans:
        ip = np.array([r[2] for r in ch.log]); qp = np.array([r[3] for r in ch.log])
        ax[0].plot(np.arange(len(ip)) / 1000, ip, lw=0.4, label=f"PRN {ch.prn}")
        ax[1].plot(np.arange(len(ch.log)) / 1000, [r[6] for r in ch.log], lw=0.8, label=f"PRN {ch.prn}")
    ax[0].set_ylabel("prompt I (integer sum)"); ax[0].set_title("prompt in-phase correlator per code period: navigation bits appear after lock")
    ax[1].set_ylabel("carrier Doppler estimate (Hz)"); ax[1].set_xlabel("time (s)"); ax[1].legend(fontsize=7, ncol=3)
    if len(E):
        ax[2].plot(E[:, 0], E[:, 1], "o")
        ax[2].plot([0], [0], "r*", ms=14)
        ax[2].set_aspect("equal"); ax[2].set_xlabel("east error (m)"); ax[2].set_ylabel("north error (m)")
        ax[2].set_title("position fixes relative to the true antenna position")
    fig.tight_layout(); fig.savefig(f"{OUT}/fix.png", dpi=110)


if __name__ == "__main__":
    main()
