# /// script
# requires-python = ">=3.11"
# ///
"""Area of the platformer chip built from generic blocks, against the special-purpose retro console.
Cell areas: Yosys 0.62 in the LibreLane 3.0.14 container, sg13g2 typical liberty (synth.sh ->
reports/). Memories: thick gain-cell banks, cells drawn and periphery estimated
(../systolic-storage/results/storage_options.txt).
    uv run area.py > results/area.txt"""
import re, pathlib

def area(name):
    t = pathlib.Path(f"reports/{name}.stat.txt").read_text()
    return float(re.search(r"Chip area for module '\\\w+': ([0-9.]+)", t).group(1))

PE16 = 6586          # ../pe-synth/results/areas.txt, the same flow
NPE = 18             # 2 tile cells + 16 sprite cells (video.ml)
mem = {  # bits, um2/bit of the nearest bank in storage_options.txt
    "line buffer, 2 x 256 x 19 (video.ml)": (2 * 256 * 19, 33777 / 8192),
    "colour table, 64 x 14 (video.ml)": (64 * 14, 6153 / 1024),
    "sequencer programme, 4 x 64 x 16 (resident; 0.1-0.4 % refresh)": (4 * 64 * 16, 17992 / 4096),
}
logic = {"feeder": area("feeder"), "output port": area("outport"), "deadline sequencer": area("deadline_sequencer")}
mem_total = sum(b * a for b, a in mem.values())
print(f"{'block':58s} {'um2':>10s}")
for variant in ("pex", "pex_lean"):
    pe = area(variant)
    print(f"\n-- with {variant} ({pe:,.0f} um2 each; pe16 is {PE16:,}: {pe / PE16:.2f}x)")
    print(f"{NPE} x {variant:52s} {NPE * pe:10,.0f}")
    for k, v in logic.items():
        print(f"{k:58s} {v:10,.0f}")
    for k, (b, a) in mem.items():
        print(f"{k + f' ({b} bits)':58s} {b * a:10,.0f}")
    total = NPE * pe + sum(logic.values()) + mem_total
    print(f"{'total':58s} {total:10,.0f}")
    print(f"{'  of which the 18 PEs':58s} {NPE * pe:10,.0f} ({100 * NPE * pe / total:.0f} %)")
con = area("retro_console")
print(f"\nretro console (special purpose, PAL build, same flow): {con:,.0f} um2, no memories")
for variant in ("pex", "pex_lean"):
    total = NPE * area(variant) + sum(logic.values()) + mem_total
    print(f"  generic chip with {variant} / console: {total / con:.1f}x")
print(f"  per display cell: console {con / 16:,.0f} um2 per sprite cell including its share of timing, colour and the"
      f" double-buffered packet; PE-X {area('pex'):,.0f} / {area('pex_lean'):,.0f} um2")
# incremental: on a chip that already has 18 pe16s, the sequencer and its programme memory
for variant in ("pex", "pex_lean"):
    ext = NPE * (area(variant) - PE16)
    extra_mem = sum(b * a for k, (b, a) in mem.items() if "programme" not in k)
    inc = ext + area("feeder") + area("outport") + extra_mem
    print(f"  incremental with {variant}: PE extensions {ext:,.0f} + feeder and output port"
          f" {area('feeder') + area('outport'):,.0f} + line buffer and colour table {extra_mem:,.0f}"
          f" = {inc:,.0f} um2 = {inc / con:.2f}x the console")
