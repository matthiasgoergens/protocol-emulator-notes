# /// script
# requires-python = ">=3.11"
# dependencies = ["numpy", "pillow"]
# ///
"""Comparison maps in the style of static-sorting-visualisation: for a found program, run many
random permutations and count, for every pair of values (a, b), how often a comparator compared
them. Also checks the lower-bound argument behind the diagonal: every pair of rank-adjacent
values must be compared directly on every input, or the network could not tell them apart.

Usage: uv run viz.py out/<topology>_n16.log [...]; writes out/<topology>_map.png"""
import json, sys, pathlib
import numpy as np
from PIL import Image, ImageDraw

rng = np.random.default_rng(1500)
tiles = []
for path in sys.argv[1:]:
    rows = [json.loads(l) for l in open(path) if l.strip()]
    sat = [r for r in rows if r["status"] == "sat"]
    if not sat: continue
    r = min(sat, key=lambda r: r["depth"])
    n, edges, prog = r["n"], r["edges"], r["program"]
    counts = np.zeros((n, n))
    adjacent_always = True
    trials = 20000
    for _ in range(trials):
        v = rng.permutation(n)
        seen = set()
        for layer in prog:
            for e, ori in layer:
                a, b = edges[e]
                lo, hi = min(v[a], v[b]), max(v[a], v[b])
                counts[lo, hi] += 1; seen.add((lo, hi))
                v[a], v[b] = (lo, hi) if ori else (hi, lo)
        assert len(set(np.argsort(v))) == n
        if not all((k, k + 1) in seen for k in range(n - 1)): adjacent_always = False
    # the output order the host reads: position of rank k
    frac = counts / trials
    img = (255 * (1 - np.clip(frac, 0, 1))).astype(np.uint8)
    im = Image.fromarray(img).resize((16 * n, 16 * n), Image.NEAREST).convert("RGB")
    d = ImageDraw.Draw(im)
    label = f"{r['topology']}: depth {r['depth']}, {sum(len(l) for l in prog)} comparators"
    tile = Image.new("RGB", (16 * n, 16 * n + 30), (255, 255, 255)); tile.paste(im, (0, 30))
    ImageDraw.Draw(tile).text((4, 8), label, fill=(0, 0, 0))
    tile.save(f"out/{r['topology']}_map.png")
    tiles.append(tile)
    print(label, "| rank-adjacent pairs compared on every input:", adjacent_always,
          "| mean comparisons per value pair off the diagonal:", round(float(frac[np.triu_indices(n, 2)].mean()), 3))
if tiles:
    sheet = Image.new("RGB", (sum(t.width for t in tiles) + 10 * len(tiles), tiles[0].height), (255, 255, 255))
    x = 0
    for t in tiles: sheet.paste(t, (x, 0)); x += t.width + 10
    sheet.save("out/maps.png")
