"""Decoded audio (our ADPCM and SBC models, bit-exact with ffmpeg / sbcdec) through the one-bit
chain: order 2, 44.1 kHz words (mode A scaling: a constant gain and TPDF rounding, which on the
chip folds into the decoder's last shift), ideal pins, 48 kHz WAVs. Also the decoders' own
quality against the source clip (codec loss, not the DAC's)."""
import os, sys
import numpy as np
from scipy.signal import resample_poly
import dac_common as dc
import analyse as an

an.load_fs()
CODEC = sys.argv[1] if len(sys.argv) > 1 else "/var/tmp/onebit-dac/codec"
out_lines = []
src = np.fromfile(os.path.join(CODEC, "music.wav"), dtype="<i2")[22:].astype(float)  # 44-byte header
src = src[: len(src) // 2 * 2].reshape(-1, 2)
for name, f in [("adpcm", "ima.ours.raw"), ("sbc_a2dp_j53", "a2dp_j53.ours.raw")]:
    x = np.fromfile(os.path.join(CODEC, f), dtype="<i2").astype(float).reshape(-1, 2)
    n = min(len(x), len(src))
    # codec loss: align by the lag that maximises correlation (SBC has a fixed delay)
    best = max(range(0, 200), key=lambda d: np.dot(x[d:n, 0], src[: n - d, 0]))
    e = x[best:n] - src[: n - best]
    snr = 10 * np.log10(np.sum(src[: n - best] ** 2) / np.sum(e ** 2))
    w = [an.sg.host_mode_a(x[:, c], an.FS_WORD["o2"]) for c in range(2)]
    bl, br = an.run("o2", w[0], w[1], dc.STEPS_A, f"codec_{name}")
    _, yl, fsd = dc.analogue(bl, dc.Impair())
    _, yr, _ = dc.analogue(br, dc.Impair())
    path = os.path.join(an.WAV, f"decoded_{name}_o2_modeA.wav")
    dc.write_wav(path, resample_poly(yl, 128, 250), resample_poly(yr, 128, 250), 48000)
    out_lines.append(f"{name}: decoded PCM vs the source clip: delay {best} samples, SNR {snr:.1f} dB (codec loss); "
                     f"through the one-bit chain (order 2, ideal pins) -> wav/decoded_{name}_o2_modeA.wav")
    print(out_lines[-1], flush=True)
with open(os.path.join(an.RES, "codec", "chain.txt"), "w") as fh:
    fh.write("\n".join(out_lines) + "\n")
