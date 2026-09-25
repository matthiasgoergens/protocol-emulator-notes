"""Extract cell areas from the IHP SG13G2 LEF files (standard cells and SRAM macros).

uv run lef_areas.py > results/lef_areas.txt
"""
import glob, os, re, sys

ROOT = os.path.expanduser("~/.ciel/ihp-sg13g2/ihp-sg13g2/libs.ref")

def macros(path):
    name = None
    for line in open(path):
        m = re.match(r"\s*MACRO\s+(\S+)", line)
        if m:
            name = m.group(1)
        m = re.match(r"\s*SIZE\s+([\d.]+)\s+BY\s+([\d.]+)", line)
        if m and name:
            yield name, float(m.group(1)), float(m.group(2))
            name = None

STORAGE = re.compile(r"sg13g2_(df|dl|sdf|sdl|sig|dll|ebuf)")
print("# Standard-cell storage elements, sg13g2_stdcell.lef (area in um2)")
print(f"# {ROOT}/sg13g2_stdcell/lef/sg13g2_stdcell.lef")
ref = {}
for name, w, h in macros(f"{ROOT}/sg13g2_stdcell/lef/sg13g2_stdcell.lef"):
    ref[name] = w * h
    if STORAGE.match(name) or name in ("sg13g2_mux2_1", "sg13g2_mux4_1", "sg13g2_inv_1",
                                       "sg13g2_nand2_1", "sg13g2_buf_1", "sg13g2_xor2_1",
                                       "sg13g2_fa_1", "sg13g2_ha_1", "sg13g2_a21oi_1"):
        print(f"{name:24s} {w:6.2f} x {h:5.2f} = {w*h:8.2f}")

print()
print("# SRAM macros, sg13g2_sram/lef (area in um2; bits = words x width)")
print(f"{'macro':36s} {'w':>8s} {'h':>8s} {'area':>10s} {'bits':>7s} {'um2/bit':>8s}")
for lef in sorted(glob.glob(f"{ROOT}/sg13g2_sram/lef/*.lef")):
    for name, w, h in macros(lef):
        m = re.search(r"_(\d+)x(\d+)_", name)
        bits = int(m.group(1)) * int(m.group(2))
        print(f"{name:36s} {w:8.2f} {h:8.2f} {w*h:10.0f} {bits:7d} {w*h/bits:8.2f}")
