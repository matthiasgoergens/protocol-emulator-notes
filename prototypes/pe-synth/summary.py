"""Collate the Yosys statistics in reports/: python3 summary.py > results/areas.txt"""
import glob, os, re

here = os.path.dirname(os.path.abspath(__file__))
print("# cell area from `stat -liberty` (typical 1.2 V liberty); flops = dfrbpq_1, latches = dlhq_1")
print("# suffix -y069: Yosys 0.69+77 (oss-cad-suite); none: Yosys 0.62 (LibreLane 3.0.14 container)")
print(f"{'report':34s} {'area um2':>10s} {'seq um2':>9s} {'cells':>6s} {'flops':>6s} {'latches':>7s}")
for f in sorted(glob.glob(os.path.join(here, "reports", "*.stat.txt"))):
    t = open(f).read()
    area = float(re.findall(r"Chip area for module '\\\S+': ([\d.]+)", t)[-1])
    seq = re.findall(r"sequential elements: ([\d.]+)", t)
    cells = re.search(r"^\s+(\d+)\s+\S+\s+cells$", t, re.M)
    cnt = lambda c: sum(int(m) for m in re.findall(rf"^\s+(\d+)\s+\S+\s+{c}$", t, re.M))
    name = os.path.basename(f)[: -len(".stat.txt")]
    print(f"{name:34s} {area:10.0f} {float(seq[-1]) if seq else 0:9.0f} {cells.group(1) if cells else '?':>6s}"
          f" {cnt('sg13g2_dfrbpq_1'):6d} {cnt('sg13g2_dlhq_1'):7d}")
