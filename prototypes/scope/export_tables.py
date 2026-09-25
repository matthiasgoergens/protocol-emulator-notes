"""Write the SPICE-derived tables the OCaml models read (ocaml/data/*.csv):
pad_iv_tt.csv   the thick-oxide inverter current I(va, vin), tt 25 C (results/pad-iv.npz): first
                row the vin grid, first column the va grid
pad_params.csv  the fitted comparator parameters (results/padmodel-fit.txt)
kick_r500.csv   kicked sampling, 500 ps kick (results/kick.npz): delta,delay and pos,w
Run: uv run --with numpy python export_tables.py
"""
import numpy as np, os
from padmodel import Pad, VT_SPICE
here = os.path.dirname(os.path.abspath(__file__)); out = os.path.join(here, "ocaml", "data")
z = np.load(os.path.join(here, "results", "pad-iv.npz"))
with open(os.path.join(out, "pad_iv_tt.csv"), "w") as f:
    f.write("nan," + ",".join(f"{x:.4f}" for x in z["vin"]) + "\n")
    for va, row in zip(z["va"], z["tt"]):
        f.write(f"{va:.4f}," + ",".join(f"{x:.6e}" for x in row) + "\n")
p = Pad()
with open(os.path.join(out, "pad_params.csv"), "w") as f:
    f.write(f"C_a,{p.C_a:.6e}\nC_m,{p.C_m:.6e}\ntau_in,{p.tau_in:.6e}\nv_lv,{p.v_lv}\nd_lv,{p.d_lv:.6e}\nvt,{VT_SPICE}\n")
k = np.load(os.path.join(here, "results", "kick.npz"))
with open(os.path.join(out, "kick_r500.csv"), "w") as f:
    for d, y in zip(k["r500_deltas"], k["r500_delay"]):
        if np.isfinite(y): f.write(f"D,{d:.5f},{y:.6e}\n")
    for p_, w in zip(k["r500_pos"], k["r500_w"]):
        f.write(f"W,{p_:.6e},{w:.6e}\n")
print("wrote", os.listdir(out))
# differential check data for the OCaml port of the pad: kick waveforms at five levels, 2 ps grid,
# 8 ns long, kick at 3 ns with a 500 ps rise; Python's pad-output edge time for each
dt = 2e-12; t = np.arange(0, 8e-9, dt)
with open(os.path.join(out, "padcheck.csv"), "w") as f:
    for d in (-0.12, -0.05, 0.0, 0.05, 0.15):
        v = VT_SPICE - 0.25 + d + 0.5 * np.clip((t - 3e-9) / 500e-12, 0, 1)
        core = p.run(v[None, :], dt)[0]
        f.write(f"{d},{t[np.argmax(core)]:.6e}\n")
print("wrote padcheck.csv")
