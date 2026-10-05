"""Rough yield arithmetic for rule breaks. Every input is an ASSUMPTION stated here, not a
measurement; the point is the shape (which failures row sparing can absorb, and at what cost),
not the absolute numbers.

1. Overlay-limited breaks (Cnt.c 0.02, Cnt.f 0.07, TGO keep-out 0.105, NW 0.24): overlay error is
   mostly systematic per exposure field (translation, rotation, magnification), so a margin that
   is too small fails every cell of the array together; sparing cannot absorb it. Model: the
   array's overlay error ~ N(0, sigma), sigma = 3-sigma / 3, with 3-sigma assumed 45 nm
   (recalled ITRS-era figure for the 130 nm node, NOT re-checked; a mature 130 nm fab on a
   scanner is likely better) and 60 nm (a pessimistic figure for a non-critical implant or
   thick-oxide layer). A die fails when |error| exceeds the margin (the break's value minus the
   minimum physical clearance, assumed below).
2. Random per-cell failures (particles, local CD variation, poly line-end pull-back past the Activ
   edge): independent per bit, probability p. Rows with a failing bit are mapped out
   (per-row profiling, Berger check); bits lost = failing rows x row length."""
import math

def phi_tail(z):
    return 0.5 * math.erfc(z / math.sqrt(2))

print("1. Overlay-limited breaks: fraction of dies whose whole array fails")
print(f"   {'break':44s} {'margin':>7s} {'3s=45nm':>9s} {'3s=60nm':>9s}")
# (name, drawn value, assumed minimum physical clearance for no failure, both in um)
cases = [("Cnt.c 0.02: contact off Activ edge (STI)", 0.02, 0.0),
         ("Cnt.c 0.07 (standard)", 0.07, 0.0),
         ("Cnt.f 0.07: contact onto spacer/gate (clear. 0.03)", 0.07, 0.03),
         ("Cnt.f 0.11 (standard, clearance 0.03)", 0.11, 0.03),
         ("TGO 0.105: edge onto S/D Activ (no gate hit)", 0.105, 0.0),
         ("TGO.c/d 0.34 kept: edge onto a gate", 0.34, 0.0),
         ("NW 0.24 (well edge, overlay part only)", 0.24, 0.12)]
for name, v, clr in cases:
    m = v - clr
    out = [2 * phi_tail(m / (s / 3)) for s in (0.045, 0.060)]
    print(f"   {name:44s} {m:7.3f} {out[0]:9.2e} {out[1]:9.2e}")
print("   Cnt.c 0.02 fails at almost any overlay: the contact then lands partly on STI. IHP's own")
print("   bit cell does exactly this (0.02, upstream deck allows 0.006 under the SRAM marker), so the")
print("   process must tolerate a contact straddling the Activ edge; the cost is contact resistance")
print("   and junction leakage at that contact, not a hard failure. Keep it off storage nodes.")

print("\n2. Random per-bit failures absorbed by mapping out rows (64 kbit)")
for rows, cols in ((256, 256), (512, 128)):
    print(f"   {rows} rows x {cols} bits:")
    for p in (1e-7, 1e-6, 1e-5, 1e-4, 1e-3):
        prow = 1 - (1 - p) ** cols
        lost_rows = rows * prow
        print(f"     p = {p:.0e}: {rows * cols * p:8.2f} failing bits, {lost_rows:7.2f} rows "
              f"mapped out, {lost_rows * cols:8.0f} bits lost ({100 * prow:.2f} %)")
print("\n   The same with column sparing is not modelled: bit lines are shared by all rows, so a")
print("   column fault (a short on the RBL/WBL) costs a column, which the compiler model does not map.")
