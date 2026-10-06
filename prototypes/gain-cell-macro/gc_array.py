# /// script
# requires-python = ">=3.11"
# dependencies = ["gdstk"]
# ///
"""The gain-cell array as a hard macro for sg13cmos5l: the thick-oxide 3T cell of
../gain-cell/draw2.py (write transistor W 0.15 / L 0.45 dogbone, storage and read transistors
W 0.30 / L 0.13), with edges a router can reach.

  uv run gc_array.py ROWS COLS [OUT_PREFIX]      (ROWS even; default 32 x 38)

writes OUT_PREFIX.gds (cell GC_ARRAY_<ROWS>x<COLS>), OUT_PREFIX.lef (abstract) and
OUT_PREFIX.cir (the schematic netlist for LVS).

Floorplan, in the macro's own coordinates (origin at the lower left of its boundary):
  - columns of tiles from ../gain-cell/draw2.py, with a strap column (GND track in Metal2 and a
    substrate tie on every row's GND bar) at the left, after every SPLIT data columns and at the
    right, so no N+ Activ is more than about 10 um from a tie (latch-up rule LU.b allows 20 um);
  - left edge: the read word lines RWL[r]. Each RWL poly line is extended past the left strap
    to a poly pad with a contact, Metal1, Via1, Metal2, Via2 and a Metal3 stub to the boundary.
    Pads alternate between two x positions (even and odd rows), because the RWLs of neighbouring
    tile pairs are only 0.51 um apart;
  - right edge: the write word lines WWL[r], the same stack on the 0.45 um wide thick-oxide gate
    line itself (no pad needed);
  - bottom edge: the read bit lines RBL[c] (Metal2, the cell's own track, extended);
  - top edge: the write bit lines WBL[c] (Metal2, likewise);
  - GND: a Metal4 stripe over each strap column, tied to the strap's Metal2 GND track by a
    Via2/Via3 stack in every tile pair. The macro has no supply other than GND: the bit lines
    and word lines are driven from outside.
Pins are drawn on datatype 2 (pin) with a text label on datatype 25, as LibreLane's own GDS
for this PDK does, and with the drawing shape on datatype 0 underneath.

Row r = 2 j + h sits in tile pair j (h = 0 the lower, mirrored row; h = 1 the upper one).
"""
import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "gain-cell"))
import gdstk
import draw2
from draw2 import V, geometry, tile, strap, SW, PX

LY = dict(draw2.LY, Via2=(29, 0), Metal3=(30, 0), Via3=(49, 0), Metal4=(50, 0))
PIN = {"Metal2": (10, 2), "Metal3": (30, 2), "Metal4": (50, 2)}
TXT = {"Metal2": (10, 25), "Metal3": (30, 25), "Metal4": (50, 25)}

VAR = V("3T", "thick", 0.45, True)
G = geometry(VAR)
H = G["H"]                  # row height, 2.75 um
SPLIT = 19                  # data columns between straps

# edge geometry (um)
EL = 1.80                   # left edge region: RWL pads in two columns, then the Metal3 pins
XA, XB = -0.55, -1.15       # RWL pad centres for even / odd rows
ER = 1.06                   # right edge region: WWL contacts
EB = ET = 1.00              # bit-line stubs below and above the array
PINLEN = 0.40               # length of a pin shape along its wire


def R(cell, layer, x0, y0, x1, y1, lay=None):
    lay = lay or LY[layer]
    cell.add(gdstk.rectangle((round(x0, 3), round(y0, 3)), (round(x1, 3), round(y1, 3)),
                             layer=lay[0], datatype=lay[1]))


def pin(cell, layer, name, x0, y0, x1, y1):
    R(cell, layer, x0, y0, x1, y1)
    R(cell, layer, x0, y0, x1, y1, PIN[layer])
    cell.add(gdstk.Label(name, ((x0 + x1) / 2, (y0 + y1) / 2), layer=TXT[layer][0],
                         texttype=TXT[layer][1]))


def stack_m1_to_m3(c, x, y):
    """Cont (on poly), Metal1, Via1, Metal2, Via2 and a Metal3 landing, centred on (x, y)."""
    R(c, "Cont", x - 0.08, y - 0.08, x + 0.08, y + 0.08)
    R(c, "Metal1", x - 0.155, y - 0.155, x + 0.155, y + 0.155)     # area 0.096 >= 0.09 (M1.d)
    R(c, "Via1", x - 0.095, y - 0.095, x + 0.095, y + 0.095)
    R(c, "Metal2", x - 0.155, y - 0.25, x + 0.155, y + 0.25)     # area 0.155 >= 0.144 (M2.d)
    R(c, "Via2", x - 0.095, y - 0.095, x + 0.095, y + 0.095)
    R(c, "Metal3", x - 0.145, y - 0.145, x + 0.145, y + 0.145)


def strap_gc(lib):
    """The strap column of draw2.strap (3T, thick) with one change. There the GND bar reaches
    its substrate tie only by abutment: the contact sits on the P+ part of the bar, and the N+
    part (every storage transistor's source) joins it through the silicide alone. Silicon would
    connect them, but the LVS deck does not see silicide, so it extracted every bar as a floating
    net. Here the pSD stops 0.09 past the P+ contact (Cnt.g2) and a second contact sits on the
    N+ part, 0.09 clear of the pSD (Cnt.g1); Metal1 joins the two."""
    c = lib.new_cell("STRAP_GC")
    for s in (1, -1):
        def r(layer, x0, y0, x1, y1):
            a, b = sorted((s * y0, s * y1))
            R(c, layer, x0, a, x1, b)
        for w in G["wwls"]:
            r("GatPoly", 0, w[0], SW, w[1])
        r("ThickGateOx", 0, 0, SW, G["tgo_top"])
        r("Activ", 0, G["bar"][0], SW, G["bar"][1])
        r("GatPoly", 0, G["rwl"][0], SW, G["rwl"][1])
        ym = (G["bar"][0] + G["bar"][1]) / 2
        r("pSD", -0.20, G["bar"][0] - 0.12, 0.29, G["bar"][1] + 0.12)   # 0.49 x 0.54: pSD.a, pSD.k
        r("Cont", 0.04, ym - 0.08, 0.20, ym + 0.08)                     # on the P+ tie
        r("Cont", 0.38, ym - 0.08, 0.54, ym + 0.08)                     # on the N+ bar
        r("Metal1", 0.015, ym - 0.215, 0.59, ym + 0.215)
        r("Via1", 0.025, ym - 0.095, 0.215, ym + 0.095)
    R(c, "Metal2", 0.02, -H, 0.22, H)                                    # GND
    return c


def build(rows, cols, lib):
    assert rows % 2 == 0
    pairs = rows // 2
    t, _ = tile(lib, VAR)
    st = strap_gc(lib)
    core = lib.new_cell(f"GC_CORE_{rows}x{cols}")
    # x positions: strap, SPLIT columns, strap, ... , strap
    xs, straps, x = [], [], 0.0
    for k in range(cols):
        if k % SPLIT == 0:
            straps.append(x)
            x += SW
        xs.append(x)
        x += PX
    straps.append(x)
    x += SW
    width = round(x, 3)
    top = 2 * H * pairs
    for j in range(pairs):
        yc = (2 * j + 1) * H
        for x0 in xs:
            core.add(gdstk.Reference(t, (x0, yc)))
        for x0 in straps:
            core.add(gdstk.Reference(st, (x0, yc)))
        for sg in (1, -1):
            # the left strap has no tile to its left: extend its bars so Activ encloses the
            # strap's contact by 0.07 (Cnt.c); the strap's pSD already reaches x = -0.20
            a, b = sorted((yc + sg * G["bar"][0], yc + sg * G["bar"][1]))
            R(core, "Activ", -0.10, a, 0, b)
            # and the right strap's bars past its N+ contact (Cnt.c)
            R(core, "Activ", width, a, width + 0.10, b)
    # end caps at the array's top and bottom (as draw2.array): strip A Activ around the outermost
    # RBL contacts, Metal2 past the outermost vias
    for x0 in xs:
        for y0, y1 in ((-0.15, 0), (top, top + 0.15)):
            R(core, "Activ", x0 + 0.18, y0, x0 + 0.48, y1)
            R(core, "Metal2", x0 + 0.23, y0, x0 + 0.43, y1)
    for x0 in straps:
        for y0, y1 in ((-0.15, 0), (top, top + 0.15)):
            R(core, "Metal2", x0 + 0.02, y0, x0 + 0.22, y1)

    # the macro cell: the core shifted so the boundary's lower left is the origin
    name = f"GC_ARRAY_{rows}x{cols}"
    m = lib.new_cell(name)
    ox, oy = EL, EB
    m.add(gdstk.Reference(core, (ox, oy)))
    W_ = round(EL + width + ER, 3)
    H_ = round(EB + top + ET, 3)

    def r(layer, x0, y0, x1, y1):
        R(m, layer, x0 + ox, y0 + oy, x1 + ox, y1 + oy)

    def p(layer, nm, x0, y0, x1, y1):
        pin(m, layer, nm, x0 + ox, y0 + oy, x1 + ox, y1 + oy)

    pins = []      # (name, layer, rect in macro coordinates, direction, use)
    def addpin(nm, layer, x0, y0, x1, y1, direction="INPUT", use="SIGNAL"):
        p(layer, nm, x0, y0, x1, y1)
        pins.append((nm, layer, (x0 + ox, y0 + oy, x1 + ox, y1 + oy), direction, use))

    for j in range(pairs):
        yc = (2 * j + 1) * H
        for h, s in ((0, -1), (1, 1)):
            row = 2 * j + h
            # RWL: poly 0.13 tall at s * (rwl[0] .. rwl[1]) about yc
            ya, yb = sorted((yc + s * G["rwl"][0], yc + s * G["rwl"][1]))
            ym = (ya + yb) / 2
            xp = XA if h == 0 else XB
            r("GatPoly", xp - 0.15, ya, 0, yb)                       # extension to the strap
            r("GatPoly", xp - 0.15, ym - 0.15, xp + 0.15, ym + 0.15)  # contact pad
            stack_m1_to_m3(m, xp + ox, ym + oy)
            r("Metal3", -EL, ym - 0.10, xp + 0.145, ym + 0.10)
            addpin(f"RWL[{row}]", "Metal3", -EL, ym - 0.10, -EL + PINLEN, ym + 0.10)
            # WWL: poly 0.45 tall at s * (wwl[0] .. wwl[1]); contact on the line itself
            wa, wb = sorted((yc + s * G["wwl"][0], yc + s * G["wwl"][1]))
            wm = (wa + wb) / 2
            xw = width + 0.42
            r("GatPoly", width, wa, xw + 0.15, wb)
            stack_m1_to_m3(m, xw + ox, wm + oy)
            r("Metal3", xw - 0.145, wm - 0.10, width + ER, wm + 0.10)
            addpin(f"WWL[{row}]", "Metal3", width + ER - PINLEN, wm - 0.10, width + ER, wm + 0.10)
    for c, x0 in enumerate(xs):
        # RBL (x0 + 0.23 .. 0.43) down to the bottom edge, WBL (x0 + 0.64 .. 0.84) up to the top
        r("Metal2", x0 + 0.23, -EB, x0 + 0.43, -0.15)
        addpin(f"RBL[{c}]", "Metal2", x0 + 0.23, -EB, x0 + 0.43, -EB + PINLEN, "INOUT")
        r("Metal2", x0 + 0.64, top, x0 + 0.84, top + ET)
        addpin(f"WBL[{c}]", "Metal2", x0 + 0.64, top + ET - PINLEN, x0 + 0.84, top + ET)
    # GND: Metal4 stripes over the straps, a Via2/Via3 stack on the Metal2 GND track per tile pair
    gnd_x = []
    for x0 in straps:
        xm = x0 + 0.12
        gnd_x.append(xm)
        for j in range(pairs):
            y = (2 * j + 1) * H
            r("Via2", xm - 0.095, y - 0.095, xm + 0.095, y + 0.095)
            r("Metal3", xm - 0.195, y - 0.195, xm + 0.195, y + 0.195)   # area 0.152 >= 0.144 (M3.d)
            r("Via3", xm - 0.095, y - 0.095, xm + 0.095, y + 0.095)
        addpin("GND", "Metal4", xm - 0.50, -EB, xm + 0.50, top + ET, "INOUT", "GROUND")
    m.add(gdstk.rectangle((0, 0), (W_, H_), layer=189, datatype=4))   # prBoundary
    info = dict(name=name, rows=rows, cols=cols, W=W_, H=H_, pins=pins, ox=ox, oy=oy,
                width=width, top=top, gnd_x=[g + ox for g in gnd_x], xs=[x0 + ox for x0 in xs])
    return m, info


def write_lef(info, path):
    W_, H_ = info["W"], info["H"]
    ox, oy = info["ox"], info["oy"]
    out = [f"VERSION 5.8 ;", "BUSBITCHARS \"[]\" ;", "DIVIDERCHAR \"/\" ;",
           f"MACRO {info['name']}", "  CLASS BLOCK ;", "  ORIGIN 0 0 ;",
           f"  FOREIGN {info['name']} 0 0 ;", f"  SIZE {W_:.3f} BY {H_:.3f} ;", "  SYMMETRY X Y ;"]
    gnd = [p for p in info["pins"] if p[0] == "GND"]
    for nm, layer, (x0, y0, x1, y1), d, use in info["pins"]:
        if nm == "GND":
            continue
        out += [f"  PIN {nm}", f"    DIRECTION {d} ;", f"    USE {use} ;", "    PORT",
                f"      LAYER {layer} ;", f"        RECT {x0:.3f} {y0:.3f} {x1:.3f} {y1:.3f} ;",
                "    END", f"  END {nm}"]
    out += ["  PIN GND", "    DIRECTION INOUT ;", "    USE GROUND ;"]
    for _, layer, (x0, y0, x1, y1), _, _ in gnd:
        out += ["    PORT", f"      LAYER {layer} ;", f"        RECT {x0:.3f} {y0:.3f} {x1:.3f} {y1:.3f} ;", "    END"]
    out += ["  END GND", "  OBS"]
    # Metal1 everywhere; Metal2 everywhere but the bit-line pin strips; Metal3 everywhere but
    # the word-line pin strips; Metal4 between the GND stripes. Nothing may be routed over the
    # cells: a signal over a storage node couples into it.
    out += ["    LAYER Metal1 ;", f"      RECT 0.000 0.000 {W_:.3f} {H_:.3f} ;",
            "    LAYER Metal2 ;", f"      RECT 0.000 {PINLEN + 0.25:.3f} {W_:.3f} {H_ - PINLEN - 0.25:.3f} ;",
            "    LAYER Metal3 ;", f"      RECT {PINLEN + 0.25:.3f} 0.000 {W_ - PINLEN - 0.25:.3f} {H_:.3f} ;",
            "    LAYER Metal4 ;"]
    edges = [0.0] + sum(([g - 0.5 - 0.25, g + 0.5 + 0.25] for g in info["gnd_x"]), []) + [W_]
    for a, b in zip(edges[0::2], edges[1::2]):
        if b - a > 0.2:
            out.append(f"      RECT {max(a, 0):.3f} 0.000 {min(b, W_):.3f} {H_:.3f} ;")
    out += ["  END", f"END {info['name']}", "END LIBRARY", ""]
    open(path, "w").write("\n".join(out))


def write_cir(info, path):
    rows, cols = info["rows"], info["cols"]
    ports = ([f"RWL[{r}]" for r in range(rows)] + [f"WWL[{r}]" for r in range(rows)] +
             [f"RBL[{c}]" for c in range(cols)] + [f"WBL[{c}]" for c in range(cols)] + ["GND"])
    out = [f"* {info['name']}: schematic for LVS (thick-oxide 3T gain cell, one per row and column)",
           f".SUBCKT {info['name']} " + " ".join(ports)]
    for r in range(rows):
        for c in range(cols):
            sn, mid = f"SN_{r}_{c}", f"MID_{r}_{c}"
            out += [f"MMW_{r}_{c} WBL[{c}] WWL[{r}] {sn} GND sg13_hv_nmos W=0.15u L=0.45u",
                    f"MMS_{r}_{c} {mid} {sn} GND GND sg13_lv_nmos W=0.3u L=0.13u",
                    f"MMR_{r}_{c} RBL[{c}] RWL[{r}] {mid} GND sg13_lv_nmos W=0.3u L=0.13u"]
    out += [f".ENDS {info['name']}", ""]
    open(path, "w").write("\n".join(out))


# Pin capacitances for the Liberty view, in pF. Estimates, not extraction: per word line, COLS
# gates (thick oxide W 0.15 x L 0.45 at about 5 fF/um2; thin W 0.30 x L 0.13 at about
# 9 fF/um2) plus the poly line; per bit line, ROWS / 2 shared contacts' junctions plus the
# Metal2 track at about 0.12 fF/um. Section 2 of README.md replaces the bit-line figure with
# the extracted one where it matters (RBL).
def pin_caps(info):
    cols, rows = info["cols"], info["rows"]
    wwl = cols * 0.15 * 0.45 * 5.0 + info["width"] * 0.10
    rwl = cols * 0.30 * 0.13 * 9.0 + info["width"] * 0.10
    bl = rows / 2 * 0.2 + info["H"] * 0.12
    return {k: round(v / 1000, 4) for k, v in dict(WWL=wwl, RWL=rwl, WBL=bl, RBL=bl).items()}


def write_lib(info, path):
    """A Liberty view with no timing arcs: the array has no clock and no internal timing that a
    static timing tool could use. The bank's controller guarantees the analogue timing (word
    line and evaluation pulses of whole clock cycles); this view gives the tools the pin loads."""
    c = pin_caps(info)
    rows, cols = info["rows"], info["cols"]
    out = [f"library ({info['name']}) {{", '  delay_model : table_lookup ;', '  time_unit : "1ns" ;',
           '  voltage_unit : "1V" ;', '  current_unit : "1mA" ;', '  capacitive_load_unit (1, pf) ;',
           '  pulling_resistance_unit : "1kohm" ;', '  leakage_power_unit : "1nW" ;',
           '  nom_process : 1 ; nom_voltage : 1.2 ; nom_temperature : 25 ;',
           '  voltage_map (GND, 0.0) ;']
    for nm, n in (("WWL", rows), ("RWL", rows), ("WBL", cols), ("RBL", cols)):
        out += [f"  type (bus_{nm}) {{ base_type : array ; data_type : bit ; bit_width : {n} ; "
                f"bit_from : {n - 1} ; bit_to : 0 ; downto : true ; }}"]
    out += [f"  cell ({info['name']}) {{", f"    area : {info['W'] * info['H']:.3f} ;",
            "    dont_use : true ; dont_touch : true ; is_macro_cell : true ;",
            "    pg_pin (GND) { voltage_name : GND ; pg_type : primary_ground ; }"]
    for nm, d in (("WWL", "input"), ("RWL", "input"), ("WBL", "input"), ("RBL", "inout")):
        out += [f"    bus ({nm}) {{", f"      bus_type : bus_{nm} ;", f"      direction : {d} ;",
                f"      capacitance : {c[nm]} ;", "      related_ground_pin : GND ;", "    }"]
    out += ["  }", "}", ""]
    open(path, "w").write("\n".join(out))


def write_bb(info, path):
    rows, cols = info["rows"], info["cols"]
    open(path, "w").write(f"""// blackbox of the hard macro {info['name']} (see gc_array.py)
(* blackbox *)
module {info['name']} (
`ifdef USE_POWER_PINS
    inout  wire GND,
`endif
    input  wire [{rows - 1}:0] WWL,
    input  wire [{rows - 1}:0] RWL,
    input  wire [{cols - 1}:0] WBL,
    inout  wire [{cols - 1}:0] RBL
);
endmodule
""")


if __name__ == "__main__":
    rows = int(sys.argv[1]) if len(sys.argv) > 1 else 32
    cols = int(sys.argv[2]) if len(sys.argv) > 2 else 38
    prefix = sys.argv[3] if len(sys.argv) > 3 else f"GC_ARRAY_{rows}x{cols}"
    lib = gdstk.Library(unit=1e-6, precision=5e-9)
    m, info = build(rows, cols, lib)
    lib.write_gds(prefix + ".gds")
    write_lef(info, prefix + ".lef")
    write_cir(info, prefix + ".cir")
    write_lib(info, prefix + ".lib")
    write_bb(info, prefix + ".bb.v")
    bits = rows * cols
    print(f"{info['name']}: {info['W']:.3f} x {info['H']:.3f} um = {info['W'] * info['H']:.1f} um2, "
          f"{bits} bits, {info['W'] * info['H'] / bits:.3f} um2 per bit (core {info['width']:.3f} x "
          f"{info['top']:.3f} um = {info['width'] * info['top'] / bits:.3f} um2 per bit)")
