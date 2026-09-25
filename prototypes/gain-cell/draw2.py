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

# A variant of the cell: kind "3T" or "2T"; ox "thick" or "thin" for the write transistor, or
# "allthick" for thick oxide in all three transistors (storage and read L 0.45); the write transistor's
# gate length lmw (thick-oxide minimum 0.45, thin 0.13); and, if narrow, a channel width of 0.15
# instead of the strip's 0.30 (a dogbone: the strip narrows under the gate only).
# Thick oxide costs a keep-out: ThickGateOx reaches 0.27 past strip B (TGO.a) and must clear the
# thin-oxide bar by another 0.27 (TGO.b); thin oxide needs only the Activ spacing of 0.21.
def V(kind="3T", ox="thick", lmw=None, narrow=True):
    return dict(kind=kind, ox=ox, lmw=lmw if lmw is not None else (0.45 if ox == "thick" else 0.13),
                narrow=narrow)

def vname(v):
    return f"{v['kind']}_{v['ox']}_L{int(round(v['lmw'] * 100))}{'n' if v['narrow'] else 'w'}"

def geometry(v):
    n = 0.03 if v["narrow"] else 0    # the dogbone's width steps keep 0.07 from the gate (Gat.d)
    d = round(v["lmw"] - 0.45 + 2 * n, 3)   # everything above the write gate moves up by this
    k = 0 if v["ox"] == "thick" else round(0.21 - 0.54, 3)   # and the bar and strip A by this
    up = lambda p: tuple(round(x + d, 3) for x in p)
    upk = lambda p: tuple(round(x + d + k, 3) for x in p)
    g = dict(b_top=0.98 + d, sn_c=up((0.75, 0.91)), wwl=(0.19 + n, 0.64 + d - n), tgo_top=1.25 + d,
             bar=upk((1.52, 1.82)), ms=upk((1.89, 2.02)), pad=upk((1.89, 2.19)),
             pad_c=upk((1.96, 2.12)), thick=v["ox"] != "thin", narrow=v["narrow"])
    if v["ox"] == "allthick":
        # all three transistors thick oxide (L 0.45): no keep-out between strip B and the bar,
        # and the storage and read gates grow by 0.32 each; ThickGateOx covers the whole tile
        g.update(ms=upk((1.89, 2.34)), pad=upk((1.89, 2.34)), pad_c=upk((2.035, 2.195)))
        if v["kind"] == "3T":
            g["rwl"] = upk((2.59, 3.04))      # Gat.b1: 0.25 between thick-oxide gates
            g["H"] = round(3.23 + d + k, 3)
        else:
            g["H"] = round(2.70 + d + k, 3)
        g["tgo_top"] = g["H"]
        g["allthick"] = True
        return g
    if v["kind"] == "3T":
        g["rwl"] = upk((2.37, 2.50))
        g["H"] = round(2.69 + d + k, 3)
    else:
        g["H"] = round(2.38 + d + k, 3)
    return g

def R(cell, layer, x0, y0, x1, y1):
    cell.add(gdstk.rectangle((round(x0, 3), round(y0, 3)), (round(x1, 3), round(y1, 3)),
                             layer=LY[layer][0], datatype=LY[layer][1]))

def tile(lib, v):
    g = geometry(v)
    H = g["H"]
    c = lib.new_cell(f"TILE_{vname(v)}")
    for s in (1, -1):          # upper row, then its mirror image
        def r(layer, x0, y0, x1, y1):
            a, b = sorted((s * y0, s * y1))
            R(c, layer, x0, a, x1, b)
        if g["narrow"]:                                              # strip B, a dogbone
            r("Activ", 0.18, 0, 0.48, 0.15)
            r("Activ", 0.255, 0.15, 0.405, g["sn_c"][0] - 0.07)
            r("Activ", 0.18, g["sn_c"][0] - 0.07, 0.48, g["b_top"])
        else:
            r("Activ", 0.18, 0, 0.48, g["b_top"])                   # strip B
        r("GatPoly", 0, g["wwl"][0], PX, g["wwl"][1])                # WWL
        r("Cont", 0.25, g["sn_c"][0], 0.41, g["sn_c"][1])            # SN on strip B
        if g["thick"]:
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

def strap(lib, v):
    """Strap column, as a tile of the same height. Word lines, the bars and ThickGateOx run
    straight through. 3T: the GND bar gets an abutted P+ tie (pSD over the bar) and a contact to
    the GND track. 2T: the bar is a word line, so the tie is a separate P+ island between rows."""
    g = geometry(v)
    H = g["H"]
    c = lib.new_cell(f"STRAP_{vname(v)}")
    for s in (1, -1):
        def r(layer, x0, y0, x1, y1):
            a, b = sorted((s * y0, s * y1))
            R(c, layer, x0, a, x1, b)
        r("GatPoly", 0, g["wwl"][0], SW, g["wwl"][1])
        if g["thick"]:
            r("ThickGateOx", 0, 0, SW, g["tgo_top"])
        r("Activ", 0, g["bar"][0], SW, g["bar"][1])
        if "rwl" in g:
            r("GatPoly", 0, g["rwl"][0], SW, g["rwl"][1])
            ym = (g["bar"][0] + g["bar"][1]) / 2
            if g.get("allthick"):     # pSD.j1: 0.40 from thick-oxide NMOS gates
                r("pSD", -0.12, g["bar"][0] - 0.12, 0.36, g["bar"][1] + 0.12)   # pSD.k: area 0.26
            else:
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

CELLS = {}     # tiles and straps already in a library, by variant name

def array(lib, name, pairs, cols, every):
    """[pairs] is a list of variants, one per row pair, stacked bottom to top; all share the
    column pitch, so bit lines run through the whole stack. A strap column follows every
    [every] data columns."""
    cells = CELLS.setdefault(id(lib), {})
    for v in pairs:
        if vname(v) not in cells:
            cells[vname(v)] = (tile(lib, v)[0], strap(lib, v), geometry(v))
    a = lib.new_cell(name)
    xs, x = [], 0.0
    straps = []
    for k in range(cols):
        if k and k % every == 0:
            straps.append(x)
            x += SW
        xs.append(x)
        x += PX
    width = x
    y = 0.0
    for v in pairs:
        t, st, g = cells[vname(v)]
        H = g["H"]
        yc = y + H
        for x0 in xs:
            a.add(gdstk.Reference(t, (x0, yc)))
        for x0 in straps:
            a.add(gdstk.Reference(st, (x0, yc)))
        if g.get("allthick"):
            # the whole row pair is thick oxide: ThickGateOx reaches 0.27 past the bars' Activ at
            # both ends of the row (TGO.a) and 0.34 past the gates (TGO.c)
            R(a, "ThickGateOx", -0.34, yc - g["tgo_top"], width + 0.34, yc + g["tgo_top"])
        elif g["thick"]:
            # ThickGateOx must extend 0.34 past the leftmost gates (TGO.c)
            R(a, "ThickGateOx", -0.16, yc - g["tgo_top"], 0, yc + g["tgo_top"])
        y += 2 * H
    top = y
    for x0 in xs:
        # array top and bottom: strip A end-caps around the outermost RBL contacts, and Metal2
        # end-caps past the outermost vias
        for y0, y1 in ((-0.15, 0), (top, top + 0.15)):
            R(a, "Activ", x0 + 0.18, y0, x0 + 0.48, y1)
            R(a, "Metal2", x0 + 0.23, y0, x0 + 0.43, y1)
    for x0 in straps:
        for y0, y1 in ((-0.15, 0), (top, top + 0.15)):
            R(a, "Metal2", x0 + 0.02, y0, x0 + 0.22, y1)
    if any(cells[vname(v)][2].get("allthick") for v in (pairs[0], pairs[-1])):
        # ThickGateOx past the strip A end-caps at the array's top and bottom (TGO.a)
        R(a, "ThickGateOx", -0.34, -0.15 - 0.34, width + 0.34, 0)
        R(a, "ThickGateOx", -0.34, top, width + 0.34, top + 0.15 + 0.34)
    return a, width, top

def per_bit(v, every):
    return (PX + SW / every) * geometry(v)["H"]

if __name__ == "__main__":
    # uv run draw2.py COLS PAIRS EVERY [ox lmw narrow|wide] ...: one uniform array per variant
    # given (default: the chosen thick-oxide dogbone), plus a mixed array alternating the first
    # two variants' row pairs; writes gain_v2.gds
    cols, npairs, every = (int(x) for x in sys.argv[1:4]) if len(sys.argv) > 3 else (8, 2, 4)
    rest = sys.argv[4:]
    variants = [V("3T", rest[i], float(rest[i + 1]), rest[i + 2] == "narrow") for i in range(0, len(rest), 3)] \
        or [V("3T", "thick", 0.45, True)]
    lib = gdstk.Library(unit=1e-6, precision=5e-9)
    for v in variants:
        for kind in ("3T", "2T"):
            w = dict(v, kind=kind)
            a, wd, h = array(lib, f"ARRAY_{vname(w)}", [w] * npairs, cols, every)
            print(f"{vname(w)}: pitch {PX} x {geometry(w)['H']} um = {PX * geometry(w)['H']:.3f} um2 "
                  f"per bit core; {per_bit(w, every):.3f} with a strap every {every}; "
                  f"{per_bit(w, 32):.3f} every 32; array {wd:.2f} x {h:.2f} um")
    if len(variants) > 1:
        mixed = [variants[i % 2] for i in range(2 * npairs)]
        a, wd, h = array(lib, "ARRAY_MIXED", mixed, cols, every)
        print(f"mixed ({vname(variants[0])} / {vname(variants[1])} alternating): array {wd:.2f} x {h:.2f} um")
    lib.write_gds("gain_v2.gds")
