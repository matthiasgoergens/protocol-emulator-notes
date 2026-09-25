# /// script
# requires-python = ">=3.11"
# dependencies = ["numpy", "scipy", "pillow"]
# ///
"""Demo B: advert detection from cheap video and audio cues, on synthetic broadcast timelines.

What the chip sees per frame (PAL, 25 frames/s): luma at 160 x 120 from the one-pin delta-sigma
ADC, with the ADC's per-pixel error added as Gaussian noise of the size dsadc.py measured (at
60 MS/s, the worse of the two rates). Audio at 8 kHz from a second one-pin ADC (60 dB SNR measured,
so its noise is negligible for these features and is not added).

Cues, all computable with PE operations (sums, abs, max/min, shifts, compares) and the systolic
matcher:
  video  black frame (grid mean and spread low); cut (mean absolute difference of the 32 x 24
         grid between frames); channel logo (per-pixel EMA of a 24 x 12 corner region, binarised
         against its own mean, correlated with a stored 1-bit template: the matcher's job)
  audio  short-term level (400 ms), crest factor over 3 s (peak / RMS), loudness range over 10 s
         (spread of the 400 ms levels), level relative to a 60 s running average (the jump)

Programme/advert decision: a logistic score over the per-second cues (weights fitted on training
timelines, then fixed: on the chip a weighted sum with shift-add weights), smoothed by an EMA,
with hysteresis. Compared cue sets: audio only, video only, both.

Regimes (the audio is where the regulation question lives):
  legacy        black frames between adverts; adverts 6 dB louder than programme (assumed)
  r128          black frames; every segment normalised to the same integrated level, adverts
                still compressed (lower crest factor and loudness range) -- this is ASSUMED by the
                generator, so it tests the detector, not the premise; real audio is checked in
                real_audio.py
  r128_noblack  as r128 but no black frames between adverts (as on many channels)
  r128_mild     as r128, but adverts compressed only as much as the real ones measured by
                real_audio.py (median 3 s crest factor about 14 dB against 16 dB for programmes,
                instead of 11 dB); r128_mild_noblack likewise without black frames

Usage:  uv run advert.py         (writes results/advert.{json,txt}, out/advert_*.png)
"""
import json, math, pathlib, sys, time
import numpy as np
import scipy.ndimage as nd
import scipy.signal as sg
from PIL import Image, ImageDraw, ImageFont

HERE = pathlib.Path(__file__).parent
RES = HERE / "results"
OUT = HERE / "out"

W, H = 160, 120
FPS = 25
FA = 8000                  # audio rate for the features
SPF = FA // FPS            # audio samples per frame
SIGMA_PIX = 0.06           # ADC error per pixel in luma units (dsadc.py: 60 MS/s, see README)
LOGO_BOX = (W - 30, 4, W - 6, 16)     # x0, y0, x1, y1 of the corner region (24 x 12)


def logo_mask():
    im = Image.new("L", (24, 12), 0)
    d = ImageDraw.Draw(im)
    d.text((1, 0), "TT1", fill=255, font=ImageFont.load_default())
    m = np.asarray(im) > 100
    return m


LOGO = logo_mask()


# ---------------------------------------------------------------------------------------------
# timeline

def timeline(rng, minutes, black):
    """List of segments: dict(label 0 programme / 1 break, kind, frames, ...)."""
    segs = []
    total = 0
    target = minutes * 60 * FPS
    first = True
    while total < target:
        # programme segment 6-12 min, possibly opening with 30 s of logo-less titles
        pm = rng.uniform(6, 12) * 60 * FPS
        # programme style: talk (speech with pauses), drama (speech over an uncompressed score),
        # music (a music programme, as compressed as any advert: the audio confounder)
        style = rng.choice(["talk", "drama", "music"], p=[0.5, 0.35, 0.15])
        if first or rng.random() < 0.3:
            segs.append(dict(label=0, kind="titles", frames=int(30 * FPS), style=style))
        first = False
        f = 0
        while f < pm:
            if rng.random() < 0.05:      # an action sequence: 15-25 s of fast cuts
                n = int(rng.uniform(15, 25) * FPS)
                segs.append(dict(label=0, kind="action", frames=n, style=style)); f += n
            n = int(np.clip(rng.lognormal(math.log(5.0), 0.6), 1.5, 20) * FPS)
            segs.append(dict(label=0, kind="prog", frames=n, style=style)); f += n
        total += f
        # break: 3-6 adverts, sometimes a channel promo carrying the logo
        nads = rng.integers(3, 7)
        items = [("ad", int(rng.choice([10, 20, 30, 30, 40]) * FPS)) for _ in range(nads)]
        if rng.random() < 0.3:
            items.insert(rng.integers(0, len(items) + 1), ("promo", int(rng.uniform(5, 10) * FPS)))
        for kind, n in items:
            if black:
                segs.append(dict(label=1, kind="black", frames=5))
            # a quarter of adverts are dialogue-led, with natural pauses and little compression
            st = "dialogue" if rng.random() < 0.25 else "compressed"
            segs.append(dict(label=1, kind=kind, frames=n, style=st))
            total += n
        if black:
            segs.append(dict(label=1, kind="black", frames=5))
    return segs


# ---------------------------------------------------------------------------------------------
# video

class Shot:
    def __init__(self, rng, kind):
        self.kind = kind
        fast = kind in ("ad", "promo", "action")
        tex = nd.gaussian_filter(rng.standard_normal((H * 2, W * 2)), rng.uniform(4, 12))
        tex /= tex.std() + 1e-9
        if kind == "prog" and rng.random() < 0.1:
            mean, con = rng.uniform(0.08, 0.15), 0.05        # a dark scene (not black)
        elif fast and kind != "action":
            mean, con = rng.uniform(0.4, 0.7), rng.uniform(0.18, 0.32)
        else:
            mean, con = rng.uniform(0.28, 0.55), rng.uniform(0.08, 0.22)
        self.tex = np.clip(mean + con * tex, 0, 1)
        sp = rng.uniform(0.5, 3.0) if fast else rng.uniform(0.0, 1.0)
        ang = rng.uniform(0, 2 * np.pi)
        self.v = np.array([np.cos(ang), np.sin(ang)]) * sp
        self.p = np.array([rng.uniform(0, W), rng.uniform(0, H)])
        nobj = rng.integers(2, 5) if fast else rng.integers(1, 4)
        self.obj = [dict(c=np.array([rng.uniform(0, W), rng.uniform(0, H)]),
                         v=rng.normal(0, 2.5 if fast else 0.8, 2),
                         r=rng.uniform(6, 25, 2), y=rng.uniform(0.1, 0.95)) for _ in range(nobj)]
        if kind == "ad" and rng.random() < 0.2:    # a static bright graphic where the logo would be
            self.obj.append(dict(c=np.array([W - 18.0, 10.0]), v=np.zeros(2), r=np.array([10.0, 6.0]), y=0.95))

    def frame(self, t, yy, xx):
        ox, oy = (self.p + self.v * t) % np.array([W, H])
        ox, oy = int(ox), int(oy)
        img = self.tex[oy:oy + H, ox:ox + W].copy()
        for o in self.obj:
            c = o["c"] + o["v"] * t
            c = np.abs((c + np.array([W, H])) % (2 * np.array([W, H])) - np.array([W, H]))
            m = ((xx - c[0]) / o["r"][0]) ** 2 + ((yy - c[1]) / o["r"][1]) ** 2 < 1
            img[m] = o["y"]
        return img


def packshot(rng):
    img = np.full((H, W), rng.uniform(0.75, 0.9))
    x0, y0 = rng.integers(20, 60), rng.integers(30, 60)
    img[y0:y0 + 30, x0:x0 + 70] = rng.uniform(0.05, 0.3)
    img[100:110, 20:140] = 0.2
    return img


def blend_logo(img):
    x0, y0, x1, y1 = LOGO_BOX
    reg = img[y0:y1, x0:x1]
    reg[LOGO] = 0.5 * reg[LOGO] + 0.5 * 0.92
    return img


class VideoFeatures:
    """Per-frame chip features."""

    def __init__(self):
        self.prev = None
        self.ema = None
        tm = LOGO.astype(np.int64)
        dil = nd.binary_dilation(LOGO, iterations=2)
        self.pos = LOGO
        self.neg = dil & ~LOGO             # the matcher's mask: logo pixels and a ring around them

    def __call__(self, img):
        g = img.reshape(24, 5, 32, 5).mean(axis=(1, 3))       # 32 x 24 grid (5 x 5 pixel cells)
        mean, spread = g.mean(), np.abs(g - g.mean()).mean()   # abs deviation: no multiplier
        cut = 0.0 if self.prev is None else np.abs(g - self.prev).mean()
        self.prev = g
        x0, y0, x1, y1 = LOGO_BOX
        reg = img[y0:y1, x0:x1]
        self.ema = reg.copy() if self.ema is None else self.ema + (reg - self.ema) / 8   # EMA, k = 3
        b = self.ema > self.ema.mean() + 0.04
        score = b[self.pos].mean() - b[self.neg].mean()        # matches on logo minus hits on ring
        return mean, spread, cut, score


# ---------------------------------------------------------------------------------------------
# audio

def one_pole(x, fc, fs=FA):
    a = math.exp(-2 * math.pi * fc / fs)
    return sg.lfilter([1 - a], [1, -a], x)


def speech(rng, n):
    """Speech-like: band-limited noise, 4 Hz syllables, word gaps and sentence pauses, speaker level
    changes every few seconds."""
    car = sg.lfilter(*sg.butter(2, [300, 3000], "bandpass", fs=FA), rng.standard_normal(n))
    t = np.arange(n) / FA
    syl = np.abs(np.sin(2 * np.pi * rng.uniform(3, 5) * t + rng.uniform(0, 6))) ** 1.5
    env = np.ones(n)
    i = 0
    while i < n:
        talk = int(rng.uniform(1.0, 4.0) * FA)
        pause = int((rng.uniform(0.3, 1.5) if rng.random() < 0.4 else rng.uniform(0.08, 0.25)) * FA)
        env[i:i + talk] = 10 ** (rng.normal(0, 4) / 20)
        env[i + talk:i + talk + pause] = 0.02
        i += talk + pause
    env = one_pole(env, 30)
    return car * syl * env


def music(rng, n, compressed):
    t = np.arange(n) / FA
    x = np.zeros(n)
    for _ in range(4):
        f = rng.uniform(110, 880)
        x += np.sin(2 * np.pi * f * t) * rng.uniform(0.2, 1) + 0.3 * np.sin(4 * np.pi * f * t)
    beat = rng.uniform(1.5, 2.5)
    env = np.exp(-((t * beat) % 1.0) * rng.uniform(3, 8))
    x *= 0.4 + env
    if not compressed:
        x *= 10 ** (one_pole(rng.normal(0, 6, n), 0.3) / 20)
    return x


def compress(x, ratio=8.0, thr_db=-20.0):
    """A fast broadcast-style compressor/limiter on the signal's envelope."""
    env = np.sqrt(one_pole(x ** 2, 20)) + 1e-9
    lev = 20 * np.log10(env / np.sqrt(np.mean(x ** 2)))
    over = np.maximum(lev - thr_db, 0)
    gain_db = -over * (1 - 1 / ratio)
    y = x * 10 ** (gain_db / 20)
    pk = np.quantile(np.abs(y), 0.999)
    return np.clip(y, -pk, pk)


MILD = (1.25, 1.0)      # compressor ratios (compressed, dialogue adverts) in the r128_mild regime


def seg_audio(rng, kind, n, regime, style=None):
    if kind == "black":
        return rng.standard_normal(n) * 1e-4
    if kind in ("prog", "titles", "action"):
        sp = speech(rng, n)
        if style == "music":
            m = music(rng, n, True)
            x = compress(m / np.std(m) + 0.3 * sp / np.std(sp))
        elif style == "drama" or kind == "titles":
            m = music(rng, n, False)
            x = sp / np.std(sp) + 0.5 * m / np.std(m)
        else:
            x = sp
        level_db = -23.0
    else:
        sp = speech(rng, n)
        m = music(rng, n, style != "dialogue")
        mild = regime.endswith("mild")        # adverts compressed only as much as real ones measured
        if style == "dialogue":
            x = compress(sp / np.std(sp) + 0.3 * m / np.std(m), ratio=MILD[1] if mild else 2.0)
        else:
            x = compress(sp / np.std(sp) + 0.7 * m / np.std(m), ratio=MILD[0] if mild else 8.0)
        level_db = -17.0 if regime == "legacy" else -23.0
    rms = np.sqrt(np.mean(x ** 2)) + 1e-12
    return x / rms * 10 ** (level_db / 20)


class AudioFeatures:
    """Per 100 ms block: mean square and peak. Per second: 400 ms level, 3 s crest factor, 10 s
    loudness range (95th - 10th percentile of 400 ms levels), level against a 60 s EMA."""

    def __init__(self):
        self.ms = []
        self.pk = []
        self.l400 = []
        self.ema60 = None

    def second(self, x):
        b = x.reshape(10, -1)
        self.ms.extend((b ** 2).mean(axis=1))
        self.pk.extend(np.abs(b).max(axis=1))
        ms = np.array(self.ms[-30:])
        pk = np.array(self.pk[-30:])
        l400 = [10 * math.log10(np.mean(self.ms[-(i + 4):len(self.ms) - i]) + 1e-12) for i in range(0, 10, 2)]
        self.l400.extend(l400)
        l400s = np.array(self.l400[-25:])
        l3 = 10 * math.log10(ms.mean() + 1e-12)
        crest = 20 * math.log10(pk.max() + 1e-9) - l3
        gated = l400s[l400s > l400s.max() - 20]           # relative gate, as EBU LRA does
        lra = np.percentile(gated, 95) - np.percentile(gated, 10)
        self.ema60 = l3 if self.ema60 is None else self.ema60 + (l3 - self.ema60) / 60
        return l3, crest, lra, l3 - self.ema60


# ---------------------------------------------------------------------------------------------

def simulate(seed, minutes, black, regimes=("legacy", "r128", "r128_mild"), keep_frames=False):
    rng = np.random.default_rng(seed)
    segs = timeline(rng, minutes, black)
    yy, xx = np.mgrid[0:H, 0:W]
    vf = VideoFeatures()
    per_frame = []
    labels = []
    kinds = []
    samples = {}
    arng = {r: np.random.default_rng(seed * 1000 + 7) for r in regimes}
    audio = {r: [] for r in regimes}
    for s in segs:
        n = s["frames"]
        for r in regimes:
            audio[r].append(seg_audio(arng[r], s["kind"], n * SPF, r, s.get("style")))
        if s["kind"] == "black":
            shots = None
        elif s["kind"] in ("ad", "promo"):
            shots = []
            f = 0
            while f < n - int(1.5 * FPS):
                m = int(np.clip(rng.lognormal(math.log(1.5), 0.5), 0.4, 4) * FPS)
                m = min(m, n - int(1.5 * FPS) - f)
                shots.append((Shot(rng, s["kind"]), m)); f += m
            shots.append((None, n - f))                       # packshot at the end
        elif s["kind"] == "action":
            shots = []
            f = 0
            while f < n:
                m = min(int(rng.uniform(0.6, 1.6) * FPS), n - f)
                shots.append((Shot(rng, "action"), m)); f += m
        else:
            shots = [(Shot(rng, "prog"), n)]
        logo = s["kind"] in ("prog", "action", "promo")
        if shots is None:
            frames = (np.full((H, W), 0.02) for _ in range(n))
        else:
            def gen(shots=shots):
                for sh, m in shots:
                    ps = packshot(rng) if sh is None else None
                    for t in range(m):
                        yield ps.copy() if sh is None else sh.frame(t, yy, xx)
            frames = gen()
        for img in frames:
            if logo:
                img = blend_logo(img)
            if keep_frames and s["kind"] not in samples and len(per_frame) > 50:
                samples[s["kind"]] = img.copy()
            noisy = img + rng.normal(0, SIGMA_PIX, img.shape)
            per_frame.append(vf(noisy))
            labels.append(s["label"])
            kinds.append(s["kind"])
    per_frame = np.array(per_frame)
    labels = np.array(labels)
    nsec = len(labels) // FPS
    # per-second video features
    pf = per_frame[: nsec * FPS].reshape(nsec, FPS, 4)
    blackf = ((pf[:, :, 0] < 0.08) & (pf[:, :, 1] < 0.03)).sum(axis=1)
    cuts = (pf[:, :, 2] > 0.06).sum(axis=1)
    vid = dict(logo=pf[:, :, 3].mean(axis=1), luma=pf[:, :, 0].mean(axis=1),
               spread=pf[:, :, 1].mean(axis=1), black=blackf.astype(float), cuts=cuts.astype(float))
    # recent-history versions (what a sequencer thread would keep as counters)
    def window_sum(x, w):
        c = np.concatenate([[0], np.cumsum(x)])
        i = np.arange(1, len(x) + 1)
        return c[i] - c[np.maximum(i - w, 0)]
    vid["black3"] = (window_sum(blackf, 3) > 0).astype(float)
    vid["cuts5"] = window_sum(cuts, 5).astype(float)
    vid["logo3"] = window_sum(vid["logo"], 3) / 3
    aud = {}
    for r in regimes:
        a = np.concatenate(audio[r])[: nsec * FA]
        af = AudioFeatures()
        feats = np.array([af.second(a[i * FA:(i + 1) * FA]) for i in range(nsec)])
        aud[r] = dict(level=feats[:, 0], crest=feats[:, 1], lra=feats[:, 2], jump=feats[:, 3])
    lab = labels[: nsec * FPS].reshape(nsec, FPS).mean(axis=1) > 0.5
    return dict(vid=vid, aud=aud, label=lab.astype(int), segs=segs, samples=samples)


CUESETS = {
    "audio": ["crest", "lra", "jump", "level"],
    "video": ["logo3", "black3", "cuts5", "spread", "luma"],
    "both": ["crest", "lra", "jump", "level", "logo3", "black3", "cuts5", "spread", "luma"],
}


def features(sim, regime, names):
    cols = []
    for k in names:
        cols.append(sim["aud"][regime][k] if k in sim["aud"][regime] else sim["vid"][k])
    return np.stack(cols, 1)


def fit_logistic(X, y, l2=1e-2, iters=300):
    mu, sd = X.mean(0), X.std(0) + 1e-9
    Z = (X - mu) / sd
    Z = np.hstack([Z, np.ones((len(Z), 1))])
    w = np.zeros(Z.shape[1])
    for _ in range(iters):                                  # Newton / IRLS
        p = 1 / (1 + np.exp(-Z @ w))
        g = Z.T @ (p - y) + l2 * w
        Hs = (Z * (p * (1 - p))[:, None]).T @ Z + l2 * np.eye(len(w))
        w -= np.linalg.solve(Hs, g)
    return mu, sd, w


def decide(X, model, tau=3.0, up=0.7, down=0.3):
    mu, sd, w = model
    Z = np.hstack([(X - mu) / sd, np.ones((len(X), 1))])
    p = 1 / (1 + np.exp(-Z @ w))
    s = np.zeros(len(p))
    e = p[0]
    st = 0
    for i in range(len(p)):
        e += (p[i] - e) / tau
        if st == 0 and e > up:
            st = 1
        elif st == 1 and e < down:
            st = 0
        s[i] = st
    return s.astype(int), p


def evaluate(state, label):
    """Delay per true boundary (seconds until the detector switches the same way, within 90 s),
    and false switches (detector transitions not matched to a true boundary)."""
    tb = np.flatnonzero(np.diff(label) != 0) + 1
    db = np.flatnonzero(np.diff(state) != 0) + 1
    used = set()
    delays = {"to_ad": [], "to_prog": []}
    missed = 0
    for b in tb:
        direction = label[b]
        cand = [d for d in db if d not in used and b - 10 <= d <= b + 90 and state[d] == direction]
        if cand:
            d = cand[0]
            used.add(d)
            delays["to_ad" if direction == 1 else "to_prog"].append(int(d - b))
        else:
            missed += 1
    false = len([d for d in db if d not in used])
    hours = len(label) / 3600
    return dict(acc=round(float(np.mean(state == label)), 4), boundaries=int(len(tb)), missed=missed,
                delay_to_ad_median=float(np.median(delays["to_ad"])) if delays["to_ad"] else None,
                delay_to_ad_max=int(max(delays["to_ad"])) if delays["to_ad"] else None,
                delay_to_prog_median=float(np.median(delays["to_prog"])) if delays["to_prog"] else None,
                delay_to_prog_max=int(max(delays["to_prog"])) if delays["to_prog"] else None,
                false_switches=false, false_per_hour=round(false / hours, 2), hours=round(hours, 2))


def main(n_train=3, n_test=3, minutes=40):
    if len(sys.argv) > 1:                       # smoke test: advert.py N_TRAIN N_TEST MINUTES
        n_train, n_test, minutes = (int(a) for a in sys.argv[1:4])
    RES.mkdir(exist_ok=True); OUT.mkdir(exist_ok=True)
    t0 = time.time()
    sims = {}
    for black in (True, False):
        for seed in range(n_train + n_test):
            sims[(black, seed)] = simulate(seed, minutes, black, keep_frames=(seed == 0 and black))
            print(f"simulated seed {seed} black {black}: {len(sims[(black, seed)]['label'])} s, "
                  f"{time.time() - t0:.0f} s wall", flush=True)
    regimes = [("legacy", True, "legacy"), ("r128", True, "r128"), ("r128_noblack", False, "r128"),
               ("r128_mild", True, "r128_mild"), ("r128_mild_noblack", False, "r128_mild")]
    out = {}
    states = {}
    lines = ["Demo B advert detection (advert.py). Synthetic timelines, %d train and %d test seeds of %d min."
             % (n_train, n_test, minutes),
             "Delays in seconds from the true boundary to the detector's switch (median / max);",
             "false = detector switches not matched to a true boundary.", ""]
    for rname, black, aregime in regimes:
        for cs, names in CUESETS.items():
            Xtr = np.vstack([features(sims[(black, s)], aregime, names) for s in range(n_train)])
            ytr = np.concatenate([sims[(black, s)]["label"] for s in range(n_train)])
            model = fit_logistic(Xtr, ytr)
            ev = []
            for s in range(n_train, n_train + n_test):
                X = features(sims[(black, s)], aregime, names)
                st, _ = decide(X, model)
                if s == n_train:
                    states[(rname, cs)] = st
                ev.append(evaluate(st, sims[(black, s)]["label"]))
            agg = dict(acc=round(float(np.mean([e["acc"] for e in ev])), 4),
                       boundaries=sum(e["boundaries"] for e in ev), missed=sum(e["missed"] for e in ev),
                       false_switches=sum(e["false_switches"] for e in ev),
                       false_per_hour=round(sum(e["false_switches"] for e in ev) / sum(e["hours"] for e in ev), 2),
                       delay_to_ad_median=[e["delay_to_ad_median"] for e in ev],
                       delay_to_ad_max=[e["delay_to_ad_max"] for e in ev],
                       delay_to_prog_median=[e["delay_to_prog_median"] for e in ev],
                       delay_to_prog_max=[e["delay_to_prog_max"] for e in ev],
                       weights=dict(zip(names + ["bias"], [round(float(x), 3) for x in model[2]])))
            out[f"{rname}/{cs}"] = agg
            lines.append(f"{rname:13s} {cs:6s} acc {agg['acc']:.3f}  boundaries {agg['boundaries']:3d} missed {agg['missed']:2d}  "
                         f"false {agg['false_switches']:2d} ({agg['false_per_hour']:.2f}/h)  "
                         f"to advert {agg['delay_to_ad_median']} max {agg['delay_to_ad_max']}  "
                         f"to programme {agg['delay_to_prog_median']} max {agg['delay_to_prog_max']}")
            print(lines[-1], flush=True)
    # single-cue separability: per-second AUC of each cue on the test seeds
    lines.append("")
    lines.append("Per-second separability of each cue on test seeds (AUC; 0.5 = none, 1 or 0 = perfect):")
    for rname, black, aregime in regimes:
        row = []
        for k in ["crest", "lra", "jump", "level", "logo3", "black3", "cuts5", "spread", "luma"]:
            x = np.concatenate([features(sims[(black, s)], aregime, [k])[:, 0] for s in range(n_train, n_train + n_test)])
            y = np.concatenate([sims[(black, s)]["label"] for s in range(n_train, n_train + n_test)])
            row.append(f"{k} {auc(x, y):.2f}")
        lines.append(f"  {rname:13s} " + "  ".join(row))
    out["seconds"] = round(time.time() - t0)
    (RES / "advert.json").write_text(json.dumps(out, indent=1))
    (RES / "advert.txt").write_text("\n".join(lines) + "\n")
    print("\n".join(lines))
    # pictures: sample frames and a timeline
    sm = sims[(True, 0)]["samples"]
    for k, img in sm.items():
        Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8)).resize((W * 3, H * 3), Image.NEAREST) \
            .save(OUT / f"advert_frame_{k}.png")
    np.savez_compressed(RES / "advert_test_seed.npz", **{f"{k}": v for k, v in sims[(True, n_train)]["vid"].items()},
                        **{f"aud_{r}_{k}": v for r in ("legacy", "r128", "r128_mild") for k, v in sims[(True, n_train)]["aud"][r].items()},
                        label=sims[(True, n_train)]["label"])
    np.savez_compressed(RES / "advert_states.npz",
                        **{f"label_{rname}": sims[(black, n_train)]["label"] for rname, black, _ in regimes},
                        **{f"{rname}_{cs}": st for (rname, cs), st in states.items()})
    for rname, black, aregime in regimes:
        rows = []
        for cs, names in CUESETS.items():
            rows.append((cs, states[(rname, cs)]))
        plot_timeline(sims[(black, n_train)]["label"], rows, OUT / f"advert_timeline_{rname}.png")


def auc(x, y):
    order = np.argsort(x)
    r = np.empty(len(x)); r[order] = np.arange(1, len(x) + 1)
    n1 = y.sum(); n0 = len(y) - n1
    return (r[y == 1].sum() - n1 * (n1 + 1) / 2) / (n1 * n0)


def plot_timeline(label, rows, path, minutes=30):
    """Truth and detector states over the first minutes of a test timeline, one pixel per 2 s."""
    L = min(minutes * 60, len(label))
    im = Image.new("RGB", (L // 2 + 110, 18 * (len(rows) + 1) + 20), "white")
    d = ImageDraw.Draw(im)
    for r, (name, st) in enumerate([("truth", label)] + rows):
        y = 4 + 18 * r
        d.text((2, y), name, fill="black")
        for i in range(0, L, 2):
            if st[i]:
                d.line([(100 + i // 2, y), (100 + i // 2, y + 12)], fill=(200, 60, 60))
    y = 4 + 18 * (len(rows) + 1)
    for m in range(0, minutes + 1, 5):
        d.text((100 + m * 30, y), f"{m} min", fill="black")
    im.save(path)


if __name__ == "__main__":
    main()
