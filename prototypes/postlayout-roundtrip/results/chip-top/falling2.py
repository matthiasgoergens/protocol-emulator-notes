# For each falling-edge flip-flop: which pad it samples (input stage) or which pin it drives (output lane 2).
import sys, re, collections
ports = {}; insts = []
for line in open(sys.argv[1]):
    w = line.split()
    if w[0] == 'port': ports[w[1]] = w[2]
    else: insts.append((w[1], w[2].replace('sg13cmos5l_', ''), dict(p.split('=', 1) for p in w[3:])))
OUT = re.compile(r'^(X|Y|Q|Q_N|L_HI|L_LO|A_DOUT\[\d+\])$')
drv = {}; readers = collections.defaultdict(list)
for name, cell, pins in insts:
    for p, n in pins.items():
        if OUT.match(p): drv[n] = (name, cell, pins)
        else: readers[n].append((name, cell, p, pins))
portnet = {n: p for p, n in ports.items()}
clk = ports['clk']
def trace(n, inv=0, d=0):
    if n == clk: return inv
    x = drv.get(n)
    if not x or d > 64: return None
    name, c, pins = x
    if c.startswith(('buf', 'dlygate')): return trace(pins['A'], inv, d + 1)
    if c.startswith('inv'): return trace(pins['A'], inv + 1, d + 1)
    return None
def back(n, d=0):
    if n in portnet: return portnet[n]
    x = drv.get(n)
    if not x or d > 30: return '?'
    name, c, pins = x
    if c.startswith(('buf', 'dlygate')): return back(pins['A'], d + 1)
    return c + ':' + name
def fwd(n, d=0):
    out = set()
    if n in portnet: out.add(portnet[n])
    for name, c, p, pins in readers[n]:
        o = pins.get('X') or pins.get('Y')
        if c.startswith(('buf', 'dlygate')) and o and d < 30: out |= fwd(o, d + 1)
        elif c.startswith('xor2') and o and d < 30: out |= {'xor->' + x for x in fwd(o, d + 1)}
        else: out.add(c)
    return out
res = collections.Counter()
for name, c, pins in insts:
    if c.startswith('dfrbpq') and (trace(pins['CLK']) or 0) % 2 == 1:
        dd = back(pins['D'])
        if dd.startswith('nor2b'):
            g = drv[pins['D']][2]
            srcs = [back(g['A']), back(g['B_N'])]
            print(name, 'input-stage flop, nor2b inputs from', srcs, '| Q ->', sorted(fwd(pins['Q'])))
        else:
            print(name, 'D from', dd, '| Q ->', sorted(fwd(pins['Q'])))
