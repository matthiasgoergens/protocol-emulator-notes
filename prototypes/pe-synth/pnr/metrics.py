"""Summarise LibreLane final metrics: python3 pnr/metrics.py > results/pnr.txt"""
import glob, json, os

KEYS = [("die", "design__die__area"), ("core", "design__core__area"),
        ("stdcell", "design__instance__area__stdcell"), ("util", "design__instance__utilization"),
        ("seq", "design__instance__area__class:sequential_cell"),
        ("repair buf", "design__instance__area__class:timing_repair_buffer"),
        ("clk buf", "design__instance__area__class:clock_buffer"),
        ("setup typ", "timing__setup__ws__corner:nom_typ_1p20V_25C"),
        ("setup slow", "timing__setup__ws__corner:nom_slow_1p08V_125C"),
        ("hold worst", "timing__hold__ws"), ("route drc", "route__drc_errors")]
here = os.path.dirname(os.path.abspath(__file__))
print("# LibreLane 3.0.14, IHP SG13G2; areas in um2, slack in ns; fmax(slow) = 1/(period - setup slack)")
print("tag".ljust(28) + "".join(k.rjust(11) for k, _ in KEYS) + "  fmax slow MHz")
for f in sorted(glob.glob(os.path.join(here, "..", "pnr-metrics", "*", "final-metrics.json"))):
    tag = os.path.basename(os.path.dirname(f))
    d = json.load(open(f))
    period = float(tag.split("_")[-2].rstrip("ns"))
    vals = [d.get(k) for _, k in KEYS]
    fmax = 1e3 / (period - d["timing__setup__ws__corner:nom_slow_1p08V_125C"])
    print(tag.ljust(28) + "".join((f"{v:11.3f}" if isinstance(v, float) and abs(v) < 10 else f"{v:11.0f}") if v is not None else "        n/a" for v in vals) + f"  {fmax:8.1f}")
