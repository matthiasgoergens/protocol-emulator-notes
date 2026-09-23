import collections, statistics
rows = [l.split() for l in open('sweep.txt')]
d = {(int(i), m, int(k), int(g)): (float(p), float(e)) for i, m, k, g, p, e in rows}
ids = sorted({k[0] for k in d})
for m in ('seeded', 'auto'):
    print(f'== {m}')
    print('  k gain  median_per  locked(per>=.9,ent>=1)  flat(ent<0.5)  newly_locked_from_unlocked')
    for k in (4, 8, 16):
        for g in (0, 1, 2, 4, 8, 32, 128):
            ps = [d[(i, m, k, g)] for i in ids]
            locked = sum(p >= .9 and e >= 1 for p, e in ps)
            flat = sum(e < .5 for p, e in ps)
            newly = sum(d[(i, m, k, 0)][0] < .5 and d[(i, m, k, g)][0] >= .9 and d[(i, m, k, g)][1] >= 1 for i in ids)
            print(f'{k:3} {g:4}  {statistics.median(p for p, _ in ps):.3f}  {locked:3}  {flat:3}  {newly:3}')
