#!/usr/bin/env -S uv run --no-project --with gdstk python
# SPDX-License-Identifier: Apache-2.0
"""Check that a macro GDS has no real metal where the PDN stripes cross the LEF's Metal4 OBS band.

    obs-band-metal.py GDS X0:X1 [X0:X1 ...] --band Y0:Y1 [--margin 1.0]

Coordinates are macro-local microns (unmirrored LEF frame). Flattens the top cell and reports, per
x-range, every polygon on Metal4 (50/*), Via3 (49/*) or TopMetal1 (126/*) that comes within MARGIN
of the stripe inside the band. Zero hits means a stripe drawn there touches only its own pins'
neighbourhood as the LEF OBS abstracts it, and the "illegal overlap" Magic reports is an artefact
of extracting from the LEF.  Layer numbers: IHP sg13 layer map (Metal4 50, Via3 49, TopMetal1 126).
"""
import argparse
import gdstk

ap = argparse.ArgumentParser()
ap.add_argument('gds'); ap.add_argument('xs', nargs='+'); ap.add_argument('--band', required=True)
ap.add_argument('--margin', type=float, default=1.0)
a = ap.parse_args()
lib = gdstk.read_gds(a.gds)
top = lib.top_level()[0]
y0, y1 = map(float, a.band.split(':'))
layers = {50: 'Metal4', 49: 'Via3', 126: 'TopMetal1'}
polys = [p for p in top.get_polygons() if p.layer in layers]
print(f'{a.gds}: top {top.name}, {len(polys)} polygons on Metal4/Via3/TopMetal1 after flattening')
total = 0
for xr in a.xs:
    x0, x1 = map(float, xr.split(':'))
    bx0, bx1, by0, by1 = x0 - a.margin, x1 + a.margin, y0 - a.margin, y1 + a.margin
    hits = []
    for p in polys:
        (px0, py0), (px1, py1) = p.bounding_box()
        if px1 > bx0 and px0 < bx1 and py1 > by0 and py0 < by1:
            hits.append((layers[p.layer], p.datatype, round(px0, 3), round(py0, 3), round(px1, 3), round(py1, 3)))
    print(f'  stripe x {x0}..{x1}, band y {y0}..{y1}, margin {a.margin}: {len(hits)} hits', *hits[:10], sep='\n    ' if hits else ' ')
    total += len(hits)
print('total hits', total)
