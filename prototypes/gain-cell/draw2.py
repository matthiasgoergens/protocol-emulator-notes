# /// script
# requires-python = ">=3.11"
# dependencies = ["gdstk"]
# ///
"""Routed gain-cell arrays for IHP SG13G2, version 2: a thick-oxide write transistor, bit lines in
Metal2, and a per-row diffusion bar. Checked with IHP's DRC deck.

Why the shape (see README): retention needs a thick-oxide NMOS write transistor (at least 1.1 ms
in every corner), and thick oxide costs a 0.27 um keep-out on each side. So write transistors of
two rows share one horizontal ThickGateOx stripe, and share their WBL contact.

A tile is one column and two rows, mirrored about the WBL contact at y = 0. Upwards from there,
for the upper row:
  strip B (thick oxide):  WBL contact (shared) | MW gate = WWL (L 0.45) | SN contact
  keep-out (TGO.a + TGO.b)
  diffusion bar across the row: GND (3T) or the read word line RWL (2T)
  strip A (thin oxide):   MS gate = SN (poly contact on a pad beside the strip) | [3T: MR gate = RWL]
                          | RBL contact, shared with the next tile's row
An L of Metal1 joins the SN contact on strip B to the pad contact. Metal2: RBL over the strip,
WBL beside it (reached by a Metal1 jog at the shared contact).

3T: MS source on the GND bar, MR gates the read. 2T: MS source is the row's RWL bar itself; a read
pulls that bar low and senses the RBL discharge (MR is gone, so is the ground line).

Every N columns a strap column carries a GND track in Metal2 and a substrate tie per row
(latch-up rule LU.b: any N+ Activ within 20 um of a tie, so N <= 38). Not drawn: the array
periphery (word-line drivers, sensing, the 2T RWL bar contacts at the array edge).

Units um, 0.005 grid."""
import sys
import gdstk

LY = {"Activ": (1, 0), "GatPoly": (5, 0), "Cont": (6, 0), "Metal1": (8, 0), "Via1": (19, 0),
      "Metal2": (10, 0), "ThickGateOx": (44, 0), "pSD": (14, 0)}
PX = 1.03

# The write transistor: gate length LMW (0.45 is the thick-oxide minimum), and, if NARROW, a
# channel width of 0.15 instead of the strip's 0.30 (a dogbone: the strip narrows under the
# gate only). Both cut its leakage; see retention/.
LMW, NARROW = 0.45, False

def geometry(kind):
    n = 0.03 if NARROW else 0         # the dogbone's width steps keep 0.07 from the gate (Gat.d)
    d = round(LMW - 0.45 + 2 * n, 3)  # everything above the write gate moves up by this
    up = lambda p: tuple(round(v + d, 3) for v in p)
    g = dict(b_top=0.98 + d, sn_c=up((0.75, 0.91)), wwl=(0.19 + n, 0.64 + d - n), tgo_top=1.25 + d,
             bar=up((1.52, 1.82)), ms=up((1.89, 2.02)), pad=up((1.89, 2.19)), pad_c=up((1.96, 2.12)))
    if kind == "3T":
        g["rwl"] = up((2.37, 2.50))
        g["H"] = round(2.69 + d, 3)
    else:
        g["H"] = round(2.38 + d, 3)
    return g

def R(cell, layer, x0, y0, x1, y1):
    cell.add(gdstk.rectangle((round(x0, 3), round(y0, 3)), (round(x1, 3), round(y1, 3)),
                             layer=LY[layer][0], datatype=LY[layer][1]))

def tile(lib, kind):
    g = geometry(kind)
    H = g["H"]
    c = lib.new_cell(f"TILE{kind}")
    for s in (1, -1):          # upper row, then its mirror image
        def r(layer, x0, y0, x1, y1):
            a, b = sorted((s * y0, s * y1))
            R(c, layer, x0, a, x1, b)
        if NARROW:                                                   # strip B, a dogbone
            r("Activ", 0.18, 0, 0.48, 0.15)
            r("Activ", 0.255, 0.15, 0.405, g["sn_c"][0] - 0.07)
            r("Activ", 0.18, g["sn_c"][0] - 0.07, 0.48, g["b_top"])
        else:
            r("Activ", 0.18, 0, 0.48, g["b_top"])                   # strip B
        r("GatPoly", 0, g["wwl"][0], PX, g["wwl"][1])                # WWL
        r("Cont", 0.25, g["sn_c"][0], 0.41, g["sn_c"][1])            # SN on strip B
        r("ThickGateOx", 0, 0, PX, g["tgo_top"])
        r("Activ", 0, g["bar"][0], PX, g["bar"][1])                  # GND / RWL bar
        r("Activ", 0.18, g["bar"][0], 0.48, H)                       # strip A
        r("GatPoly", 0, g["ms"][0], 0.55, g["ms"][1])                # MS gate with its left end-cap
        r("GatPoly", 0.55, g["pad"][0], 0.85, g["pad"][1])           # SN pad
        r("Cont", 0.62, g["pad_c"][0], 0.78, g["pad_c"][1])
        r("Metal1", 0.20, g["sn_c"][0], 0.78, g["sn_c"][1])          # SN link, across
        r("Metal1", 0.62, g["sn_c"][0], 0.78, g["pad_c"][1] + 0.05)  # SN link, up to the pad
        if "rwl" in g:
            r("GatPoly", 0, g["rwl"][0], PX, g["rwl"][1])            # RWL (3T)
        # RBL: contact shared with the neighbouring tile at y = +-H, via straight up to Metal2
        r("Cont", 0.25, H - 0.08, 0.41, H + 0.08)
        r("Metal1", 0.225, H - 0.215, 0.435, H + 0.215)
        r("Via1", 0.235, H - 0.095, 0.425, H + 0.095)
    # WBL: the shared contact at y = 0, jogged in Metal1 to the WBL track
    R(c, "Cont", 0.25, -0.08, 0.41, 0.08)
    R(c, "Metal1", 0.20, -0.105, 0.885, 0.105)
    R(c, "Via1", 0.645, -0.095, 0.835, 0.095)
    R(c, "Metal2", 0.23, -H, 0.43, H)                                # RBL
    R(c, "Metal2", 0.64, -H, 0.84, H)                                # WBL
    return c, H

SW = 0.60      # strap column: a GND track in Metal2 and a substrate tie per row

def strap(lib, kind):
    """Strap column, as a tile of the same height. Word lines, the bars and ThickGateOx run
    straight through. 3T: the GND bar gets an abutted P+ tie (pSD over the bar) and a contact to
    the GND track. 2T: the bar is a word line, so the tie is a separate P+ island between rows."""
    g = geometry(kind)
    H = g["H"]
    c = lib.new_cell(f"STRAP{kind}")
    for s in (1, -1):
        def r(layer, x0, y0, x1, y1):
            a, b = sorted((s * y0, s * y1))
            R(c, layer, x0, a, x1, b)
        r("GatPoly", 0, g["wwl"][0], SW, g["wwl"][1])
        r("ThickGateOx", 0, 0, SW, g["tgo_top"])
        r("Activ", 0, g["bar"][0], SW, g["bar"][1])
        if "rwl" in g:
            r("GatPoly", 0, g["rwl"][0], SW, g["rwl"][1])
            ym = (g["bar"][0] + g["bar"][1]) / 2
            r("pSD", -0.20, g["bar"][0] - 0.10, 0.44, g["bar"][1] + 0.10)   # abutted tie
            r("Cont", 0.04, ym - 0.08, 0.20, ym + 0.08)
            r("Metal1", 0.015, ym - 0.215, 0.225, ym + 0.215)
            r("Via1", 0.025, ym - 0.095, 0.215, ym + 0.095)
    if "rwl" not in g:
        # P+ island at y = +-H, between the bars of neighbouring tiles
        for yc in (H, -H):
            R(c, "Activ", -0.03, yc - 0.21, 0.27, yc + 0.21)   # Act.d: area >= 0.122
            R(c, "pSD", -0.20, yc - 0.38, 0.44, yc + 0.38)
            R(c, "Cont", 0.04, yc - 0.08, 0.20, yc + 0.08)
            R(c, "Metal1", 0.015, yc - 0.215, 0.225, yc + 0.215)
            R(c, "Via1", 0.025, yc - 0.095, 0.215, yc + 0.095)
    R(c, "Metal2", 0.02, -H, 0.22, H)                                # GND
    return c

def array(lib, kind, cols, pairs, every):
    """cols data columns, with a strap column after every [every] of them"""
    t, H = tile(lib, kind)
    st = strap(lib, kind)
    a = lib.new_cell(f"ARRAY{kind}_{cols}x{2 * pairs}")
    top = 2 * H * pairs
    x, xs = 0.0, []
    for k in range(cols):
        if k and k % every == 0:
            a.add(gdstk.Reference(st, (x, H), columns=1, rows=pairs, spacing=(SW, 2 * H)))
            x += SW
        xs.append(x)
        x += PX
    width = x
    for k in range(1, (cols - 1) // every + 1):          # GND track end-caps
        x0 = xs[k * every] - SW
        for y0, y1 in ((-0.15, 0), (top, top + 0.15)):
            R(a, "Metal2", x0 + 0.02, y0, x0 + 0.22, y1)
    for x0 in xs:
        a.add(gdstk.Reference(t, (x0, H), columns=1, rows=pairs, spacing=(PX, 2 * H)))
        # array top and bottom: strip A end-caps around the outermost RBL contacts, and Metal2
        # end-caps past the outermost vias
        for y0, y1 in ((-0.15, 0), (top, top + 0.15)):
            R(a, "Activ", x0 + 0.18, y0, x0 + 0.48, y1)
            R(a, "Metal2", x0 + 0.23, y0, x0 + 0.43, y1)
    for p in range(pairs):
        yc = H + 2 * H * p
        # ThickGateOx must extend 0.34 past the leftmost gates (TGO.c)
        R(a, "ThickGateOx", -0.16, yc - geometry(kind)["tgo_top"], 0, yc + geometry(kind)["tgo_top"])
    return a, width, top

lib = gdstk.Library(unit=1e-6, precision=5e-9)
cols, pairs, every = (int(v) for v in sys.argv[1:4]) if len(sys.argv) > 3 else (8, 2, 4)
if len(sys.argv) > 4:
    LMW, NARROW = float(sys.argv[4]), sys.argv[5] == "narrow"
    print(f"write transistor L {LMW}, W {0.15 if NARROW else 0.30}")
for kind in ("3T", "2T"):
    a, w, h = array(lib, kind, cols, pairs, every)
    H = geometry(kind)["H"]
    per = (PX + SW / every) * H
    print(f"{kind}: core pitch {PX} x {H} um = {PX * H:.3f} um2 per bit; with a strap every "
          f"{every} columns {per:.3f}; this {cols}x{2 * pairs} array {w:.2f} x {h:.2f} um")
lib.write_gds("gain_v2.gds")
