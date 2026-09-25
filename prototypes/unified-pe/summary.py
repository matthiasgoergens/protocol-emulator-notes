# Summarise reports/*.stat.txt: cell area, flop count and area (Yosys 0.62, sg13g2 typical liberty).
import glob, re, os
rows = []
for f in sorted(glob.glob("reports/*.stat.txt")):
    t = open(f).read()
    area = float(re.search(r"Chip area for module '\\\S+': ([\d.]+)", t).group(1))
    m = re.search(r"^\s+(\d+)\s+(\S+)\s+sg13g2_dfrbpq_1", t, re.M)
    nff, aff = (int(m.group(1)), float(m.group(2))) if m else (0, 0.0)
    cells = re.search(r"^\s+(\d+)\s+\S+\s+cells", t, re.M)
    rows.append((os.path.basename(f)[:-9], area, int(cells.group(1)) if cells else 0, nff, aff))
print(f"{'report':24s} {'area um2':>10s} {'cells':>6s} {'flops':>6s} {'flop um2':>9s}")
for r in rows:
    print(f"{r[0]:24s} {r[1]:10.0f} {r[2]:6d} {r[3]:6d} {r[4]:9.0f}")
