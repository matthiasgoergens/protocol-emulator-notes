# Turns LibreLane's powered gate-level netlist into a SPICE schematic for a flat KLayout LVS of
# the whole layout, the hard macros included: one .SUBCKT for the top, an X line per instance
# with its ports in the order of the cell's .SUBCKT line, then the standard-cell CDL and the
# macros' own schematics appended. LibreLane's netgen LVS treats the macros as black boxes; this
# checks their insides and their connections in one comparison.
# Usage: python3 pnl2spice.py PNL.v TOP OUT.cir CDL [MACRO.cir ...]
# Cells with no ports in the CDL (none here) and filler cells are written like any other cell:
# the layout has them too.
import re, sys

pnl, top, out, cdl, *macros = sys.argv[1:]
ports = {}
for f in [cdl] + macros:
    for m in re.finditer(r"^\.SUBCKT\s+(\S+)\s+(.*?)$((?:\n\+.*$)*)", open(f).read(), re.M | re.I):
        ports[m.group(1)] = (m.group(2) + " " + m.group(3).replace("\n+", " ")).split()

src = open(pnl).read()
src = re.sub(r"//.*", "", src)
mod = re.search(rf"module\s+{re.escape(top)}\s*\((.*?)\);(.*?)endmodule", src, re.S)
body = mod.group(2)

def name(n):
    n = n.strip()
    return n[1:] if n.startswith("\\") else n

# top ports with bus widths
top_ports = []
for d in re.finditer(r"(input|output|inout)\s+(?:wire\s+)?(\[(\d+):(\d+)\]\s+)?([\\\w\[\]\.]+)\s*;", body):
    if d.group(2):
        hi, lo = int(d.group(3)), int(d.group(4))
        top_ports += [f"{name(d.group(5))}[{i}]" for i in range(lo, hi + 1)]
    else:
        top_ports.append(name(d.group(5)))

def expand(expr):
    expr = expr.strip()
    if expr.startswith("{"):
        return [x for e in split_top(expr[1:-1]) for x in expand(e)]
    m = re.fullmatch(r"(\\?[\w\.\[\]$]+?)\s*\[(\d+):(\d+)\]", expr)
    if m and not expr.startswith("\\"):
        hi, lo = int(m.group(2)), int(m.group(3))
        return [f"{name(m.group(1))}[{i}]" for i in range(hi, lo - 1, -1)]
    if re.fullmatch(r"\d+'[bh][01xz]+", expr):
        raise SystemExit(f"constant in a connection: {expr}")
    return [name(expr)]

def split_top(s):
    parts, depth, cur = [], 0, ""
    for ch in s:
        if ch == "," and depth == 0:
            parts.append(cur); cur = ""
            continue
        depth += ch == "{"
        depth -= ch == "}"
        cur += ch
    if cur.strip():
        parts.append(cur)
    return parts

lines = [f".SUBCKT {top} " + " ".join(top_ports)]
for inst in re.finditer(r"^\s*(\w+)\s+(\\\S+|\w+)\s*\((.*?)\);", body, re.S | re.M):
    cell, iname, conns = inst.group(1), name(inst.group(2)), inst.group(3)
    if cell in ("input", "output", "inout", "wire", "assign"):
        continue
    if cell not in ports:
        raise SystemExit(f"no .SUBCKT for {cell}")
    pins = {}
    for c in re.finditer(r"\.(\w+)\s*\(((?:[^()]|\{[^}]*\})*)\)", conns):
        pins[c.group(1)] = expand(c.group(2)) if c.group(2).strip() else []
    nets = []
    for p in ports[cell]:
        b = re.fullmatch(r"(\w+)\[(\d+)\]", p)
        if b:                                   # a bus port of a macro, MSB first in Verilog
            bus = pins.get(b.group(1), [])
            width = sum(1 for q in ports[cell] if q.startswith(b.group(1) + "["))
            nets.append(bus[width - 1 - int(b.group(2))] if bus else f"unconnected_{iname}_{p}")
        else:
            v = pins.get(p, [])
            nets.append(v[0] if v else f"unconnected_{iname}_{p}")
    lines.append(f"X{iname.replace('.', '_').replace('[', '_').replace(']', '_')} " + " ".join(nets) + f" {cell}")
lines.append(f".ENDS {top}")
text = "\n".join(lines) + "\n\n" + "".join(open(f).read() + "\n" for f in [cdl] + macros)
open(out, "w").write(text)
print(f"{top}: {len(lines) - 2} instances, {len(top_ports)} ports -> {out}")
