# Area budget of the unified chip (notes/architecture-v0.md, section 6) against 6 x 4 IHP tiles.
# Every line names its source; "est" marks an estimate. Run: python3 budget.py > results/budget.txt
import re

TILE = 202.08 * 154.98          # um2, tt-support-tools tile_sizes.yaml (notes/tiny-tapeout-ihp-rules.md)
ALLOC = 24 * TILE

def area(report):
    t = open(f"reports/{report}.stat.txt").read()
    return float(re.search(r"Chip area for module '\\\S+': ([\d.]+)", t).group(1))

PE = area("upe_v0")
# standard-cell logic, Yosys synthesised cell area (um2)
logic = [
    ("sequencer v1 (proxy: CAN variant, shared config, measured)", 29428,
     "sequencer-ps2-can/synth (master); includes 8-bit pc, JC, CFG, tagged OUT"),
    ("segment interconnect, 4 segments, lean", area("xbarlean16k4"), "unified-pe/reports/xbarlean16k4"),
    ("feed registers, 4 x 18 flops (est)", 4 * 18 * 48.99, "LEF flop area x count, est"),
    ("four-phase pin stage, 8 out + 8 in (scaled)", 2633 * 4, "multiphase/sta/synth.log x 4, est"),
    ("pin streamer", 11359, "pin-streamer/README.md"),
    ("pin sampler (also the byte packer)", 12639, "pin-sampler/README.md"),
    ("edge-tracking sampler, 4 samples/clock", 9184, "eth10-node/synth/area.txt (master)"),
    ("edge-tracking sampler, 1 sample/clock", 2991, "eth10-node/synth/area.txt (master)"),
    ("stuff tracker x 2", 2 * area("stuff"), "unified-pe/reports/stuff"),
    ("line coder x 2", 2 * area("linecode"), "unified-pe/reports/linecode"),
    ("systolic matcher with enable", 11422, "eth10-node/synth/area.txt (master)"),
    ("pin NCO, 24 bit, four points per clock", area("pin_nco"), "unified-pe/reports/pin_nco"),
    ("host link (est)", 3000, "est"),
    ("gain-cell refresh, Berger and canary control (est)", 3000, "est"),
    ("reset synchronisers, phase control (est)", 1000, "est"),
]
# drawn or macro blocks, taken at their placed/drawn size (um2)
macros_base = [
    ("gain-cell banks, 2 x 128x32 thick + Berger, placed", 2 * 26618,
     "systolic-storage/results/candidates-placed.txt"),
    ("fine delay: DTC on 2 pins + one TDC line (est)", 2 * 6500 + 2473,
     "multiphase/README.md cheap point; sta/dtc_area.txt; est"),
]
srams = {"256x16": 28127, "512x16": 45309, "1024x16": 79674}   # systolic-storage/results/lef_areas.txt
HALO = 1.10                                                      # est: 10 % around each macro

logic_sum = sum(a for _, a, _ in logic)
print(f"allocation: 24 tiles x {TILE:,.0f} = {ALLOC:,.0f} um2")
print(f"PE (upe_v0, synthesised): {PE:,.0f} um2")
print()
print(f"{'block':62s} {'synth um2':>10s}  source")
for n, a, s in logic:
    print(f"{n:62s} {a:10,.0f}  {s}")
print(f"{'sum of logic other than PEs':62s} {logic_sum:10,.0f}")
for n, a, s in macros_base:
    print(f"{n:62s} {a:10,.0f}  {s} (placed/drawn)")
print()
print("placed total = (logic + N x PE) x factor + (macros + SRAM) x halo")
print("factor 1.5: pe-synth row of 8 PEs, core/synth at 90 % utilisation; 2.0: pessimistic, est")
print(f"{'N PEs':>6s} {'SRAM':>8s} {'factor':>6s} {'placed um2':>11s} {'of alloc':>8s} {'slack um2':>10s}")
for n in (12, 16, 20):
    for sname, sa in srams.items():
        for f in (1.5, 2.0):
            macros = (sum(a for _, a, _ in macros_base) + sa) * HALO
            tot = (logic_sum + n * PE) * f + macros
            print(f"{n:6d} {sname:>8s} {f:6.1f} {tot:11,.0f} {tot / ALLOC:8.1%} {ALLOC - tot:10,.0f}")
