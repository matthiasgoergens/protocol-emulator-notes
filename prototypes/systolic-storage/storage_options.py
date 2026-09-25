"""Area per bit of the storage options available to a PE, at IHP SG13G2.

uv run storage_options.py > results/storage_options.txt

Standard-cell and SRAM areas are read from the PDK LEF files (see lef_areas.py). Gain-cell bit
cells come from prototypes/gain-cell (drawn, DRC-clean). The gain-cell *periphery* is NOT drawn:
it is estimated here from standard cells, and every such line is marked "estimate".
"""
import os, re

ROOT = os.path.expanduser("~/.ciel/ihp-sg13g2/ihp-sg13g2/libs.ref")


def lef_sizes(path):
    out, name = {}, None
    for line in open(path):
        m = re.match(r"\s*MACRO\s+(\S+)", line)
        if m:
            name = m.group(1)
        m = re.match(r"\s*SIZE\s+([\d.]+)\s+BY\s+([\d.]+)", line)
        if m and name:
            out[name] = float(m.group(1)) * float(m.group(2))
            name = None
    return out


STD = lef_sizes(f"{ROOT}/sg13g2_stdcell/lef/sg13g2_stdcell.lef")
DFF = STD["sg13g2_dfrbpq_1"]      # smallest flop; the library has no flop without reset
LATCH = STD["sg13g2_dlhq_1"]
MUX2 = STD["sg13g2_mux2_1"]
MUX4 = STD["sg13g2_mux4_1"]
BUF = STD["sg13g2_buf_1"]
INV = STD["sg13g2_inv_1"]
NAND2 = STD["sg13g2_nand2_1"]
A21OI = STD["sg13g2_a21oi_1"]
EBUF = STD["sg13g2_ebufn_2"]

# gain-cell bit cells, strap every 32 columns (prototypes/gain-cell/README.md)
GC_THICK = 2.89   # 3T, thick-oxide write, W 0.15 / L 0.45
GC_THIN = 2.20    # 3T, thin-oxide write, W 0.15 / L 0.13
SRAM_CELL = 3.01  # PDK SRAM bit cell (2.81 x 1.07, prototypes/sram-cut/pdk-cell/refs.txt); unused

# lifetimes of a stored 1, 10 ns sense (prototypes/gain-cell/retention/results/)
LIFE = {  # seconds
    "thick": {"tt27": 12.06e-3, "tt85": 12.21e-3, "ff85": 3.10e-3},
    "thin": {"tt27": 118.8e-6, "tt85": 8.0e-6, "ff85": 1.2e-6},
}


def read_mux_per_bit(words):
    """Area per stored bit of a words:1 read mux built from mux4/mux2 trees."""
    if words <= 1:
        return 0.0
    area, n = 0.0, words
    while n > 1:
        if n >= 4:
            area += (n // 4) * MUX4
            n = n // 4 + n % 4
        else:
            area += (n - 1) * MUX2
            n = 1
    return area / words


def flop_regfile(words, width):
    """Flop register file: flop + hold mux per bit, read mux tree, write decoder (estimate)."""
    bits = words * width
    decoder = words * (NAND2 + A21OI)
    return bits * (DFF + MUX2 + read_mux_per_bit(words)) + decoder


def latch_regfile(words, width):
    """Latch register file: latch per bit, read mux tree, one gated enable per word (estimate)."""
    bits = words * width
    per_word = NAND2 + A21OI + LATCH  # write decode + a glitch-free gate (latch + and) per word
    return bits * (LATCH + read_mux_per_bit(words)) + words * per_word


def shift_line(bits):
    """Fixed-length delay line of flops: no enable, no mux."""
    return bits * DFF


def gain_array(rows, cols, cell):
    """Gain-cell array plus standard-cell periphery (estimate, not drawn).

    per row: write and read word-line drivers + a row-decoder gate;
    per column: write driver, sense inverter, output latch;
    fixed: control and address register.
    """
    per_row = 2 * BUF + NAND2 + A21OI
    per_col = EBUF + INV + LATCH
    fixed = 8 * DFF + 10 * NAND2
    return rows * cols * cell + rows * per_row + cols * per_col + fixed


def sram_macros():
    rows = []
    import glob
    for lef in sorted(glob.glob(f"{ROOT}/sg13g2_sram/lef/*1P_*.lef")):
        for name, a in lef_sizes(lef).items():
            m = re.search(r"_(\d+)x(\d+)_", name)
            rows.append((name, a, int(m.group(1)) * int(m.group(2))))
    return sorted(rows, key=lambda r: r[1])


def main():
    print("# Storage options per PE, IHP SG13G2. Areas in um2 from the PDK LEF unless marked.")
    print(f"# dfrbpq_1 {DFF:.2f}  dlhq_1 {LATCH:.2f}  mux2 {MUX2:.2f}  mux4 {MUX4:.2f}  "
          f"buf_1 {BUF:.2f}  ebufn_2 {EBUF:.2f}")
    print()
    print(f"{'option':44s} {'bits':>6s} {'area':>9s} {'um2/bit':>8s}  note")
    configs = [(8, 16), (16, 16), (32, 16), (64, 16), (256, 16)]
    for w, b in [(1, 16)] + configs[:3]:
        a = shift_line(w * b)
        print(f"{'flop delay line ' + str(w) + 'x' + str(b):44s} {w*b:6d} {a:9.0f} {a/(w*b):8.2f}  LEF")
    for w, b in configs[:4]:
        a = flop_regfile(w, b)
        print(f"{'flop register file ' + str(w) + 'x' + str(b):44s} {w*b:6d} {a:9.0f} {a/(w*b):8.2f}  estimate from LEF cells")
    for w, b in configs[:4]:
        a = latch_regfile(w, b)
        print(f"{'latch register file ' + str(w) + 'x' + str(b):44s} {w*b:6d} {a:9.0f} {a/(w*b):8.2f}  estimate from LEF cells")
    for kind, cell in (("thick", GC_THICK), ("thin", GC_THIN)):
        for r, c in [(16, 16), (32, 16), (32, 32), (64, 32), (128, 32), (256, 32)]:
            a = gain_array(r, c, cell)
            print(f"{'gain-cell ' + kind + ' ' + str(r) + 'x' + str(c):44s} {r*c:6d} {a:9.0f} {a/(r*c):8.2f}  "
                  f"cells drawn, periphery estimate")
    for name, a, bits in sram_macros()[:6]:
        print(f"{'SRAM ' + name:44s} {bits:6d} {a:9.0f} {a/bits:8.2f}  LEF (smallest 1P macros)")
    print()
    print("# lifetimes of a stored 1 (10 ns sense), in us and in 50 MHz cycles")
    for kind, d in LIFE.items():
        for cond, s in d.items():
            print(f"gain-cell {kind:5s} {cond}: {s*1e6:10.1f} us = {s*50e6:10.0f} cycles")


if __name__ == "__main__":
    main()
