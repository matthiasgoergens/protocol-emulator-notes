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
# x positions (right half)
PS = 0.145            # PMOS strip inner edge (strip 0.15 wide)
PP = (0.105, 0.405)   # PMOS contact pads
NW = 0.715            # n-well edge = PP[1] + 0.31 (NW.c)
NS = (1.025, 1.325)   # NMOS strip = NW + 0.31 (NW.d), W 0.30
XB = 1.595            # half pitch in x = NS[1] + 0.18 (Gat.c) + 0.09 (half of Gat.b)
XC_P = 0.255          # PMOS contact column (centre of the pads)
XC_N = 1.175          # NMOS contact column
X_BL = 0.62           # bit line (Metal2) centre
X_GC = 0.715          # gate-contact column in the well gap (0.23 from both Activ edges)
# y positions
Q_TRACK = (0.09, 0.25)        # Metal1 track of the right storage node Q_R (Q_L: mirrored)
G_P = (-0.315, -0.185)        # inverter gate over the PMOS strip
G_N = (-0.32, -0.19)          # inverter gate over the NMOS strip
G_WL = (0.19, 0.32)           # word line over the NMOS strip


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
    a("GatPoly", PS - 0.18, G_P[0], X_GC, G_P[1])
    a("GatPoly", X_GC - 0.15, -0.32, X_GC + 0.15, -0.02)            # pad around the contact
    a("Cont", X_GC - 0.08, -Q_TRACK[1], X_GC + 0.08, -Q_TRACK[0])
    a("GatPoly", X_GC, G_N[0], NS[1] + 0.18, G_N[1])
    # --- word line: over the NMOS strip, to a contacted pad at the column boundary
    a("GatPoly", NS[0] - 0.18, G_WL[0], XB, G_WL[1])
    a("GatPoly", XB - 0.15, 0.105, XB + 0.15, 0.405)
    a("Cont", XB - 0.08, 0.175, XB + 0.08, 0.335)
    # --- Metal1
    a("Metal1", -0.845, Q_TRACK[0], XC_N + 0.08, Q_TRACK[1])       # Q_R track (to the left gate)
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
    R("pSD", -NW, -YB, NW, YB)
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
    R("pSD", -NW, 0, NW, 0.40)
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


if __name__ == "__main__":
    cols, rows = (int(v) for v in sys.argv[1:3]) if len(sys.argv) > 2 else (4, 4)
    lib = gdstk.Library(unit=1e-6, precision=5e-9)
    a, w, h = array(lib, cols, rows)
    lib.write_gds("sram6t.gds")
    print(f"6T at standard rules: pitch {2*XB:.3f} x {2*YB:.3f} um = {4*XB*YB:.3f} um2 per bit; "
          f"array {cols}x{rows}: {w:.2f} x {h:.2f} um plus a 1.20 um tap row top and bottom")
