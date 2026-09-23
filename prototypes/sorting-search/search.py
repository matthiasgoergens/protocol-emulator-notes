# /// script
# requires-python = ">=3.11"
# dependencies = ["numpy", "python-sat"]
# ///
"""How well can a fixed wiring be programmed to sort? A benchmark for program search with an
exact objective and published optima.

Hardware: n cells, a fixed set of links (the "tapeout"). A program is a sequence of layers; in
each layer some links act as compare-exchange units (a matching: at most one per cell), each
with an orientation saying which end receives the minimum. The host may read the outputs in any
fixed order, so the requirement is: all inputs with the same number of ones give the same output
(by the 0-1 principle that means the network sorts, up to a fixed output permutation).

Search: SAT with counterexample-guided refinement (CEGIS): encode the network on a small set of
0/1 inputs, solve, check the program exhaustively on all 2^n inputs with an independent numpy
simulator, add failing inputs, repeat. UNSAT on a subset proves the depth impossible outright.
"""
import itertools, json, random, sys, threading, time
import numpy as np
from pysat.solvers import Solver


def topology(name, n, seed=2027):
    rng = random.Random(seed)
    line = [(i, i + 1) for i in range(n - 1)]
    ring = line + [(n - 1, 0)]
    def rand_matchings(k, base):
        edges = set(tuple(sorted(e)) for e in base)
        out = []
        for _ in range(k):
            while True:
                p = list(range(n)); rng.shuffle(p)
                m = [tuple(sorted((p[2 * i], p[2 * i + 1]))) for i in range(n // 2)]
                if not any(e in edges for e in m): break
            edges.update(m); out += m
        return out
    if name == "line": return line
    if name == "ring": return ring
    if name.startswith("ring+rand"): return ring + rand_matchings(int(name[len("ring+rand"):]), ring)
    if name == "hypercube": return [(i, i ^ d) for d in (1, 2, 4, 8) if d < n for i in range(n) if i < i ^ d]
    if name == "complete": return list(itertools.combinations(range(n), 2))
    if name.startswith("rand"): return rand_matchings(int(name[len("rand"):]), [])
    raise ValueError(name)


def simulate(n, edges, prog, X):
    """prog: list of layers, each a list of (edge_index, min_at_first_end). X: int array of inputs."""
    v = [((X >> c) & 1).astype(bool) for c in range(n)]
    for layer in prog:
        used = set()
        for e, ori in layer:
            a, b = edges[e]
            assert a not in used and b not in used, "layer is not a matching"
            used.update((a, b))
            lo, hi = v[a] & v[b], v[a] | v[b]
            v[a], v[b] = (lo, hi) if ori else (hi, lo)
    out = np.zeros(len(X), dtype=np.int64)
    for c in range(n): out |= v[c].astype(np.int64) << c
    return out


def failures(n, edges, prog, max_per_weight=2):
    X = np.arange(1 << n, dtype=np.int64)
    w = np.array([bin(x).count("1") for x in range(1 << n)]) if n <= 16 else None
    out = simulate(n, edges, prog, X)
    bad = []
    for t in range(1, n):
        o = out[w == t]; xs = X[w == t]
        vals, counts = np.unique(o, return_counts=True)
        if len(vals) > 1:
            mode = vals[np.argmax(counts)]
            wrong = xs[o != mode]
            bad += [int(x) for x in wrong[:max_per_weight]]
    return bad


class Encoding:
    def __init__(self, n, edges, depth):
        self.n, self.edges, self.depth = n, edges, depth
        self.nv = 0
        self.s = Solver(name="cadical195")
        self.act = [[self.new() for _ in edges] for _ in range(depth)]
        self.ori = [[self.new() for _ in edges] for _ in range(depth)]
        self.z = [[self.new() for _ in range(n)] for _ in range(n + 1)]
        self.inc = [[e for e, (a, b) in enumerate(edges) if c in (a, b)] for c in range(n)]
        for L in range(depth):
            for c in range(n):
                es = self.inc[c]
                for i in range(len(es)):
                    for j in range(i + 1, len(es)):
                        self.s.add_clause([-self.act[L][es[i]], -self.act[L][es[j]]])
        self.idle = [[self.new() for _ in range(n)] for _ in range(depth)]
        for L in range(depth):
            for c in range(n):
                es = self.inc[c]
                for e in es: self.s.add_clause([-self.idle[L][c], -self.act[L][e]])
                self.s.add_clause([self.idle[L][c]] + [self.act[L][e] for e in es])
        self.T, self.F = self.new(), None
        self.s.add_clause([self.T])
        self.inputs = 0

    def new(self):
        self.nv += 1; return self.nv

    def add_input(self, x):
        n = self.n
        t = bin(x).count("1")
        v = [self.T if (x >> c) & 1 else -self.T for c in range(n)]
        for L in range(self.depth):
            nxt = [self.z[t][c] for c in range(n)] if L == self.depth - 1 else [self.new() for _ in range(n)]
            for c in range(n):
                self.s.add_clause([-self.idle[L][c], -nxt[c], v[c]])
                self.s.add_clause([-self.idle[L][c], nxt[c], -v[c]])
            for e, (a, b) in enumerate(self.edges):
                act, ori = self.act[L][e], self.ori[L][e]
                for o, (p, q) in ((ori, (a, b)), (-ori, (b, a))):
                    g = [-act, -o]   # guard: this link active with min at p, max at q
                    self.s.add_clause(g + [-nxt[p], v[a]]); self.s.add_clause(g + [-nxt[p], v[b]])
                    self.s.add_clause(g + [nxt[p], -v[a], -v[b]])
                    self.s.add_clause(g + [-nxt[q], v[a], v[b]])
                    self.s.add_clause(g + [nxt[q], -v[a]]); self.s.add_clause(g + [nxt[q], -v[b]])
            v = nxt
        self.inputs += 1

    def solve(self, limit):
        timer = threading.Timer(limit, self.s.interrupt); timer.start()
        r = self.s.solve_limited(expect_interrupt=True)
        timer.cancel()
        try: self.s.clear_interrupt()
        except NotImplementedError: pass   # CaDiCaL clears it by itself
        return r

    def program(self):
        m = set(l for l in self.s.get_model() if l > 0)
        return [[(e, self.ori[L][e] in m) for e in range(len(self.edges)) if self.act[L][e] in m]
                for L in range(self.depth)]


def find(n, edges, depth, limit, seed=1):
    """Returns ('sat', program) / ('unsat', None) / ('timeout', None), with statistics."""
    rng = random.Random(seed)
    enc = Encoding(n, edges, depth)
    start = [1 << c for c in range(n)] + [((1 << n) - 1) ^ (1 << c) for c in range(n)]
    start += [rng.getrandbits(n) for _ in range(32)]
    for x in start: enc.add_input(x)
    t0 = time.time(); rounds = 0
    while True:
        left = limit - (time.time() - t0)
        if left <= 0: return "timeout", None, dict(inputs=enc.inputs, rounds=rounds)
        r = enc.solve(left); rounds += 1
        if r is None: return "timeout", None, dict(inputs=enc.inputs, rounds=rounds)
        if r is False: return "unsat", None, dict(inputs=enc.inputs, rounds=rounds, secs=round(time.time() - t0, 1))
        prog = enc.program()
        bad = failures(n, edges, prog)
        if not bad:
            return "sat", prog, dict(inputs=enc.inputs, rounds=rounds, secs=round(time.time() - t0, 1),
                                     comparators=sum(len(l) for l in prog))
        for x in bad: enc.add_input(x)


def min_depth(name, n, start, limit):
    edges = topology(name, n)
    log = []
    best = None
    d = start
    while d >= 1:
        status, prog, st = find(n, edges, d, limit)
        log.append(dict(depth=d, status=status, **st))
        print(json.dumps(dict(topology=name, n=n, links=len(edges), depth=d, status=status, **st,
                              program=prog, edges=edges if status == 'sat' else None)), flush=True)
        if status != "sat": break
        best = (d, prog)
        used = sum(1 for l in prog if l)
        d = min(d, used) - 1   # layers left empty come for free
    return dict(topology=name, n=n, links=len(edges), best=best[0] if best else None,
                program=best[1] if best else None, log=log)


if __name__ == "__main__":
    name, n, start, limit = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), float(sys.argv[4])
    res = min_depth(name, n, start, limit)
    with open(f"out/{name}_n{n}.json", "w") as f: json.dump(res, f)
