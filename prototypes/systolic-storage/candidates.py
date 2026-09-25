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


# storage blocks: (name, area, bits, kind, port width in bits); one port per block
def designs():
    out = []
    # D0: uniform, no storage beyond each PE's two registers
    n = BUDGET // A_PE
    out.append(("D0 uniform, no storage", n, [], "pipeline registers only: 32 flop bits per PE"))
    # D1: uniform, an 8x16 latch register file in every PE
    rf = so.latch_regfile(8, 16)
    n = int(BUDGET // (A_PE + rf))
    out.append(("D1 uniform, 8x16 latch RF per PE", n, [("local RF", rf, 128, "static", 16)] * n,
                "every PE can hold 8 words"))
    # D2: edge storage column of thick-oxide gain-cell banks; same bits as D2s
    a, bits = gbank(128, 32, "thick")
    nb = 2
    n = int((BUDGET - nb * a) // A_PE)
    out.append(("D2 edge column, 2 thick banks 128x32", n, [("thick bank", a, bits, "thick", 32)] * nb,
                "storage at the array's edge"))
    # D2s: the same bits with the smallest 4 kbit SRAM macros instead
    sa = 28127.0  # RM_IHPSG13_1P_256x16_c2_bm_bist, from results/lef_areas.txt
    ns = 2
    n = int((BUDGET - ns * sa) // A_PE)
    out.append(("D2s edge column, 2 SRAM 256x16 macros", n, [("SRAM 256x16", sa, 4096, "static", 16)] * ns,
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
                [("local thin bank", ta, tbits, "thin", 16)] * nt + [("thick bank", ka, kbits, "thick", 32)] * nk,
                "dense short-lived storage near producers, long-lived at the edge"))
    # D4: the array itself as a delay line (recirculate through pipeline registers)
    n = BUDGET // A_PE
    out.append(("D4 array as delay line", n, [], "any PE can be switched to pass-through: 32 bits of delay per PE"))
    return out


# workloads: (name, bits needed, longest value life in us, bits accessed per cycle, PEs needed)
# rates: vfir writes 8 bits and reads (k-1) x 8 per 10-cycle pixel; the line buffer moves 768 bits
# in and out per 3200-cycle line; USB FS 12 Mbit/s in and out; the sequencer fetches 16 bits per
# cycle; the product reads 8 x 16-bit weights per cycle; the merge 4 x 16 bits per cycle.
WORKLOADS = [
    ("vertical 3-tap filter, 256x8-bit lines", 2 * 256 * 8, 127.4, 2.4, 3),
    ("vertical 2-tap filter", 256 * 8, 63.4, 1.6, 2),
    ("Ethernet line buffer, 5 lines/packet", 117 * 32, 603.2, 0.24, 1),
    ("Ethernet line buffer, 20 lines/packet", 296 * 32, 1561.4, 0.24, 1),
    ("USB FS packet buffer, 64 bytes", 512, 60.0, 0.48, 1),
    ("sequencer programme store, 4x64x16", 4096, float("inf"), 16.0, 0),
    ("8x8 16-bit product, weights in 8 PEs", 1024, 20000.0, 128.0, 8),
    ("next-frame ring config (double buffer)", 848, 20000.0, 0.01, 16),
    ("systolic matcher / sorting network", 0, 0.1, 0.0, 16),
    # illustrative: 16 PEs merging sorted runs held beside them, 20 us each
    ("16-PE merge, local runs, 4x16 bit/cycle", 2048, 20.0, 64.0, 16),
    # illustrative: 8x8 corner turn in 8 PEs, a block lives 64 cycles
    ("8x8 corner turn, 2x16 bit/cycle", 1024, 1.28, 32.0, 8),
]


def life_us(kind, cond):
    if kind == "static":
        return float("inf")
    return so.LIFE[kind][cond] * 1e6 * GUARD


def verdict(design, w):
    """One port per block, one access of its width per cycle. Workload traffic is spread over
    the blocks in proportion to the bits they hold; a block holding values that outlive it also
    spends 2 cycles per row per lifetime refreshing. A block over 100 % fails."""
    name, npe, blocks, _ = design
    wname, bits, life, rate, pes = w
    if pes > npe:
        return "N (PEs)"
    if bits == 0:
        return "Y"
    if not blocks:
        spare = npe - pes
        if name.startswith("D4") and bits <= spare * 32 and life < 1e4:
            return f"Y* ({math.ceil(bits/32)} PEs as delay)"
        return "N (no storage)"
    # the same reachability rule for every design: all storage is reachable unless the rate
    # exceeds what the edge blocks plus a 16-bit path through the array (to storage beside
    # other PEs) can deliver; then only the storage beside the PEs used
    shared = [b for b in blocks if not b[0].startswith("local")]
    via_array = 16 if any(b[0].startswith("local") for b in blocks) else 0
    if rate > sum(b[4] for b in shared) + via_array:
        per = 1 if name.startswith("D1") else 4
        blocks = [b for b in blocks if b[0].startswith("local")][: math.ceil(max(pes, 1) / per)]
        if not blocks:
            return "N (bandwidth)"
    if bits > sum(b[2] for b in blocks):
        return f"N ({sum(b[2] for b in blocks)} bits)"

    def spread(bs):
        """Place bits in proportion to port width, capped by capacity."""
        take, need = [0] * len(bs), bits
        while need > 0:
            open_ = [i for i, b in enumerate(bs) if take[i] < b[2]]
            if not open_:
                return None
            w = sum(bs[i][4] for i in open_)
            round_need = need
            for i in open_:
                t = min(bs[i][2] - take[i], max(1, math.ceil(round_need * bs[i][4] / w)), need)
                take[i] += t
                need -= t
                if need == 0:
                    break
        return take

    def longest_first(bs, cond):
        take, need = [], bits
        for b in bs:
            t = min(need, b[2])
            take.append(t)
            need -= t
        return take

    def score(bs, take, cond):
        worst, refresh = 0.0, 0.0
        for b, t in zip(bs, take):
            if not t:
                continue
            util = rate * t / bits / b[4]
            if life_us(b[3], cond) < life:
                r = 2 * math.ceil(t / b[4]) / (life_us(b[3], cond) * 50)
                refresh = max(refresh, r)
                util += r
            worst = max(worst, util)
        return (2, 0) if worst > 1 + 1e-9 else ((0, 0) if refresh == 0 else (1, refresh))

    out = []
    local = [b for b in blocks if b[0].startswith("local")]
    for cond in ("tt27", "tt85", "ff85"):
        bs = sorted(blocks, key=lambda b: -life_us(b[3], cond))
        tries = [(bs, longest_first(bs, cond)), (bs, spread(bs))]
        if local and sum(b[2] for b in local) >= bits:
            tries.append((local, spread(local)))
        durable = [b for b in blocks if life_us(b[3], cond) >= life]
        if durable and sum(b[2] for b in durable) >= bits:
            tries.append((durable, spread(durable)))
        best = min(score(x, t, cond) for x, t in tries if t is not None)
        out.append({0: "Y", 1: f"R{best[1]*100:.1f}%", 2: "N"}[best[0]])
    return "/".join(out)


def main():
    print(f"# budget {BUDGET} um2 for PEs + storage; PE {A_PE} um2 (estimate); guard {GUARD}")
    print("# verdicts per condition tt27/tt85/ff85: Y fits without refresh, R<x>% needs refresh"
          " at x% of the busiest bank's port cycles, N does not fit (capacity, or port over 100%)\n")
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
