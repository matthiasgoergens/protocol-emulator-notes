# /// script
# dependencies = ["gdstk"]
# ///
"""Copy the PDK's 16x2 bit-cell block out of the 64x64 macro into pdk_bitcell.gds, twice: as drawn
(PDK_16x2, with the SRAM marker layer 25/0) and with the marker removed (PDK_16x2_NOMARK), so the
DRC deck treats it as ordinary layout."""
import gdstk
p = "/home/matthias/.ciel/ihp-sg13g2/ihp-sg13g2/libs.ref/sg13g2_sram/gds/RM_IHPSG13_1P_64x64_c2_bm_bist.gds"
src = gdstk.read_gds(p)
cells = {c.name: c for c in src.cells}
top = cells["RM_IHPSG13_1P_BITKIT_16x2_SRAM"]
out = gdstk.Library(unit=1e-6, precision=5e-9)
a = top.copy("PDK_16x2"); a.flatten()
b = top.copy("PDK_16x2_NOMARK"); b.flatten()
b.filter([(25, 0), (25, 1), (25, 4)], remove=True)
# the labels on TEXT/pin datatypes are harmless; keep them
out.add(a, b)
out.write_gds("pdk_bitcell.gds")
print(a.bounding_box(), len(a.polygons), len(b.polygons))
