# /// script
# requires-python = ">=3.11"
# dependencies = ["numpy", "scipy", "pillow"]
# ///
"""Judge a simulated composite waveform pixel by pixel against an expected screen.

The decoder is ../composite-video/tv.py, unmodified, at our clock (17 x fsc); it decodes the last
field in the capture. For every active line and each of its 64 pixels, the decoded colour at the
pixel's centre is classified to the nearest palette reference and compared with the expected
palette index, which the simulation's reference model wrote (S lines).

usage: uv run judge_screen.py WAVE.f32 EXPECT.txt [PNG]
"""
import sys, pathlib
import numpy as np
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent / "composite-video"))
import tv  # noqa: E402

FCLK = 17 * 315e6 / 88
tv.FS = FCLK
S = tv.STD["NTSC"]


def main():
    wave, expect = sys.argv[1], sys.argv[2]
    png = sys.argv[3] if len(sys.argv) > 3 else None
    pal, rows, geo = {}, {}, {}
    for ln in open(expect):
        f = ln.split()
        if f[0] == "P":
            pal[int(f[1])] = np.array([float(x) for x in f[2:5]])
        elif f[0] == "S":
            rows[int(f[1])] = [int(x) for x in f[2:]]
        elif f[0] == "G":
            geo = {f[i]: float(f[i + 1]) for i in range(1, len(f), 2)}
    comp = np.fromfile(wave, dtype="<f4").astype(float)
    img = tv.decode(tv.lowpass(comp, S["recon"], 401), S)
    w = img.shape[1]
    keys = sorted(pal)
    refs = np.stack([pal[k] for k in keys])
    good = total = 0
    bad_by_colour = {}
    bad_lines = set()
    for r in range(img.shape[0]):
        if r not in rows:
            continue
        for x, want in enumerate(rows[r]):
            t = (geo["play_offset_clocks"] + (x + 0.5) * geo["pix_clocks"]) / FCLK
            c0 = int(round((t - S["active_start"]) / S["active_len"] * w - 0.5))
            rgb = img[r, max(0, c0 - 2):c0 + 3].mean(axis=0)
            got = keys[int(np.argmin(((refs - rgb) ** 2).sum(axis=1)))]
            total += 1
            if got == want:
                good += 1
            else:
                bad_by_colour[(want, got)] = bad_by_colour.get((want, got), 0) + 1
                bad_lines.add(r)
    print(f"pixels correct {good} of {total} ({100.0 * good / total:.2f} %); lines with an error: {len(bad_lines)}")
    if bad_by_colour:
        top = sorted(bad_by_colour.items(), key=lambda kv: -kv[1])[:8]
        print("  most frequent confusions (expected -> decoded): " + ", ".join(f"{a}->{b} x{n}" for (a, b), n in top))
    if png:
        from PIL import Image
        Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8)).resize((768, 480), Image.NEAREST).save(png)
        print(f"  picture: {png}")


if __name__ == "__main__":
    main()
