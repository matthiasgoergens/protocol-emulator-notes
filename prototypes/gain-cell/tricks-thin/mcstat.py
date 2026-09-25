# Statistics of Monte Carlo lifetimes (mc.py output): median, 1st percentile, and the worst cell
# of a 64 kbit array extrapolated with a lognormal fit.
# Why lognormal: the leak is subthreshold (or tunnelling) current, exponential in a Gaussian
# threshold shift, so ln(lifetime) is close to Gaussian. Two fits are reported: over all samples
# (mean and standard deviation of ln t), and over the lower half only (a probit regression of
# ln t on the normal quantile, which weighs the tail that matters). The worst cell of N = 65536 is
# placed at the quantile where half of all arrays have a cell that short-lived:
# p = ln 2 / N, z = -4.25. Also printed: the lifetime a 90 % array yield needs (p = -ln 0.9 / N).
import math, re, statistics, sys
from statistics import NormalDist

ND = NormalDist()
N = 65536
for f in sys.argv[1:]:
    t, t1, t0, l1, h0, vw1 = [], [], [], [], [], []
    for line in open(f):
        m = re.search(r"vw1 ([-\d.]+) vw0 \S+ L1 (\S+) H0 (\S+) t1 (\S+) t0 (\S+) life (\S+)", line)
        if m:
            vw1.append(float(m[1]))
            l1.append(float(m[2]) if m[2] != "None" else float("nan"))
            h0.append(float(m[3]) if m[3] != "None" else float("nan"))
            t1.append(float(m[4])); t0.append(float(m[5])); t.append(float(m[6]))
    n = len(t)
    if n < 10:
        print(f"{f}: only {n} samples"); continue
    s = sorted(t)
    fin = [x for x in s if 0 < x < math.inf]
    ln = [math.log(x) for x in fin]
    mu, sd = statistics.mean(ln), statistics.stdev(ln)
    # probit fit on the lower half
    k = len(fin) // 2
    zs = [ND.inv_cdf((i + 0.5) / n) for i in range(k)]
    ys = ln[:k]
    zb, yb = statistics.mean(zs), statistics.mean(ys)
    slope = sum((z - zb) * (y - yb) for z, y in zip(zs, ys)) / sum((z - zb) ** 2 for z in zs)
    icpt = yb - slope * zb
    z50 = ND.inv_cdf(math.log(2) / N)
    z90 = ND.inv_cdf(-math.log(0.9) / N)
    u = lambda x: (f"{x * 1e3:.3g} ms" if x >= 1e-3 else f"{x * 1e6:.3g} us") if x < math.inf else "inf"
    nfail0 = sum(1 for a, b in zip(t1, t0) if b < a)
    print(f"{f}: {n} samples ({n - len(fin)} infinite or zero)")
    print(f"  median {u(statistics.median(s))}, min {u(s[0])}, 1st percentile {u(s[max(0, int(0.01 * n) - 1)])}"
          f" (sample {max(0, int(0.01 * n) - 1) + 1} of {n}), max {u(s[-1])}")
    print(f"  the stored 0 fails first in {nfail0} of {n}; written 1: {min(vw1):.3f}..{max(vw1):.3f} V;"
          f" L1 {min(l1):.3f}..{max(l1):.3f} V; H0 {min(h0):.3f}..{max(h0):.3f} V")
    print(f"  lognormal, all samples: median {u(math.exp(mu))}, sigma(ln t) {sd:.3f} (x{math.exp(sd):.2f} per sigma);"
          f" 64 kbit worst cell (z {z50:.2f}) {u(math.exp(mu + z50 * sd))}; 90 % array yield (z {z90:.2f}) {u(math.exp(mu + z90 * sd))}")
    print(f"  lognormal, lower-half probit fit: median {u(math.exp(icpt))}, sigma {slope:.3f};"
          f" 64 kbit worst cell {u(math.exp(icpt + z50 * slope))}; 90 % array yield {u(math.exp(icpt + z90 * slope))}")
