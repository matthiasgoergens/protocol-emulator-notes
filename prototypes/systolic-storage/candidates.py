"""Candidate systolic arrays with storage inside, at a fixed 200k um2 budget (array + storage).

uv run candidates.py > results/candidates.txt

PE area is an ESTIMATE: a 16-bit PE (add/sub/min/max with saturation, one neighbour input, a
16-bit state and a 16-bit pipeline register, about 24 configuration flops), scaled from the
semiring ring's measured 10,603 um2 per 24-bit cell with two 5-way source muxes and 53
configuration flops (semiring-ring/README.md: 169,641 um2 for 16 cells). Storage areas come from
storage_options.py (LEF cells; gain-cell periphery estimated).
"""
import math

import storage_options as so

BUDGET = 200_000
A_PE = 5_000            # estimate, see docstring
GUARD = 0.8


def berger(w):
    return math.ceil(math.log2(w + 1))


def gbank(rows, width, kind):
    cols = width + berger(width)
    cell = so.GC_THICK if kind == "thick" else so.GC_THIN
    return so.gain_array(rows, cols, cell), rows * width


# storage blocks: (name, area, bits, ports, kind)
def designs():
    out = []
    # D0: uniform, no storage beyond each PE's two registers
    n = BUDGET // A_PE
    out.append(("D0 uniform, no storage", n, [], "pipeline registers only: 32 flop bits per PE"))
    # D1: uniform, an 8x16 latch register file in every PE
    rf = so.latch_regfile(8, 16)
    n = int(BUDGET // (A_PE + rf))
    out.append(("D1 uniform, 8x16 latch RF per PE", n, [("latch RF", rf, 128, 1, "static")] * n,
                "every PE can hold 8 words"))
    # D2: edge storage column of thick-oxide gain-cell banks; same bits and ports as D2s
    a, bits = gbank(128, 32, "thick")
    nb = 2
    n = int((BUDGET - nb * a) // A_PE)
    out.append(("D2 edge column, 2 thick banks 128x32", n, [("thick bank", a, bits, 1, "thick")] * nb,
                "storage at the array's edge, one port per bank"))
    # D2s: the same budget with the smallest SRAM macros instead
    sa = 28127.0  # RM_IHPSG13_1P_256x16_c2_bm_bist, from results/lef_areas.txt
    ns = 2
    n = int((BUDGET - ns * sa) // A_PE)
    out.append(("D2s edge column, 2 SRAM 256x16 macros", n, [("SRAM 256x16", sa, 4096, 1, "static")] * ns,
                "same idea with PDK macros"))
    # D3: graded: a thin bank beside every 4th PE (short-lived values near the producer),
    #     thick banks at the far edge (values that age as they flow)
    ta, tbits = gbank(32, 16, "thin")
    ka, kbits = gbank(128, 32, "thick")
    nk = 2
    n = 0
    while (n + 1) * A_PE + ((n + 1 + 3) // 4) * ta + nk * ka <= BUDGET:
        n += 1
    nt = (n + 3) // 4
    out.append(("D3 graded: thin 32x16 per 4 PEs + 2 thick 128x32 at the edge", n,
                [("thin bank", ta, tbits, 1, "thin")] * nt + [("thick bank", ka, kbits, 1, "thick")] * nk,
                "dense short-lived storage near producers, long-lived at the edge"))
    # D4: the array itself as a delay line (recirculate through pipeline registers)
    n = BUDGET // A_PE
    out.append(("D4 array as delay line", n, [], "any PE can be switched to pass-through: 32 bits of delay per PE"))
    return out


# workloads: (name, bits needed, longest interval in us, words accessed per cycle, PEs needed)
WORKLOADS = [
    ("vertical 3-tap filter, 256x8-bit lines", 2 * 256 * 8, 127.4, 0.1, 3),
    ("vertical 2-tap filter", 256 * 8, 63.4, 0.1, 2),
    ("Ethernet line buffer, 5 lines/packet", 117 * 32, 603.2, 0.05, 1),
    ("Ethernet line buffer, 20 lines/packet", 296 * 32, 1561.4, 0.05, 1),
    ("USB FS packet buffer, 64 bytes", 512, 60.0, 0.05, 1),
    ("sequencer programme store, 4x64x16", 4096, float("inf"), 1.0, 0),
    ("8x8 16-bit product, weights in 8 PEs", 1024, 20000.0, 8.0, 8),
    ("next-frame ring config (double buffer)", 848, 20000.0, 0.01, 16),
    ("systolic matcher / sorting network", 0, 0.1, 0.0, 16),
    # illustrative: 16 PEs merging sorted runs held beside them, 4 words per cycle, 20 us each
    ("16-PE merge, local runs, 4 words/cycle", 2048, 20.0, 4.0, 16),
    # illustrative: 8x8 corner turn in 8 PEs, a block lives 64 cycles
    ("8x8 corner turn, 2 words/cycle", 1024, 1.28, 2.0, 8),
]


def life_us(kind, cond):
    if kind == "static":
        return float("inf")
    return so.LIFE[kind][cond] * 1e6 * GUARD


def verdict(design, w):
    name, npe, blocks, _ = design
    wname, bits, life, rate, pes = w
    if pes > npe:
        return "N (PEs)"
    if bits == 0:
        return "Y"
    if not blocks:
        # D0/D4: flops inside PEs; D4 may spend PEs as delay
        spare = npe - pes
        if name.startswith("D4") and bits <= spare * 32 and life < 1e4:
            return f"Y* ({math.ceil(bits/32)} PEs as delay)"
        return "N (no storage)"
    if pes:
        # a bank beside every 4th PE serves only the PEs next to it
        local = [b for b in blocks if b[0] == "thin bank"][: math.ceil(pes / 4)]
        blocks = local + [b for b in blocks if b[0] != "thin bank"]
    total = sum(b[2] for b in blocks)
    ports = sum(b[3] for b in blocks)
    if rate > ports:
        return f"N ({ports} ports)"
    if bits > total:
        return f"N ({total} bits)"
    edge_ports = sum(b[3] for b in blocks if b[0] != "thin bank")
    if rate > edge_ports:
        # the bandwidth only exists beside the PEs, so the data must live there
        blocks = [b for b in blocks if b[0] == "thin bank"]
        if bits > sum(b[2] for b in blocks):
            return "N (local bits)"
    out = []
    for cond in ("tt27", "tt85", "ff85"):
        # fill the longest-lived blocks first; what spills to shorter-lived ones is refreshed
        need, bw = bits, 0.0
        for b in sorted(blocks, key=lambda b: -life_us(b[4], cond)):
            take = min(need, b[2])
            if take and life_us(b[4], cond) < life:
                bw += 2 * math.ceil(take / 32) / (life_us(b[4], cond) * 50)
            need -= take
            if not need:
                break
        out.append("Y" if bw == 0 else (f"R{bw*100:.1f}%" if bw < 1 else "N"))
    return "/".join(out)


def main():
    print(f"# budget {BUDGET} um2 for PEs + storage; PE {A_PE} um2 (estimate); guard {GUARD}")
    print("# verdicts per condition tt27/tt85/ff85: Y fits without refresh, R<x>% needs refresh"
          " at x% of one port's cycles, N does not fit\n")
    ds = designs()
    for d in ds:
        name, npe, blocks, note = d
        sa = sum(b[1] for b in blocks)
        bits = sum(b[2] for b in blocks)
        print(f"{name}: {npe} PEs ({npe*A_PE} um2) + storage {sa:.0f} um2 = {npe*A_PE+sa:.0f} um2;"
              f" {bits} storage bits in {len(blocks)} blocks; {note}")
        kinds = {}
        for b in blocks:
            kinds.setdefault(b[0], [0, 0.0, 0])
            kinds[b[0]][0] += 1
            kinds[b[0]][1] += b[1]
            kinds[b[0]][2] += b[2]
        for k, (c, a, bt) in kinds.items():
            print(f"    {c} x {k}: {a/c:.0f} um2 each, {bt//c} bits, {a/bt:.2f} um2/bit")
    print()
    print(f"{'workload':42s}" + "".join(f"{d[0][:3]:>22s}" for d in ds))
    for w in WORKLOADS:
        print(f"{w[0]:42s}" + "".join(f"{verdict(d, w):>22s}" for d in ds))


if __name__ == "__main__":
    main()
