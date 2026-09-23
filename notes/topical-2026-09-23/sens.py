# How far does a +1 nudge to one cell spread, per op mix, with saturating vs wrapping bytes?
# Each cell: r_i <- op_i(r[left], r[partner]) + k_i. Ops: max, min, add-const-only ("copy"), a-b, a+b.
import numpy as np, sys
n, T, trials = 64, 400, 200
rng = np.random.default_rng(2027)
left = (np.arange(n) - 1) % n
def run(ops, ks, partner, x, sat):
    xs = []
    for _ in range(T):
        a, b = x[left], x[partner]
        v = np.select([ops == 0, ops == 1, ops == 2, ops == 3], [np.maximum(a, b), np.minimum(a, b), a - b, a + b], a)
        v = v + ks
        x = np.clip(v, 0, 255) if sat else v % 256
        xs.append(x)
    return np.array(xs)
mixes = {'max/min': [0, 1], 'max/min/copy': [0, 1, 4], 'max/min + sub': [0, 1, 2], 'max/min + add': [0, 1, 3], 'sub/add': [2, 3]}
for sat in (True, False):
    for name, pool in mixes.items():
        spread, maxdiff, alive, railed = [], [], [], []
        for t in range(trials):
            partner = rng.integers(0, n, n)
            ops = rng.choice(pool, n)
            ks = rng.integers(-8, 9, n)
            x0 = rng.integers(0, 256, n)
            x1 = x0.copy(); x1[0] = min(255, x1[0] + 1) if x0[0] < 255 else 254
            r0 = run(ops, ks, partner, x0, sat)
            alive.append((r0[-50:] != r0[-1]).any(axis=0).mean())   # cells still changing late on
            railed.append(((r0[-1] == 0) | (r0[-1] == 255)).mean())
            d = np.abs(r0 - run(ops, ks, partner, x1, sat))
            if not sat: d = np.minimum(d, 256 - d)
            spread.append((d[-50:] > 0).mean()); maxdiff.append(d[-50:].max())
        print(f"{'saturate' if sat else 'wrap':8} {name:14} cells differing (last 50 steps): {np.mean(spread):.2f}  median max|diff|: {np.median(maxdiff):5.0f}  worst: {max(maxdiff):3}  cells still moving: {np.mean(alive):.2f}  cells on a rail: {np.mean(railed):.2f}")
