#!/usr/bin/env -S uv run --no-project python
# SPDX-License-Identifier: Apache-2.0
"""Count Magic DRC boxes (drc.magic.rpt) per rule, inside each given macro box or outside all.

    magic-drc-by-region.py DRC_MAGIC_RPT NAME:X0,Y0,X1,Y1 ...

A box counts as inside a macro when it lies entirely within the macro's die-coordinate bbox.
The total equals LibreLane's magic__drc_error__count. (The .lyrdb merges two Cnt.c rules and
drops 21 boxes, so the text report is used.)
"""
import collections
import re
import sys

boxes = []
for spec in sys.argv[2:]:
    name, coords = spec.split(':')
    boxes.append((name, *map(float, coords.split(','))))
lines = open(sys.argv[1]).read().splitlines()
counts = collections.Counter()
rule = None
for i, line in enumerate(lines):
    m = re.match(r'\s*([\d.-]+)um ([\d.-]+)um ([\d.-]+)um ([\d.-]+)um', line)
    if m:
        x0, y0, x1, y1 = map(float, m.groups())
        where = next((n for n, a, b, c, d in boxes if a <= x0 and x1 <= c and b <= y0 and y1 <= d), 'outside')
        counts[(rule, where)] += 1
    elif 0 < i < len(lines) - 1 and lines[i - 1].startswith('---') and lines[i + 1].startswith('---'):
        rule = line.strip()
total = collections.Counter()
for (rule, where), n in sorted(counts.items(), key=lambda kv: -kv[1]):
    print(f'{n:7d}  {where:9s} {rule}')
    total[where] += n
print('total', sum(total.values()), dict(total))
