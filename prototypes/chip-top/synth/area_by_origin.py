#!/usr/bin/env python3
"""Approximate standard-cell area per RTL origin, from a run's synthesis netlist.
  synth/area_by_origin.py RUN_DIR MAP [DEPTH]
Each flip-flop belongs to the OCaml call site that built it (MAP from bin/origins.exe); each
combinational cell is shared equally among the flip-flops and macro or output pins its output
reaches before the next flip-flop. Origins are cut to DEPTH call sites (default 1, the innermost
outside the library). Approximate: shared logic is split evenly, not by who needs it."""
import re, sys, os, collections
run, mapf = sys.argv[1], sys.argv[2]
depth = int(sys.argv[3]) if len(sys.argv) > 3 else 1
PDK = os.environ.get("PDK_ROOT", "/var/tmp/roundtrip-cmos5l/pdk")
lib = open(f"{PDK}/ihp-sg13cmos5l/libs.ref/sg13cmos5l_stdcell/lib/sg13cmos5l_stdcell_typ_1p20V_25C.lib").read()
area = {m.group(1): float(m.group(2)) for m in re.finditer(r"cell\s*\(\"?(\w+)\"?\)\s*\{[^}]*?area\s*:\s*([\d.]+)", lib)}
origin = {}
for line in open(mapf):
    f = line.rstrip("\n").split("\t")
    fr = [x.rsplit(":", 1)[0].replace("blocks/", "") for x in f[3].split() if not x.startswith(("bin/", "src/signal__type"))]
    if len(fr) > 1:
        fr = [x for x in fr if not x.startswith("src/tt_top")]
    origin[f[0]] = " < ".join(fr[:depth]) or "?"
synth = [d for d in sorted(os.listdir(run)) if d.endswith("yosys-synthesis")][0]
txt = open(os.path.join(run, synth, "tt_um_chip_top.nl.v")).read()
insts = {}
for m in re.finditer(r"^\s*(\w+)\s+(\\?\S+)\s*\((.*?)\);", txt, re.S | re.M):
    cell, inst, body = m.groups()
    if cell in ("module", "wire", "input", "output", "assign"):
        continue
    insts[inst] = (cell, dict((p, n.strip()) for p, n in re.findall(r"\.(\w+)\(([^()]*)\)", body)))
OUT = {"X", "Y", "Q", "L_HI", "L_LO"}
sinks = collections.defaultdict(list)
for i, (c, ps) in insts.items():
    for p, n in ps.items():
        if p not in OUT:
            sinks[n].append(i)
def flop_origin(i):
    q = insts[i][1].get("Q", "")
    m = re.match(r"\\?chip\.(\w+?)(\[\d+\])?\s*$", q)
    return origin.get(m.group(1), "?") if m else "? (" + q[:30] + ")"
memo = {}
def reach(i):
    """the set of flip-flop/macro origins combinational cell i feeds"""
    if i in memo:
        return memo[i]
    memo[i] = frozenset()
    res = set()
    for p, n in insts[i][1].items():
        if p in OUT:
            if not sinks.get(n):
                res.add("output port")
            for j in sinks.get(n, []):
                c = insts[j][0]
                if "dfrbp" in c:
                    res.add(flop_origin(j))
                elif c.startswith("RM_"):
                    res.add("SRAM " + j)
                else:
                    res |= reach(j)
    memo[i] = frozenset(res)
    return memo[i]
sys.setrecursionlimit(100000)
tot = collections.Counter(); ff = collections.Counter(); logic = collections.Counter()
for i, (c, ps) in insts.items():
    a = area.get(c, 0.0)
    if "dfrbp" in c:
        o = flop_origin(i); tot[o] += a; ff[o] += a
    elif not c.startswith("RM_"):
        r = reach(i) or {"(unreached)"}
        for o in r:
            tot[o] += a / len(r); logic[o] += a / len(r)
print(f"# {run}: {sum(tot.values()):.0f} um2 of standard cells (typical liberty areas), by origin")
print(f"{'total':>9s} {'flops':>8s} {'logic':>8s}  origin")
for o, a in tot.most_common():
    if a >= 500:
        print(f"{a:9.0f} {ff[o]:8.0f} {logic[o]:8.0f}  {o}")
