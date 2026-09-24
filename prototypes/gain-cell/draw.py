# /// script
# requires-python = ">=3.11"
# dependencies = ["gdstk"]
# ///
"""A 3-transistor NMOS gain cell for IHP SG13G2, drawn by coordinates and checked with IHP's DRC.

Transistors: MW (write: WBL to SN, gate WWL), MS (storage: gate SN, source GND, drain MID),
MR (read: MID to RBL, gate RWL). Two active strips:
  strip A (x 0.00..0.30): GND contact, MS gate (the SN poly stub), MR gate (RWL), RBL contact
  strip B (x 0.74..1.04), raised: SN contact, MW gate (WWL), WBL contact
The SN poly stub ends in a contact pad between the strips, joined to strip B's SN contact by an
L-shaped Metal1 link. RWL and WWL run horizontally across the row; strip B starts above RWL and
strip A ends below WWL, so each word line crosses only its own strip. Rows interleave: the next
row's strip A sits beside this row's strip B.

Units: um, on a 0.005 grid. This first version stops at the cell core: the bit-line and ground
wiring (Metal2) is not drawn yet, so the pitch is a lower bound until it is."""
import gdstk

L = {"Activ": (1, 0), "GatPoly": (5, 0), "Cont": (6, 0), "Metal1": (8, 0)}
PITCH_X, PITCH_Y = 1.29, 1.475

def rect(cell, layer, x0, y0, x1, y1):
    cell.add(gdstk.rectangle((x0, y0), (x1, y1), layer=L[layer][0], datatype=L[layer][1]))

def cont_m1(cell, x0, y0):
    """a 0.16 contact with a Metal1 pad (0.05 end-cap past it in y, flush in x)"""
    rect(cell, "Cont", x0, y0, x0 + 0.16, y0 + 0.16)
    rect(cell, "Metal1", x0, y0 - 0.05, x0 + 0.16, y0 + 0.21)

def make_cell(lib):
    c = lib.new_cell("GAIN3T")
    # strip A: GND contact, MS gate, MR gate, RBL contact
    rect(c, "Activ", 0.00, 0.00, 0.30, 1.205)
    cont_m1(c, 0.07, 0.07)                       # GND
    cont_m1(c, 0.07, 0.975)                      # RBL
    # MS gate: the SN poly stub, from a left end-cap to a contact pad right of strip A
    rect(c, "GatPoly", -0.18, 0.34, 0.37, 0.47)
    rect(c, "GatPoly", 0.37, 0.255, 0.67, 0.555)  # pad around the SN poly contact
    rect(c, "Cont", 0.44, 0.325, 0.60, 0.485)
    # strip B: SN contact, MW gate, WBL contact
    rect(c, "Activ", 0.74, 0.935, 1.04, 1.745)
    cont_m1(c, 0.81, 1.005)                      # SN on strip B
    cont_m1(c, 0.81, 1.515)                      # WBL
    # the SN link in Metal1: up from the poly contact, across to strip B's SN contact
    rect(c, "Metal1", 0.44, 0.275, 0.60, 1.215)
    rect(c, "Metal1", 0.44, 0.955, 0.97, 1.215)
    return c

def make_array(lib, cell, cols, rows):
    a = lib.new_cell(f"ARRAY_{cols}x{rows}")
    for r in range(rows):
        for k in range(cols):
            a.add(gdstk.Reference(cell, (k * PITCH_X, r * PITCH_Y)))
        # word lines across the row: RWL (MR gates) and WWL (MW gates), with end-caps
        y = r * PITCH_Y
        a.add(gdstk.rectangle((-0.18, y + 0.735), (cols * PITCH_X - 0.07, y + 0.865), layer=5, datatype=0))
        a.add(gdstk.rectangle((0.56, y + 1.275), (cols * PITCH_X + 0.74 - PITCH_X + 0.30 + 0.18, y + 1.405), layer=5, datatype=0))
    return a

lib = gdstk.Library(unit=1e-6, precision=5e-9)
cell = make_cell(lib)
arr = make_array(lib, cell, 4, 4)
lib.write_gds("gain3t.gds")
print(f"pitch {PITCH_X} x {PITCH_Y} um = {PITCH_X * PITCH_Y:.3f} um2 per bit (cell core, before bit-line routing)")
