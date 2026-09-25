# /// script
# dependencies = ["gdstk"]
# ///
"""Print the sub-cell placements of the PDK bit-cell block, to get the bit-cell pitch."""
import gdstk
p = "/home/matthias/.ciel/ihp-sg13g2/ihp-sg13g2/libs.ref/sg13g2_sram/gds/RM_IHPSG13_1P_64x64_c2_bm_bist.gds"
cells = {c.name: c for c in gdstk.read_gds(p).cells}
for n in ("RM_IHPSG13_1P_BITKIT_CELL_2x1", "RM_IHPSG13_1P_BITKIT_16x2_SRAM"):
    print("==", n)
    for r in cells[n].references:
        print("  ", r.cell.name, tuple(round(float(v), 3) for v in r.origin), r.rotation, r.x_reflection,
              getattr(r, "repetition", None) and (r.repetition.columns, r.repetition.rows, r.repetition.spacing))
