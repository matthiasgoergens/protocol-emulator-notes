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
# x layout of a column, set by rule values (configure()). STANDARD: IHP's standard rules; PDK: the
# values IHP's own SRAM bit cell uses under its SRAM marker, applied to this cell: Activ enclosure of
# Cont 0.02 across a strip (Cnt.c; the PDK cell's PMOS pads are 0.20 wide) and a poly end cap of
# 0.13 (Gat.c; the PDK cell's PMOS gates). Along the strips the PDK cell keeps 0.07 and Cnt.f 0.11,
# so the row height is unchanged. x = end cap + strip + Gat.d 0.07 + poly pad 0.30 + Gat.b 0.18.
STANDARD = dict(cnt_c=0.07, gat_c=0.18, cnt_c_end=0.07, cnt_f=0.11, cnt_d=0.07, act_b=0.21,
                tgo_a=0.27, tgo_b=0.27, tgo_c=0.34, tgo_d=0.34)
PDK = dict(STANDARD, cnt_c=0.02, gat_c=0.13)
RULES = dict(STANDARD)

def configure(**rules):
    global RULES, XS0, SWA, XC, XP0, PW, PX, XW, DX, SW
    RULES = dict(STANDARD, **rules)
    XS0 = RULES["gat_c"]                        # strip left edge = MS gate end cap
    SWA = round(0.16 + 2 * RULES["cnt_c"], 3)   # strip width (contacts across it)
    XC = round(XS0 + SWA / 2, 3)                # contact / RBL column
    XP0 = round(XS0 + SWA + 0.07, 3)            # SN poly pad (Gat.d from the strip)
    PW = round(0.16 + 2 * RULES["cnt_d"], 3)    # pad (Cnt.d around the contact)
    PX = round(XP0 + PW + 0.18, 3)              # + Gat.b
    XW = round(XC + 0.41, 3)                    # WBL track (Metal2 space 0.21 from RBL)
    # two Metal2 tracks per column (RBL over the strip, WBL beside it; M2.a 0.20, M2.b 0.21) set a
    # floor on the pitch once the front-end rules are relaxed enough
    PX = round(max(PX, XW + 0.10 + 0.21 + 0.10 - XC), 3)
    assert PX - XW - 0.10 + XC - 0.10 >= 0.21 - 1e-9, "WBL too close to the next column's RBL"
    # the strap's GND track (x 0.02..0.22 in the strap) must keep M2.b 0.21 from the WBL of the
    # column before it; if the column is narrower, shift the strap's contents right by DX and widen it
    DX = max(0.0, round(0.21 - (PX - XW - 0.10) - 0.02, 3))
    SW = round(0.60 + DX, 3)

configure()

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
    """y positions of the upper row of a tile (the lower row is its mirror image), from the rule
    values in RULES. Upwards from the shared WBL contact at y = 0:
      half contact 0.08, Cnt.f, [dogbone step n], WWL gate(s), [n], Cnt.f, SN contact 0.16,
      Activ enclosure of Cont along the strip (cnt_c_end), then to the bar: Act.b (thin strip B
      or all-thick), or TGO.a + TGO.b (thick strip B next to a thin bar);
      bar 0.30, Gat.d 0.07, MS gate (L 0.13, or 0.45 all-thick) with the SN poly pad
      (0.16 + 2 Cnt.d), Gat.b (0.25 between thick gates), RWL, Cnt.f, half contact 0.08."""
    r = RULES
    # a dogbone strip B narrows under the write gate; its width steps keep Gat.d 0.07 from the gate,
    # and the wide ends enclose the contacts by cnt_c_end, so a gate edge sits at least
    # max(Cnt.f, cnt_c_end + 0.07) from a contact (0.14 at the standard rules, where draw2.py wrote
    # it as Cnt.f 0.11 plus a 0.03 step)
    cg = max(r["cnt_f"], r["cnt_c_end"] + 0.07) if v["narrow"] else r["cnt_f"]
    allthick = v["ox"] == "allthick"
    w0 = round(0.08 + cg, 3)
    wwls = [(round(w0 + j * (v["lmw"] + 0.18), 3), round(w0 + j * (v["lmw"] + 0.18) + v["lmw"], 3))
            for j in range(v.get("stack", 1))]
    wtop = wwls[-1][1]
    sn0 = round(wtop + cg, 3)
    sn_c = (sn0, round(sn0 + 0.16, 3))
    b_top = round(sn_c[1] + r["cnt_c_end"], 3)
    thick_b = v["ox"] == "thick"
    if thick_b:
        # ThickGateOx edge: TGO.a past strip B and TGO.c past the write gate; the bar TGO.b beyond
        tgo_top = round(max(b_top + r["tgo_a"], wtop + r["tgo_c"]), 3)
        bar0 = round(max(tgo_top + r["tgo_b"], b_top + r["act_b"]), 3)
    else:
        tgo_top = None
        bar0 = round(b_top + r["act_b"], 3)
    if v.get("pms"):
        bar0 = round(bar0 + 0.41, 3)          # n-well clearance (NW.c + NW.d), as draw2.py
    bar = (bar0, round(bar0 + 0.30, 3))
    lms = 0.45 if allthick else 0.13
    ms0 = round(bar[1] + 0.07, 3)
    if thick_b:
        ms0 = round(max(ms0, tgo_top + r["tgo_d"]), 3)   # TGO.d: thin gate clear of ThickGateOx
    pad_h = round(0.16 + 2 * r["cnt_d"], 3)
    ms = (ms0, round(ms0 + lms, 3))
    pad = (ms0, round(ms0 + max(pad_h, lms), 3))
    pc = round(ms0 + (max(pad_h, lms) - 0.16) / 2, 3)
    pad_c = (pc, round(pc + 0.16, 3))
    g = dict(b_top=b_top, sn_c=sn_c, wwl=wwls[0], wwls=wwls, tgo_top=tgo_top, pms=v.get("pms", False),
             bar=bar, ms=ms, pad=pad, pad_c=pad_c, thick=v["ox"] != "thin", narrow=v["narrow"])
    gb = 0.25 if allthick else 0.18                     # Gat.b1 between thick-oxide gates
    if v["kind"] == "3T":
        r0 = round(pad[1] + gb, 3)
        g["rwl"] = (r0, round(r0 + lms, 3))
        g["H"] = round(g["rwl"][1] + r["cnt_f"] + 0.08, 3)
    else:
        g["H"] = round(pad[1] + r["cnt_f"] + 0.08, 3)
    if allthick:
        g["tgo_top"] = g["H"]
        g["allthick"] = True
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
            ys1 = round(g["wwls"][0][0] - 0.07, 3)
            ys2 = round(g["wwls"][-1][1] + 0.07, 3)
            r("Activ", XS0, 0, XS0 + SWA, ys1)
            r("Activ", XC - 0.075, ys1, XC + 0.075, ys2)
            r("Activ", XS0, ys2, XS0 + SWA, g["b_top"])
        else:
            r("Activ", XS0, 0, XS0 + SWA, g["b_top"])                   # strip B
        for w in g["wwls"]:
            r("GatPoly", 0, w[0], PX, w[1])                          # WWL (one or two gates)
        if g["pms"]:
            r("NWell", 0, g["bar"][0] - 0.31, PX, H)
            r("pSD", 0, g["bar"][0] - 0.18, PX, H)
        r("Cont", XC - 0.08, g["sn_c"][0], XC + 0.08, g["sn_c"][1])            # SN on strip B
        if g["thick"]:
            r("ThickGateOx", 0, 0, PX, g["tgo_top"])
        r("Activ", 0, g["bar"][0], PX, g["bar"][1])                  # GND / RWL bar
        r("Activ", XS0, g["bar"][0], XS0 + SWA, H)                       # strip A
        r("GatPoly", 0, g["ms"][0], XP0, g["ms"][1])                # MS gate with its left end-cap
        r("GatPoly", XP0, g["pad"][0], XP0 + PW, g["pad"][1])           # SN pad
        r("Cont", XP0 + PW / 2 - 0.08, g["pad_c"][0], XP0 + PW / 2 + 0.08, g["pad_c"][1])
        r("Metal1", XC - 0.13, g["sn_c"][0], XP0 + PW / 2 + 0.08, g["sn_c"][1])          # SN link, across
        r("Metal1", XP0 + PW / 2 - 0.08, g["sn_c"][0], XP0 + PW / 2 + 0.08, g["pad_c"][1] + 0.05)  # SN link, up to the pad
        if "rwl" in g:
            r("GatPoly", 0, g["rwl"][0], PX, g["rwl"][1])            # RWL (3T)
        # RBL: contact shared with the neighbouring tile at y = +-H, via straight up to Metal2
        r("Cont", XC - 0.08, H - 0.08, XC + 0.08, H + 0.08)
        r("Metal1", XC - 0.105, H - 0.215, XC + 0.105, H + 0.215)
        r("Via1", XC - 0.095, H - 0.095, XC + 0.095, H + 0.095)
    # WBL: the shared contact at y = 0, jogged in Metal1 to the WBL track
    R(c, "Cont", XC - 0.08, -0.08, XC + 0.08, 0.08)
    R(c, "Metal1", XC - 0.13, -0.105, XW + 0.145, 0.105)
    R(c, "Via1", XW - 0.095, -0.095, XW + 0.095, 0.095)
    R(c, "Metal2", XC - 0.10, -H, XC + 0.10, H)                                # RBL
    R(c, "Metal2", XW - 0.10, -H, XW + 0.10, H)                                # WBL
    return c, H

# SW (strap column: a GND track in Metal2 and a substrate tie per row) is set in configure()
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
                r("pSD", -0.12 if XS0 >= 0.18 else -0.17, g["bar"][0] - 0.12,
                  min(0.36, round(SW + XS0 - 0.42 - DX, 3)), g["bar"][1] + 0.12)   # pSD.k: area >= 0.25
            else:
                r("pSD", -0.20, g["bar"][0] - 0.10, round(0.26 + XS0, 3), g["bar"][1] + 0.10)   # abutted tie
            r("Cont", 0.04, ym - 0.08, 0.20, ym + 0.08)
            r("Metal1", 0.015, ym - 0.215, 0.225, ym + 0.215)
            r("Via1", 0.025, ym - 0.095, 0.215, ym + 0.095)
    if "rwl" not in g:
        # P+ island at y = +-H, between the bars of neighbouring tiles
        for yc in (H, -H):
            R(c, "Activ", -0.03, yc - 0.21, 0.27, yc + 0.21)   # Act.d: area >= 0.122
            R(c, "pSD", -0.20, yc - 0.38, round(0.26 + XS0, 3), yc + 0.38)
            R(c, "Cont", 0.04, yc - 0.08, 0.20, yc + 0.08)
            R(c, "Metal1", 0.015, yc - 0.215, 0.225, yc + 0.215)
            R(c, "Via1", 0.025, yc - 0.095, 0.215, yc + 0.095)
    R(c, "Metal2", 0.02, -H, 0.22, H)                                # GND
    if DX:
        # move everything but the shapes that run through the strap (word lines, bars, ThickGateOx)
        for p in c.polygons:
            (x0, _), (x1, _) = p.bounding_box()
            if not (abs(x0) < 1e-6 and abs(x1 - SW) < 1e-6):
                p.translate(DX, 0)
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
            R(a, "Activ", x0 + XS0, y0, x0 + XS0 + SWA, y1)
            R(a, "Metal2", x0 + XC - 0.10, y0, x0 + XC + 0.10, y1)
    for x0 in straps:
        for y0, y1 in ((-0.15, 0), (top, top + 0.15)):
            R(a, "Metal2", x0 + DX + 0.02, y0, x0 + DX + 0.22, y1)
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

def markers(a, w, h, which):
    """SRAM marker (25/0) and/or DigiBnd (16/0) over the whole array, with a margin."""
    for name, (l, d) in (("sram", (25, 0)), ("digi", (16, 0))):
        if name in which:
            a.add(gdstk.rectangle((-1.0, -1.0), (round(w + 1.0, 3), round(h + 1.0, 3)), layer=l, datatype=d))

if __name__ == "__main__":
    # uv run draw2.py COLS PAIRS EVERY [ox lmw narrow|wide] ...: one uniform array per variant
    # given (default: the chosen thick-oxide dogbone), plus a mixed array alternating the first
    # two variants' row pairs; writes gain_v2.gds
    # rule_breaks: uv run gain_rb.py standard|pdk|k=v,k=v MARKERS OUT.gds COLS PAIRS EVERY [ox lmw narrow|wide]...
    # MARKERS: none, sram, digi or sram,digi, drawn over each array
    tier, which, out = sys.argv[1], sys.argv[2], sys.argv[3]
    sys.argv = sys.argv[:1] + sys.argv[4:]
    base, _, extra = tier.partition(":")
    rules = dict({"pdk": PDK, "standard": STANDARD}[base])
    rules.update({k: float(v) for k, v in (kv.split("=") for kv in extra.split(",") if kv)})
    configure(**rules)
    which = [] if which == "none" else which.split(",")
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
            markers(a, wd, h, which)
            print(f"{vname(w)}: pitch {PX} x {geometry(w)['H']} um = {PX * geometry(w)['H']:.3f} um2 "
                  f"per bit core; {per_bit(w, every):.3f} with a strap every {every}; "
                  f"{per_bit(w, 32):.3f} every 32; array {wd:.2f} x {h:.2f} um")
    if len(variants) > 1:
        mixed = [variants[i % 2] for i in range(2 * npairs)]
        a, wd, h = array(lib, "ARRAY_MIXED", mixed, cols, every)
        markers(a, wd, h, which)
        print(f"mixed ({vname(variants[0])} / {vname(variants[1])} alternating): array {wd:.2f} x {h:.2f} um")
    lib.write_gds(out)
    print(f"rules {RULES}: column pitch {PX} um; wrote {out}")
