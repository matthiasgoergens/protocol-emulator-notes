#!/usr/bin/env python3
"""Generate switch-matrix lists and tile CSVs for the hardened-block tiles PIO8 and PIO32
from a project's LUT4AB list: block inputs take the LUT-input jump wires (4:1), block
outputs replace LA_O..LH_O in the JN/JE/JS/JW2BEG driver lists, carry is passed through,
and the shared reset/enable jump wires are declared.

Usage: make_hard_tiles.py <project dir>   (BEL Verilog files must already be in Tile/PIO8 and Tile/PIO32)
"""
import re, sys, pathlib

MUXPORTS = set(list('ABCDEFGH') + [f'S{i}' for i in range(4)])

def expand(side):
    m = re.match(r'^([^\[\]]*)\[([^\]]*)\]([^\[\]]*)$', side.strip())
    if not m:
        return [side.strip()]
    pre, mid, post = m.groups()
    return [pre + x + post for x in mid.split('|')]

def brk(p, n):
    return f'{p[:-1]}[{"|".join([p[-1]] * n)}]'

def make(root, base, tile, bel, inputs, outputs):
    out = [f'# {tile}', 'INCLUDE, ../include/Base.list', '']
    srcsets = ['J2MID_ABa_END', 'J2MID_CDa_END', 'J2MID_EFa_END', 'J2MID_GHa_END',
               'J2MID_ABb_END', 'J2MID_CDb_END', 'J2MID_EFb_END', 'J2MID_GHb_END',
               'J2END_AB_END', 'J2END_CD_END', 'J2END_EF_END', 'J2END_GH_END',
               'J_l_AB_END', 'J_l_CD_END', 'J_l_EF_END', 'J_l_GH_END']
    for i, p in enumerate(inputs):
        s = srcsets[i % len(srcsets)]
        out.append(f'{brk(p, 4)},[{s}0|{s}1|{s}2|{s}3]')
    out.append('')
    lut_o = re.compile(r'\bL[A-H]_O\b'); k = 0
    drop_src = lambda b: (re.search(r'\bM_(AB|AD|AH|EF)\b', b) or re.search(r'\bC[io]\b', b)
                          or re.search(r'\bL[A-H]_(I|Ci|Co)', b))
    for l in base:
        s = l.strip()
        if not s or s.startswith('#') or s.startswith('INCLUDE') or s.startswith('L['):
            continue
        dest, src = s.split(',', 1)
        if any(t in MUXPORTS for t in expand(dest)) or re.search(r'\bL[A-H]_', dest) or 'Ci' in dest or 'Co' in dest:
            continue
        if any(drop_src(b) for b in expand(src)):
            d, sl = expand(dest), expand(src)
            if len(d) != len(sl):
                print('skip', l); continue
            keep = [(a, b) for a, b in zip(d, sl) if not drop_src(b)]
            if not keep:
                continue
            m = re.match(r'^([^\[\]]*)\[([^\]]*)\]([^\[\]]*)$', dest)
            if m:
                pre, _, post = m.groups()
                dest = f'{pre}[{"|".join(a[len(pre):len(a) - len(post) if post else None] for a, _ in keep)}]{post}'
            src = '[' + '|'.join(b for _, b in keep) + ']'
            s = dest + ',' + src
        def sub(m):
            nonlocal k
            r = outputs[k % len(outputs)]; k += 1; return r
        out.append(lut_o.sub(sub, s))
    out.append('Co0,Ci0')
    (root / tile / f'{tile}_switch_matrix.list').write_text('\n'.join(out) + '\n')
    csv = [f'TILE,{tile}', 'INCLUDE,../include/Base.csv', 'NORTH,Co,0,-1,Ci,1,# carry',
           'JUMP,J_SR_BEG,0,0,J_SR_END,1', 'JUMP,J_EN_BEG,0,0,J_EN_END,1',
           f'BEL,./{bel}.v', f'MATRIX,./{tile}_switch_matrix.list', 'EndTILE']
    # every stock tile CSV pads rows to at least eight columns; the parser indexes into them
    csv = [','.join((l.split(',') + [''] * 8)[:8]) for l in csv]
    (root / tile / f'{tile}.csv').write_text('\n'.join(csv) + '\n')
    print(tile, 'inputs', len(inputs), 'outputs', len(outputs), 'list lines', len(out))

def main(project):
    root = pathlib.Path(project) / 'Tile'
    base = (root / 'LUT4AB/LUT4AB_switch_matrix.list').read_text().split('\n')
    make(root, base, 'PIO8', 'PIO8_bel', [f'D{i}' for i in range(8)] + ['LOAD', 'SHIFT', 'DIR'], ['SO', 'EMPTY'])
    make(root, base, 'PIO32', 'PIO32_bel',
         [f'DIN{i}' for i in range(32)] + ['SHIFT8', 'DIR', 'SET', 'DO_SHIFT'] + [f'BIT_COUNT{i}' for i in range(6)],
         [f'DOUT{i}' for i in range(32)] + [f'SHIFT_COUNT{i}' for i in range(6)])

if __name__ == '__main__':
    main(sys.argv[1])
