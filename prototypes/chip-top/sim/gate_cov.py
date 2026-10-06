#!/usr/bin/env python3
"""Gate-level flip-flop coverage per block of the Hardcaml.

    gate_cov.py FFS DEF NETLIST.v REGMAP CHIP_TT.v [NEVER_OUT]

FFS     gate_lockstep.exe ... ffs=FILE: every extracted flip-flop ("uNNN@x,y/master edge changes"),
        named by its GDS reference (master and origin in micrometres)
DEF     the harden's final DEF: component name, master, placement and orientation
NETLIST the harden's final netlist (tt_submission/tt_um_chip_top.v): component name -> Q net, whose
        name is the Hardcaml register's Verilog name (\\chip._NNN[b])
REGMAP  lockstep.exe regmap SIZES 512 FILE: Verilog name -> width, source line, block, label
CHIP_TT the hardened RTL (chip_tt.v): Yosys may name a Q net after a wire that aliases the register
        (assign _273 = _9223;), so plain aliases are followed to the register

The extracted reference's origin is the DEF placement for orientation N and the placement plus the
cell height for FS (the only two the flip-flops use), which is how compare_def.exe matches them too.
Prints per block: flip-flops, changed, never changed; NEVER_OUT gets one line per never-changed
flip-flop with its register, bit, source line and label.
"""
import re
import sys
from collections import Counter, defaultdict

ffs_file, def_file, nl_file, regmap_file, rtl_file = sys.argv[1:6]
never_out = sys.argv[6] if len(sys.argv) > 6 else None
rtl = open(rtl_file).read()
# name -> (name, bit offset): plain aliases and single-bit selects
alias = {a: (b, 0) for a, b in re.findall(r'assign\s+(_\d+)\s*=\s*(_\d+)\s*;', rtl)}
alias.update({a: (b, int(i)) for a, b, i, j in re.findall(r'assign\s+(_\d+)\s*=\s*(_\d+)\[(\d+):(\d+)\]\s*;', rtl) if i == j})

# DEF components
text = open(def_file).read()
units = int(re.search(r'UNITS DISTANCE MICRONS (\d+)', text).group(1))
comp = {}
for m in re.finditer(r'-\s+(\S+)\s+(\S+)\s+\+\s+(?:PLACED|FIXED)\s+\(\s*(-?\d+)\s+(-?\d+)\s*\)\s+(\w+)', text):
    name, master, x, y, orient = m.groups()
    comp.setdefault((master, int(x), int(y)), []).append((name, orient))

# cell heights from the masters' placements is not needed: the flip-flop's FS origin is y + h, with
# h the row height; take it from the ROW statements
rows = sorted({int(m.group(1)) for m in re.finditer(r'ROW\s+\S+\s+\S+\s+-?\d+\s+(-?\d+)', text)})
h = min(b - a for a, b in zip(rows, rows[1:]) if b > a)

# netlist: instance -> Q net
nl = open(nl_file).read()
qnet = {}
for m in re.finditer(r'(sg13cmos5l_dfrbp\w*)\s+(\S+)\s*\((.*?)\);', nl, re.S):
    q = re.search(r'\.Q\(\s*([^)]*?)\s*\)', m.group(3))
    if q:
        qnet[m.group(2)] = q.group(1)

# regmap: verilog name -> (width, loc, block, label)
regmap = {}
for line in open(regmap_file):
    name, width, loc, *rest = line.split()
    block = ' '.join(rest[:-1])
    regmap[name] = (int(width), loc, block, rest[-1])

per_block = defaultdict(Counter)
never = []
unmatched = 0
for line in open(ffs_file):
    owner, edge, changes = line.split()
    m = re.match(r'(\S+)@(-?[\d.]+),(-?[\d.]+)/(\S+)', owner)
    _, ox, oy, master = m.groups()
    x, y = round(float(ox) * units), round(float(oy) * units)
    cands = [(n, o) for (n, o) in comp.get((master, x, y), []) if o == 'N'] + \
            [(n, o) for (n, o) in comp.get((master, x, y - h), []) if o == 'FS']
    if len(cands) != 1:
        unmatched += 1
        block, desc = '(unmatched)', owner
    else:
        inst = cands[0][0]
        net = qnet.get(inst, '?')
        mm = re.match(r'\\?chip\.(_\d+)(?:\[(\d+)\])?', net)
        reg = mm.group(1) if mm else None
        bit = int(mm.group(2) or 0) if mm else 0
        hops = 0
        while reg is not None and reg not in regmap and reg in alias and hops < 20:
            (reg, off), hops = alias[reg], hops + 1
            bit += off
        if reg in regmap:
            width, loc, block, label = regmap[reg]
            desc = '%s %s bit %d of %d (%s, %s) %s' % (owner, reg, bit, width, loc, label, inst)
        else:
            block, desc = '(net %s)' % ('renamed' if net != '?' else 'none'), '%s %s %s' % (owner, inst, net)
    per_block[block]['ffs'] += 1
    if int(changes) > 0:
        per_block[block]['changed'] += 1
    else:
        never.append((block, desc))
tot = Counter()
for b in sorted(per_block):
    c = per_block[b]
    tot.update(c)
    print('  %-14s %5d of %5d changed (%5.1f %%), %4d never' % (b, c['changed'], c['ffs'], 100.0 * c['changed'] / c['ffs'], c['ffs'] - c['changed']))
print('  %-14s %5d of %5d changed (%5.1f %%), %4d never; %d flip-flops not matched to a DEF component' %
      ('all', tot['changed'], tot['ffs'], 100.0 * tot['changed'] / tot['ffs'], tot['ffs'] - tot['changed'], unmatched))
if never_out:
    with open(never_out, 'w') as f:
        for b, d in sorted(never):
            f.write('%-14s %s\n' % (b, d))
