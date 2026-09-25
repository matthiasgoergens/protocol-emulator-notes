"""Summarise KLayout DRC report databases (.lyrdb): violations per rule, with the first few
locations (bounding boxes, um). Usage: python3 drc_summary.py DIR..."""
import sys, re, glob, collections
import xml.etree.ElementTree as ET
for d in sys.argv[1:]:
    for f in sorted(glob.glob(f"{d}/**/*.lyrdb", recursive=True)):
        t = ET.parse(f).getroot()
        cnt = collections.Counter(); where = collections.defaultdict(list)
        for it in t.iter("item"):
            cat = it.findtext("category").strip("'")
            cnt[cat] += 1
            v = " ".join(x.text or "" for x in it.iter("value"))
            nums = [float(x) for x in re.findall(r"-?\d+\.?\d*", v)]
            if nums and len(where[cat]) < 4:
                xs, ys = nums[0::2], nums[1::2]
                where[cat].append(f"({min(xs):.3f},{min(ys):.3f})-({max(xs):.3f},{max(ys):.3f})")
        print(f"== {f}: {sum(cnt.values())} violations")
        for k, n in cnt.most_common():
            print(f"  {k:24s} {n:5d}  {' '.join(where[k])}")
