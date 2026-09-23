# /// script
# requires-python = ">=3.11"
# dependencies = ["numpy", "python-sat"]
# ///
"""The heuristic side of the benchmark: beam search over layers on the set of reachable 0/1
vectors (the quantity SorterHunter-style searches use). A prefix sorts, up to a fixed output
order, exactly when the set has shrunk to n + 1 vectors, one per weight.

Each layer is built by adding comparators one at a time until it is a maximal matching on the
fixed links, picking among the best few by set size (ties at random), since on sparse wirings
many useful comparators only move values without shrinking the set yet; the beam keeps the best prefixes by set size.
Usage: uv run greedy.py TOPOLOGY N BEAM ROUNDS"""
import json, random, sys, time
import numpy as np
import search


def apply(S, a, b, ori):
    va, vb = (S >> a) & 1, (S >> b) & 1
    lo, hi = va & vb, va | vb
    na, nb = (lo, hi) if ori else (hi, lo)
    S = S & ~((1 << a) | (1 << b))
    return np.unique(S | (na << a) | (nb << b))


def layer(S, edges, rng, pick=3):
    used, chosen = set(), []
    while True:
        cands = []
        for e, (a, b) in enumerate(edges):
            if a in used or b in used: continue
            for ori in (True, False):
                T = apply(S, a, b, ori)
                cands.append((len(T) + rng.random() * 0.5, e, ori, T))   # comparators never grow the set; random ties
        if not cands: return S, chosen
        cands.sort(key=lambda c: c[0])
        k, e, ori, T = rng.choice(cands[:pick])
        chosen.append((e, ori)); used.update(edges[e]); S = T


def run(name, n, beam, rounds, seed=0):
    edges = search.topology(name, n)
    rng = random.Random(seed)
    best = None
    t0 = time.time()
    for r in range(rounds):
        states = [(np.arange(1 << n, dtype=np.int64), [])]
        depth = 0
        while all(len(S) > n + 1 for S, _ in states) and depth < 4 * n:
            nxt = []
            for S, prog in states:
                for _ in range(beam):
                    T, lay = layer(S, edges, rng)
                    if lay: nxt.append((T, prog + [lay]))
            nxt.sort(key=lambda x: len(x[0]))
            seen, states = set(), []
            for T, prog in nxt:
                key = len(T), tuple(sorted(map(tuple, prog[-1])))
                if key in seen: continue
                seen.add(key); states.append((T, prog))
                if len(states) == beam: break
            depth += 1
        done = [p for S, p in states if len(S) == n + 1]
        if done:
            p = min(done, key=lambda p: sum(map(len, p)))
            assert not search.failures(n, edges, p), "beam result fails the exhaustive check"
            if best is None or (len(p), sum(map(len, p))) < (len(best), sum(map(len, best))):
                best = p
                print(json.dumps(dict(topology=name, n=n, links=len(edges), method="beam", beam=beam, round=r,
                                      depth=len(p), comparators=sum(map(len, p)), secs=round(time.time() - t0, 1),
                                      status="sat", inputs=0, program=p, edges=edges)), flush=True)
    return best


if __name__ == "__main__":
    run(sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4]))
