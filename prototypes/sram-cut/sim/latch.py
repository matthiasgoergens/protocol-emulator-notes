"""Leakage of the standard-cell latch sg13g2_dlhq_1 holding a bit (GATE low, D low), per corner and
temperature, averaged over the two stored values. Same model decks as the bit cells.
  ./run.sh RUN latch.py"""
from common import *

def one(ct):
    c, t = ct
    res = []
    for q in (0, 1):
        name = f"latch_{c}_{t}_{q}"
        ckt = (f"* dlhq_1 leakage\n" + libs(c) + f".temp {t}\n"
               ".include /pdk/libs.ref/sg13g2_stdcell/spice/sg13g2_stdcell.spice\n"
               f"vdd vdd 0 {VDD}\nvg g 0 0\nvd d 0 0\nX1 q d g vdd 0 sg13g2_dlhq_1\n"
               f".nodeset v(X1.qint)={0 if q else VDD} v(q)={q * VDD}\n")
        out = run(name, ckt + control("op\nprint v(q)\nlet il = -i(vdd)\nprint il"))
        res.append((meas(out, "v\\(q\\)"), meas(out, "il")))
    return c, t, res

print("sg13g2_dlhq_1 holding (GATE 0, D 0): leakage from VDD, pA, for Q = 0 and Q = 1")
for c, t, res in pmap(one, [(c, t) for c in CORNERS for t in TEMPS]):
    print(f"{c:7s} {t:3d}  Q={res[0][0]:.2f}: {1e12*res[0][1]:9.1f}   Q={res[1][0]:.2f}: {1e12*res[1][1]:9.1f}   "
          f"mean {0.5e12*(res[0][1]+res[1][1]):9.1f}")
