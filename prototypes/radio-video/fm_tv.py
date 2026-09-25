# /// script
# requires-python = ">=3.11"
# dependencies = ["numpy", "scipy", "pillow"]
# ///
"""Demo A's picture: a band waterfall, the audio as an oscilloscope trace and the RDS text, drawn
as a 640 x 480 frame and then passed through the composite-video path of ../composite-video/tv.py
(PAL encoder, two-pin sigma-delta output at 60 MS/s, the software TV) so the PNG shows what a TV
would display.

The waterfall comes from a model of a scanner channel: a second NCO and nibble correlator stepping
across the band in 100 kHz steps, integrating |I|+|Q| of the correlator output over a 50 us dwell per
step (a CIC1 dump), on the one-bit samples of the crowded-band scenario ('multi', target 20 dB
below the strongest station). The audio and RDS come from fm_rx.py's PE receiver on that scenario.

Usage: uv run fm_tv.py   -> out/fm_tv_source.png, out/fm_tv_PAL.png, results/fm_tv.json
"""
import json, math, pathlib, sys
import numpy as np
from PIL import Image, ImageDraw, ImageFont

HERE = pathlib.Path(__file__).parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE.parent / "composite-video"))
import fm_rx as F

OUT = HERE / "out"
RES = HERE / "results"
F0, F1, STEP = 87.5e6, 108e6, 100e3
DWELL = 12000                              # samples (50 us at 240 MS/s), a multiple of 4


def scanner(world, rows):
    """Channel power in dB per 100 kHz step, one sweep per row."""
    freqs = np.arange(F0, F1, STEP)
    per_sweep = len(freqs) * DWELL
    out = np.zeros((rows, len(freqs)))
    n_needed = rows * per_sweep
    buf = np.zeros(0, bool)
    k = 0
    pos = 0
    for r in range(rows):
        for j, f in enumerate(freqs):
            while len(buf) - pos < DWELL:
                buf = np.concatenate([buf[pos:], world.chunk(k) > 0]); pos = 0; k += 1
            bits = buf[pos:pos + DWELL]; pos += DWELL
            kk = int(round(f / F.FS * 65536)) & 0xFFFF
            n = np.arange(DWELL, dtype=np.int64)
            ph = (n * kk) & 0xFFFF
            cn = (ph >> 15) ^ ((ph >> 14) & 1)
            sn = ph >> 15
            b = bits.astype(np.int64)
            cI = (b ^ cn).reshape(-1, 4).sum(axis=1) - 2
            cQ = (1 - (b ^ sn)).reshape(-1, 4).sum(axis=1) - 2
            # CIC1 dumps every 60 clocks (1 us), then sum |I| + |Q| over the dwell
            I = cI.reshape(-1, 60).sum(axis=1)
            Q = cQ.reshape(-1, 60).sum(axis=1)
            out[r, j] = np.abs(I).sum() + np.abs(Q).sum()
    return freqs, 20 * np.log10(out + 1)


def render(freqs, wf, audio, fs_a, rds, info):
    img = Image.new("RGB", (640, 480), (0, 0, 32))
    d = ImageDraw.Draw(img)
    font = ImageFont.load_default()
    big = font
    # waterfall: rows of the band, newest at the bottom, 600 px wide
    lo, hi = np.percentile(wf, 5), wf.max()
    z = np.clip((wf - lo) / (hi - lo), 0, 1)
    rows, cols = z.shape
    wf_img = np.zeros((rows, cols, 3))
    wf_img[..., 0] = np.clip(z * 2 - 0.6, 0, 1)
    wf_img[..., 1] = np.clip(z * 1.6 - 0.2, 0, 1)
    wf_img[..., 2] = np.clip(0.4 + z * 0.6, 0, 1) * (z < 0.9) + (z >= 0.9)
    w = Image.fromarray((wf_img * 255).astype(np.uint8)).resize((600, 150), Image.NEAREST)
    img.paste(w, (20, 30))
    d.text((20, 12), "FM BAND 87.5 - 108 MHz   (one pin, one bit, 240 MS/s)", fill=(255, 255, 255), font=big)
    for mhz in (88, 92, 96, 100, 104, 108):
        x = 20 + int((mhz * 1e6 - F0) / (F1 - F0) * 600)
        d.line([(x, 182), (x, 188)], fill=(255, 255, 255))
        d.text((x - 8, 190), f"{mhz}", fill=(255, 255, 255), font=font)
    tx = 20 + int((info["fc"] - F0) / (F1 - F0) * 600)
    d.polygon([(tx - 5, 24), (tx + 5, 24), (tx, 30)], fill=(255, 220, 0))
    # oscilloscope: 20 ms of audio
    d.rectangle([20, 210, 620, 330], outline=(80, 255, 80))
    n = int(0.02 * fs_a)
    a = audio[-n:]
    a = a - a.mean()
    s = 55 / (np.abs(a).max() + 1e-9)
    pts = [(20 + i * 600 / n, 270 - a[i] * s) for i in range(n)]
    d.line(pts, fill=(80, 255, 80), width=2)
    d.text((24, 214), "AUDIO  20 ms", fill=(80, 255, 80), font=font)
    # RDS
    d.text((20, 345), "RDS PS", fill=(255, 220, 0), font=font)
    ps = rds.get("ps") or "--------"
    small = Image.new("RGB", (80, 14), (0, 0, 32))
    ImageDraw.Draw(small).text((1, 1), ps, fill=(255, 220, 0), font=font)
    img.paste(small.resize((400, 70), Image.NEAREST), (120, 340))
    rt = (rds.get("rt") or "").rstrip()
    d.text((20, 420), "RT: " + rt[:60], fill=(255, 255, 255), font=font)
    d.text((20, 440), f"{info['fc']/1e6:.1f} MHz  CNR {info['cnr']:.0f} dB  {info['rel']:.0f} dB below strongest  "
                      f"RDS block errors {rds.get('bler', 1):.1%}", fill=(200, 200, 200), font=font)
    return img


def main():
    OUT.mkdir(exist_ok=True); RES.mkdir(exist_ok=True)
    cnr, rel = 30.0, 20.0
    o, kd, world = F.run(cnr, "multi", rel, seconds=3.0, receivers=("pe",), keep=True)
    w2 = F.World(1.0, cnr, F.SCEN["multi"](rel), 30.0, 7)
    freqs, wf = scanner(w2, 24)
    info = dict(fc=world.stations[0]["fc"], cnr=cnr, rel=rel)
    img = render(freqs, wf, kd["pe_audio"], 100e3, o["pe"]["rds"], info)
    img.save(OUT / "fm_tv_source.png")
    import tv
    tv.FS = 60e6
    s = tv.STD["PAL"]
    src = np.asarray(img).astype(float) / 255
    comp = tv.encode(src, s)
    lo, hi = -0.05, 1.10
    x = (comp - (lo + hi) / 2) / (hi - lo) * 2 * 0.8
    bits = tv.sigma_delta(x, 4)                            # two pins
    rec = tv.lowpass(bits, s["recon"], 401) / (2 * 0.8) * (hi - lo) + (lo + hi) / 2
    dec = tv.decode(rec, s)
    ideal = tv.decode(tv.lowpass(comp, s["recon"], 401), s)
    tv.save(dec, OUT / "fm_tv_PAL.png", 480)
    peaks = sorted(zip(wf.mean(axis=0), freqs), reverse=True)[:8]
    res = dict(run=o, psnr_vs_ideal_db=round(tv.psnr(dec, ideal), 1),
               scanner_top_channels_MHz=[round(f / 1e6, 1) for _, f in peaks])
    (RES / "fm_tv.json").write_text(json.dumps(res, indent=1))
    print(json.dumps({k: v for k, v in res.items() if k != "run"}, indent=1))
    print(F.fmt(o))


if __name__ == "__main__":
    main()
