# /// script
# requires-python = ">=3.11"
# dependencies = ["pillow"]
# ///
"""After `console_tv.py frames game`: a real-time GIF (one field per frame at 50 Hz, half size) and
a strip of stills at the demo's events.
    uv run stills.py 36 82 150 205 276"""
import pathlib, sys
from PIL import Image

frames = sorted(pathlib.Path("out").glob("game_*.png"))
imgs = [Image.open(p).convert("RGB").resize((384, 240), Image.BILINEAR) for p in frames]
pal = imgs[len(imgs) // 2].quantize(colors=255, method=Image.Quantize.MEDIANCUT)
q = [im.quantize(palette=pal, dither=Image.Dither.NONE) for im in imgs]
q[0].save("out/game.gif", save_all=True, append_images=q[1:], duration=20, loop=0, optimize=True)
print(len(imgs), "frames -> out/game.gif")
picks = [int(a) for a in sys.argv[1:]]
w, h = 768, 480
strip = Image.new("RGB", (w * len(picks) // 2, h // 2))
for i, f in enumerate(picks):
    im = Image.open(f"out/game_{f:03d}.png").convert("RGB")
    im.save(f"out/still_{f:03d}.png")
    strip.paste(im.resize((w // 2, h // 2), Image.BILINEAR), (i * w // 2, 0))
strip.save("out/stills.png")
print("stills:", picks)
