#!/usr/bin/env python3
"""Make a sparse-routing variant of a FABulous project: drop the length-4 and length-6
wires from the tile wire definitions and prune the matching mux inputs from every
switch-matrix list elementwise (removing whole lines orphans jump wires).

Usage: prune_long_wires.py <project dir>   (then delete *_ConfigMem.csv and run `run_fab`)
"""
import re, sys, pathlib

LW = re.compile(r'\b(N4|NN4|S4|SS4|EE4|WW4|E6|W6)(BEG|END|MID)\d*\b')

def expand(side):
    m = re.match(r'^([^\[\]]*)\[([^\]]*)\]([^\[\]]*)$', side.strip())
    if not m:
        return None
    pre, mid, post = m.groups()
    return [pre + x + post for x in mid.split('|')]

def contract(tokens, template):
    m = re.match(r'^([^\[\]]*)\[([^\]]*)\]([^\[\]]*)$', template.strip())
    pre, _, post = m.groups()
    inner = [t[len(pre):len(t) - len(post) if post else None] for t in tokens]
    return f'{pre}[{"|".join(inner)}]{post}'

def filter_list(p, manual):
    out = []
    for l in p.read_text().split('\n'):
        s = l.strip()
        if not s or s.startswith('#') or s.startswith('INCLUDE') or ',' not in s:
            out.append(l); continue
        dest, src = s.split(',', 1)
        if LW.search(dest):
            continue
        if not LW.search(src):
            out.append(l); continue
        d, sl = expand(dest), expand(src)
        if d is None or sl is None or len(d) != len(sl):
            manual.append((str(p), l)); continue
        keep = [(a, b) for a, b in zip(d, sl) if not LW.search(b)]
        if keep:
            out.append(contract([a for a, _ in keep], dest) + ',' + contract([b for _, b in keep], src))
    p.write_text('\n'.join(out))

def filter_csv(p):
    p.write_text('\n'.join(l for l in p.read_text().split('\n') if not LW.search(l)))

def main(project):
    root = pathlib.Path(project) / 'Tile'
    manual = []
    filter_csv(root / 'include/Base.csv'); filter_list(root / 'include/Base.list', manual)
    filter_list(root / 'LUT4AB/LUT4AB_switch_matrix.list', manual)
    for t in ('W_IO', 'N_term_single', 'S_term_single'):
        filter_csv(root / t / f'{t}.csv'); filter_list(root / t / f'{t}_switch_matrix.list', manual)
    print('lines needing manual attention:', len(manual))
    for m in manual: print(m)

if __name__ == '__main__':
    main(sys.argv[1])
