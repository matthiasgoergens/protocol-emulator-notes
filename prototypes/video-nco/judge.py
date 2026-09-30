# /// script
# requires-python = ">=3.11"
# dependencies = ["numpy==2.5.3", "scipy==1.18.1", "pillow==12.3.0"]
# ///
"""G4 waveform experiment; the hue/amplitude path is behavioural, not integrated RTL."""
import argparse
import hashlib
import json
import pathlib
import platform
import subprocess
import sys
import tempfile

import numpy as np
import scipy
from scipy import signal
import PIL

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parent.parent
sys.path.insert(0, str(HERE.parent / "composite-video"))
import tv

FCLK = 60_000_000
WIDTH = 24
MOD = 1 << WIDTH
PHASES = (0, 0.125, 0.25, 0.375)


def increment(frequency):
    return round(frequency / FCLK * MOD)


def quarter_phase(n, inc, start=0, grid=4):
    """The exact integer additions in assists.v; coarser grids hold samples."""
    j = np.arange(n, dtype=np.int64)
    q = (j % 4) // (4 // grid) * (4 // grid)
    offsets = np.array([0, inc >> 2, inc >> 1, (inc >> 1) + (inc >> 2)])
    return ((j // 4) * inc + offsets[q] + start) % MOD


def check_rtl(out):
    """Check carrier-only samples against unchanged default-width pin_nco RTL."""
    rows = []
    rtl = HERE.parent / "unified-pe/rtl/assists.v"
    with tempfile.TemporaryDirectory(prefix="video-nco-") as td:
        work = pathlib.Path(td)
        for name, s in tv.STD.items():
            inc = increment(s["fsc"])
            tb = f"""module tb;
reg clk=0, clear=1, ld_inc=0, en=0;
reg [7:0] bus=0;
wire [3:0] nibble;
wire [7:0] phase;
pin_nco dut(clk, clear, bus, ld_inc, en, nibble, phase);
always #5 clk=~clk;
integer i, trace;
initial begin
  trace=$fopen("{work / 'trace.txt'}", "w");
  repeat (2) @(negedge clk);
  clear=0; ld_inc=1; bus=8'h{inc >> 16:02x};
  @(negedge clk); bus=8'h{(inc >> 8) & 255:02x};
  @(negedge clk); bus=8'h{inc & 255:02x};
  @(negedge clk); ld_inc=0; en=1;
  for (i=0; i<10000; i=i+1) begin
    $fdisplay(trace, "%h %h", nibble, phase);
    @(negedge clk);
  end
  $fclose(trace); $finish;
end
endmodule
"""
            (work / "tb.v").write_text(tb)
            subprocess.run(["iverilog", "-g2012", "-s", "tb", "-o", str(work / "sim"),
                            str(rtl), str(work / "tb.v")], check=True, capture_output=True)
            result = subprocess.run(["vvp", str(work / "sim")], check=True,
                                    capture_output=True, text=True)
            trace = (work / "trace.txt").read_text()
            (out / f"{name}-rtl.txt").write_text(trace)
            samples = [ln.split() for ln in trace.splitlines()]
            assert len(samples) == 10000, len(samples)
            raw = quarter_phase(40000, inc).reshape(-1, 4)
            expected = ((raw >= MOD // 2) * (1 << np.arange(4))).sum(axis=1)
            actual = np.array([int(a, 16) for a, _ in samples])
            phases = np.array([int(b, 16) for _, b in samples])
            phase_ref = ((np.arange(10000, dtype=np.int64) * inc) % MOD) >> 16
            wrong = int(np.count_nonzero(actual != expected))
            phase_wrong = int(np.count_nonzero(phases != phase_ref))
            # A swapped pair must be visible; otherwise this workload cannot check ordering.
            swapped = ((expected & 9) | ((expected & 2) << 1) | ((expected & 4) >> 1))
            fault_wrong = int(np.count_nonzero(actual != swapped))
            rows.append(dict(standard=name, increment=inc, clocks=len(samples),
                             wrong_nibbles=wrong, wrong_phase_bytes=phase_wrong,
                             swapped_quarters_detected=fault_wrong))
            assert wrong == phase_wrong == 0 and fault_wrong > 0, rows[-1]
    (out / "rtl.json").write_text(json.dumps(rows, indent=2) + "\n")
    return rows


def prepare(s):
    """Main-clock envelopes/timing, held over four quarters, shared by every arm."""
    tv.FS = FCLK
    n = round(s["lines"] * s["line"] * FCLK)
    t = np.arange(n) / FCLK
    # Integer clock scheduling: ceil each desired line start, avoiding float floor ties.
    starts = np.ceil(np.arange(s["lines"] + 1) * s["line"] * FCLK).astype(int)
    li = np.searchsorted(starts, np.arange(n), side="right") - 1
    tau = (np.arange(n) - starts[li]) / FCLK
    img = tv.test_picture()
    y, u, v = tv.rgb_to_yuv(img)
    h, w, _ = img.shape
    active = ((li >= s["first_active"]) & (li < s["first_active"] + s["n_active"])
              & (tau >= s["active_start"]) & (tau < s["active_start"] + s["active_len"]))
    row = np.clip((li - s["first_active"]) * h // s["n_active"], 0, h - 1)
    col = np.clip(((tau - s["active_start"]) / s["active_len"] * w).astype(int), 0, w - 1)
    y, u, v = (tv.lowpass(np.where(active, q[row, col], 0.0), bw)
               for q, bw in ((y, s["luma_bw"]), (u, 1.3e6), (v, 1.3e6)))
    sw = np.where(li % 2 == 0, 1.0, -1.0) if s["pal"] else np.ones(n)
    scale = s["white"] - s["black"]
    base = np.where(active, s["black"] + scale * y, s["blank"])
    a = np.where(active, scale * u, 0.0)
    b = np.where(active, scale * sw * v, 0.0)
    vs = li < s["vsync_lines"]
    half = s["line"] / 2
    broad = vs & ((tau < half - s["sync"]) | ((tau >= half) & (tau < s["line"] - s["sync"])))
    base = np.where(broad | (~vs & (tau < s["sync"])), 0.0, base)
    burst = (~vs & (tau >= s["burst_start"])
             & (tau < s["burst_start"] + s["burst_cycles"] / s["fsc"]))
    a = np.where(burst, -s["burst_amp"] / np.sqrt(2) if s["pal"] else -s["burst_amp"], a)
    b = np.where(burst, sw * s["burst_amp"] / np.sqrt(2) if s["pal"] else 0.0, b)
    amplitude = np.hypot(a, b)
    # Proposed 8-bit hue control, held for a main clock; identical in both arms.
    offset = np.rint(np.arctan2(b, a) / (2 * np.pi) * 256).astype(np.int64) % 256
    return base, amplitude, offset, np.diff(starts).tolist()


def waveform(data, s, start, grid=None, frequency_scale=1.0, chroma=True):
    base, amplitude, offset, _ = data
    n = len(base) * 4
    off = np.repeat(offset, 4) * (MOD // 256)
    if grid is None:
        cycles = np.arange(n) * (s["fsc"] / (4 * FCLK)) + start
        carrier = np.sin(2 * np.pi * (cycles + off / MOD))
    else:
        phase = (quarter_phase(n, increment(s["fsc"] * frequency_scale),
                               round(start * MOD), grid) + off + MOD // 2) % MOD
        # MSB polarity matches assists.v; pi offset makes its fundamental +sin.
        carrier = (2 * (phase >= MOD // 2) - 1) * (np.pi / 4)
    raw = np.repeat(base, 4) + np.repeat(amplitude if chroma else amplitude * 0, 4) * carrier
    # Filter quarter samples before downsampling, then use the decoder at its normal rate.
    # This is an ideal resistor-DAC/filter model, with no pad or phase-clock skew.
    filt = signal.firwin(1601, s["recon"], fs=4 * FCLK)
    comp = signal.oaconvolve(raw, filt, mode="same")[::4]
    tv.FS = FCLK
    # Measure normal sync intervals independently from the clock scheduler.
    rs = tv.lowpass(comp, 1.0e6, 255)
    threshold = s["blank"] / 2
    low = rs < threshold
    falls = np.flatnonzero(low[1:] & ~low[:-1]) + 1
    rises = np.flatnonzero(~low[1:] & low[:-1]) + 1
    syncs = []
    for e in falls:
        ri = np.searchsorted(rises, e, side="right")
        if ri < len(rises) and 3e-6 < (rises[ri] - e) / FCLK < 6.5e-6:
            syncs.append(e - 1 + (rs[e-1] - threshold) / (rs[e-1] - rs[e]))
    return tv.decode(comp, s), np.diff(syncs)


def measure(image, reference, s):
    image, periods = image
    reference, _ = reference
    if image.shape != reference.shape or len(image) != s["n_active"]:
        raise AssertionError((image.shape, reference.shape, s["n_active"]))
    # The six chromatic bars occupy the first third; omit edges and grey bars.
    cols = ((np.arange(1, 7) + 0.5) * image.shape[1] / 8).astype(int)
    rows = np.arange(4, s["n_active"] // 3 - 4)
    a = np.stack([image[rows, c-3:c+4].mean(axis=1) for c in cols], axis=1)
    b = np.stack([reference[rows, c-3:c+4].mean(axis=1) for c in cols], axis=1)
    _, ua, va = tv.rgb_to_yuv(a)
    _, ub, vb = tv.rgb_to_yuv(b)
    hue = np.angle((ua + 1j * va) * (ub - 1j * vb)) * 180 / np.pi
    errors = np.abs(hue)
    period_values, counts = np.unique(np.rint(periods).astype(int), return_counts=True)
    expected_periods = {int(np.floor(s["line"] * FCLK)), int(np.ceil(s["line"] * FCLK))}
    sync_ok = bool(set(period_values).issubset(expected_periods)
                   and len(periods) == s["lines"] - s["vsync_lines"] - 1)
    return dict(active_lines=len(image), psnr_dB=float(tv.psnr(image, reference)),
                max_hue_error_deg=float(errors.max()), mean_hue_error_deg=float(errors.mean()),
                hue_error_deg_by_line_and_bar=hue.tolist(),
                sync_period_clocks=periods.tolist(), sync_ok=sync_ok,
                sync_period_histogram={str(v): int(c) for v, c in zip(period_values, counts)},
                passed=bool(tv.psnr(image, reference) >= 35 and errors.max() <= 2 and sync_ok))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=pathlib.Path, default=HERE / "results")
    parser.add_argument("--rtl-only", action="store_true")
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    rtl = check_rtl(args.out)
    print("RTL", rtl, flush=True)
    if args.rtl_only:
        return
    observations = []
    for name, s in tv.STD.items():
        data = prepare(s)
        for start in PHASES:
            reference = waveform(data, s, start)
            for grid in (1, 2, 4):
                image = waveform(data, s, start, grid=grid)
                metrics = measure(image, reference, s)
                observation = dict(standard=name, start_cycles=start, quarters_per_clock=grid,
                                   increment=increment(s["fsc"]), **metrics)
                observations.append(observation)
                print(name, start, grid, {k: v for k, v in metrics.items()
                                         if k not in ("hue_error_deg_by_line_and_bar", "sync_period_clocks")}, flush=True)
                if start == 0 and grid == 4:
                    tv.save(reference[0], args.out / f"{name}-ideal.png", 480)
                    tv.save(image[0], args.out / f"{name}-quarter.png", 480)
            # A wrong carrier and chroma-off case must make the primary judge fail.
            if start == 0:
                for control in ("frequency-plus-1-percent", "chroma-off"):
                    image = waveform(data, s, start, grid=4,
                                     frequency_scale=1.01 if control.startswith("frequency") else 1.0,
                                     chroma=control != "chroma-off")
                    metrics = measure(image, reference, s)
                    observations.append(dict(standard=name, control=control, **metrics))
                    print(name, control, {k: v for k, v in metrics.items()
                                          if k not in ("hue_error_deg_by_line_and_bar", "sync_period_clocks")}, flush=True)
                    assert not metrics["passed"], (name, control)
    paths = [pathlib.Path(__file__), HERE.parent / "composite-video/tv.py",
             HERE.parent / "unified-pe/rtl/assists.v"]
    metadata = dict(clock_Hz=FCLK, accumulator_bits=WIDTH, starting_phases_cycles=PHASES,
                    python=sys.version, platform=platform.platform(), numpy=np.__version__,
                    scipy=scipy.__version__, pillow=PIL.__version__,
                    git_head=subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
                    source_sha256={str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
                                   for p in paths},
                    thresholds=dict(psnr_dB=35, max_hue_error_deg=2),
                    observations=observations)
    (args.out / "observations.json").write_text(json.dumps(metadata, indent=2) + "\n")


if __name__ == "__main__":
    main()
