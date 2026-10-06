#!/usr/bin/env python3
"""Name the worst setup paths of a LibreLane run by their RTL origin.

  synth/paths.py RUN_DIR MAP [CORNER|REPORT] [N]

RUN_DIR is runs/wokwi of a harden; MAP is bin/origins.exe's map for the same Verilog. Reads the
post-PnR STA max.rpt of CORNER (default nom_slow_1p08V_125C) and the final netlist, and prints, for
the N worst endpoints (default 20): the slack, the start and end registers with the OCaml call
sites that built them, the logic depth, and the named Hardcaml signals the path passes through.
"""
import re, sys, os, collections

run, mapf = sys.argv[1], sys.argv[2]
corner = sys.argv[3] if len(sys.argv) > 3 else "nom_slow_1p08V_125C"
N = int(sys.argv[4]) if len(sys.argv) > 4 else 20

origin = {}
for line in open(mapf):
    f = line.rstrip("\n").split("\t")
    frames = [x for x in f[3].split() if not x.startswith(("bin/origins", "src/signal__type"))]
    if len(frames) > 1:
        frames = [x for x in frames if not x.startswith("src/tt_top")]
    origin[f[0]] = (f[1], int(f[2]), frames)

def short(net):
    """chip._1673 or chip._1673[3] -> its origin."""
    m = re.match(r"\\?chip\.(\w+?)(?:\[(\d+)\])?\s*$", net)
    if not m:
        return None
    nm = m.group(1)
    if nm not in origin:
        return f"{nm}(?)"
    kind, w, fr = origin[nm]
    loc = " < ".join(x.rsplit(":", 1)[0].replace("blocks/", "") for x in fr[:3])
    return f"{nm}{'[' + m.group(2) + ']' if m.group(2) else ''} {kind}/{w} @ {loc}"

# flip-flop instance names survive the flow; their Q nets keep the Hardcaml names best in the
# synthesis netlist, before buffering renames them
qnet = {}
synth = [d for d in sorted(os.listdir(run)) if d.endswith("yosys-synthesis")]
nl = os.path.join(run, synth[0], "tt_um_chip_top.nl.v") if synth else os.path.join(run, "final/nl/tt_um_chip_top.nl.v")
fin = os.path.join(run, "final/nl/tt_um_chip_top.nl.v")
txt = open(nl).read() + (open(fin).read() if os.path.exists(fin) else "")
for m in re.finditer(r"sg13cmos5l_(d\w+)\s+(\S+)\s*\((.*?)\);", txt, re.S):
    inst, body = m.group(2), m.group(3)
    q = re.search(r"\.Q\(([^)]*)\)", body)
    if q and inst not in qnet:
        qnet[inst] = q.group(1).strip()
for m in re.finditer(r"RM_IHPSG13\w+\s+(\S+)\s*\(", txt):
    qnet[m.group(1)] = m.group(1)

def sta_dir():
    for d in sorted(os.listdir(run)):
        if d.endswith("openroad-stapostpnr"):
            return os.path.join(run, d)
rpt = open(corner if os.path.isfile(corner) else os.path.join(sta_dir(), corner, "max.rpt")).read()
paths = rpt.split("Startpoint: ")[1:]
seen, out = set(), []
for p in paths:
    sp = p.split()[0]
    ep = re.search(r"Endpoint: (\S+)", p).group(1)
    sl = re.search(r"(-?[\d.]+)\s+slack", p)
    if not sl:
        continue
    slack = float(sl.group(1))
    arrival = p.split("data arrival time")[0]
    nets = re.findall(r"^\s+(\S+) \(net\)", arrival, re.M)
    cells = re.findall(r"^\s+\d+\s+[\d.]+\s+[\d.]+\s+[\d.]+\s+[\d.]+ [v^] (\S+)/\w+ \((\S+)\)", arrival, re.M)
    logic = [c for c in cells if not re.search(r"buf_|clkbuf|inv_|dly", c[1]) and not c[0].startswith("clk")]
    named = []
    for n in nets:
        s = short(n)
        if s and (not named or named[-1] != s):
            named.append(s)
    out.append((slack, sp, ep, len(logic), len(cells), named))
out.sort()
def where(inst):
    o = short(qnet.get(inst, inst)) or qnet.get(inst, inst)
    return re.sub(r"^\S+ ", "", o).replace("src/signal__type.ml:666 < ", "")
print(f"# {run} {corner}: {len(out)} paths")
groups = {}
for slack, sp, ep, nlog, ncell, named in out:
    k = (where(sp), where(ep.split("/")[0]))
    if k not in groups:
        groups[k] = [slack, 0, sp, ep, nlog]
    groups[k][1] += 1
print(f"\n## the {N} worst (start origin, end origin) pairs: worst slack, number of reported paths, logic cells")
for i, (k, (slack, cnt, sp, ep, nlog)) in enumerate(sorted(groups.items(), key=lambda kv: kv[1][0])[:N]):
    print(f"{i+1:2d}. {slack:+7.3f} ns  {cnt:4d} paths  {nlog:2d} cells\n      from {k[0]}\n      to   {k[1]}")
print(f"\n## the {min(N, 5)} worst paths in full")
for slack, sp, ep, nlog, ncell, named in out[:min(N, 5)]:
    print(f"\nslack {slack:+.3f} ns  logic cells {nlog}, all cells {ncell}")
    print(f"  start {sp}: {short(qnet.get(sp, sp)) or qnet.get(sp, sp)}")
    print(f"  end   {ep}: {short(qnet.get(ep.split('/')[0], ep)) or qnet.get(ep.split('/')[0], ep)}")
    for s in named:
        print(f"    via {s}")
