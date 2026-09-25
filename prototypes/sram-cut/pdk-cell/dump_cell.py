# /// script
# dependencies = ["gdstk"]
# ///
"""List the bit cell of the PDK SRAM macro: bounding box, layers, polygons."""
import gdstk, sys, collections
p = "/home/matthias/.ciel/ihp-sg13g2/ihp-sg13g2/libs.ref/sg13g2_sram/gds/RM_IHPSG13_1P_64x64_c2_bm_bist.gds"
lib = gdstk.read_gds(p)
cells = {c.name: c for c in lib.cells}
for n in sorted(cells):
    if "BITKIT" in n and ("CELL" in n or "16x2" in n or "TAP" in n or "EDGE" in n or "CORNER" in n):
        c = cells[n]
        bb = c.bounding_box()
        print(n, bb)
name = sys.argv[1] if len(sys.argv) > 1 else "RM_IHPSG13_64x64_c2_1P_BITKIT_CELL"
c = cells[name]
print("\n==", name, c.bounding_box())
print("references:", [r.cell.name if hasattr(r.cell,'name') else r.cell for r in c.references])
by = collections.defaultdict(list)
for pg in c.get_polygons(depth=None):
    by[(pg.layer, pg.datatype)].append(pg)
for k in sorted(by):
    print(k, len(by[k]))
    for pg in by[k]:
        pts = pg.points
        print("   ", [tuple(round(float(x),3) for x in pt) for pt in pts])
for lb in c.get_labels(depth=None):
    print("label", lb.text, lb.layer, lb.texttype, tuple(round(float(x),3) for x in lb.origin))
