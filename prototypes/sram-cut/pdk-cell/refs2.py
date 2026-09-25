# /// script
# dependencies = ["gdstk"]
# ///
"""Which cells place the 16x2 bit-cell blocks, and at what spacing (to check for tap columns)."""
import gdstk, sys, collections
p = sys.argv[1]
lib = gdstk.read_gds(p)
for c in lib.cells:
    pl = [r for r in c.references if r.cell.name.endswith("BITKIT_16x2_SRAM")]
    if pl:
        xs = sorted({round(float(r.origin[0]), 3) for r in pl}); ys = sorted({round(float(r.origin[1]), 3) for r in pl})
        rep = [(r.repetition.columns, r.repetition.rows, r.repetition.spacing) for r in pl if r.repetition.columns]
        print(c.name, len(pl), "refs; x", xs[:6], "...", len(xs), "; y", ys[:6], "...", len(ys), rep[:3])
        print("  bbox", c.bounding_box())
