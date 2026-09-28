# /// script
# requires-python = ">=3.11"
# dependencies = ["numpy", "scipy", "pyloudnorm"]
# ///
"""Do real adverts still differ from programmes in the cheap audio cues once loudness is equalised?

Input: the manifest of freely licensed recordings collected under /var/tmp/radio-video/real
(manifest.csv: file, label advert|programme, source, licence, era; WAV, mono, 32 kHz). The audio
itself is not in the repository; results/real_audio_manifest.csv keeps the list with sources.

Per file:
  - integrated loudness (ITU-R BS.1770 via pyloudnorm) as found: were the adverts louder?
  - then normalised to -23 LUFS (EBU R128 / ATSC A/85 style), and on that:
      loudness range, EBU Tech 3342 style: short-term loudness (3 s, 10 Hz), gates at -70 LUFS and
        -20 LU relative, spread between the 10th and 95th percentiles
      crest factor over 3 s windows (peak / RMS, dB): median over the file
      pause fraction: 400 ms blocks more than 20 dB below the file's median block level
Per window (3 s, 1 s hop, the detector's view): crest, and 10 s local loudness range; AUC of each
cue between adverts and programmes, over all windows and per era group.

Normalising the level changes neither crest nor loudness range (both are ratios), so the question
"do they still separate after regulation" is answered by whether they separate at all; the
integrated loudness column shows the size of the level jump regulation removed.

Usage: uv run real_audio.py [manifest]  -> results/real_audio.txt, results/real_audio.json
"""
import csv, json, math, pathlib, sys
import numpy as np
import scipy.io.wavfile as wavfile
import scipy.signal as sg
import pyloudnorm as pyln

HERE = pathlib.Path(__file__).parent
RES = HERE / "results"
BASE = pathlib.Path("/var/tmp/radio-video/real")


def kweight(x, fs):
    """K-weighted signal (BS.1770 pre-filter) via pyloudnorm's filter definitions."""
    m = pyln.Meter(fs)
    y = x.copy()
    for f in m._filters.values():
        y = f.apply_filter(y)
    return y


def short_term(yk, fs, win, hop):
    n, h = int(win * fs), int(hop * fs)
    if len(yk) < n:
        return np.array([])
    c = np.concatenate([[0], np.cumsum(yk ** 2)])
    idx = np.arange(0, len(yk) - n + 1, h)
    ms = (c[idx + n] - c[idx]) / n
    return -0.691 + 10 * np.log10(ms + 1e-12)


def lra(st):
    st = st[st > -70]
    if len(st) < 5:
        return float("nan")
    rel = 10 * np.log10(np.mean(10 ** (st / 10))) - 20
    st = st[st > rel]
    return float(np.percentile(st, 95) - np.percentile(st, 10))


def auc(pos, neg):
    x = np.concatenate([pos, neg]); y = np.concatenate([np.ones(len(pos)), np.zeros(len(neg))])
    ok = np.isfinite(x); x, y = x[ok], y[ok]
    order = np.argsort(x); r = np.empty(len(x)); r[order] = np.arange(1, len(x) + 1)
    n1 = y.sum(); n0 = len(y) - n1
    return float((r[y == 1].sum() - n1 * (n1 + 1) / 2) / (n1 * n0)) if n1 and n0 else float("nan")


def analyse(path, fs_expected=None):
    fs, x = wavfile.read(path)
    x = x.astype(float)
    if x.ndim > 1:
        x = x.mean(axis=1)
    x /= 32768.0
    meter = pyln.Meter(fs)
    L = meter.integrated_loudness(x)
    y = x * 10 ** ((-23 - L) / 20)
    yk = kweight(y, fs)
    st3 = short_term(yk, fs, 3.0, 0.1)
    b4 = short_term(yk, fs, 0.4, 0.1)
    # windows of 3 s, hop 1 s: crest (true peak not needed: sample peak of the unweighted signal)
    n3 = 3 * fs
    crest, loc_lra = [], []
    for i in range(0, len(y) - n3 + 1, fs):
        w = y[i:i + n3]
        rms = math.sqrt(np.mean(w ** 2)) + 1e-12
        crest.append(20 * math.log10(np.abs(w).max() / rms + 1e-12))
        j = i // int(0.1 * fs)
        seg = b4[j: j + 100]                                  # 400 ms blocks over the next 10 s
        loc_lra.append(lra(seg) if len(seg) >= 50 else float("nan"))
    med = np.median(b4[b4 > -70]) if np.any(b4 > -70) else -70
    pause = float(np.mean(b4 < med - 20)) if len(b4) else float("nan")
    return dict(integrated_lufs=round(float(L), 1), lra_lu=round(lra(st3), 1),
                crest_median_db=round(float(np.median(crest)), 1) if crest else None,
                pause_fraction=round(pause, 3), seconds=round(len(x) / fs, 1)), \
        np.array(crest), np.array(loc_lra)


def main():
    man = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else BASE / "manifest.csv"
    rows = list(csv.DictReader(man.open()))
    RES.mkdir(exist_ok=True)
    out = {"files": []}
    win = {"advert": {"crest": [], "lra": []}, "programme": {"crest": [], "lra": []}}
    by_era = {}
    lines = ["Real audio (real_audio.py): freely licensed recordings, each normalised to -23 LUFS before the",
             "dynamics cues are measured. Columns: integrated loudness as found (LUFS), loudness range (LU,",
             "EBU Tech 3342 style), median 3 s crest factor (dB), fraction of 400 ms blocks 20 dB below median.", ""]
    for r in rows:
        if r["label"] not in ("advert", "programme"):
            continue
        p = BASE / "wav" / r["file"]
        if not p.exists():
            continue
        st, crest, loc = analyse(p)
        era = r.get("era", "")
        grp = "pre-1980" if era[:4].isdigit() and int(era[:4]) < 1980 else "1980+"
        out["files"].append(dict(file=r["file"], label=r["label"], era=era, licence=r.get("licence"), **st))
        win[r["label"]]["crest"].append(crest); win[r["label"]]["lra"].append(loc)
        by_era.setdefault(grp, {"advert": {"crest": [], "lra": []}, "programme": {"crest": [], "lra": []}})
        by_era[grp][r["label"]]["crest"].append(crest); by_era[grp][r["label"]]["lra"].append(loc)
        lines.append(f"{r['label']:9s} {era:>6s} {r['file'][:34]:34s} {st['seconds']:7.1f} s  {st['integrated_lufs']:6.1f} LUFS  "
                     f"LRA {st['lra_lu']:5.1f}  crest {st['crest_median_db']}  pauses {st['pause_fraction']:.3f}")
        print(lines[-1], flush=True)
    lines.append("")

    def summarise(name, w):
        res = {}
        for k in ("crest", "lra"):
            a = np.concatenate(w["advert"][k]) if w["advert"][k] else np.array([])
            p = np.concatenate(w["programme"][k]) if w["programme"][k] else np.array([])
            a, p = a[np.isfinite(a)], p[np.isfinite(p)]
            if len(a) and len(p):
                res[k] = dict(auc_programme_higher=round(auc(p, a), 3), advert_median=round(float(np.median(a)), 1),
                              programme_median=round(float(np.median(p)), 1), advert_windows=len(a), programme_windows=len(p))
        lines.append(f"{name}: " + "; ".join(f"{k}: adverts median {v['advert_median']}, programmes {v['programme_median']}, "
                                             f"AUC {v['auc_programme_higher']} ({v['advert_windows']}/{v['programme_windows']} windows)"
                                             for k, v in res.items()))
        return res

    out["windows_all"] = summarise("all eras", win)
    for g, w in sorted(by_era.items()):
        out[f"windows_{g}"] = summarise(g, w)
    # file-level comparison (each file one vote: avoids long files dominating)
    fa = [f for f in out["files"] if f["label"] == "advert"]
    fp = [f for f in out["files"] if f["label"] == "programme"]
    for k in ("integrated_lufs", "lra_lu", "crest_median_db", "pause_fraction"):
        a = np.array([f[k] for f in fa if f[k] is not None], float)
        p = np.array([f[k] for f in fp if f[k] is not None], float)
        if len(a) and len(p):
            lines.append(f"file level {k}: adverts median {np.nanmedian(a):.2f} (n {len(a)}), programmes median "
                         f"{np.nanmedian(p):.2f} (n {len(p)}), AUC programme higher {auc(p, a):.2f}")
    (RES / "real_audio.json").write_text(json.dumps(out, indent=1))
    (RES / "real_audio.txt").write_text("\n".join(lines) + "\n")
    with (RES / "real_audio_manifest.csv").open("w") as f:
        wr = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        wr.writeheader(); wr.writerows(rows)
    print("\n".join(lines[-8:]))


if __name__ == "__main__":
    main()
