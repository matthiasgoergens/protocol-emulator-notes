# /// script
# requires-python = ">=3.11"
# dependencies = ["numpy", "pillow"]
# ///
"""Apply sheet.py's filter (flat / noise / in between) to a fuzzing queue directory, and draw a
contact sheet of the in-between entries. Usage: uv run queue_eval.py out/fuzz_<mode>_<seed>"""
import sys, zlib, pathlib
import numpy as np
from PIL import Image, ImageDraw
# same definitions as sheet.py (copied: sheet.py runs on import)
def load(p):
    b = pathlib.Path(p).read_bytes()
    hdr_end = b.index(b"\n15\n") + 4
    return np.frombuffer(b[hdr_end:], dtype=np.uint8).reshape(240, 256)

def cmap(img):
    # false colour: a smooth hue wheel over the 16 palette indices
    t = img.astype(float) / 15.0
    r = 0.5 + 0.5 * np.cos(2 * np.pi * (t + 0.00))
    g = 0.5 + 0.5 * np.cos(2 * np.pi * (t + 0.33))
    b = 0.5 + 0.5 * np.cos(2 * np.pi * (t + 0.67))
    return (np.stack([r, g, b], -1) * 255).astype(np.uint8)

def interesting(r):
    return r["entropy"] > 1.5 and 0.03 < r["comp"] < 0.45 and r["hsame"] < 0.97 and r["vsame"] < 0.99

d = pathlib.Path(sys.argv[1])
rows = []
for p in sorted(d.glob("*_f0.pgm")):
    a = load(p); b = load(str(p).replace("_f0", "_f2"))
    hist = np.bincount(a.ravel(), minlength=16) / a.size
    ent = float(-(hist[hist > 0] * np.log2(hist[hist > 0])).sum())
    comp = len(zlib.compress(a.tobytes(), 9)) / a.size
    rows.append(dict(id=p.name[:5], entropy=ent, comp=comp, hsame=float((a[:, 1:] == a[:, :-1]).mean()),
                     vsame=float((a[1:, :] == a[:-1, :]).mean()), change=float((a != b).mean())))
good = [r for r in rows if interesting(r)]
noise = sum(r["comp"] > 0.45 for r in rows); flat = sum(r["entropy"] < 0.5 for r in rows)
print(f"{d.name}: {len(rows)} entries, {len(good)} in between ({100 * len(good) / max(1, len(rows)):.0f} %), {noise} noise, {flat} flat")
sel = good[:48]
if sel:
    sheet = Image.new("RGB", (8 * 132, ((len(sel) + 7) // 8) * 136), (20, 20, 20))
    dr = ImageDraw.Draw(sheet)
    for k, r in enumerate(sel):
        im = Image.fromarray(cmap(load(d / f"{r['id']}_f0.pgm"))).resize((128, 120), Image.NEAREST)
        x, y = (k % 8) * 132 + 2, (k // 8) * 136 + 2
        sheet.paste(im, (x, y)); dr.text((x + 2, y + 121), f"{r['id']} c{r['change']:.2f}", fill=(230, 230, 230))
    sheet.save(d / "sheet.png")
