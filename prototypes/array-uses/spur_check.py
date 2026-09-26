import numpy as np
lines = []
for ch in (0, 1, 2):
    y = np.loadtxt(f"out/ddc-ch{ch}.txt")[5000:]
    X = np.abs(np.fft.rfft(y * np.hanning(len(y)))); f = np.fft.rfftfreq(len(y), 1 / 50000)
    m = (f > 2500) & (f < 10000); i = np.argmax(X * m)
    lines.append(f"channel {ch}: strongest line 2.5-10 kHz at {f[i]:.0f} Hz, {20*np.log10(X.max()/X[i]):.1f} dB below the largest peak")
k = round(6e6 * 65536 / 60e6); fl = k * 60e6 / 65536
lines.append(f"channel 1 LO: K = {k}, {fl:.0f} Hz ({fl-6e6:+.0f} Hz from the carrier)")
for h in (9, 11):
    a = abs(h * fl - round(h * fl / 60e6) * 60e6)
    lines.append(f"LO harmonic {h} sampled at 60 MS/s aliases to {a:.0f} Hz; the 6 MHz carrier lands at {abs(a-6e6):.0f} Hz, "
                 f"beating with the main image at {fl-6e6:.0f} Hz: {abs(abs(a-6e6)-(fl-6e6)):.0f} Hz")
open("results/ddc_spur.txt", "w").write("# spur check (script: /var/tmp/array-uses/spur.py, copied here)\n" + "\n".join(lines) + "\n")
print("\n".join(lines))
