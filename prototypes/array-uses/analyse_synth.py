"""Independent check and plots for the synthesiser (synth.ml), in numpy.

Reference: from the schedule the OCaml run logged (per 4 ms tick: each voice's frequency and
amplitude), synthesise the four square voices in floating point at 960 kHz with continuous
phase, pass them through the same two RC poles at 20 kHz, decimate to 48 kHz. Then fit the chip's
WAV as a linear combination of the four reference voices (least squares). If the PE
configuration plays every note at the right pitch and time, each fitted gain is close to the
common scale and the residual is the noise voice plus artefacts; a voice at a wrong pitch or
muted gets a gain near 0.

Usage: uv run --with numpy --with matplotlib analyse_synth.py out results/synth_check.txt
"""
import sys
import wave
from pathlib import Path

import numpy as np

FS_REF = 960_000
FS_OUT = 48_000
FCLK = 60e6
PAUSE = 1017  # clocks per reload: 128 bytes, the first at the tick and one per 8 clocks (synth.ml); results/synth.txt: 1,015,983 paused over 999 reloads


def read_wav(p):
    with wave.open(str(p)) as w:
        return np.frombuffer(w.readframes(w.getnframes()), dtype="<i2").astype(float)


def reference(schedule, n_out, pause_clocks=0):
    """pause_clocks: the chain mode stops the segment for this many clocks after every tick but
    the first; the phases then advance only while the segment runs"""
    rows = np.loadtxt(schedule)
    t_clk = rows[:, 0]
    n_ref = n_out * (FS_REF // FS_OUT)
    t = np.arange(n_ref) / FS_REF
    tick = np.searchsorted(t_clk / FCLK, t, side="right") - 1
    since = t - t_clk[tick] / FCLK
    # fraction of each reference sample during which the segment runs (the pause is 16-17
    # samples long, so rounding it to whole samples drifts by up to a sample per reload)
    dt = 1.0 / FS_REF
    overlap = np.clip(pause_clocks / FCLK - since, 0.0, dt)
    running = np.where(tick > 0, 1.0 - overlap / dt, 1.0)
    voices = []
    for v in range(4):
        f = rows[tick, 1 + 2 * v]; a = rows[tick, 2 + 2 * v]
        ph = np.cumsum(running * f / FS_REF) % 1.0
        sq = np.where(ph < 0.5, 1.0, -1.0) * a / 32768.0      # g = MSB: +K in the first half
        voices.append(sq)
    return voices


def fit(chip, voices):
    step = FS_REF // FS_OUT
    cols = []
    for sq in voices:
        # the RC filter is linear: filter each voice, then decimate (sample at the end of each block)
        y = rc_fast(sq, FS_REF)
        cols.append(y[step - 1::step][: len(chip)])
    M = np.stack(cols, axis=1)
    g, *_ = np.linalg.lstsq(M, chip, rcond=None)
    res = chip - M @ g
    return g, res, M


def rc_fast(x, fs, fc=20e3):
    from scipy.signal import lfilter  # noqa
    a = 1 - np.exp(-2 * np.pi * fc / fs)
    y = lfilter([a], [1, -(1 - a)], x)
    return lfilter([a], [1, -(1 - a)], y)


def main():
    d = Path(sys.argv[1]); out = Path(sys.argv[2])
    lines = []
    specs = {}
    for mode in [m for m in ("direct", "chain", "chain-hold", "chain-toggle") if (d / f"synth-{m}.wav").exists()]:
        chip = read_wav(d / f"synth-{mode}.wav")
        pc = PAUSE if mode.startswith("chain") else 0
        voices = reference(d / f"synth-{mode}-schedule.txt", len(chip), pc)
        g, res, M = fit(chip, voices)
        # pin output 2*density-1 has full scale 1; the WAV scales the filtered pin by 30000
        lines.append(f"{mode}: {len(chip)} samples; fitted gains per voice (ideal 30000 each): "
                     + " ".join(f"{x:.0f}" for x in g))
        sig = np.sum((M @ g) ** 2); rp = np.sum(res ** 2)
        lines.append(f"{mode}: tonal signal / residual (noise voice + artefacts) = {10*np.log10(sig/rp):.1f} dB")
        # control: shift one voice's pitch by a semitone in the reference; its gain must collapse
        wrong = list(voices); wrong[3] = shifted(d / f"synth-{mode}-schedule.txt", len(chip), 3, pc)
        if mode == "chain":
            g0, _, M0 = fit(chip, reference(d / f"synth-{mode}-schedule.txt", len(chip), 0))
            r0 = chip - M0 @ g0
            lines.append(f"chain, reference ignoring the pauses: gains " + " ".join(f"{x:.0f}" for x in g0)
                         + f"; signal/residual {10*np.log10(np.sum((M0@g0)**2)/np.sum(r0**2)):.1f} dB")
        g2, _, _ = fit(chip, wrong)
        lines.append(f"{mode}: control, melody reference a semitone sharp: gains "
                     + " ".join(f"{x:.0f}" for x in g2))
        specs[mode] = chip
    out.write_text("\n".join(lines) + "\n")
    print("\n".join(lines))
    plot(specs, d)


def shifted(schedule, n_out, v, pc=0):
    rows = np.loadtxt(schedule).copy()
    rows[:, 1 + 2 * v] *= 2 ** (1 / 12)
    tmp = Path("/var/tmp/array-uses/sched_shift.txt"); np.savetxt(tmp, rows)
    return reference(tmp, n_out, pc)[v]


def plot(specs, d):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    titles = {"direct": "configuration changes applied at once (double-buffered)",
              "chain": "chain reloads, pin showing the half-shifted configuration",
              "chain-hold": "chain reloads, pin held while the segment is paused",
              "chain-toggle": "chain reloads, pin toggling (the modulator's zero) while paused"}
    modes = list(specs)
    fig, axes = plt.subplots(len(modes), 1, figsize=(9, 2.6 * len(modes)), dpi=120, sharex=True)
    for ax, m in zip(np.atleast_1d(axes), modes):
        ax.specgram(specs[m], NFFT=4096, Fs=FS_OUT, noverlap=3072, cmap="magma", vmin=-40)
        ax.set_ylim(0, 3000); ax.set_ylabel("Hz"); ax.set_title(titles[m], fontsize=10)
    np.atleast_1d(axes)[-1].set_xlabel("time (s)")
    fig.suptitle("Five voices on 16 upe_v0 PEs: pin after the RC filter", fontsize=11)
    fig.tight_layout(); fig.savefig(d / "synth-spectrogram.png"); plt.close(fig)


if __name__ == "__main__":
    main()
