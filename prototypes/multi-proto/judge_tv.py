# /// script
# requires-python = ">=3.11"
# dependencies = ["numpy", "scipy", "pillow"]
# ///
"""Judge a simulated composite waveform with the independent software TV.

The decoder is ../composite-video/tv.py, imported unmodified; only its sample rate is set to our
clock (17 x fsc). It finds syncs itself, locks to each line's burst and demodulates chroma; it knows
nothing of the generator. The judge then samples each 8-pixel block of each displayed line at its
centre, classifies the decoded colour to the nearest palette reference, and compares with what the
sender put in the frames (lines whose frame was corrupted or filtered must come out black).

usage: uv run judge_tv.py WAVE.f32 EXPECT.txt [PNG]
"""
import sys, pathlib
import numpy as np
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent / "composite-video"))
import tv  # noqa: E402

FCLK = 17 * 315e6 / 88
tv.FS = FCLK
S = tv.STD["NTSC"]


def load_expect(path):
    pal, lines, geo = {}, {}, {}
    for ln in open(path):
        f = ln.split()
        if not f or f[0].startswith("#"):
            continue
        if f[0] == "P":
            pal[int(f[1])] = np.array([float(x) for x in f[2:5]])
        elif f[0] == "L":
            lines[int(f[1])] = (f[2], [int(x) for x in f[3:11]])
        elif f[0] == "G":
            geo = {f[i]: float(f[i + 1]) for i in range(1, len(f), 2)}
    return pal, lines, geo


def line_periods(comp):
    """Sync-to-sync intervals in clocks, from the 1 MHz low-passed waveform as a TV's sync
    separator sees it (normal hsyncs only: low for 3..6.5 us)."""
    rs = tv.lowpass(comp, 1.0e6, 255)
    thr = S["blank"] / 2
    low = rs < thr
    falls = np.flatnonzero(low[1:] & ~low[:-1]) + 1
    rises = np.flatnonzero(~low[1:] & low[:-1]) + 1
    starts = []
    for e in falls:
        after = rises[rises > e]
        if len(after) and 3e-6 < (after[0] - e) / FCLK < 6.5e-6:
            frac = (rs[e - 1] - thr) / (rs[e - 1] - rs[e])
            starts.append(e - 1 + frac)
    return np.diff(np.array(starts))


def main():
    wave, expect = sys.argv[1], sys.argv[2]
    png = sys.argv[3] if len(sys.argv) > 3 else None
    comp = np.fromfile(wave, dtype="<f4").astype(float)
    pal, lines, geo = load_expect(expect)
    img = tv.decode(tv.lowpass(comp, S["recon"], 401), S)
    w = img.shape[1]
    keys = sorted(pal)
    refs = np.stack([pal[k] for k in keys])
    good = total = 0
    wrong_lines = set()
    confusions = {}
    for r in range(img.shape[0]):
        src = r // 2
        if src not in lines:
            continue
        kind, blocks = lines[src]
        for b in range(8):
            t = (geo["play_offset_clocks"] + (8 * b + 4) * geo["pix_clocks"]) / FCLK
            col = (t - S["active_start"]) / S["active_len"] * w - 0.5
            c0 = int(round(col))
            rgb = img[r, max(0, c0 - 8):c0 + 9].mean(axis=0)
            got = keys[int(np.argmin(((refs - rgb) ** 2).sum(axis=1)))]
            want = blocks[b] if kind == "ok" else 0
            total += 1
            if got == want:
                good += 1
            else:
                wrong_lines.add(src)
                confusions[(want, got)] = confusions.get((want, got), 0) + 1
    per = line_periods(comp)
    vals, counts = np.unique(np.round(per).astype(int), return_counts=True)
    hist = ", ".join(f"{v}:{c}" for v, c in zip(vals, counts))
    print(f"decoded {img.shape[0]} lines; blocks correct {good} of {total}; source lines with an error: "
          f"{sorted(wrong_lines)[:12]}{' ...' if len(wrong_lines) > 12 else ''} ({len(wrong_lines)})")
    if confusions:
        top = sorted(confusions.items(), key=lambda kv: -kv[1])[:6]
        print("  most frequent confusions (sent -> decoded): " + ", ".join(f"{a}->{b} x{n}" for (a, b), n in top))
    print(f"  line periods (clocks: count): {hist}")
    if png:
        from PIL import Image
        Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8)).resize((768, 480), Image.NEAREST).save(png)
        print(f"  picture: {png}")


if __name__ == "__main__":
    main()
