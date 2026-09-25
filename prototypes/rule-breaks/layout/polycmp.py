import gdstk, sys
def polys(f, top):
    lib = gdstk.read_gds(f); c = {x.name: x for x in lib.cells}[top].copy("t"); c.flatten()
    return sorted((p.layer, p.datatype, tuple(map(tuple, p.points.round(4).tolist()))) for p in c.polygons)
a, b = polys(sys.argv[1], sys.argv[3]), polys(sys.argv[2], sys.argv[3])
print("identical" if a == b else f"differ: {len(a)} vs {len(b)} polygons, {len(set(a) ^ set(b))} not shared")
