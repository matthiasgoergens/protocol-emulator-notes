# Placement controls for compare_def: one cell mirrored in place, one master swapped at the same footprint.
import gdstk, sys
src, top, prefix, out = sys.argv[1:5]
def load():
    lib = gdstk.read_gds(src)
    cells = {c.name: c for c in lib.cells}
    return lib, cells, cells[top]
# mirror: the first unrotated, unreflected reference to an inverter, flipped about its row's centre line
lib, cells, t = load()
r = next(r for r in t.references if r.cell.name == prefix + "inv_1" and not r.x_reflection and r.rotation == 0)
(x0, y0), (x1, y1) = r.cell.bounding_box()
print("mirror", r.cell.name, r.origin)
r.x_reflection = True
r.origin = (r.origin[0], r.origin[1] + y1 + y0)
lib.write_gds(out + "_mirror.gds")
# master swap: the first nand2_1 becomes a nor2_1 (same footprint in both IHP libraries)
lib, cells, t = load()
r = next(r for r in t.references if r.cell.name == prefix + "nand2_1")
print("swap", r.cell.name, r.origin, cells[prefix + "nand2_1"].bounding_box(), cells[prefix + "nor2_1"].bounding_box())
r.cell = cells[prefix + "nor2_1"]
lib.write_gds(out + "_swap.gds")
