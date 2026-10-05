"""Level sweep per modulator order: a 1 kHz tone in 0.3 s segments from -100 dB to +1 dB relative
to a_1/2, through the bit-exact OCaml model and the ideal analogue path. Gives SNR and THD+N
against input level, the overload point, and from that the full scale used for every other
test (FS = the level 3 dB below where THD+N first exceeds -60 dB... see choose_fs).

Output: results/levels.txt (table) and results/levels.png.
"""
import os
import sys
import numpy as np
import dac_common as dc

SEG = 0.3
SKIP = 0.1
LEVELS = list(range(-100, -10, 10)) + list(np.arange(-12, 1.5, 1.0))


def main():
    os.makedirs(dc.SCRATCH, exist_ok=True)
    res_dir = os.path.join(dc.HERE, "..", "results")
    lines = []
    allres = {}
    for order in ["o2", "o3", "o4"]:
        a1 = dc.A1[order]
        n_seg = int(SEG * dc.FS_A)
        t = np.arange(n_seg) / dc.FS_A
        segs = []
        for lv in LEVELS:
            amp = 10 ** (lv / 20) * a1 / 2 * 2  # relative to a_1: lv = 0 dB is amplitude a_1
            segs.append(amp * np.sin(2 * np.pi * 1000 * t))
        x = np.concatenate(segs)
        # TPDF dither of 1 LSB peak on each, as the host would add
        rng = np.random.default_rng(1)
        x = x + rng.uniform(-0.5, 0.5, x.shape) + rng.uniform(-0.5, 0.5, x.shape)
        wp = os.path.join(dc.SCRATCH, f"levels_{order}.words")
        dc.write_words(wp, x, x)
        prefix = os.path.join(dc.SCRATCH, f"levels_{order}")
        print(dc.render(order, wp, prefix, dc.STEPS_A), flush=True)
        bits = dc.read_bits(prefix + ".L.bits", len(x) * dc.STEPS_A)
        _, yd, fsd = dc.analogue(bits, dc.Impair())
        rows = []
        for i, lv in enumerate(LEVELS):
            s0 = int((i * SEG + SKIP) * fsd)
            s1 = int((i + 1) * SEG * fsd)
            seg = yd[s0:s1]
            sig, noise, harms = dc.tone_metrics(seg, fsd, 1000)
            rows.append((lv, 10 * np.log10(sig / noise), harms))
        allres[order] = rows
        lines.append(f"== {order}: a_1 = {a1}; level in dB re amplitude a_1 (0 dB: the input equals the feedback)")
        lines.append(f"{'level':>7} {'S/(THD+N) dB':>13}  harmonics 2-5 dB re signal")
        for lv, sn, h in rows:
            lines.append(f"{lv:7.1f} {sn:13.1f}  " + " ".join(f"{v:7.1f}" for v in h))
    out = "\n".join(lines)
    print(out)
    with open(os.path.join(res_dir, "levels.txt"), "w") as f:
        f.write(out + "\n")
    try:
        import matplotlib
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
        fig, ax = plt.subplots(figsize=(7, 4))
        for order, rows in allres.items():
            ax.plot([r[0] for r in rows], [r[1] for r in rows], marker=".", label=order)
        ax.set_xlabel("input level, dB re a_1")
        ax.set_ylabel("S/(THD+N), 20 Hz-20 kHz, dB")
        ax.grid(True, alpha=0.3)
        ax.legend()
        fig.tight_layout()
        fig.savefig(os.path.join(res_dir, "levels.png"), dpi=110)
    except Exception as e:  # plotting is a convenience
        print("plot failed:", e)


if __name__ == "__main__":
    main()
