"""Measure the rendered hot/cold audio from the outside and plot the walk.

Checks, all on the rendered 22 kHz stereo signal (not on the controller's intentions):
  - silence between beeps: rms level in dBFS of the gaps (the XOR sigma-delta's A' = 1/2)
  - beep pitch: FFT peak inside every neutral / warmer / colder beep against the planned notes
  - beep period: onsets detected from the envelope against the planned period
  - stereo: left/right rms ratio per beep against the planned pan gains
Writes audio_checks.txt and hotcold.png to RESULTS_DIR, and clips to CLIP_DIR.
Usage: analyse.py RESULTS_DIR AUDIO_NPY CLIP_DIR
"""
import csv, json, math, sys, wave
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from geographiclib.geodesic import Geodesic

F_WAV = 22000
G = Geodesic.WGS84


def load(rdir):
    truth = list(csv.DictReader(open(f"{rdir}/truth.csv")))
    plans = list(csv.DictReader(open(f"{rdir}/plans.csv")))
    meta = json.load(open(f"{rdir}/walk.json"))
    return truth, plans, meta


def clip(audio, t0, t1, path):
    x = audio[int(t0 * F_WAV):int(t1 * F_WAV)]
    pcm = np.clip(x * 0.9 * 32767, -32767, 32767).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(2); w.setsampwidth(2); w.setframerate(F_WAV); w.writeframes(pcm.tobytes())


def main(rdir, npy, cdir):
    truth, plans, meta = load(rdir)
    audio = np.load(npy)
    tlat, tlon = meta["target"]
    out = []
    # ---------------- distance: chip integer vs geodesic of the reported fix, and vs the truth
    derr, dtrue, ts = [], [], []
    assert len(truth) == len(plans), (len(truth), len(plans))
    for tr, p in zip(truth, plans):
        if p["mode"] == "nofix" or p["held"] == "1":
            continue
        g = G.Inverse(float(tr["rep_lat"]), float(tr["rep_lon"]), tlat, tlon)["s12"]
        gt = G.Inverse(float(tr["true_lat"]), float(tr["true_lon"]), tlat, tlon)["s12"]
        dc = int(p["d_cm"]) / 100
        derr.append(dc - g); dtrue.append(dc - gt); ts.append(int(p["fix"]))
    derr = np.array(derr); dtrue = np.array(dtrue)
    out.append(f"distance, integer pipeline vs WGS84 geodesic of the reported (unrounded) fix: max |err| {np.abs(derr).max()*100:.2f} cm over {len(derr)} fixes")
    out.append(f"distance vs the true position (GPS error included): rms {np.sqrt((dtrue**2).mean()):.2f} m, max {np.abs(dtrue).max():.2f} m")
    # ---------------- silence and beeps, per second from the plans
    def envelope(seg):          # 2 ms moving rms of both channels
        e2 = (seg.astype(np.float64) ** 2).mean(axis=1)
        return np.sqrt(np.convolve(e2, np.ones(44) / 44, "same"))
    gaps, pitch_err, ratio_err, n_beeps = [], [], [], 0
    plan_pitch = {"1": (880, 1320), "-1": (440, 330), "0": (660, 660)}
    period_err = []
    for p in plans:
        if p["mode"] != "beep":
            continue
        i = int(p["fix"])
        seg = audio[i * F_WAV:(i + 1) * F_WAV]
        e = envelope(seg)
        on = e > 0.05
        # onsets inside this second
        edges = np.flatnonzero(on[1:] & ~on[:-1]) + 1
        if len(edges) >= 2 and int(p["period_ms"]) < 450:
            period_err.append(np.median(np.diff(edges)) / F_WAV * 1000 - int(p["period_ms"]))
        # gaps: samples at least 10 ms from any 'on' sample
        dil = np.convolve(on.astype(float), np.ones(441), "same") > 0
        if (~dil).sum() > 2000:
            gaps.append(seg[~dil])
        for s0 in edges[:2]:
            blen = int(min(90, int(p["period_ms"]) * 2 // 5) * F_WAV / 1000)
            b = seg[s0:s0 + blen]
            if len(b) < blen or blen < 400:
                continue
            n_beeps += 1
            # first-half note: FFT of the first 40 % of the beep (past the 5 ms ramp)
            h = b[int(0.005 * F_WAV):blen // 2, 0] + b[int(0.005 * F_WAV):blen // 2, 1]
            nf_ = 1 << 16
            spec = np.abs(np.fft.rfft(h * np.hanning(len(h)), nf_))
            fpk = np.argmax(spec[20:]) + 20
            fpk = fpk * F_WAV / nf_
            want = plan_pitch[p["trend"]][0]
            pitch_err.append(fpk / (want) - 1)
            gl, gr = int(p["gain_l"]), int(p["gain_r"])
            rl = np.sqrt((b[:, 0] ** 2).mean()); rr = np.sqrt((b[:, 1] ** 2).mean())
            if gl > 3000 and gr > 3000:
                ratio_err.append(20 * math.log10((rr / rl) / (gr / gl)))
    gaps = np.concatenate(gaps)
    silence_db = 20 * math.log10(np.sqrt((gaps.astype(np.float64) ** 2).mean()) + 1e-12)
    out.append(f"silence between beeps: rms {silence_db:.1f} dBFS over {len(gaps)/F_WAV:.1f} s of gaps")
    pe = np.array(pitch_err) * 1200 / math.log(2)   # cents (approx.)
    out.append(f"beep pitch (first note) vs plan over {n_beeps} beeps: max |err| {np.abs(np.array(pitch_err)).max()*100:.2f} % "
               f"(FFT bin {F_WAV/65536:.2f} Hz; NCO step 3.9 Hz)")
    out.append(f"beep period (< 450 ms) from onsets vs plan: median err {np.median(period_err):.1f} ms, max |err| {np.abs(period_err).max():.1f} ms over {len(period_err)} seconds")
    re = np.array(ratio_err)
    out.append(f"stereo right/left level vs planned pan gains over {len(re)} beeps: median {np.median(re):+.2f} dB, 95 % within {np.percentile(np.abs(re),95):.2f} dB")
    counts = {m: sum(1 for p in plans if p["mode"] == m) for m in ("nofix", "beep", "found")}
    tr = [p["trend"] for p in plans if p["mode"] != "nofix"]
    out.append(f"modes per fix: {counts}; trend warmer/neutral/colder: {tr.count('1')}/{tr.count('0')}/{tr.count('-1')}")
    txt = "\n".join(out)
    print(txt)
    open(f"{rdir}/audio_checks.txt", "w").write(txt + "\n")

    # ---------------- plot
    fig, ax = plt.subplots(4, 1, figsize=(11, 14), gridspec_kw=dict(height_ratios=[1.3, 1, 1, 1]))
    def enu(lat, lon):
        g = G.Inverse(tlat, tlon, lat, lon)
        a = math.radians(g["azi1"]); return g["s12"] * math.sin(a), g["s12"] * math.cos(a)
    T = np.array([enu(float(r["true_lat"]), float(r["true_lon"])) for r in truth])
    R = np.array([enu(float(r["rep_lat"]), float(r["rep_lon"])) for r in truth])
    ax[0].plot(T[:, 0], T[:, 1], lw=1.5, label="true walk", color="#444")
    sc = ax[0].scatter(R[3:, 0], R[3:, 1], s=4, c=np.arange(3, len(R)), cmap="viridis", label="reported fixes (colour = time)")
    ax[0].plot([0], [0], marker="*", ms=16, color="#d62728", ls="", label="cache")
    ax[0].set_aspect("equal"); ax[0].set_xlabel("east (m)"); ax[0].set_ylabel("north (m)")
    ax[0].legend(loc="lower left"); ax[0].set_title("walk around the target (Singapore, 1.3441 N 103.8200 E)")
    fb = [p for p in plans if p["mode"] != "nofix"]
    t = np.array([int(p["fix"]) for p in fb])
    d = np.array([int(p["d_cm"]) / 100 for p in fb])
    trd = np.array([int(p["trend"]) for p in fb])
    ax[1].semilogy(t, d, color="#1f77b4", label="distance (chip integer pipeline)")
    for val, col in ((1, "#ff7f0e"), (-1, "#1f77b4")):
        m = trd == val
        ax[1].fill_between(t, 0.5, 1000, where=m, color=col, alpha=0.15, step="mid",
                           label="warmer" if val == 1 else "colder")
    ax[1].set_ylim(0.5, 800); ax[1].set_ylabel("distance (m)"); ax[1].legend(loc="upper right")
    ax[1].set_title("distance and trend")
    per = np.array([int(p["period_ms"]) if p["mode"] == "beep" else np.nan for p in fb])
    ax[2].plot(t, per, label="beep period (ms)", color="#2ca02c")
    ax2 = ax[2].twinx()
    rel = np.array([(float(p["rel_deg"]) + 180) % 360 - 180 for p in fb])
    ax2.plot(t, rel, ".", ms=2, color="#9467bd", label="target relative to heading (deg)")
    ax2.set_ylabel("relative bearing (deg)"); ax[2].set_ylabel("beep period (ms)")
    ax[2].set_title("beep period (distance) and direction cue (stereo pan)")
    ax[2].legend(loc="upper left"); ax2.legend(loc="upper right")
    x = audio[:, 0].astype(np.float64)
    ax[3].specgram(x, NFFT=1024, Fs=F_WAV, noverlap=512, cmap="magma", vmin=-120)
    ax[3].set_ylim(0, 3000); ax[3].set_xlabel("time (s)"); ax[3].set_ylabel("Hz")
    ax[3].set_title("spectrogram of the rendered left channel (pin -> RC model)")
    fig.tight_layout()
    fig.savefig(f"{rdir}/hotcold.png", dpi=110)
    # ---------------- clips: start (no fix, far, colder), a warmer approach, the arrival
    n = len(audio) / F_WAV
    clip(audio, 0, 30, f"{cdir}/clip1_start_colder.wav")
    warm = [int(p["fix"]) for p in fb if p["trend"] == "1" and int(p["d_cm"]) < 20000]
    w0 = warm[0] if warm else 300
    clip(audio, w0 - 5, w0 + 25, f"{cdir}/clip2_warmer.wav")
    clip(audio, n - 90, n - 40, f"{cdir}/clip3_arrival.wav")
    print("clips at", 0, w0 - 5, n - 90)


if __name__ == "__main__":
    main(*sys.argv[1:])
