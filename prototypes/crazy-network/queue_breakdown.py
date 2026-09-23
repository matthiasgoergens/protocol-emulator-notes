# /// script
# requires-python = ">=3.11"
# dependencies = ["numpy"]
# ///
"""Why do queue entries fail sheet.py's filter? One reason per entry, first match wins."""
import sys, zlib, pathlib, collections
import numpy as np
for d in sys.argv[1:]:
    c = collections.Counter()
    for p in sorted(pathlib.Path(d).glob("*_f0.pgm")):
        b = p.read_bytes(); a = np.frombuffer(b[b.index(b"\n15\n") + 4:], dtype=np.uint8).reshape(240, 256)
        h = np.bincount(a.ravel(), minlength=16) / a.size
        ent = float(-(h[h > 0] * np.log2(h[h > 0])).sum()); comp = len(zlib.compress(a.tobytes(), 9)) / a.size
        hs = float((a[:, 1:] == a[:, :-1]).mean()); vs = float((a[1:, :] == a[:-1, :]).mean())
        c["flat" if ent < 0.5 else "noise" if comp > 0.45 else "low variety" if ent <= 1.5 else "too simple (comp)" if comp <= 0.03
          else "horizontal stripes" if hs >= 0.97 else "vertical stripes / static rows" if vs >= 0.99 else "in between"] += 1
    print(pathlib.Path(d).name, dict(c.most_common()))
