# /// script
# requires-python = ">=3.11"
# dependencies = ["numpy", "pillow"]
# ///
"""Colour the reference-model previews (out/prev_*.idx) with the palette measured through the
software TV (results/palette.json), as PNGs and a GIF. A design aid only: the real pictures come
from the chip's pins through the TV."""
import json, pathlib, sys
import numpy as np
from PIL import Image
pal = json.load(open("results/palette.json"))
lut = {}
for line in open("out/prev_lut.txt"):
    i, h, l, s = map(int, line.split())
    rgb = np.array(pal[f"{h if s else 0},{l}"])
    if s == 1:  # one chroma pin: half saturation
        grey = np.array(pal[f"0,{l}"]); rgb = (rgb + grey) / 2
    lut[i] = rgb
table = np.array([lut.get(i, [0, 0, 0]) for i in range(64)])
frames = []
for p in sorted(pathlib.Path("out").glob("prev_*.idx")):
    idx = np.frombuffer(p.read_bytes(), dtype=np.uint8).reshape(240, 256)
    img = Image.fromarray((table[idx] * 255).astype(np.uint8)).resize((512, 480), Image.NEAREST)
    img.save(p.with_suffix(".png")); frames.append(img)
frames[0].save("out/preview.gif", save_all=True, append_images=frames[1:], duration=int(sys.argv[1]) if len(sys.argv) > 1 else 40, loop=0)
print(len(frames), "frames")
