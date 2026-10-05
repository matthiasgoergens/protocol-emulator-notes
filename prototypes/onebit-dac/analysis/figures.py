"""Figures and the filter numbers for the README.

- results/spectra.png: spectra of the pin bitstream (o2, o3, o4; mode B, 997 Hz at -20 dBFS)
  with the reconstruction filter's response, 100 Hz-3 MHz;
- results/filter.txt: the filter's response at a few frequencies, the residual ultrasonic noise
  after it (o3, idle and at -1 dBFS), and the ZOH images of a 997 Hz tone in mode A and mode B.
"""
import os
import numpy as np
from scipy import signal
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import dac_common as dc
import signals as sg
import analyse as an

an.load_fs()
RES = an.RES


def welch_bits(bits):
    x = 1.0 - 2.0 * bits.astype(np.float64)
    f, p = signal.welch(x, fs=dc.FM, nperseg=1 << 18, window="blackmanharris")
    return f, p


def main():
    rng = np.random.default_rng(5)
    x_cd = sg.to_cd(sg.tone(997, -20, 1.0, dc.FS_A), rng)
    fig, ax = plt.subplots(figsize=(8, 4.5))
    for order in ["o2", "o3", "o4"]:
        w, steps = an.host("B", x_cd, order)
        bl, _ = an.run(order, w, w, steps, f"fig_{order}")
        f, p = welch_bits(bl)
        ax.semilogx(f[1:], 10 * np.log10(p[1:] + 1e-30), lw=0.7, label=f"{order} bitstream")
    sos = dc.filter_sos()
    fr = np.logspace(2, np.log10(3e6), 400)
    _, h = signal.sosfreqz(sos, worN=fr, fs=dc.FM)
    ax2 = ax.twinx()
    ax2.semilogx(fr, 20 * np.log10(np.abs(h)), "k--", lw=1, label="filter")
    ax2.set_ylabel("filter, dB")
    ax2.set_ylim(-150, 10)
    ax.axvline(20e3, color="grey", lw=0.5)
    ax.set_xlabel("Hz")
    ax.set_ylabel("PSD of the +-1 stream, dB/Hz")
    ax.set_xlim(100, 3e6)
    ax.legend(loc="lower left", fontsize=8)
    ax2.legend(loc="lower right", fontsize=8)
    ax.set_title("997 Hz at -20 dBFS, mode B, 6 MHz modulator")
    fig.tight_layout()
    fig.savefig(os.path.join(RES, "spectra.png"), dpi=110)

    lines = ["Reconstruction filter: 1 kohm / 2.2 nF (72 kHz), buffer, Sallen-Key Butterworth 40 kHz (10k, 10k, 560p, 270p)"]
    for fq in [1e3, 10e3, 20e3, 24.1e3, 43.1e3, 100e3, 176.5e3, 1e6, 3e6]:
        _, hh = signal.sosfreqz(sos, worN=[fq], fs=dc.FM)
        lines.append(f"  |H({fq/1e3:7.1f} kHz)| = {20*np.log10(abs(hh[0])):7.1f} dB")
    # residual ultrasonic noise at the filter output (full-rate signal, before decimation)
    for lv in [None, -1.0]:
        x = sg.tone(997, lv, 0.4, dc.FS_A) if lv is not None else np.zeros(int(0.4 * dc.FS_A))
        w, steps = an.host("B", sg.to_cd(x, rng), "o3")
        bl, _ = an.run("o3", w, w, steps, f"resid_{lv}")
        y, _, _ = dc.analogue(bl, dc.Impair())
        y = y[int(0.1 * dc.FM) :]
        lp = signal.sosfiltfilt(signal.butter(8, 20e3, fs=dc.FM, output="sos"), y)
        resid = y - lp
        lines.append(f"  o3, {'idle' if lv is None else '-1 dBFS 997 Hz'}: rms above 20 kHz at the filter output "
                     f"{np.sqrt(np.mean(resid**2))*1e3:.2f} mV (3.3 V pin), signal rms {np.std(lp)*1e3:.1f} mV")
    # images of a 997 Hz -1 dBFS tone around the host rate
    for mode in ["A", "B"]:
        x_cd = sg.to_cd(sg.tone(997, -1, 1.0, dc.FS_A), rng)
        w, steps = an.host(mode, x_cd, "o3")
        bl, _ = an.run("o3", w, w, steps, f"img_{mode}")
        y, _, _ = dc.analogue(bl, dc.Impair())
        y = y[int(0.2 * dc.FM) : int(0.2 * dc.FM) + (1 << 22)]
        f, p, _ = dc.spectrum(signal.resample_poly(y, 1, 16), dc.FM / 16)
        df = f[1] - f[0]
        def lvl(fq):
            k = int(round(fq / df))
            return 10 * np.log10(p[k - 30 : k + 31].sum())
        s0 = lvl(997)
        for img in [dc.FS_A - 997, dc.FS_A + 997, 2 * dc.FS_A - 997, 4 * dc.FS_A - 997]:
            lines.append(f"  mode {mode}: image at {img/1e3:6.1f} kHz {lvl(img) - s0:7.1f} dB re the tone (after the filter)")
    out = "\n".join(lines)
    print(out)
    with open(os.path.join(RES, "filter.txt"), "w") as f:
        f.write(out + "\n")


if __name__ == "__main__":
    main()
