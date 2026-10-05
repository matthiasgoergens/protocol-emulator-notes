"""End-to-end analysis: host words -> bit-exact OCaml model of the PE configurations -> pin and
reconstruction-filter model -> audio-band metrics and WAV files.

Usage: analyse.py tones | impair | music | all
Results go to ../results/ (text) and ../results/wav/ (audio).
"""
import os
import sys
import numpy as np
import dac_common as dc
import signals as sg

RES = os.path.join(dc.HERE, "..", "results")
WAV = os.path.join(RES, "wav")

# Full scale per order: the host maps 0 dBFS (CD 32767) to this word amplitude. Chosen from
# results/levels.txt (see README): a few dB below the level where S/(THD+N) collapses.
FS_WORD = {"o2": None, "o3": None, "o4": None}


def load_fs():
    import json
    with open(os.path.join(RES, "fullscale.json")) as f:
        FS_WORD.update(json.load(f))


def run(order, l, r, steps, tag):
    os.makedirs(dc.SCRATCH, exist_ok=True)
    wp = os.path.join(dc.SCRATCH, f"{tag}.words")
    dc.write_words(wp, l, r)
    prefix = os.path.join(dc.SCRATCH, tag)
    dc.render(order, wp, prefix, steps)
    n = len(l) * steps
    return dc.read_bits(prefix + ".L.bits", n), dc.read_bits(prefix + ".R.bits", n)


def host(mode, x_cd, order):
    if mode == "A":
        return sg.host_mode_a(x_cd, FS_WORD[order]), dc.STEPS_A
    return sg.host_mode_b(x_cd, FS_WORD[order]), dc.STEPS_B


def tone_set(order, mode, imps, f0=997.0):
    """THD+N at -1 dBFS, -20 dBFS; dynamic range (AES17: THD+N at -60 dBFS, + 60); idle noise.
    One render per level; the impairments are applied to the same bitstreams."""
    rng = np.random.default_rng(5)
    out = {}
    for lv in [-1.0, -20.0, -60.0, None]:
        dur = 1.3
        x = sg.tone(f0, lv, dur, dc.FS_A) if lv is not None else np.zeros(int(dur * dc.FS_A))
        x_cd = sg.to_cd(x, rng)
        w, steps = host(mode, x_cd, order)
        bl, _ = run(order, w, w, steps, f"tone_{order}_{mode}_{lv}")
        for imp in imps:
            _, yd, fsd = dc.analogue(bl, imp)
            seg = yd[int(0.25 * fsd) : int(0.25 * fsd) + 65536 * 1]
            key = (imp.label(), lv)
            if lv is None:
                out[key] = (dc.band_noise(seg, fsd), dc.band_noise(seg, fsd, weight=True))
            else:
                out[key] = dc.tone_metrics(seg, fsd, f0) + (dc.tone_metrics(seg, fsd, f0, weight=True)[1],)
    return out


def summarise(out, imp):
    lab = imp.label()
    s1, n1, h1, n1a = out[(lab, -1.0)]
    s20, n20, _, _ = out[(lab, -20.0)]
    s60, n60, _, n60a = out[(lab, -60.0)]
    nz, nza = out[(lab, None)]
    fs_pow = s1 * 10 ** (1 / 10)                 # a 0 dBFS sine's mean square
    return {
        "thdn_-1": 10 * np.log10(n1 / s1),
        "thdn_-20": 10 * np.log10(n20 / s20),
        "dr": 10 * np.log10(s60 / n60) + 60,
        "dr_a": 10 * np.log10(s60 / n60a) + 60,
        "snr_idle": 10 * np.log10(fs_pow / nz),
        "snr_idle_a": 10 * np.log10(fs_pow / nza),
        "h2": h1[0], "h3": h1[1],
    }


def fmt(name, d):
    return (f"{name:<44} THD+N(-1 dBFS) {d['thdn_-1']:7.1f} dB  THD+N(-20) {d['thdn_-20']:7.1f}  "
            f"DR {d['dr']:6.1f} ({d['dr_a']:6.1f} A)  SNR idle {d['snr_idle']:6.1f} ({d['snr_idle_a']:6.1f} A)  "
            f"H2 {d['h2']:6.1f} H3 {d['h3']:6.1f}")


def tones():
    lines = ["Ideal pin and filter; 997 Hz; 20 Hz-20 kHz; DR per AES17 (THD+N at -60 dBFS + 60); "
             "SNR idle = 0 dBFS sine power over the noise with digital silence in; (A) A-weighted."]
    for order in ["o2", "o3", "o4"]:
        for mode in ["A", "B"]:
            out = tone_set(order, mode, [dc.Impair()])
            lines.append(fmt(f"{order} mode {mode} ({'44.1 kHz link' if mode == 'A' else 'host 4x + NS'})", summarise(out, dc.Impair())))
            print(lines[-1], flush=True)
    with open(os.path.join(RES, "tones.txt"), "w") as f:
        f.write("\n".join(lines) + "\n")


def impairment_list():
    imps = [dc.Impair()]
    for sj in [10e-12, 30e-12, 100e-12, 300e-12, 1e-9]:
        imps.append(dc.Impair(sj=sj))
    for de in [50e-12, 200e-12, 1e-9]:
        imps.append(dc.Impair(delta=de))
    for sv in [1e-6, 10e-6, 100e-6]:
        imps.append(dc.Impair(sv_inband=sv))
    # shared rail with 8 fast pads: 0.4 V p-p bounce (fast-ethernet pad study), the audio edges
    # moved by kd per volt; 1 ps/mV is an assumed delay sensitivity of the output driver
    imps.append(dc.Impair(kpads=8, bmax=0.2, kd=1e-9))
    imps.append(dc.Impair(kpads=8, bmax=0.2, kd=0.3e-9))
    # the same impairments on a complementary pin pair (differential) and as return-to-zero
    for mode in [1, 2]:
        imps.append(dc.Impair(delta=200e-12, mode=mode))
        imps.append(dc.Impair(sj=100e-12, mode=mode))
        imps.append(dc.Impair(sv_inband=10e-6, mode=mode))
    # "realistic quiet": 30 ps clock jitter, 100 ps asymmetry, 3 uV supply
    imps.append(dc.Impair(sj=30e-12, delta=100e-12, sv_inband=3e-6))
    # "realistic shared": the same plus the shared rail
    imps.append(dc.Impair(sj=30e-12, delta=100e-12, sv_inband=3e-6, kpads=8, bmax=0.2, kd=1e-9))
    return imps


def impair():
    lines = ["Impairments (see dac_common.Impair); same bitstreams for every row of an order."]
    for order, mode in [("o3", "B"), ("o2", "B"), ("o4", "B")]:
        imps = impairment_list()
        out = tone_set(order, mode, imps)
        lines.append(f"== {order} mode {mode}")
        for imp in imps:
            lines.append(fmt(imp.label(), summarise(out, imp)))
            print(lines[-1], flush=True)
    with open(os.path.join(RES, "impairments.txt"), "w") as f:
        f.write("\n".join(lines) + "\n")


def music():
    os.makedirs(WAV, exist_ok=True)
    L, R = sg.music(6.0)
    lines = []
    # the source itself, for reference
    from scipy.signal import resample_poly
    dc.write_wav(os.path.join(WAV, "source_44k1.wav"), L, R, 44100)
    quiet = dc.Impair(sj=30e-12, delta=100e-12, sv_inband=3e-6)
    shared = dc.Impair(sj=30e-12, delta=100e-12, sv_inband=3e-6, kpads=8, bmax=0.2, kd=1e-9)
    cases = [("o2", "B", [("ideal", dc.Impair())]), ("o3", "A", [("ideal", dc.Impair())]),
             ("o3", "B", [("ideal", dc.Impair()), ("quietrail", quiet), ("sharedrail", shared)]),
             ("o4", "B", [("ideal", dc.Impair())])]
    for order, mode, imps in cases:
        wl, steps = host(mode, L, order)
        wr, _ = host(mode, R, order)
        bl, br = run(order, wl, wr, steps, f"music_{order}_{mode}")
        for short, imp in imps:
            _, yl, fsd = dc.analogue(bl, imp)
            _, yr, _ = dc.analogue(br, dc.Impair(**{**imp.__dict__, "seed": imp.seed + 100}))
            # to 48 kHz for listening: 93,750 -> 48,000 is 128/250
            l48 = resample_poly(yl, 128, 250)
            r48 = resample_poly(yr, 128, 250)
            name = f"music_{order}_mode{mode}_{short}.wav"
            dc.write_wav(os.path.join(WAV, name), l48, r48, 48000)
            lines.append(f"{order} mode {mode} {imp.label():<60} -> wav/{name}")
            print(lines[-1], flush=True)
    # underruns: 8 gaps of 20 ms at random places. The chip holds the last frame (what the pump
    # does); the alternative substitutes zeros. Click measure, per gap edge: the peak of the
    # output high-passed above 4 kHz within +-1 ms of the edge, in dB re the same measure on the
    # gapless output at the same place in the music (0 dB: the edge adds nothing audible above
    # the music's own transients there).
    from scipy import signal as ss
    rng = np.random.default_rng(21)
    n_gap = int(0.02 * dc.FS_A)
    starts = np.sort(rng.choice(np.arange(int(0.5 * dc.FS_A), int(5.0 * dc.FS_A)), 8, replace=False))
    hpf = ss.butter(4, 4000, "high", fs=dc.FM / 64, output="sos")
    w0, steps0 = host("A", L, "o3")
    b0, _ = run("o3", w0, w0, steps0, "underrun_none")
    _, y0, fsd0 = dc.analogue(b0, dc.Impair())
    hp0 = ss.sosfilt(hpf, y0)
    ms = int(0.001 * fsd0)
    for policy in ["hold", "zero"]:
        Lu, Ru, gaps, prev = [], [], [], 0
        shift = 0
        for st in starts:
            Lu.append(L[prev:st]); Ru.append(R[prev:st])
            Lu.append(np.full(n_gap, L[st - 1] if policy == "hold" else 0.0))
            Ru.append(np.full(n_gap, R[st - 1] if policy == "hold" else 0.0))
            gaps.append(st + shift)
            shift += n_gap
            prev = st
        Lu.append(L[prev:]); Ru.append(R[prev:])
        Lu, Ru = np.concatenate(Lu), np.concatenate(Ru)
        wl, steps = host("A", Lu, "o3")
        wr, _ = host("A", Ru, "o3")
        bl, br = run("o3", wl, wr, steps, f"underrun_{policy}")
        _, yl, fsd = dc.analogue(bl, dc.Impair())
        _, yr, _ = dc.analogue(br, dc.Impair())
        dc.write_wav(os.path.join(WAV, f"underrun_{policy}_o3_modeA.wav"), resample_poly(yl, 128, 250), resample_poly(yr, 128, 250), 48000)
        hp = ss.sosfilt(hpf, yl)
        clicks = []
        for st, g in zip(starts, gaps):
            ref = np.max(np.abs(hp0[int(st / dc.FS_A * fsd) - ms : int(st / dc.FS_A * fsd) + ms]))
            for e in [g, g + n_gap]:
                c = int(e / dc.FS_A * fsd)
                clicks.append(20 * np.log10(np.max(np.abs(hp[c - ms : c + ms])) / ref))
        lines.append(f"underrun policy {policy}: 8 gaps of 20 ms, 16 edges; high-passed (>4 kHz) peak within 1 ms of an edge, "
                     f"dB re the gapless output there: median {np.median(clicks):+.1f}, worst {np.max(clicks):+.1f} -> wav/underrun_{policy}_o3_modeA.wav")
        print(lines[-1], flush=True)
    with open(os.path.join(RES, "music.txt"), "w") as f:
        f.write("\n".join(lines) + "\n")


if __name__ == "__main__":
    load_fs()
    what = sys.argv[1] if len(sys.argv) > 1 else "all"
    if what in ("tones", "all"):
        tones()
    if what in ("impair", "all"):
        impair()
    if what in ("music", "all"):
        music()
