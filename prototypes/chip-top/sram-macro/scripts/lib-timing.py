#!/usr/bin/env -S uv run --no-project python
# SPDX-License-Identifier: Apache-2.0
"""Summarise the A_CLK timing arcs of IHP SRAM macro Liberty files.

    lib-timing.py LIB...

For each file: clock-to-output (A_CLK -> A_DOUT, min and max over the table), setup and hold
constraints per input pin related to A_CLK (max over the table, rise and fall), and A_CLK's minimum
pulse width. Only reads the files; table maxima are over the whole slew/load range, so they are
upper bounds for any operating point inside it.
"""
import re
import sys


def blocks(text, start):
    """Yield (header, body) for brace-delimited groups whose header matches `start`."""
    for m in re.finditer(start, text):
        i = text.index('{', m.end())
        depth, j = 1, i + 1
        while depth:
            depth += {'{': 1, '}': -1}.get(text[j], 0)
            j += 1
        yield m, text[i + 1:j - 1]


def nums(body, table):
    out = []
    for _, tb in blocks(body, table + r'\s*\([^)]*\)\s*'):
        v = re.search(r'values\s*\((.*?)\)\s*;', tb, re.S)
        out += [float(x) for x in re.findall(r'-?\d+\.\d+|-?\d+', v.group(1))]
    return out


for path in sys.argv[1:]:
    text = open(path).read()
    print(path.rsplit('/', 1)[-1])
    rows = {}
    # pins and buses at any depth: find timing() groups and the nearest enclosing pin/bus name
    for m, body in blocks(text, r'\b(pin|bus)\s*\(\s*"?([A-Z_\[\]0-9:]+)"?\s*\)\s*'):
        name = m.group(2)
        for _, tb in blocks(body, r'\btiming\s*\(\s*\)\s*'):
            rp = re.search(r'related_pin\s*:\s*"?(\w+)"?', tb)
            tt = re.search(r'timing_type\s*:\s*"?(\w+)"?', tb)
            if not rp or rp.group(1) != 'A_CLK' or not tt:
                continue
            kind = tt.group(1)
            vals = nums(tb, r'cell_(?:rise|fall)') if kind == 'rising_edge' else nums(tb, r'(?:rise|fall)_constraint')
            if vals:
                key = (re.sub(r'\[.*', '', name), kind)
                lo, hi = rows.get(key, (float('inf'), float('-inf')))
                rows[key] = (min(lo, min(vals)), max(hi, max(vals)))
    for (pin, kind), (lo, hi) in sorted(rows.items(), key=lambda kv: (kv[0][1], kv[0][0])):
        print(f'  {kind:16s} {pin:12s} min {lo:8.4f}  max {hi:8.4f} ns')
