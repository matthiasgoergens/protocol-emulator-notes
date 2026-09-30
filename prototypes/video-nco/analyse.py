"""Summarise retained observations and require agreement with a fresh process."""
import json
import pathlib
import subprocess

HERE = pathlib.Path(__file__).resolve().parent


def main():
    primary = json.loads((HERE / "results/observations.json").read_text())
    confirmation = json.loads((HERE / "results-confirmation/observations.json").read_text())
    for key in ("source_sha256", "observations", "ideal_phase_calibrations", "pal_switch_calibration"):
        assert primary[key] == confirmation[key], f"fresh process differs: {key}"
    for filename in ("rtl.json", "PAL-rtl.txt", "NTSC-rtl.txt"):
        assert (HERE / "results" / filename).read_bytes() == (HERE / "results-confirmation" / filename).read_bytes()
    for standard in ("PAL", "NTSC"):
        for arm in ("ideal", "quarter"):
            filename = f"{standard}-{arm}.png"
            assert (HERE / "results-initial" / filename).read_bytes() == (HERE / "results" / filename).read_bytes(), filename
    tool = subprocess.run(["iverilog", "-V"], capture_output=True, text=True, check=True)
    (HERE / "results/iverilog-version.txt").write_text(tool.stdout + tool.stderr)
    lines = ["Fresh-process confirmation: all individual observations and RTL samples match.",
             "", "| Standard | Samples/clock | Fields | PSNR range (dB) | Max hue error range (degrees) | Passing fields |",
             "| --- | --- | --- | --- | --- | --- |"]
    for standard in ("PAL", "NTSC"):
        for grid in (1, 2, 4):
            rows = [r for r in primary["observations"]
                    if r["standard"] == standard and r.get("quarters_per_clock") == grid]
            psnr = [r["psnr_dB"] for r in rows]
            hue = [r["max_hue_error_deg"] for r in rows]
            passes = sum(r["passed"] for r in rows)
            lines.append(f"| {standard} | {grid} | {len(rows)} | {min(psnr):.2f}–{max(psnr):.2f} | "
                         f"{min(hue):.3f}–{max(hue):.3f} | {passes}/{len(rows)} |")
    lines += ["", "The picture and hue thresholds remain 35 dB and 2 degrees. The paired sync",
              "threshold is 1 clock, introduced after the initial exploratory run.", ""]
    text = "\n".join(lines)
    (HERE / "results/summary.md").write_text(text)
    print(text)


if __name__ == "__main__":
    main()
