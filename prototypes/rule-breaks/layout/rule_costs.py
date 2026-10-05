"""Area per bit that each rule costs, from the generators themselves (so Metal floors and the
interactions between rules are included): relax one rule at a time from a base rule set and
report the change in area per bit. 'occupancy' is the length the rule's value takes up in the
pitch (value times the number of times it appears in the pitch) times the other pitch, per bit.

  uv run --with gdstk rule_costs.py > rule-costs.txt"""
import sys
sys.argv = ["x"]
import gain_rb as g
import sram6t_rb as s

def gain_area(rules, ox, every=32):
    g.configure(**rules)
    v = g.V("3T", ox, 0.45 if ox != "thin" else 0.13, True)
    return round((g.PX + g.swidth(v) / every) * g.geometry(v)["H"], 4), g.PX, g.geometry(v)["H"]

def sram_area(rules):
    s.configure(**rules)
    return round(4 * s.XB * s.YB, 4), 2 * s.XB, 2 * s.YB

print("# gain cells (3T, dogbone write transistor, strap every 32 columns); areas in um2 per bit")
steps = [("Cnt.c across the strips (x)", "cnt_c", 0.02), ("Gat.c end cap (x)", "gat_c", 0.13),
         ("Cnt.c along the strips (y)", "cnt_c_end", 0.02), ("Cnt.f contact to gate (y)", "cnt_f", 0.07),
         ("Cnt.d poly pad (x, y; ignores Cnt.e, not drawn)", "cnt_d", 0.02),
         ("TGO.a + TGO.b keep-out (y, thick write only)", ("tgo_a", "tgo_b"), 0.105)]
for ox in ("thin", "thick", "allthick"):
    base = dict(g.STANDARD)
    a0, px0, h0 = gain_area(base, ox)
    print(f"\n{ox}: standard {a0} ({px0} x {h0})")
    for name, key, val in steps:
        keys = key if isinstance(key, tuple) else (key,)
        r = dict(base, **{k: val for k in keys})
        a, px, h = gain_area(r, ox)
        print(f"  {name:45s} {g.STANDARD[keys[0]]} -> {val}: {a} ({px} x {h}), saves {a0 - a:.4f} ({100 * (a0 - a) / a0:.1f} %)")
    for label, r in (("PDK values (tier 0)", g.PDK),
                     ("tier 1 (+ Cnt.c 0.02 along the strips)", dict(g.PDK, cnt_c_end=0.02)),
                     ("tier 2 (+ TGO 0.105, Cnt.f 0.07)", dict(g.PDK, cnt_c_end=0.02, tgo_a=0.105, tgo_b=0.105, cnt_f=0.07))):
        a, px, h = gain_area(r, ox)
        print(f"  {label:45s} {a} ({px} x {h}), saves {a0 - a:.4f} ({100 * (a0 - a) / a0:.1f} %)")

print("\n# 6T (core cell; y = 1.07 is set by Metal1 and unchanged)")
a0, x0, y0 = sram_area(s.STANDARD)
print(f"standard {a0} ({x0} x {y0})")
for name, key, val in (("Cnt.c PMOS pads 0.30 -> 0.20", "cnt_c", 0.02), ("NW.c", "nw_c", 0.27), ("NW.d", "nw_d", 0.27),
                       ("Gat.c NMOS", "gat_c_n", 0.17), ("Gat.c PMOS", "gat_c_p", 0.13)):
    a, x, y = sram_area(dict(s.STANDARD, **{key: val}))
    print(f"  {name:30s} -> {val}: {a} ({x:.3f}), saves {a0 - a:.4f} ({100 * (a0 - a) / a0:.1f} %)")
for label, r in (("PDK values (tier 0)", s.PDK), ("PDK + Gat.c NMOS 0.13", dict(s.PDK, gat_c_n=0.13)),
                 ("PDK + NW.c/NW.d 0.24 (tier 2)", dict(s.PDK, nw_c=0.24, nw_d=0.24)),
                 ("PDK + NW.c/NW.d 0.20 (not drawable here)", dict(s.PDK, nw_c=0.20, nw_d=0.20))):
    a, x, y = sram_area(r)
    print(f"  {label:40s} {a} ({x:.3f}), saves {a0 - a:.4f} ({100 * (a0 - a) / a0:.1f} %)")
