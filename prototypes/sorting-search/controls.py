# /// script
# requires-python = ">=3.11"
# dependencies = ["numpy", "python-sat"]
# ///
"""The exhaustive checker must accept a known sorting network and reject a broken one."""
import search
n = 16
edges = search.topology("hypercube", n)
idx = {e: i for i, e in enumerate(edges)}
prog = []
k = 2
while k <= n:          # bitonic sort on hypercube links
    j = k // 2
    while j >= 1:
        layer = []
        for i in range(n):
            p = i ^ j
            if p > i:
                layer.append((idx[(i, p)], (i & k) == 0))
        prog.append(layer); j //= 2
    k *= 2
print("bitonic depth", len(prog), "failures:", len(search.failures(n, edges, prog, 1000)))
broken = [list(l) for l in prog]; e, o = broken[5][3]; broken[5][3] = (e, not o)
print("one comparator flipped, failures:", len(search.failures(n, edges, broken, 1000)))
del broken[7][0]
print("and one removed, failures:", len(search.failures(n, edges, broken, 1000)))
