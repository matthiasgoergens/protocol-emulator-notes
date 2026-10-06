#!/usr/bin/env python3
"""Where the hold buffers of a LibreLane run sit, by the RTL origin of the flip-flops they feed.

  synth/holds.py RUN_DIR MAP

For every hold buffer (hold*, inserted by repair_timing -hold) the script follows its output
through further hold buffers to the flip-flops (or macro pins) it feeds, and walks its input back
through hold buffers to the first other driver. It counts buffers per (driver kind, sink origin),
where an origin is the OCaml call site that built the flip-flop (bin/origins.exe's MAP)."""
import re, sys, os, collections

run, mapf = sys.argv[1], sys.argv[2]
origin = {}
for line in open(mapf):
    f = line.rstrip("\n").split("\t")
    fr = [x for x in f[3].split() if not x.startswith(("bin/", "src/tt_top", "src/signal__type"))]
    origin[f[0]] = " < ".join(x.rsplit(":", 1)[0].replace("blocks/", "") for x in fr[:2])

txt = open(os.path.join(run, "final/nl/tt_um_chip_top.nl.v")).read()
insts = {}
for m in re.finditer(r"^\s*(\w+)\s+(\\?\S+)\s*\((.*?)\);", txt, re.S | re.M):
    cell, inst, body = m.groups()
    if cell in ("module", "wire", "input", "output", "assign"):
        continue
    pins = dict((p, n.strip()) for p, n in re.findall(r"\.(\w+)\(([^()]*)\)", body))
    insts[inst] = (cell, pins)
OUT = {"X", "Y", "Q", "L_HI", "L_LO"}
driver, sinks = {}, collections.defaultdict(list)
for inst, (cell, pins) in insts.items():
    for p, n in pins.items():
        if not n:
            continue
        if p in OUT or (cell.startswith("RM_") and p.startswith("A_DOUT")):
            driver[n] = (inst, p)
        else:
            sinks[n].append((inst, p))

def is_hold(i): return i.startswith("hold")
def name_of_flop(inst):
    cell, pins = insts[inst]
    q = pins.get("Q", "")
    m = re.match(r"\\?chip\.(\w+?)(\[\d+\])?\s*$", q)
    if m:
        return origin.get(m.group(1), m.group(1) + "?")
    return "flop with Q " + q

def sink_origin(inst, pin):
    cell = insts[inst][0]
    if "df" in cell or "dl" in cell[:13]:
        return ("flop " + pin, name_of_flop(inst))
    if cell.startswith("RM_"):
        return ("macro " + re.sub(r"\[\d+\]|\d+$", "", pin), inst)
    return ("cell " + cell.replace("sg13cmos5l_", ""), "")

def src_kind(net):
    while True:
        d = driver.get(net)
        if not d:
            return "port/const " + net
        inst, pin = d
        if is_hold(inst):
            net = insts[inst][1]["A"]
            continue
        cell = insts[inst][0]
        if "df" in cell:
            return "flop: " + name_of_flop(inst)
        if cell.startswith("RM_"):
            return "macro " + inst
        return "logic " + cell.replace("sg13cmos5l_", "")

count = collections.Counter()
srcs = collections.Counter()
pair = collections.Counter()
holds = [i for i in insts if is_hold(i)]
for h in holds:
    out = insts[h][1]["X"]
    ends = []
    stack = [out]
    while stack:
        n = stack.pop()
        for inst, pin in sinks.get(n, []):
            if is_hold(inst):
                stack.append(insts[inst][1]["X"])
            else:
                ends.append(sink_origin(inst, pin))
    s = src_kind(insts[h][1]["A"])
    sk = s if s.startswith("flop") else s.split()[0] + " " + (s.split()[1] if len(s.split()) > 1 else "")
    for e in set(ends):
        count[e] += 1 / max(1, len(set(ends)))
    srcs[sk if len(sk) < 120 else sk[:120]] += 1
    for e in set(ends):
        pair[(sk.split(":")[0] if not sk.startswith("flop") else "flop", e[0].split()[0], e[1])] += 1 / max(1, len(set(ends)))
print(f"# {run}: {len(holds)} hold buffers")
print("\n## by the flip-flop or pin they feed (origin of the sink)")
for (k, o), c in count.most_common(40):
    print(f"{c:7.0f}  {k:14s} {o}")
print("\n## by the driver behind them")
for s, c in srcs.most_common():
    print(f"{c:7d}  {s}")

# Self-loops: a chain of hold buffers whose first non-hold driver is a flip-flop that the chain
# feeds back into (through at most four gates): the register's own enable or clear multiplexer.
def isflop(i): return "dfrbp" in insts[i][0]
kinds = collections.Counter()
for h in holds:
    d = driver.get(insts[h][1]["A"])
    if d and is_hold(d[0]):
        continue  # not the head of its chain
    src = d[0] if d else None
    seen, frontier, flops = set(), [(insts[h][1]["X"], 0)], set()
    while frontier:
        n, k = frontier.pop()
        for i, p in sinks.get(n, []):
            if i in seen:
                continue
            seen.add(i)
            if isflop(i):
                flops.add(i)
            elif k < 4 and not insts[i][0].startswith("RM_"):
                for pp, nn in insts[i][1].items():
                    if pp in OUT:
                        frontier.append((nn, k + (0 if is_hold(i) else 1)))
    if src and isflop(src) and src in flops:
        kinds["self-loop (flip-flop back to itself)"] += 1
    elif src and isflop(src):
        kinds["flip-flop to another flip-flop"] += 1
    elif src and insts[src][0].startswith("RM_"):
        kinds["from an SRAM macro output"] += 1
    else:
        kinds["from logic (an input of a gate)"] += 1
print(f"\n## chain heads by kind ({sum(kinds.values())} chains)")
for k, c in kinds.most_common():
    print(f"{c:7d}  {k}")
