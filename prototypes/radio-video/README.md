# Two demos: FM radio with RDS on a TV, and advert detection from a TV signal

A feasibility study with working models for two "fun but real" demonstrations for the Tiny Tapeout
chip (IHP SG13G2, core clock about 60 MHz, digital pins only). Both are configurations of the
chip's generic blocks, not new special hardware:

- the four-thread deadline sequencer (`../deadline-sequencer`);
- the pin primitives, including the four-phase input and output stage (`../multiphase`: four
  one-bit samples per clock per pin, 240 MS/s);
- a systolic array of one generic programmable PE (`../pe-synth`, `../semiring-ring`,
  `../systolic-storage`), for which this study proposes a small set of extensions;
- generic assists: the programmable CRC, bit stuffing, the systolic matcher (`../systolic-matcher`);
- memory (latches, SRAM macros, gain cells: `../gain-cell`, `../../notes/gain-cell-compiler.md`).

Everything here is a model, run on a heavily loaded host: Python for the signal chains, a
Verilog PE with a lockstep check and Yosys synthesis for the extension area. No SPICE and no
silicon. Every number below points to a file in `results/` or `pe-ext/`.

## Evidence

All of this is model output. There is no SPICE, extracted layout or silicon in
this workstream.

### Demo A: FM and RDS

`results/fm_sweep.txt` is the retained 3.0 s sweep table; the row-level data is
in `results/fm_sweep.jsonl`. In the single-station case at 24 dB CNR, the
PE-friendly receiver gets 55.2 dB SINAD and RDS BLER 0.127, against 53.1 dB
and 0.000 for the floating-point reference on the same one-bit samples and
53.8 dB and 0.000 for the ideal analogue-sample reference. At 30 dB CNR the
PE result is 60.2 dB and BLER 0.022. The multi-station row at 30 dB CNR and
0 dB relative level gets 53.4 dB and BLER 0.224; the target is deliberately
close to an equal neighbour 400 kHz away. These are three-second, one-seed
models, not a receiver sensitivity claim.

`pe-ext/check.py` was rerun for 20,000 cycles: 0 mismatches with the normal
model and 8,006 mismatches with `FAULT=1`, which plants an EMA shift error.
The synthesis summary in `pe-ext/results.txt` reports 17,294.86 µm² for the
full PE extension against 11,483.49 µm² for the base cell under the same
Yosys flow.

### Demo B: advert detection

`results/advert.txt` and `results/advert.json` come from a fresh smoke run,
`uv run advert.py 1 1 8`: one training seed and one test seed of eight
minutes. The run has only one true advert boundary per test timeline, so its
boundary and delay counts are a smoke test, not an estimate of field
performance. Video-only accuracy is 0.996 in each of the five regimes. The
combined result is 0.950 for `r128_mild` and 0.889 for
`r128_mild_noblack`; the audio-only result is 0.208 and misses the boundary.
The cue AUC rows in `results/advert.txt` show why: cut, spread and luma are
strong on this generator, while audio cues are not reliable at this sample
size. `results/real_audio.txt` is the separate real-recording check used to
set the mild-compression regime.

The PNGs in `out/advert_frame_*.png` and `out/advert_timeline_*.png` show the
generated frames and detector timelines. The generated `.npz` state and seed
dumps are intermediate reproducibility scratch, not evidence used by these
claims.

### Demo B: CAN output

`results/can_out.txt` was regenerated from the fresh advert states with
`uv run can_out.py`. The independent decoder accepts
2,000/2,000 clean frames. Of 2,000 single-bit faults, 1,998 are rejected,
two are harmless faults after the CRC in fields this decoder does not check,
and zero wrong frames are accepted. The state streams use about 76–81 bit/s
at the tested rates, or 0.061–0.065 % of a 125 kbit/s CAN bus.

## Reproduction

```text
uv run advert.py 1 1 8
uv run can_out.py
uv run python pe-ext/check.py 20000
FAULT=1 uv run python pe-ext/check.py 20000
uv run fm_rx.py sweep
```
