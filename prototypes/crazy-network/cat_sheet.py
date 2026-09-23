# /// script
# requires-python = ">=3.11"
# dependencies = ["numpy", "pillow"]
# ///
"""Contact sheet of a random sample of one breakdown category. Usage: cat_sheet.py DIR CATEGORY OUT"""
import sys, zlib, pathlib, random
import numpy as np
from PIL import Image
d, want, out = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3]
def load(p):
    b = p.read_bytes(); return np.frombuffer(b[b.index(b"\n15\n") + 4:], dtype=np.uint8).reshape(240, 256)
def cat(a):
    h = np.bincount(a.ravel(), minlength=16) / a.size
    ent = float(-(h[h > 0] * np.log2(h[h > 0])).sum()); comp = len(zlib.compress(a.tobytes(), 9)) / a.size
    hs = float((a[:, 1:] == a[:, :-1]).mean()); vs = float((a[1:, :] == a[:-1, :]).mean())
    return ("flat" if ent < 0.5 else "noise" if comp > 0.45 else "low" if ent <= 1.5 else "simple" if comp <= 0.03
            else "hstripes" if hs >= 0.97 else "vstripes" if vs >= 0.99 else "between")
ps = [p for p in sorted(d.glob("*_f0.pgm")) if cat(load(p)) == want]
random.Random(0).shuffle(ps); ps = ps[:32]
t = np.arange(16) / 15.0
lut = (np.stack([0.5 + 0.5 * np.cos(2 * np.pi * (t + o)) for o in (0, .33, .67)], -1) * 255).astype(np.uint8)
sheet = Image.new("RGB", (8 * 130, 4 * 122), (20, 20, 20))
for k, p in enumerate(ps):
    sheet.paste(Image.fromarray(lut[load(p)]).resize((128, 120)), ((k % 8) * 130, (k // 8) * 122))
sheet.save(out); print(len(ps), "shown")
