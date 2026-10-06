#!/usr/bin/env python3
"""Plantable copy of a hardened gate netlist for the edge-phase test in Icarus (sim/edge_plants.sh).

    nl_plants.py NETLIST.v OUT.v > MAP.txt

Finds every flip-flop whose clock pin reaches the clk port through an odd number of inverters (the
both-edges stage's falling-edge flops), and rewrites its clock connection as (NET ^ edge_tb.plant[k]),
so that `+plant=k` on the vvp command line puts flop k on the rising edge. MAP.txt lists k, the
instance, and its role, traced as postlayout-roundtrip's results/chip-top/falling2.py does: a lane-2
toggle (D from an a21oi, Q through the lane XOR to an output pin), a first-stage input sampler (D from
a nor2b of the reset and a pad) or a second-stage one (a nor2b of the reset and another such flop)."""
import re
import sys
from collections import defaultdict

src, out = sys.argv[1], sys.argv[2]
text = open(src).read()
inst_re = re.compile(r'^\s*(sg13cmos5l_\w+)\s+(\S+)\s*\((.*?)\);', re.S | re.M)
pin_re = re.compile(r'\.(\w+)\(\s*([^()]*?)\s*\)')
insts = []
for m in inst_re.finditer(text):
    pins = {p: n.strip() for p, n in pin_re.findall(m.group(3))}
    insts.append((m.group(1).replace('sg13cmos5l_', ''), m.group(2), pins, m.start(3), m.end(3)))
OUT = {'X', 'Y', 'Q', 'Q_N', 'L_HI', 'L_LO'}
drv = {}
for cell, name, pins, _, _ in insts:
    for p, n in pins.items():
        if p in OUT:
            drv[n] = (cell, name, pins)


def trace(net, inv=0, depth=0):
    if net == 'clk':
        return inv
    x = drv.get(net)
    if not x or depth > 64:
        return None
    cell, _, pins = x
    if cell.startswith(('buf', 'clkbuf', 'dlygate')):
        return trace(pins['A'], inv, depth + 1)
    if cell.startswith(('inv', 'clkinv')):
        return trace(pins['A'], inv + 1, depth + 1)
    return None


def back(net, depth=0):
    """the source of a net through buffers: a port name, or cell:instance"""
    x = drv.get(net)
    if not x:
        return net
    cell, name, pins = x
    if cell.startswith(('buf', 'dlygate')) and depth < 30:
        return back(pins['A'], depth + 1)
    return cell + ':' + name


falling = []
for cell, name, pins, s, e in insts:
    if cell.startswith('dfrbp') and (trace(pins['CLK']) or 0) % 2 == 1:
        d = back(pins['D'])
        if d.startswith('nor2b'):
            g = drv[pins['D']][2]
            srcs = [back(g['A']), back(g['B_N'])]
            pad = [x for x in srcs if 'in[' in x]
            role = ('first-stage sampler of ' + pad[0]) if pad else 'second-stage sampler, after ' + ' '.join(x for x in srcs if x.startswith('dfrbp'))
        elif d.startswith('a21oi'):
            role = 'lane-2 toggle'
        else:
            role = 'other (D from %s)' % d
        falling.append((name, pins['CLK'], role, s, e))
# rewrite the clock connections, from the end of the file so offsets stay valid
pieces = []
pos = len(text)
for k, (name, clk, role, s, e) in sorted(enumerate(falling), key=lambda x: -x[1][3]):
    body = text[s:e]
    body = re.sub(r'\.CLK\(\s*' + re.escape(clk) + r'\s*\)', '.CLK(%s ^ edge_tb.plant[%d])' % (clk, k), body, count=1)
    pieces.append(text[e:pos])
    pieces.append(body)
    pos = s
pieces.append(text[:pos])
open(out, 'w').write(''.join(reversed(pieces)))
for k, (name, clk, role, _, _) in enumerate(falling):
    print(k, name, role)
print('#', len(falling), 'falling-edge flip-flops', file=sys.stderr)
