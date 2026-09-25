# Analysis of the pad runs written by padsim.py / run_all.sh. Run on the host:
#   uv run --with numpy python3 analyse.py > ../results/pads.txt
# Every number printed comes from /var/tmp/fast-eth/pads/<case>-<corner>-<temp>/out.dat.
import glob, os, sys
import numpy as np

ROOT = "/var/tmp/fast-eth/pads"
UI = 8e-9
CORN = {"tt": (1.2, 3.3), "ss": (1.08, 3.0), "ff": (1.32, 3.6)}
ORDER = [(c, t) for c in ("tt", "ss", "ff") for t in (27, 85)]

def load(case, c, t):
    p = f"{ROOT}/{case}-{c}-{t}/out.dat"
    if not os.path.exists(p):
        return None
    with open(p) as f:
        names = f.readline().split()
    d = np.loadtxt(p, skiprows=1)
    if d.ndim < 2 or len(d) < 10:
        return None
    return {n: d[:, i] for i, n in enumerate(names)}

def uniform(t, v, dt=5e-12):
    tt = np.arange(t[0], t[-1], dt)
    return tt, np.interp(tt, t, v)

def crossings(t, v, level, direction=0):
    s = np.sign(v - level)
    idx = np.nonzero(s[:-1] * s[1:] < 0)[0]
    out = []
    for i in idx:
        up = v[i + 1] > v[i]
        if direction and (up != (direction > 0)):
            continue
        out.append((t[i] + (level - v[i]) * (t[i + 1] - t[i]) / (v[i + 1] - v[i]), up))
    return out

def edge_times(t, v, lo, hi):
    """10-90 % rise and fall times of each full transition between lo and hi (absolute levels)."""
    a, b = lo + 0.1 * (hi - lo), lo + 0.9 * (hi - lo)
    rises, falls = [], []
    ca, cb = crossings(t, v, a), crossings(t, v, b)
    for ta, up in ca:
        if up:
            nxt = [x for x, u in cb if u and x > ta and x - ta < 6e-9]
            if nxt: rises.append(nxt[0] - ta)
    for tb, up in cb:
        if not up:
            nxt = [x for x, u in ca if not u and x > tb and x - tb < 6e-9]
            if nxt: falls.append(nxt[0] - tb)
    return rises, falls

def eye(t, v, ref_t, ref_bits, delay, t0=100e-9):
    """Eye of a 2-level signal: for each sampling phase within the UI, eye height = min over 1-bits
    minus max over 0-bits. ref_bits[k] is the bit sent in UI k starting at ref_t; the receive
    signal is delayed by `delay`. Returns (best height, best phase, eye width where height > 0)."""
    hs = []
    phases = np.linspace(0, UI, 81)[:-1]
    for ph in phases:
        ones, zeros = [], []
        for k, b in enumerate(ref_bits):
            ts = ref_t + k * UI + delay + ph
            if ts < t0 or ts > t[-1]:
                continue
            x = np.interp(ts, t, v)
            (ones if b else zeros).append(x)
        hs.append(min(ones) - max(zeros) if ones and zeros else np.nan)
    hs = np.array(hs)
    i = int(np.nanargmax(hs))
    width = (hs > 0).sum() * (phases[1] - phases[0])
    return hs[i], phases[i], width

def bits_from(t, v, level, n, t0=2e-9):
    return [1 if np.interp(t0 + (k + 0.5) * UI, t, v) > level else 0 for k in range(n)]

def jitter_pp(cr, t_ref=2e-9, skip=100e-9):
    """Peak-to-peak spread of crossing times modulo the UI (data-dependent jitter)."""
    ph = np.array([((x - t_ref) % UI) for x, _ in cr if x > skip])
    if len(ph) == 0:
        return np.nan
    # unwrap around the mean
    m = np.angle(np.mean(np.exp(2j * np.pi * ph / UI))) * UI / (2 * np.pi)
    d = ((ph - m + UI / 2) % UI) - UI / 2
    return d.max() - d.min()

def ns(x): return f"{x * 1e9:.2f}"

def toggle():
    print("## Toggle-rate test: square wave per pad into 2 nH + 10 pF, swing at the pin (node o)")
    print("rates are toggles/s (a 62.5 Mt/s toggle = 62.5 MHz edge rate = 31.25 MHz square)\n")
    rates = [62.5, 100, 125, 166.7, 250, 333]
    for drv in ("4mA", "16mA", "30mA"):
        print(f"### sg13g2_IOPadOut{drv}: swing / IOVDD (%)")
        print("| corner | " + " | ".join(f"{r} Mt/s" for r in rates) + " |")
        print("|---" * (len(rates) + 1) + "|")
        for c, tmp in ORDER:
            d = load("toggle", c, tmp)
            if d is None:
                print(f"| {c} {tmp}C | missing |"); continue
            io = CORN[c][1]
            row = []
            for j in range(len(rates)):
                v = d[f"v(o{drv}_{j})"]; tt = d["time"]
                m = tt > 60e-9
                row.append(f"{100 * (v[m].max() - v[m].min()) / io:.0f}")
            print(f"| {c} {tmp}C | " + " | ".join(row) + " |")
        print()

def eyes_cap():
    print("## PRBS7 NRZI at 125 Mbaud, 30 mA pad into 2 nH + C, at the pin")
    print("| load | corner | rise 10-90 (ns) | fall 10-90 (ns) | delay c2p->pin 50% (ns) | DDJ p-p at IOVDD/2 (ns) | eye height (% IOVDD) | eye width (ns) |")
    print("|---|---|---|---|---|---|---|---|")
    for case in ("eye_cap5", "eye_cap10"):
        for c, tmp in ORDER:
            d = load(case, c, tmp)
            if d is None:
                print(f"| {case} | {c} {tmp}C | missing |"); continue
            vdd, io = CORN[c]
            t, v = uniform(d["time"], d["v(o)"])
            _, vc = uniform(d["time"], d["v(c)"])
            r, f = edge_times(t, v, 0, io)
            cc = [x for x, _ in crossings(t, vc, vdd / 2)]
            co = [x for x, _ in crossings(t, v, io / 2)]
            dl = np.median([min((y - x for y in co if y > x), default=np.nan) for x in cc[:40]])
            bits = bits_from(t, vc, vdd / 2, 140)
            h, ph, w = eye(t, v, 2e-9, bits, dl)
            print(f"| {case[4:]} | {c} {tmp}C | {ns(np.mean(r))} ({ns(min(r))}-{ns(max(r))}) | {ns(np.mean(f))} ({ns(min(f))}-{ns(max(f))}) | {ns(dl)} | {ns(jitter_pp(crossings(t, v, io / 2)))} | {100 * h / io:.0f} | {ns(w)} |")
    print()

def eye_sfp():
    print("## SFP transmit input: two 30 mA pads in antiphase, 150 ohm series, 50 ohm lines, AC-coupled 100 ohm differential")
    print("| corner | diff swing p-p (mV) | rise 20-80 (ns) | fall 20-80 (ns) | DDJ p-p at 0 V (ns) | eye height (mV) | eye width (ns) |")
    print("|---|---|---|---|---|---|---|")
    for c, tmp in ORDER:
        d = load("eye_sfp", c, tmp)
        if d is None:
            print(f"| {c} {tmp}C | missing |"); continue
        t, vp = uniform(d["time"], d["v(sp)"]); _, vn = uniform(d["time"], d["v(sn)"])
        v = vp - vn
        m = t > 200e-9
        hi, lo = np.percentile(v[m], 99), np.percentile(v[m], 1)
        a, b = lo + 0.2 * (hi - lo), lo + 0.8 * (hi - lo)
        r, f = [], []
        # 20-80 edges
        rr, ff = edge_times(t, v, lo - (hi - lo) * 0.125 / 0.75 + (hi - lo) * 0.125 / 0.75, hi)
        ca, cb = crossings(t, v, a), crossings(t, v, b)
        for ta, up in ca:
            nxt = [x for x, u in cb if u == up and x > ta and x - ta < 6e-9] if up else []
            if nxt: r.append(nxt[0] - ta)
        for tb, up in cb:
            nxt = [x for x, u in ca if u == up and x > tb and x - tb < 6e-9] if not up else []
            if nxt: f.append(nxt[0] - tb)
        cr = crossings(t, v, 0.0)
        # reference bits: sign at the centre of each UI after the median delay
        _, cp = uniform(d["time"], d["v(op)"])
        bits = bits_from(t, cp, CORN[c][1] / 2, 140)
        co = [x for x, _ in cr]
        cc = [x for x, _ in crossings(t, cp, CORN[c][1] / 2)]
        dl = np.median([min((y - x for y in co if y > x), default=np.nan) for x in cc[20:60]])
        h, ph, w = eye(t, v, 2e-9, bits, dl, t0=200e-9)
        print(f"| {c} {tmp}C | {1000 * (hi - lo):.0f} | {ns(np.mean(r))} | {ns(np.mean(f))} | {ns(jitter_pp(cr, skip=200e-9))} | {1000 * h:.0f} | {ns(w)} |")
    print()

def eye_tx():
    print("## 100BASE-TX MLT-3 by pin pair: 82 ohm series each, 250 ohm across the primary, 1:1 magnetics, 1 m 100 ohm line, 100 ohm")
    print("TP-PMD template (from memory of ANSI X3.263 / 802.3 clause 25, to verify): peak 950-1050 mV, symmetry 98-102 %, rise/fall 3-5 ns, rise/fall symmetry <= 0.5 ns, overshoot <= 5 %, jitter <= 1.4 ns p-p\n")
    print("| corner | +peak (mV) | -peak (mV) | symmetry (%) | overshoot (%) | rise 10-90 (ns) | fall 10-90 (ns) | jitter p-p at +-50 % (ns) | eye height upper/lower (mV) |")
    print("|---|---|---|---|---|---|---|---|---|")
    for c, tmp in ORDER:
        d = load("eye_tx", c, tmp)
        if d is None:
            print(f"| {c} {tmp}C | missing |"); continue
        t, va = uniform(d["time"], d["v(la)"]); _, vb = uniform(d["time"], d["v(lb)"])
        v = va - vb
        io = CORN[c][1]
        _, ca = uniform(d["time"], d["v(oa)"]); _, cb = uniform(d["time"], d["v(ob)"])
        # ideal level per UI from the pin states (A - B) sampled mid-UI, 160 UIs
        lv = [int(np.interp(2e-9 + (k + 0.5) * UI + 3e-9, t, ca) > io / 2) - int(np.interp(2e-9 + (k + 0.5) * UI + 3e-9, t, cb) > io / 2) for k in range(160)]
        m = t > 200e-9
        # settled level: value at 85 % of a UI into runs of >= 2 UIs at the same level
        pos, neg, peaks_p, peaks_n = [], [], [], []
        dl = 5.2e-9  # nominal pin-to-line delay; refined below
        for k in range(1, 159):
            ts = 2e-9 + k * UI + dl
            if ts < 200e-9: continue
            x = np.interp(ts + 0.85 * UI, t, v)
            if lv[k] == 1 and lv[k - 1] == 1: pos.append(x)
            if lv[k] == -1 and lv[k - 1] == -1: neg.append(x)
            seg = v[(t > ts) & (t < ts + UI)]
            if lv[k] == 1 and lv[k - 1] == 0 and len(seg): peaks_p.append(seg.max())
            if lv[k] == -1 and lv[k - 1] == 0 and len(seg): peaks_n.append(seg.min())
        vp, vn = np.median(pos), np.median(neg)
        ov = max((max(peaks_p) - vp) / vp, (min(peaks_n) - vn) / vn) * 100
        r, f = [], []
        for k in range(1, 160):
            if lv[k - 1] == 0 and lv[k] == 1:
                ts = 2e-9 + k * UI + dl - 2e-9
                seg_m = (t > ts) & (t < ts + 7e-9)
                cr1 = crossings(t[seg_m], v[seg_m], 0.1 * vp, 1); cr9 = crossings(t[seg_m], v[seg_m], 0.9 * vp, 1)
                if cr1 and cr9: r.append(cr9[0][0] - cr1[0][0])
            if lv[k - 1] == 1 and lv[k] == 0:
                ts = 2e-9 + k * UI + dl - 2e-9
                seg_m = (t > ts) & (t < ts + 7e-9)
                cr1 = crossings(t[seg_m], v[seg_m], 0.9 * vp, -1); cr9 = crossings(t[seg_m], v[seg_m], 0.1 * vp, -1)
                if cr1 and cr9: f.append(cr9[0][0] - cr1[0][0])
        jp = jitter_pp(crossings(t, v, 0.5 * vp), skip=200e-9)
        jn = jitter_pp(crossings(t, v, 0.5 * vn), skip=200e-9)
        # eye heights at best phase: upper eye between level +1 and 0, lower between 0 and -1
        best_u, best_l = -9, -9
        for ph in np.linspace(0, UI, 41)[:-1]:
            s = {1: [], 0: [], -1: []}
            for k in range(160):
                ts = 2e-9 + k * UI + dl + ph
                if ts < 200e-9: continue
                s[lv[k]].append(np.interp(ts, t, v))
            if s[1] and s[0] and s[-1]:
                best_u = max(best_u, min(s[1]) - max(s[0]))
                best_l = max(best_l, min(s[0]) - max(s[-1]))
        print(f"| {c} {tmp}C | {1000 * vp:.0f} | {1000 * vn:.0f} | {100 * vp / -vn:.1f} | {ov:.1f} | {ns(np.mean(r))} | {ns(np.mean(f))} | {ns(max(jp, jn))} | {1000 * best_u:.0f} / {1000 * best_l:.0f} |")
    print()

def inputs():
    print("## sg13g2_IOPadIn")
    print("DC threshold: pad voltage where p2c crosses VDD/2 (from in_dc)\n")
    print("| corner | threshold (V) |"); print("|---|---|")
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import padsim
    for c, tmp in ORDER:
        try: print(f"| {c} {tmp}C | {padsim.threshold(c, tmp):.3f} |")
        except Exception as e: print(f"| {c} {tmp}C | missing ({e}) |")
    print("\n62.5 MHz input through 50 ohm + 3 pF + 2 nH: p2c duty cycle (ideal 50 %) and pad->p2c delay\n")
    cases = ["in_full", "in_ac_300_0", "in_ac_150_0", "in_ac_75_0"]
    print("| corner | " + " | ".join(cases) + " |"); print("|---" * (len(cases) + 1) + "|")
    for c, tmp in ORDER:
        vdd = CORN[c][0]
        row = []
        for case in cases:
            d = load(case, c, tmp)
            if d is None: row.append("missing"); continue
            t, p = uniform(d["time"], d["v(p2c)"])
            m = t > 50e-9
            duty = (p[m] > vdd / 2).mean() * 100
            swing = p[m].max() - p[m].min()
            _, pad = uniform(d["time"], d["v(pad)"])
            if case == "in_full":
                lvl = CORN[c][1] / 2
            else:
                lvl = padsim.threshold(c, tmp)
            cin = [x for x, u in crossings(t, pad, lvl) if x > 50e-9]
            cout = [x for x, u in crossings(t, p, vdd / 2) if x > 50e-9]
            dls = [min((y - x for y in cout if y > x), default=np.nan) for x in cin]
            dl = np.nanmedian(dls) if dls else np.nan
            ok = swing > 0.9 * vdd
            row.append(f"{duty:.0f} % / {ns(dl)} ns" + ("" if ok else f" (swing {swing:.2f} V)"))
        print(f"| {c} {tmp}C | " + " | ".join(row) + " |")
    print()

if __name__ == "__main__":
    what = sys.argv[1:] or ["toggle", "eyes_cap", "eye_sfp", "eye_tx", "inputs"]
    for w in what:
        globals()[w]()
