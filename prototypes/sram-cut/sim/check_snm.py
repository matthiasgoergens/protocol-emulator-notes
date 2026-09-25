"""Cross-check of common.snm (Seevinck's rotation) against a brute-force search for the largest
axis-aligned square in the Q-low lobe of the butterfly, on the tt/27 C curves of the 6T cell.
  python3 check_snm.py DIR   (DIR holds bf_6t_0.3_0.3_0.15_mos_tt_27_{hold,read}_None.dat)"""
import sys
from common import read_table, snm
d = sys.argv[1]
for m in ("hold", "read"):
    t = read_table(f"{d}/bf_6t_0.3_0.3_0.15_mos_tt_27_{m}_None.dat"); s = t["v-sweep"]
    near = lambda v: min(range(len(s)), key=lambda i: abs(s[i] - v))
    fB = lambda x: t["v(yb)"][near(x)]     # QB = fB(Q)
    fA = lambda y: t["v(ya)"][near(y)]     # Q = fA(QB)
    best = 0
    grid = [i * 0.01 for i in range(121)]
    for x0 in grid:
        for y0 in grid:
            lo, hi = 0, 1.2
            for _ in range(20):
                a = (lo + hi) / 2
                ok = (x0 + a <= 1.2 and y0 + a <= 1.2
                      and all(x0 >= fA(y0 + a * k / 10) for k in range(11))
                      and all(y0 + a <= fB(x0 + a * k / 10) for k in range(11)))
                lo, hi = (a, hi) if ok else (lo, a)
            best = max(best, lo)
    print(f"{m}: Seevinck lobes {[round(1e3 * x, 1) for x in snm(s, t['v(ya)'], t['v(yb)'])]} mV; "
          f"brute force (10 mV grid) {1e3 * best:.1f} mV")
