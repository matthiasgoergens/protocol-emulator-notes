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
      "Metal2": (10, 0), "ThickGateOx": (44, 0), "pSD": (14, 0), "NWell": (31, 0)}
PX = 1.03

# A variant of the cell: kind "3T" or "2T"; ox "thick" or "thin" for the write transistor, or
# "allthick" for thick oxide in all three transistors (storage and read L 0.45); the write transistor's
# gate length lmw (thick-oxide minimum 0.45, thin 0.13); and, if narrow, a channel width of 0.15
# instead of the strip's 0.30 (a dogbone: the strip narrows under the gate only).
# Thick oxide costs a keep-out: ThickGateOx reaches 0.27 past strip B (TGO.a) and must clear the
# thin-oxide bar by another 0.27 (TGO.b); thin oxide needs only the Activ spacing of 0.21.
# Two further options (tricks-thin/, 2026-09-25): stack=2 puts a second write gate in series on
# strip B (both are WWL lines; they join at the array edge), at the gate space of 0.18; pms=True
# makes strip A and the bar P+ in an n-well (a PMOS storage and read transistor, bar = VDD):
# the n-well must clear strip B by 0.31 (NW.d) and enclose the bar by 0.31 (NW.c), so the bar
# moves up by 0.41; the strap column then carries a VDD track and an abutted n-well tie on the
# bar, and a separate P+ substrate tie at the WBL contact row.
def V(kind="3T", ox="thick", lmw=None, narrow=True, stack=1, pms=False):
    return dict(kind=kind, ox=ox, lmw=lmw if lmw is not None else (0.45 if ox == "thick" else 0.13),
                narrow=narrow, stack=stack, pms=pms)

def vname(v):
    return (f"{v['kind']}_{v['ox']}_L{int(round(v['lmw'] * 100))}{'n' if v['narrow'] else 'w'}"
            f"{'_S2' if v.get('stack', 1) == 2 else ''}{'_P' if v.get('pms') else ''}")

def geometry(v):
    n = 0.03 if v["narrow"] else 0    # the dogbone's width steps keep 0.07 from the gate (Gat.d)
    sx = (v.get("stack", 1) - 1) * (v["lmw"] + 0.18)     # a second write gate, at Gat.b
    d = round(v["lmw"] - 0.45 + 2 * n + sx, 3)   # everything above the write gate moves up by this
    k = 0 if v["ox"] == "thick" else round(0.21 - 0.54, 3)   # and the bar and strip A by this
    k = round(k + (0.41 if v.get("pms") else 0), 3)          # n-well clearance (NW.c + NW.d)
    up = lambda p: tuple(round(x + d, 3) for x in p)
    upk = lambda p: tuple(round(x + d + k, 3) for x in p)
    w0 = 0.19 + n
    wwls = [(round(w0 + j * (v["lmw"] + 0.18), 3), round(w0 + j * (v["lmw"] + 0.18) + v["lmw"], 3))
            for j in range(v.get("stack", 1))]
    g = dict(b_top=0.98 + d, sn_c=up((0.75, 0.91)), wwl=wwls[0], wwls=wwls, tgo_top=1.25 + d,
             pms=v.get("pms", False),
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
        for w in g["wwls"]:
            r("GatPoly", 0, w[0], PX, w[1])                          # WWL (one or two gates)
        if g["pms"]:
            r("NWell", 0, g["bar"][0] - 0.31, PX, H)
            r("pSD", 0, g["bar"][0] - 0.18, PX, H)
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
SWP = 0.85     # the same with an n-well: GND and VDD tracks

def swidth(v):
    return SWP if v.get("pms") else SW

def strap(lib, v):
    """Strap column, as a tile of the same height. Word lines, the bars and ThickGateOx run
    straight through. 3T: the GND bar gets an abutted P+ tie (pSD over the bar) and a contact to
    the GND track. 2T: the bar is a word line, so the tie is a separate P+ island between rows."""
    g = geometry(v)
    H = g["H"]
    c = lib.new_cell(f"STRAP_{vname(v)}")
    if g["pms"]:
        return strap_pms(c, g, H)
    for s in (1, -1):
        def r(layer, x0, y0, x1, y1):
            a, b = sorted((s * y0, s * y1))
            R(c, layer, x0, a, x1, b)
        for w in g["wwls"]:
            r("GatPoly", 0, w[0], SW, w[1])
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

def strap_pms(c, g, H):
    """strap for n-well rows: the bar is N+ here (an abutted n-well tie, VDD track at x 0.45),
    except a pSD sliver at the right edge that encloses the next tile's PMOS gates (pSD.i); a
    P+ substrate tie at y = 0 on the GND track at x 0.02"""
    sw = SWP
    for s in (1, -1):
        def r(layer, x0, y0, x1, y1):
            a, b = sorted((s * y0, s * y1))
            R(c, layer, x0, a, x1, b)
        for w in g["wwls"]:
            r("GatPoly", 0, w[0], sw, w[1])
        r("Activ", 0, g["bar"][0], sw, g["bar"][1])
        r("NWell", 0, g["bar"][0] - 0.31, sw, H)
        r("pSD", sw - 0.15, g["bar"][0] - 0.18, sw, H)
        if "rwl" in g:
            r("GatPoly", 0, g["rwl"][0], sw, g["rwl"][1])
        ym = (g["bar"][0] + g["bar"][1]) / 2
        r("Cont", 0.47, ym - 0.08, 0.63, ym + 0.08)
        r("Metal1", 0.445, ym - 0.215, 0.655, ym + 0.215)
        r("Via1", 0.455, ym - 0.095, 0.645, ym + 0.095)
    R(c, "Activ", -0.03, -0.15, 0.38, 0.15)             # substrate tie (Act.d: area 0.123)
    R(c, "pSD", -0.20, -0.32, 0.55, 0.32)
    R(c, "Cont", 0.04, -0.08, 0.20, 0.08)
    R(c, "Metal1", 0.015, -0.215, 0.225, 0.215)
    R(c, "Via1", 0.025, -0.095, 0.215, 0.095)
    R(c, "Metal2", 0.02, -H, 0.22, H)                    # GND
    R(c, "Metal2", 0.45, -H, 0.65, H)                    # VDD
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
    sw = max(swidth(v) for v in pairs)
    for k in range(cols):
        if k and k % every == 0:
            straps.append(x)
            x += sw
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
        if g["pms"]:
            # n-well and pSD past the array's left and right ends (NW.c, pSD.c, pSD.i)
            for s in (1, -1):
                for x0, x1, lay, e in ((-0.31, 0, "NWell", 0.31), (width, width + 0.31, "NWell", 0.31),
                                       (-0.18, 0, "pSD", 0.18), (width, width + 0.18, "pSD", 0.18)):
                    y0, y1 = sorted((yc + s * (g["bar"][0] - e), yc + s * H))
                    R(a, lay, x0, y0, x1, y1)
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
            if sw == SWP:
                R(a, "Metal2", x0 + 0.45, y0, x0 + 0.65, y1)
    if any(cells[vname(v)][2].get("allthick") for v in (pairs[0], pairs[-1])):
        # ThickGateOx past the strip A end-caps at the array's top and bottom (TGO.a)
        R(a, "ThickGateOx", -0.34, -0.15 - 0.34, width + 0.34, 0)
        R(a, "ThickGateOx", -0.34, top, width + 0.34, top + 0.15 + 0.34)
    for (v, y0, y1) in ((pairs[0], -0.46, 0), (pairs[-1], top, top + 0.46)):
        if geometry(v)["pms"]:      # n-well and pSD past the end-caps of strip A
            R(a, "NWell", -0.31, y0, width + 0.31, y1)
            R(a, "pSD", -0.18, max(y0, -0.33) if y0 < 0 else y0, width + 0.18, min(y1, top + 0.33) if y0 >= 0 else y1)
    return a, width, top

def per_bit(v, every):
    return (PX + swidth(v) / every) * geometry(v)["H"]

if __name__ == "__main__":
    # uv run draw2.py COLS PAIRS EVERY [ox lmw narrow|wide] ...: one uniform array per variant
    # given (default: the chosen thick-oxide dogbone), plus a mixed array alternating the first
    # two variants' row pairs; writes gain_v2.gds
    cols, npairs, every = (int(x) for x in sys.argv[1:4]) if len(sys.argv) > 3 else (8, 2, 4)
    rest = sys.argv[4:]
    # the third word may carry options: narrow+s2 (two write gates), narrow+p (PMOS strip A)
    variants = [V("3T", rest[i], float(rest[i + 1]), rest[i + 2].split("+")[0] == "narrow",
                  stack=2 if "s2" in rest[i + 2].split("+") else 1, pms="p" in rest[i + 2].split("+"))
                for i in range(0, len(rest), 3)] or [V("3T", "thick", 0.45, True)]
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
