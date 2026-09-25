# /// script
# requires-python = ">=3.11"
# dependencies = ["gdstk"]
# ///
"""A 6T SRAM bit cell for IHP SG13G2 drawn at the standard (non-SRAM) rules, so that IHP's DRC
deck passes it without the SRAM marker layer. Topology as in the PDK's own bit cell (a "thin"
cell, point-symmetric about its centre):

  x:  | NMOS strip L | well gap | PMOS L  PMOS R | well gap | NMOS strip R |
      bit lines and VDD/VSS in Metal2 (vertical), word line in Metal3 (horizontal)

Right half (the left half is the same rotated by 180 degrees):
  NMOS strip, straight, W 0.30: BL contact (y = +YB, shared with the row above) | PG gate = WL |
     Q_R contact (y = 0) | PD gate (input Q_L) | VSS contact (y = -YB, shared with the row below)
  PMOS strip, W 0.15 with 0.30 contact pads (dogbone): VDD contact (y = -YB, shared) | PU gate
     (input Q_L) | drain pad (Q_R) on the Q_R Metal1 track
  The inverter gate poly jogs through a contacted pad in the well gap, which the Q_L Metal1
  track reaches; the WL poly is contacted at the column boundary (shared with the mirrored
  neighbour) and taken up to the Metal3 word line through a Metal2 island.

The rules that set the pitch (versus the PDK cell, which uses relaxed rules under its SRAM
marker): Cnt.c 0.07 Activ enclosure of Cont (PMOS pads 0.30 wide instead of 0.20), NW.c/NW.d
0.31 (instead of 0.27 each), Gat.c 0.18 end cap. Y is set by Metal1 (BL pad, two storage-node
tracks), as in the PDK cell.

  uv run sram6t.py [COLS ROWS]   writes sram6t.gds with CELL6T, ARRAY6T (COLS x ROWS bits, rows
                                  and columns mirrored, with a tap row at the top and bottom)
Units um, 0.005 grid."""
import sys
import gdstk

LY = {"Activ": (1, 0), "GatPoly": (5, 0), "Cont": (6, 0), "Metal1": (8, 0), "Via1": (19, 0),
      "Metal2": (10, 0), "Via2": (29, 0), "Metal3": (30, 0), "pSD": (14, 0), "NWell": (31, 0)}

YB = 0.535            # half pitch in y (row pitch 1.07)
Q_TRACK = (0.09, 0.25)        # Metal1 track of the right storage node Q_R (Q_L: mirrored)
G_P = (-0.315, -0.185)        # inverter gate over the PMOS strip
G_N = (-0.32, -0.19)          # inverter gate over the NMOS strip
G_WL = (0.19, 0.32)           # word line over the NMOS strip

# Rule values that set the x pitch. STANDARD: IHP's standard rules. PDK: the values IHP's own bit
# cell uses under its SRAM marker (measured from RM_IHPSG13_1P_BITKIT_CELL, see
# ../../sram-cut/pdk-cell/dump_cell.txt): PMOS contact pads 0.20 wide (Activ enclosure of Cont
# 0.02 across the pad, Cnt.c), n-well enclosure of P+Activ and space to N+Activ 0.27 (NW.c,
# NW.d), poly end caps 0.17 on the NMOS and 0.13 on the PMOS (Gat.c).
STANDARD = dict(cnt_c=0.07, nw_c=0.31, nw_d=0.31, gat_c_n=0.18, gat_c_p=0.18)
PDK = dict(cnt_c=0.02, nw_c=0.27, nw_d=0.27, gat_c_n=0.17, gat_c_p=0.13)
RULES = dict(STANDARD)


def configure(**rules):
    """Set the x positions (right half) from the rule values."""
    global PS, PP, NW, NS, XB, XC_P, XC_N, X_BL, X_GC, PSD_X, RULES
    RULES = dict(STANDARD, **rules)
    r = RULES
    pad = round(0.16 + 2 * r["cnt_c"], 3)
    PP = (0.105, round(0.105 + pad, 3))       # PMOS contact pads (Act.b corner to corner: 0.21)
    PS = 0.145 if pad >= 0.29 else round(PP[1] - 0.15, 3)   # PMOS strip, W 0.15
    NW = round(PP[1] + r["nw_c"], 3)          # n-well edge (NW.c)
    NS = (round(NW + r["nw_d"], 3), round(NW + r["nw_d"] + 0.30, 3))   # NMOS strip (NW.d), W 0.30
    XB = round(NS[1] + r["gat_c_n"] + 0.09, 3)
    # pSD edge: at the n-well edge, or nearer the PMOS when pSD.j (0.30 to the NFET gates) needs it
    PSD_X = min(NW, round(NS[0] - 0.30, 3))  # half pitch: end cap + half of Gat.b
    XC_P = round((PP[0] + PP[1]) / 2, 3)
    XC_N = round((NS[0] + NS[1]) / 2, 3)
    X_GC = round((PP[1] + NS[0]) / 2, 3)      # gate-contact column, centred in the well gap
    # bit line (Metal2): 0.21 from VDD (x 0..0.10) and from VSS (XC_N +- 0.10)
    X_BL = round(min(0.62, XC_N - 0.41), 3)
    assert X_BL >= 0.41 - 1e-9, "no room for the bit line in Metal2"


configure()


def half_shapes():
    """(layer, x0, y0, x1, y1) of the right half."""
    s = []
    a = lambda *r: s.append(r)
    # --- PMOS (right): VDD pad at -YB (shared with the row below), strip, drain pad on Q_R track
    a("Activ", PP[0], -YB - 0.15, PP[1], -YB + 0.15)
    a("Activ", PS, -YB, PS + 0.15, 0.02)
    a("Activ", PP[0], 0.02, PP[1], 0.32)
    a("Cont", XC_P - 0.08, -YB - 0.08, XC_P + 0.08, -YB + 0.08)
    a("Cont", XC_P - 0.08, Q_TRACK[0], XC_P + 0.08, Q_TRACK[1])
    # --- NMOS (right): straight strip; BL contact at +YB, Q_R at 0, VSS at -YB
    a("Activ", NS[0], -YB, NS[1], YB)
    for y in (YB, 0.0, -YB):
        a("Cont", XC_N - 0.08, y - 0.08, XC_N + 0.08, y + 0.08)
    # --- right inverter gate (input Q_L): over the PMOS strip, a contacted pad in the well gap,
    # then over the NMOS strip
    a("GatPoly", round(PS - RULES["gat_c_p"], 3), G_P[0], X_GC, G_P[1])
    a("GatPoly", X_GC - 0.15, -0.32, X_GC + 0.15, -0.02)            # pad around the contact
    a("Cont", X_GC - 0.08, -Q_TRACK[1], X_GC + 0.08, -Q_TRACK[0])
    a("GatPoly", X_GC, G_N[0], round(NS[1] + RULES["gat_c_n"], 3), G_N[1])
    # --- word line: over the NMOS strip, to a contacted pad at the column boundary
    a("GatPoly", round(NS[0] - RULES["gat_c_n"], 3), G_WL[0], XB, G_WL[1])
    a("GatPoly", XB - 0.15, 0.105, XB + 0.15, 0.405)
    a("Cont", XB - 0.08, 0.175, XB + 0.08, 0.335)
    # --- Metal1
    a("Metal1", round(-X_GC - 0.13, 3), Q_TRACK[0], XC_N + 0.08, Q_TRACK[1])       # Q_R track (to the left gate)
    a("Metal1", XC_N - 0.08, -0.13, XC_N + 0.08, Q_TRACK[1])       # down onto the Q_R contact
    a("Metal1", X_GC - 0.08, -Q_TRACK[1], X_GC + 0.13, -Q_TRACK[0])  # end of the Q_L track
    a("Metal1", X_BL - 0.145, YB - 0.105, XC_N + 0.13, YB + 0.105)  # BL: contact to via
    a("Metal1", -0.145, -YB - 0.105, XC_P + 0.13, -YB + 0.105)      # VDD: contact to via at x=0
    a("Metal1", XC_N - 0.215, -YB - 0.105, XC_N + 0.215, -YB + 0.105)  # VSS: contact to via
    a("Metal1", XB - 0.105, -0.145, XB + 0.105, 0.385)              # WL: contact down to via
    # --- Via1
    a("Via1", X_BL - 0.095, YB - 0.095, X_BL + 0.095, YB + 0.095)
    a("Via1", -0.095, -YB - 0.095, 0.095, -YB + 0.095)
    a("Via1", XC_N - 0.095, -YB - 0.095, XC_N + 0.095, -YB + 0.095)
    a("Via1", XB - 0.095, -0.095, XB + 0.095, 0.095)
    # --- Metal2: BL_R, VSS_R (vertical, full height); WL island at the boundary
    a("Metal2", X_BL - 0.10, -YB, X_BL + 0.10, YB)
    a("Metal2", XC_N - 0.10, -YB, XC_N + 0.10, YB)
    a("Metal2", XB - 0.10, -0.36, XB + 0.10, 0.36)
    a("Via2", XB - 0.095, -0.095, XB + 0.095, 0.095)
    return s


def cell(lib):
    c = lib.new_cell("CELL6T")
    for (ly, x0, y0, x1, y1) in half_shapes():
        for sg in (1, -1):
            xa, xb = sorted((sg * x0, sg * x1)); ya, yb = sorted((sg * y0, sg * y1))
            c.add(gdstk.rectangle((round(xa, 4), round(ya, 4)), (round(xb, 4), round(yb, 4)),
                                  layer=LY[ly][0], datatype=LY[ly][1]))
    R = lambda ly, x0, y0, x1, y1: c.add(gdstk.rectangle((x0, y0), (x1, y1), layer=LY[ly][0], datatype=LY[ly][1]))
    R("Metal2", -0.10, -YB, 0.10, YB)                   # VDD
    R("Metal3", -XB, -0.10, XB, 0.10)                   # word line
    R("NWell", -NW, -YB, NW, YB)
    R("pSD", -PSD_X, -YB, PSD_X, YB)
    return c


def tap(lib):
    """Tap row cell, one column wide, 1.20 tall, placed above/below the array (its y = 0 edge
    abuts the array; it is mirrored for the bottom). It carries an n-well tie in the n-well stripe
    and a substrate tie in each p-well, contacted to the VDD / VSS Metal2 tracks, and closes the
    shared boundary shapes of the last row."""
    c = lib.new_cell("TAP6T")
    R = lambda ly, x0, y0, x1, y1: c.add(gdstk.rectangle((round(x0, 4), round(y0, 4)), (round(x1, 4), round(y1, 4)),
                                                         layer=LY[ly][0], datatype=LY[ly][1]))
    H = 1.20
    yn = 0.675                                           # n-well tie centre
    # n-well tie: N+ Activ in the well (no pSD there), contact to VDD Metal2 at x = 0
    R("NWell", -NW, 0, NW, H)
    R("Activ", -0.15, yn - 0.205, 0.15, yn + 0.205)
    R("Cont", -0.08, yn - 0.08, 0.08, yn + 0.08)
    R("Metal1", -0.105, yn - 0.215, 0.105, yn + 0.215)
    R("Via1", -0.095, yn - 0.095, 0.095, yn + 0.095)
    R("Metal2", -0.10, 0, 0.10, H)
    # the PMOS pads of the last row stop at y = +0.15 into the tap row; pSD must cover them, and
    # reaches out to the substrate ties as one polygon (separate pSD shapes would need 0.31)
    R("pSD", -PSD_X, 0, PSD_X, 0.40)
    yt = 0.605
    for sg in (1, -1):
        # substrate tie: P+ Activ under the VSS Metal2 track, contact to it
        R("Activ", sg * XC_N - 0.15, yt - 0.205, sg * XC_N + 0.15, yt + 0.205)   # Act.d: 0.123
        x0, x1 = sorted((sg * 0.18, sg * (XC_N + 0.18)))
        R("pSD", x0, 0.33, x1, yt + 0.235)
        R("Cont", sg * XC_N - 0.08, yt - 0.08, sg * XC_N + 0.08, yt + 0.08)
        R("Metal1", sg * XC_N - 0.105, yt - 0.215, sg * XC_N + 0.105, yt + 0.215)
        R("Activ", sg * NS[0] if sg > 0 else -NS[1], 0, sg * NS[1] if sg > 0 else -NS[0], 0.15)  # strip end cap
        R("Via1", sg * XC_N - 0.095, yt - 0.095, sg * XC_N + 0.095, yt + 0.095)
        R("Metal2", sg * XC_N - 0.10, 0, sg * XC_N + 0.10, H)
        R("Metal2", sg * X_BL - 0.10, 0, sg * X_BL + 0.10, 0.15)   # bit-line end caps
    return c


def array(lib, cols, rows):
    cc, tp = cell(lib), tap(lib)
    a = lib.new_cell("ARRAY6T")
    X, Y = 2 * XB, 2 * YB
    for j in range(rows):
        for i in range(cols):
            # mirror columns about x, rows about y, so boundary shapes are shared
            a.add(gdstk.Reference(cc, (i * X, j * Y), x_reflection=bool(j % 2),
                                  rotation=0))
            if i % 2:
                a.references[-1].rotation = 3.141592653589793
                a.references[-1].x_reflection = not bool(j % 2)
    # rows mirrored: row j occupies y in [j*Y - YB, j*Y + YB]
    for i in range(cols):
        a.add(gdstk.Reference(tp, (i * X, (rows - 1) * Y + YB), rotation=0, x_reflection=False))
        a.add(gdstk.Reference(tp, (i * X, -YB), x_reflection=True))
    # Metal3 word lines: close the Via2 enclosure at both array ends
    for j in range(rows):
        R = lambda x0, x1: a.add(gdstk.rectangle((x0, j * Y - 0.10), (x1, j * Y + 0.10), layer=30, datatype=0))
        R(-XB - 0.15, -XB)
        R((cols - 1) * X + XB, (cols - 1) * X + XB + 0.15)
    return a, cols * X, rows * Y


def markers(cell, x0, y0, x1, y1, which):
    """SRAM marker (25/0) and/or DigiBnd (16/0) over a rectangle."""
    if "sram" in which:
        cell.add(gdstk.rectangle((x0, y0), (x1, y1), layer=25, datatype=0))
    if "digi" in which:
        cell.add(gdstk.rectangle((x0, y0), (x1, y1), layer=16, datatype=0))


if __name__ == "__main__":
    # uv run sram6t_rb.py COLS ROWS standard|pdk [sram,digi] [OUT.gds]
    cols, rows = int(sys.argv[1]), int(sys.argv[2])
    tier = sys.argv[3] if len(sys.argv) > 3 else "standard"
    which = sys.argv[4].split(",") if len(sys.argv) > 4 and sys.argv[4] != "none" else []
    out = sys.argv[5] if len(sys.argv) > 5 else "sram6t_rb.gds"
    configure(**(PDK if tier == "pdk" else STANDARD))
    lib = gdstk.Library(unit=1e-6, precision=5e-9)
    a, w, h = array(lib, cols, rows)
    if which:
        markers(a, round(-XB - 0.2, 3), round(-YB - 1.2, 3), round(w - XB + 0.2, 3), round(h - YB + 1.2, 3), which)
    lib.write_gds(out)
    print(f"6T {tier} {RULES}: pitch {2*XB:.3f} x {2*YB:.3f} um = {4*XB*YB:.4f} um2 per bit; "
          f"array {cols}x{rows}: {w:.2f} x {h:.2f} um plus a 1.20 um tap row top and bottom; markers {which}")
