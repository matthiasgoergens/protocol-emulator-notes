# /// script
# requires-python = ">=3.11"
# dependencies = ["numpy", "pillow"]
# ///
"""Score the search results and draw contact sheets of the most interesting ones.
Interesting = neither flat nor noise: several palette entries used, compressible but not trivially,
some structure both across and down the picture. Also records how much the picture changes
between field 0 and field 2 (animation)."""
import json, sys, zlib, pathlib
import numpy as np
from PIL import Image, ImageDraw

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

rows = []
for p in sorted(pathlib.Path("out/search").glob("*_f0.pgm")):
    pid = int(p.name[:5])
    a = load(p)
    b = load(str(p).replace("_f0", "_f2"))
    hist = np.bincount(a.ravel(), minlength=16) / a.size
    ent = float(-(hist[hist > 0] * np.log2(hist[hist > 0])).sum())
    comp = len(zlib.compress(a.tobytes(), 9)) / a.size
    hsame = float((a[:, 1:] == a[:, :-1]).mean())
    vsame = float((a[1:, :] == a[:-1, :]).mean())
    change = float((a != b).mean())
    rows.append(dict(id=pid, entropy=round(ent, 2), comp=round(comp, 3), hsame=round(hsame, 3), vsame=round(vsame, 3), change=round(change, 3)))

json.dump(rows, open("out/search_metrics.json", "w"))
def interesting(r):
    return r["entropy"] > 1.5 and 0.03 < r["comp"] < 0.45 and r["hsame"] < 0.97 and r["vsame"] < 0.99
cands = [r for r in rows if interesting(r)]
# score: prefer structure (compressible) with variety (entropy), both directions of structure
for r in cands:
    r["score"] = r["entropy"] * (1 - r["comp"]) * (1.0 - abs(r["hsame"] - r["vsame"]) * 0.5)
cands.sort(key=lambda r: -r["score"])
print(f"{len(rows)} programs, {len(cands)} pass the filter")
print("flat:", sum(r["entropy"] < 0.5 for r in rows), " noise-like (comp > 0.45):", sum(r["comp"] > 0.45 for r in rows))
for page in range(3):
    sel = cands[page * 48:(page + 1) * 48]
    if not sel: break
    sheet = Image.new("RGB", (8 * 132, 6 * 136), (20, 20, 20))
    d = ImageDraw.Draw(sheet)
    for k, r in enumerate(sel):
        im = Image.fromarray(cmap(load(f"out/search/{r['id']:05d}_f0.pgm"))).resize((128, 120), Image.NEAREST)
        x, y = (k % 8) * 132 + 2, (k // 8) * 136 + 2
        sheet.paste(im, (x, y))
        d.text((x + 2, y + 121), f"{r['id']} c{r['change']:.2f}", fill=(230, 230, 230))
    sheet.save(f"out/sheet_{page}.png")
    print("page", page, [r["id"] for r in sel])
