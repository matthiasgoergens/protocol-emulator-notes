# /// script
# requires-python = ">=3.11"
# dependencies = ["numpy", "scipy", "pillow"]
# ///
"""Composite video from a few digital pins, entirely precomputed on the host.

encode:  RGB test picture -> PAL or NTSC composite signal (floating point, 0 = sync tip, 1 = white)
modulate: composite -> sigma-delta stream with L output levels at 66 Msps (L = 2 is one pin)
decode:  a software TV: reconstruction low-pass, sync detection, burst phase lock, chroma
         demodulation (with the PAL delay line), YUV -> RGB
measure: PSNR of the picture decoded from the stream against the picture decoded from the ideal
         composite, and in-band SNR of the reconstructed composite.
"""
import json, pathlib, sys, time
import numpy as np
import scipy.signal as sg
from PIL import Image, ImageDraw, ImageFont

FS = 66e6
OUT = pathlib.Path(__file__).parent / "out"

STD = {
    "PAL": dict(line=64e-6, lines=312, fsc=4.43361875e6, sync=4.7e-6, burst_start=5.6e-6, burst_cycles=10,
                active_start=10.5e-6, active_len=52.0e-6, blank=0.3, black=0.3, white=1.0,
                first_active=23, n_active=288, vsync_lines=3, burst_amp=0.15, luma_bw=5.0e6, recon=6.0e6, pal=True),
    "NTSC": dict(line=1 / 15734.264, lines=262, fsc=315e6 / 88, sync=4.7e-6, burst_start=5.3e-6, burst_cycles=9,
                 active_start=10.9e-6, active_len=52.6e-6, blank=40 / 140, black=47.5 / 140, white=1.0,
                 first_active=21, n_active=240, vsync_lines=3, burst_amp=20 / 140, luma_bw=4.2e6, recon=4.8e6, pal=False),
}


def test_picture(w=640, h=480):
    """An original test card: 75 % colour bars, a hue and brightness sweep, a grey ramp and text."""
    img = np.zeros((h, w, 3))
    bars = [(1, 1, 1), (1, 1, 0), (0, 1, 1), (0, 1, 0), (1, 0, 1), (1, 0, 0), (0, 0, 1), (0, 0, 0)]
    for i, c in enumerate(bars):
        img[: h // 3, i * w // 8:(i + 1) * w // 8] = np.array(c) * 0.75
    ys, xs = np.mgrid[h // 3: 2 * h // 3, 0:w]
    hue = xs / w * 6.0
    val = 1.0 - (ys - h // 3) / (h // 3) * 0.8
    k = lambda n: (n + hue) % 6
    f = lambda n: val - val * 0.75 * np.clip(np.minimum(k(n), 4 - k(n)), 0, 1)
    img[h // 3: 2 * h // 3] = np.stack([f(5), f(3), f(1)], axis=-1) * 0.85
    img[2 * h // 3:, :] = (np.arange(w) / (w - 1))[None, :, None] * 0.9
    small = Image.new("RGB", (160, 16), (0, 0, 0))
    ImageDraw.Draw(small).text((4, 2), "ONE BIT TELEVISION", fill=(255, 255, 255), font=ImageFont.load_default())
    txt = np.asarray(small.resize((640, 64), Image.NEAREST)).astype(float) / 255
    region = img[2 * h // 3 + 60: 2 * h // 3 + 124]
    mask = txt[..., 0] > 0.5
    region[mask] = [0.95, 0.85, 0.2]
    region[~mask] = region[~mask] * 0.35
    return img


def rgb_to_yuv(rgb):
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    y = 0.299 * r + 0.587 * g + 0.114 * b
    return y, 0.493 * (b - y), 0.877 * (r - y)


def lowpass(x, cut, taps=255):
    return sg.oaconvolve(x, sg.firwin(taps, cut, fs=FS), mode="same")


def encode(img, s):
    tl = s["line"]
    n = int(round(s["lines"] * tl * FS))
    t = np.arange(n) / FS
    li = (t // tl).astype(int)
    tau = t - li * tl
    h, w, _ = img.shape
    y_img, u_img, v_img = rgb_to_yuv(img)
    act = (li >= s["first_active"]) & (li < s["first_active"] + s["n_active"]) & \
          (tau >= s["active_start"]) & (tau < s["active_start"] + s["active_len"])
    row = np.clip((li - s["first_active"]) * h // s["n_active"], 0, h - 1)
    col = np.clip(((tau - s["active_start"]) / s["active_len"] * w).astype(int), 0, w - 1)
    Y = np.where(act, y_img[row, col], 0.0)
    U = np.where(act, u_img[row, col], 0.0)
    V = np.where(act, v_img[row, col], 0.0)
    Y, U, V = lowpass(Y, s["luma_bw"]), lowpass(U, 1.3e6), lowpass(V, 1.3e6)
    wt = 2 * np.pi * s["fsc"] * t
    sw = np.where(li % 2 == 0, 1.0, -1.0) if s["pal"] else np.ones(n)
    k = s["white"] - s["black"]
    sig = np.full(n, s["blank"])
    sig = np.where(act, s["black"] + k * Y + k * (U * np.sin(wt) + sw * V * np.cos(wt)), sig)
    vs = li < s["vsync_lines"]
    half = tl / 2
    broad = vs & (((tau < half - s["sync"])) | ((tau >= half) & (tau < tl - s["sync"])))
    sig = np.where(broad, 0.0, sig)
    sig = np.where(~vs & (tau < s["sync"]), 0.0, sig)
    bmask = ~vs & (tau >= s["burst_start"]) & (tau < s["burst_start"] + s["burst_cycles"] / s["fsc"])
    a = s["burst_amp"]
    burst = (-np.sin(wt) + sw * np.cos(wt)) * a / np.sqrt(2) if s["pal"] else -np.sin(wt) * a
    sig = np.where(bmask, sig + burst, sig)
    return sig


def sigma_delta(x, levels):
    """Second-order modulator (the structure measured in the one-bit synthesiser), L-level quantiser,
    input x in [-1, 1]. Returns output levels in [-1, 1]."""
    step = 2.0 / (levels - 1)
    out = np.empty_like(x)
    i1 = i2 = 0.0
    fb = 0.0
    for n in range(len(x)):
        i1 += x[n] - fb
        i2 += i1 - fb
        q = round((i2 + 1.0) / step)
        q = 0 if q < 0 else (levels - 1 if q > levels - 1 else q)
        fb = q * step - 1.0
        out[n] = fb
    return out


def decode(r, s, w_out=768):
    """Software TV. r: composite estimate (0 = sync tip)."""
    r = np.concatenate([r, np.full(8000, s["blank"])])   # the last active line reads past the field end
    thr = s["blank"] / 2
    # a TV's sync separator slices a heavily low-passed copy, so noise cannot fake a sync edge
    rs = lowpass(r, 1.0e6, 255)
    low = rs < thr
    edges = np.flatnonzero(low[1:] & ~low[:-1]) + 1
    rises = np.flatnonzero(~low[1:] & low[:-1]) + 1
    starts, prev_broad = [], -1
    for e in edges:
        after = rises[rises > e]
        if len(after) == 0:
            break
        dur = (after[0] - e) / FS
        if dur > 10e-6:
            prev_broad = e
            continue
        if 3e-6 < dur < 6.5e-6:
            # sub-sample crossing time
            frac = (rs[e - 1] - thr) / (rs[e - 1] - rs[e])
            starts.append((e - 1 + frac, prev_broad))
    last_broad = max(b for _, b in starts)
    hs = [st for st, b in starts if b == last_broad]
    first = s["first_active"] - s["vsync_lines"]
    lines = hs[first:first + s["n_active"]]
    n_act = int(round(s["active_len"] * FS))
    wfs = 2 * np.pi * s["fsc"] / FS
    chroma_lp = sg.firwin(127, 1.3e6, fs=FS)
    out = np.zeros((len(lines), w_out, 3))
    prev_uv = None
    for k_line, st in enumerate(lines):
        i0 = int(st + s["burst_start"] * FS)
        nb = int(s["burst_cycles"] / s["fsc"] * FS)
        idx = np.arange(i0, i0 + nb)
        zb = 2 * np.mean((r[idx] - s["blank"]) * np.exp(-1j * wfs * idx))
        th = np.angle(zb)
        if s["pal"]:
            sw = 1.0 if np.real(zb) > 0 else -1.0
            th0 = th + sw * np.pi / 4
        else:
            sw, th0 = 1.0, th
        rot = np.exp(1j * (np.pi / 2 - th0))
        a0 = int(st + s["active_start"] * FS) - 100
        idx = np.arange(a0, a0 + n_act + 200)
        seg = r[idx]
        zraw = 2 * np.convolve(seg * np.exp(-1j * wfs * idx), chroma_lp, mode="same")
        chroma_est = np.real(zraw * np.exp(1j * wfs * idx))
        kk = s["white"] - s["black"]
        yv = (np.convolve(seg - chroma_est, sg.firwin(63, s["luma_bw"], fs=FS), mode="same") - s["black"]) / kk
        z = zraw * rot
        u, v = -np.imag(z) / kk, sw * np.real(z) / kk
        if s["pal"] and prev_uv is not None:
            u2, v2 = (u + prev_uv[0]) / 2, (v + prev_uv[1]) / 2
        else:
            u2, v2 = u, v
        prev_uv = (u, v)
        pos = (st + s["active_start"] * FS - a0) + (np.arange(w_out) + 0.5) / w_out * n_act
        yi, ui, vi = (np.interp(pos, np.arange(len(seg)), q) for q in (yv, u2, v2))
        R = yi + vi / 0.877
        B = yi + ui / 0.493
        G = (yi - 0.299 * R - 0.114 * B) / 0.587
        out[k_line] = np.stack([R, G, B], axis=-1)
    return np.clip(out, 0, 1)


def psnr(a, b):
    mse = np.mean((a - b) ** 2)
    return 10 * np.log10(1.0 / mse)


def save(img, path, h=None):
    im = Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8))
    if h:
        im = im.resize((im.width, h), Image.NEAREST)
    im.save(path)


def main():
    OUT.mkdir(exist_ok=True)
    src = test_picture()
    save(src, OUT / "source.png")
    results = {}
    for name, s in STD.items():
        t0 = time.time()
        comp = encode(src, s)
        ideal = decode(lowpass(comp, s["recon"], 401), s)
        save(ideal, OUT / f"{name}_ideal.png", 480)
        ref_src = np.asarray(Image.fromarray((src * 255).astype(np.uint8)).resize((ideal.shape[1], ideal.shape[0]), Image.BOX)).astype(float) / 255
        res = {"samples_per_field": len(comp), "psnr_ideal_vs_source_dB": round(psnr(ideal, ref_src), 1)}
        lo, hi = -0.05, 1.10          # composite range mapped into the modulator's input range
        for levels, span in ((2, 0.5), (4, 0.8), (8, 0.9)):
            x = (comp - (lo + hi) / 2) / (hi - lo) * 2 * span
            bits = sigma_delta(x, levels)
            rec = lowpass(bits, s["recon"], 401) / (2 * span) * (hi - lo) + (lo + hi) / 2
            ref = lowpass(comp, s["recon"], 401)
            snr = 10 * np.log10(np.var(ref) / np.var(rec - ref))
            dec = decode(rec, s)
            toggles = int(np.count_nonzero(np.diff(bits)))
            save(dec, OUT / f"{name}_L{levels}.png", 480)
            res[f"L{levels}"] = {"pins": int(np.log2(levels)), "inband_snr_dB": round(snr, 1),
                                 "psnr_vs_ideal_dB": round(psnr(dec, ideal), 1),
                                 "toggle_rate_MHz": round(toggles / (len(bits) / FS) / 1e6, 1),
                                 "bytes_per_field": len(bits) * int(np.log2(levels)) // 8}
            print(name, levels, res[f"L{levels}"], flush=True)
        res["seconds"] = round(time.time() - t0, 1)
        results[name] = res
        print(name, res, flush=True)
    (OUT / "results.json").write_text(json.dumps(results, indent=2))


if __name__ == "__main__":
    main()
