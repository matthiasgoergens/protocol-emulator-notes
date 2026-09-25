"""Summarise one DRC run directory: per rule, the count of violations and the smallest measured
distance among its edge pairs (how far below the rule value the layout goes). Reads the merged
*_full.lyrdb; which decks ran is stated by the caller (run.sh runs the main table alone and the
main table plus the maximal deck as two separate runs)."""
import sys, glob, os, re, math, collections
import xml.etree.ElementTree as ET

def seg_dist(p, q, r, s):
    def pt_seg(a, b, c):
        bx, by = c[0] - b[0], c[1] - b[1]
        L = bx * bx + by * by
        t = 0 if L == 0 else max(0, min(1, ((a[0] - b[0]) * bx + (a[1] - b[1]) * by) / L))
        return math.hypot(a[0] - b[0] - t * bx, a[1] - b[1] - t * by)
    return min(pt_seg(p, r, s), pt_seg(q, r, s), pt_seg(r, p, q), pt_seg(s, p, q))

d = sys.argv[1]
files = glob.glob(os.path.join(d, "*_full.lyrdb")) or glob.glob(os.path.join(d, "*.lyrdb"))
if not files:
    print(f"{d}: no result database"); sys.exit(1)
items = [it for f in files for it in ET.parse(f).getroot().iter("item")]
count, dmin = collections.Counter(), {}
for it in items:
    cat = it.findtext("category").strip("'")
    count[cat] += 1
    for v in it.iter("value"):
        m = re.match(r"edge-pair: \(([-\d.]+),([-\d.]+);([-\d.]+),([-\d.]+)\)[/|]\(([-\d.]+),([-\d.]+);([-\d.]+),([-\d.]+)\)", v.text or "")
        if m:
            a = list(map(float, m.groups()))
            dmin[cat] = min(dmin.get(cat, 9), seg_dist(a[0:2], a[2:4], a[4:6], a[6:8]))
print(f"{sum(count.values())} violations" + ("" if count else " (clean)"))
for k, n in sorted(count.items()):
    extra = f"  min measured {dmin[k]:.3f} um" if k in dmin else ""
    print(f"  {k:24s} {n:5d}{extra}")
