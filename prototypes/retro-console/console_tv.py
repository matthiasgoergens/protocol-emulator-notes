# /// script
# requires-python = ">=3.11"
# dependencies = ["numpy", "scipy", "pillow"]
# ///
"""Turn the console chip's per-clock pin dumps into composite video (resistor-DAC model) and decode
them with the independent software TV from ../composite-video/tv.py."""
import sys, json, pathlib
import numpy as np
from PIL import Image
sys.path.insert(0, str(pathlib.Path(__file__).parent.parent / "composite-video"))
import tv

STANDARD = "NTSC" if "--ntsc" in sys.argv else "PAL"
if STANDARD == "NTSC":
    FS = 16 * 315e6 / 88
    STD = dict(line=3640 / FS, lines=262, fsc=FS / 16, sync=269 / FS, burst_start=304 / FS, burst_cycles=9,
               active_start=10.9e-6, active_len=52.6e-6, blank=4 / 14, black=4 / 14, white=1.0,
               first_active=22, n_active=240, vsync_lines=3, burst_amp=2 / 14, luma_bw=4.2e6, recon=4.8e6, pal=False)
    VIS_START, PIXC, FIRST_VIS, NVIS, HUES = 722, 11, 30, 224, 16
else:
    FS = 12 * 4.43361875e6
    STD = dict(line=3405 / FS, lines=312, fsc=FS / 12, sync=250 / FS, burst_start=298 / FS, burst_cycles=10,
               active_start=10.5e-6, active_len=52.0e-6, blank=4 / 14, black=4 / 14, white=1.0,
               first_active=23, n_active=288, vsync_lines=3, burst_amp=2 / 14, luma_bw=5.0e6, recon=6.0e6, pal=True)
    VIS_START, PIXC, FIRST_VIS, NVIS, HUES = 662, 10, 40, 240, 13
tv.FS = FS
A = 1.57   # chroma square-wave amplitude in DAC units: fundamental 4A/pi = 2 units = 20 IRE burst


def composite(path):
    b = np.frombuffer(pathlib.Path(path).read_bytes(), dtype=np.uint8).astype(float)
    code = b.astype(int) & 15
    val = (b.astype(int) >> 4) & 1
    oe1 = (b.astype(int) >> 5) & 1
    oe2 = (b.astype(int) >> 6) & 1
    sq = np.where(val == 1, A, -A)
    return (code + sq * oe1 + sq * oe2) / 14.0


def decode(path):
    comp = composite(path)
    return tv.decode(tv.lowpass(comp, STD["recon"], 401), STD)


def to_png(img, path, h=480):
    Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8)).resize((img.shape[1], h), Image.NEAREST).save(path)


if __name__ == "__main__":
    mode = [a for a in sys.argv[1:] if not a.startswith("--")][0]
    if mode == "palette":
        img = decode("out/palette_000.bin")
        to_png(img, "out/palette.png")
        # sample block centres: 16 hues across, 11 lumas down (visible lines 30..253 of the field)
        h, w, _ = img.shape
        pal = {}
        for hue in range(HUES):
            for luma in range(11):
                line = FIRST_VIS + (luma * NVIS) // 11 + 10 - STD["first_active"]
                col = int(((VIS_START + PIXC * (hue * 16 + 8)) - STD["active_start"] * FS) / (STD["active_len"] * FS) * w)
                pal[f"{hue},{luma}"] = [round(float(c), 3) for c in img[line, col]]
        pathlib.Path("out/palette.json").write_text(json.dumps(pal))
        for hue in range(HUES):
            print(hue, " ".join("#%02x%02x%02x" % tuple(int(255 * c) for c in pal[f"{hue},{l}"]) for l in (3, 6, 9)))
    elif mode == "frames":
        prefix = [a for a in sys.argv[1:] if not a.startswith("--")][1] if len([a for a in sys.argv[1:] if not a.startswith("--")]) > 1 else "frame"
        paths = sorted(pathlib.Path("out").glob(prefix + "_*.bin"))
        frames = []
        for p in paths:
            img = decode(p)
            to_png(img, p.with_suffix(".png"))
            frames.append(Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8)).resize((640, 400), Image.BILINEAR))
            print(p.name, flush=True)
        frames[0].save(f"out/{prefix}.gif", save_all=True, append_images=frames[1:], duration=33, loop=0)
