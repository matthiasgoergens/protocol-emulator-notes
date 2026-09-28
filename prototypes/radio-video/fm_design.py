# /// script
# requires-python = ">=3.11"
# dependencies = ["numpy", "scipy"]
# ///
"""The measurements behind fm_rx.py's design choices (CNR 40 dB, single station, 0.5 s each):
  1. LO waveform in the nibble correlator (square vs 3-level) and the low-IF offset;
  2. the audio anti-alias filter before 100 kS/s (number of EMA stages, shift).
For each: the PE receiver's SINAD, and (for 1) the SINAD of an ideal floating-point audio filter
applied to the PE discriminator's output, which separates front-end limits from audio-filter limits.
Usage: uv run fm_design.py -> results/fm_design.txt"""
import sys, pathlib
import numpy as np
HERE = pathlib.Path(__file__).parent
sys.path.insert(0, str(HERE))
import fm_rx as F

lines = ["fm_design.py: CNR 40 dB, single station, 0.5 s per row, seed 1. SINAD in dB (1 kHz, 15 kHz band)."]
lines.append("")
lines.append("1. LO waveform and low-IF offset (audio filter: 4 EMA stages, k = 3)")
for lo, off in (("sq", 31.25e3), ("tri3", 31.25e3), ("tri3", 0.0), ("tri3", 60e3), ("sq", 100e3)):
    o, kd, w = F.run(40, seconds=0.5, receivers=("pe",), keep=True, lo=lo, lo_offset=off)
    d = kd["pe_delta"].astype(float) * 1e6 / 65536
    s_ideal, _ = F.sinad(F.ref_audio(d), 100e3, ftone=1000 / (1 + 30e-6))
    lines.append(f"  LO {lo:4s} offset {off/1e3:6.2f} kHz: PE SINAD {o['pe']['sinad_db']:5.1f}, ideal audio filter on the PE "
                 f"discriminator {s_ideal:5.1f}, octant path {o['pe_octant']['sinad_db']:5.1f}, RDS BLER {o['pe']['rds']['bler']:.3f}")
    print(lines[-1], flush=True)
lines.append("")
lines.append("2. Audio anti-alias filter before 100 kS/s (LO tri3, offset 31.25 kHz)")
for st in ((2, 2), (3, 2), (3, 3), (4, 3), (5, 3)):
    F.AUDIO_EMA = st
    o = F.run(40, seconds=0.5, receivers=("pe",))
    lines.append(f"  {st[0]} EMA stages, k = {st[1]}: PE SINAD {o['pe']['sinad_db']:5.1f}, tone {o['pe']['tone_rms_hz']:.0f} Hz rms (ideal 15,910)")
    print(lines[-1], flush=True)
(HERE / "results" / "fm_design.txt").write_text("\n".join(lines) + "\n")
