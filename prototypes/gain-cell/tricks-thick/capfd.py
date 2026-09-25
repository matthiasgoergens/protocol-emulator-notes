# /// script
# requires-python = ">=3.11"
# dependencies = ["numpy", "scipy"]
# ///
"""2D finite-difference estimate of the metal capacitance a storage node (SN) can get over the
gain cell, from the IHP SG13G2 back-end stack (process spec rev 1.2, section 2.16: Metal2-5
490 nm thick, 540 nm inter-level oxide, 850 nm Metal5 to TopMetal1; eps_r 4.1; minimum Metal(n)
width 0.20 and space 0.21 um, layout rules Mn.a/Mn.b).

A cross-section is periodic in y (the direction across the lines) and extends in z. Everything
at or below the top of Metal2 is taken as a ground plane (the bit lines and the transistors),
and the top is a zero-flux boundary. One run reports, per um of line length, the capacitance of
the SN conductor to the counter-electrode (CE) conductors and to the ground plane.

Check of the method: a wide parallel plate pair must give eps/d (--check).
Usage: uv run capfd.py [--check]"""
import sys
import numpy as np
import scipy.sparse as sp
import scipy.sparse.linalg as spl

EPS0 = 8.854e-3          # fF/um
ER = 4.1
H = 0.005                # grid, um
Z = {"M2top": 2.09, "M3": (2.63, 3.12), "M4": (3.66, 4.15), "M5": (4.69, 5.18), "TM1": (6.03, 8.03)}

def solve(period, zmax, conductors, zmin=Z["M2top"]):
    """conductors: list of (name, potential, [(y0, y1, z0, z1), ...]). Returns (C_total of the
    conductor at potential 1 in fF/um, flux into each other conductor and the ground plane)."""
    ny, nz = int(round(period / H)), int(round((zmax - zmin) / H)) + 1
    ys = (np.arange(ny) + 0.5) * H
    zs = zmin + np.arange(nz) * H
    fixed = np.full((ny, nz), np.nan)
    owner = np.full((ny, nz), -1)
    fixed[:, 0] = 0.0                                  # ground plane
    for k, (name, v, rects) in enumerate(conductors):
        for y0, y1, z0, z1 in rects:
            m = (((ys >= y0) & (ys <= y1))[:, None]) & (((zs >= z0 - 1e-9) & (zs <= z1 + 1e-9))[None, :])
            fixed[m] = v
            owner[m] = k
    idx = -np.ones((ny, nz), int)
    free = np.isnan(fixed)
    idx[free] = np.arange(free.sum())
    n = free.sum()
    rows, cols, vals = [], [], []
    b = np.zeros(n)
    for j in range(ny):
        for k in range(nz):
            if not free[j, k]:
                continue
            i = idx[j, k]
            diag = 0.0
            for dj, dk in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                jj, kk = (j + dj) % ny, k + dk        # periodic in y
                if kk >= nz:                          # zero flux at the top
                    continue
                diag += 1
                if free[jj, kk]:
                    rows.append(i); cols.append(idx[jj, kk]); vals.append(-1.0)
                else:
                    b[i] += fixed[jj, kk]
            rows.append(i); cols.append(i); vals.append(diag)
    A = sp.csr_matrix((vals, (rows, cols)), shape=(n, n))
    phi = fixed.copy()
    phi[free] = spl.spsolve(A, b)
    # energy: C = eps * integral |grad phi|^2 (one conductor at 1 V, all else at 0)
    gy = (np.roll(phi, -1, 0) - phi) / H
    gz = np.diff(phi, axis=1) / H
    energy = ER * EPS0 * (np.sum(gy ** 2) + np.sum(gz ** 2)) * H * H
    # flux into each fixed conductor at 0 V: sum over its boundary faces of eps * (phi_free - 0)/H
    flux = {"ground": 0.0}
    for j in range(ny):
        for k in range(nz):
            if free[j, k]:
                continue
            key = "ground" if owner[j, k] < 0 else conductors[owner[j, k]][0]
            if fixed[j, k] != 0.0:
                continue
            for dj, dk in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                jj, kk = (j + dj) % ny, k + dk
                if 0 <= kk < nz and free[jj, kk]:
                    flux[key] = flux.get(key, 0.0) + ER * EPS0 * phi[jj, kk]
    return energy, flux

if "--check" in sys.argv:
    # parallel plates 10 um wide, 0.54 um apart, periodic: expect eps*10/0.54 fF/um
    e, f = solve(10.0, 6.0, [("top", 1.0, [(0, 10, 3.66, 4.15)]), ("bot", 0.0, [(0, 10, 2.63, 3.12)])])
    print(f"check: plates 10 um wide, 0.54 apart: {e:.4f} fF/um, expected {ER * EPS0 * 10 / 0.54:.4f}; flux {f}")
    raise SystemExit

w, s = 0.20, 0.21
p = 2 * (w + s)          # one SN line and one CE line per period
print(f"line width {w}, space {s} (pitch {w + s}); per um of line length, fF/um")
# A: Metal4 lines alternating SN / CE; Metal5 above is a CE plate, Metal3 below absent
for m5 in ("CE plate", "absent"):
    cond = [("SN", 1.0, [(0.0, w, *Z["M4"])]), ("CE", 0.0, [(w + s, 2 * w + s, *Z["M4"])])]
    if m5 == "CE plate":
        cond.append(("CE5", 0.0, [(0.0, p, *Z["M5"])]))
    e, f = solve(p, 7.0, cond)
    print(f"A  M4 SN|CE alternating, M5 {m5:8s}: SN total {e:.4f}; to CE {f.get('CE', 0) + f.get('CE5', 0):.4f}"
          f" (M4 neighbours {f.get('CE', 0):.4f}, M5 {f.get('CE5', 0):.4f}); to ground {f['ground']:.4f}")
# B: M4 and M5 both alternating, SN above CE and CE above SN (a woven stack)
cond = [("SN", 1.0, [(0.0, w, *Z["M4"]), (w + s, 2 * w + s, *Z["M5"])]),
        ("CE", 0.0, [(w + s, 2 * w + s, *Z["M4"]), (0.0, w, *Z["M5"])])]
e, f = solve(p, 7.0, cond)
print(f"B  M4+M5 alternating, crossed (per period {p} um = 2 SN lines): SN total {e:.4f}; to CE {f.get('CE', 0):.4f};"
      f" to ground {f['ground']:.4f}")
# C: M3, M4, M5 all alternating, crossed
cond = [("SN", 1.0, [(0.0, w, *Z["M4"]), (w + s, 2 * w + s, *Z["M5"]), (w + s, 2 * w + s, *Z["M3"])]),
        ("CE", 0.0, [(w + s, 2 * w + s, *Z["M4"]), (0.0, w, *Z["M5"]), (0.0, w, *Z["M3"])])]
e, f = solve(p, 7.0, cond)
print(f"C  M3+M4+M5 alternating, crossed (per period = 3 SN lines): SN total {e:.4f}; to CE {f.get('CE', 0):.4f};"
      f" to ground {f['ground']:.4f}")
