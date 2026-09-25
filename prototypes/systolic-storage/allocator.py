"""A toy allocator for memory that forgets (notes/gain-cell-compiler.md, "A compiler model").

Rows have deadlines: a value written to row r at time t is readable until t + L(r, cond), where
L depends on the row type (thick- or thin-oxide 3T gain cell), the operating condition, and a
per-row factor from profiling (weak rows). Values come from traces (kernel,loc,width,value,
t_def,t_last in 50 MHz cycles). The allocator walks the trace in time order and:

  - places each value in a free row, best fit: the row type with the shortest lifetime that still
    covers the whole interval; if none does, the longest-lived free row;
  - when a row's deadline comes before the value's last use, either migrates the value to a free
    row that lives longer (read + write, which also frees the short row) or refreshes it in place
    (read + write). Both cost one refresh operation of two port cycles;
  - counts overflows (no free row at a definition), which make a row mix infeasible.

The compiler schedules against the *profiled* lifetime times a guard factor; a separate decay
model applies the *true* lifetime per bit, so a mis-profiled weak row corrupts data. Every word
carries a Berger check (the count of 0s in the data, stored in the same row), and every read is
checked, which is how the planted weak row is detected (test_allocator.py).

uv run allocator.py mixes      -> results/mixes.txt       (best thick/thin mix per condition)
uv run allocator.py summary    -> results/summary.txt     (interval histograms per trace)
"""
import collections, csv, heapq, math, random, sys
from dataclasses import dataclass, field

import storage_options as so

CLK = 50e6
CONDS = ("tt27", "tt85", "ff85")
TYPES = {"thick": so.GC_THICK, "thin": so.GC_THIN}
LIFE = {k: {c: s * CLK for c, s in d.items()} for k, d in so.LIFE.items()}  # cycles


@dataclass
class Value:
    loc: str
    width: int
    value: int
    t_def: int
    t_last: int


def load(path, only=None):
    import re
    out = []
    with open(path) as f:
        for r in csv.DictReader(f):
            if only and not re.search(only, r["loc"]):
                continue
            v = Value(r["loc"], int(r["width"]), int(r["value"]), int(r["t_def"]), int(r["t_last"]))
            if v.t_last >= v.t_def:        # never-read values need no storage
                out.append(v)
    return out


@dataclass
class Row:
    idx: int
    kind: str
    profiled: float = 1.0   # lifetime factor the compiler believes
    true: float = 1.0       # lifetime factor the silicon has
    bit_spread: list = field(default_factory=list)  # per-bit multiplier >= 1 on the true lifetime


def make_rows(n_thick, n_thin, width, weak=(), seed=7):
    """weak: iterable of (index, true_factor, profiled_factor) applied after creation."""
    rng = random.Random(seed)
    rows = [Row(i, "thick" if i < n_thick else "thin") for i in range(n_thick + n_thin)]
    for r in rows:
        r.bit_spread = [1.0 + 0.5 * rng.random() for _ in range(width + berger_bits(width))]
    for i, t, p in weak:
        rows[i].true, rows[i].profiled = t, p
    return rows


def berger_bits(width):
    return math.ceil(math.log2(width + 1))


def berger(word, width):
    return width - bin(word).count("1")


class Decay:
    """Per-bit decay of stored 1s. A 1 in bit b of row r written at tw reads as 0 after
    L_true(r) * spread[b]; 0s never change. Checks every read with the Berger code."""

    def __init__(self, cond, width):
        self.cond, self.width, self.cb = cond, width, berger_bits(width)
        self.reads = self.corrupt = self.detected = self.silent = self.false_alarm = 0
        self.detect_rows = collections.Counter()

    def read(self, row, data, tw, t):
        life = LIFE[row.kind][self.cond] * row.true
        age = t - tw
        stored = data | (berger(data, self.width) << self.width)
        got = 0
        for b in range(self.width + self.cb):
            if (stored >> b) & 1 and age <= life * row.bit_spread[b]:
                got |= 1 << b
        d = got & ((1 << self.width) - 1)
        c = got >> self.width
        bad = d != data
        flag = berger(d, self.width) != c
        self.reads += 1
        self.corrupt += bad
        self.detected += flag
        self.silent += bad and not flag
        self.false_alarm += flag and not bad
        if flag:
            self.detect_rows[row.idx] += 1
        return d


def allocate(values, rows, cond, guard=0.8, decay=None, migrate=True, max_ops=None):
    """Returns a dict of counts. Rows of equal (kind, profiled) are one class, used round robin."""
    lp = {r.idx: LIFE[r.kind][cond] * r.profiled * guard for r in rows}
    classes = collections.defaultdict(collections.deque)  # (lifetime) -> free row ids
    for r in rows:
        classes[lp[r.idx]].append(r.idx)
    byid = {r.idx: r for r in rows}
    lifetimes = sorted(classes)
    ev = []  # (time, order, kind, value index)
    for i, v in enumerate(values):
        heapq.heappush(ev, (v.t_def, 1, i))
    where = {}    # value -> (row, time written)
    stats = collections.Counter()
    stats["values"] = len(values)
    live = peak = 0

    def take(length, better_than=None):
        """Best-fit free row: shortest lifetime covering length, else the longest free one."""
        cands = [L for L in lifetimes if classes[L] and (better_than is None or L > better_than)]
        if not cands:
            return None
        fit = [L for L in cands if L >= length]
        L = fit[0] if fit else cands[-1]
        return classes[L].popleft()

    while ev:
        t, kind, i = heapq.heappop(ev)
        v = values[i]
        if kind == 0:                                  # last use: read, free the row
            r, tw = where.pop(i)
            if decay:
                decay.read(byid[r], v.value, tw, t)
            classes[lp[r]].append(r)
            live -= 1
        elif kind == 1:                                # definition
            r = take(v.t_last - v.t_def)
            if r is None:
                stats["overflow"] += 1
                continue
            where[i] = (r, t)
            live += 1
            peak = max(peak, live)
            stats[f"placed_{byid[r].kind}"] += 1
            heapq.heappush(ev, (v.t_last, 0, i))
            if t + lp[r] < v.t_last:
                heapq.heappush(ev, (t + int(lp[r]), 2, i))
        else:                                          # deadline before last use
            r, tw = where[i]
            remaining = v.t_last - t
            r2 = take(remaining, better_than=lp[r]) if migrate else None
            if decay:
                decay.read(byid[r], v.value, tw, t)    # the refresh read is checked too
            if r2 is not None:
                classes[lp[r]].append(r)
                r = r2
                stats["migrations"] += 1
            else:
                stats["refreshes"] += 1
            where[i] = (r, t)
            if t + lp[r] < v.t_last:
                heapq.heappush(ev, (t + int(lp[r]), 2, i))
            if max_ops is not None and stats["refreshes"] + stats["migrations"] > max_ops:
                stats["aborted"] = 1
                break
    stats["peak_live"] = peak
    stats["ops"] = stats["refreshes"] + stats["migrations"]
    return stats


def area(n_thick, n_thin, width, with_berger=True):
    cols = width + (berger_bits(width) if with_berger else 0)
    per_row = 2 * so.BUF + so.NAND2 + so.A21OI
    per_col = so.EBUF + so.INV + so.LATCH
    fixed = 8 * so.DFF + 10 * so.NAND2
    return (n_thick * cols * so.GC_THICK + n_thin * cols * so.GC_THIN
            + (n_thick + n_thin) * per_row + cols * per_col + fixed)


def span(values):
    return max(v.t_last for v in values) - min(v.t_def for v in values) + 1


def peak_live(values):
    ev = sorted([(v.t_def, 1) for v in values] + [(v.t_last + 1, -1) for v in values])
    cur = best = 0
    for _, d in ev:
        cur += d
        best = max(best, cur)
    return best


def lower_bound_ops(values, cond, guard):
    """Refresh operations if an unlimited supply of thick rows were free."""
    L = LIFE["thick"][cond] * guard
    return sum(max(0, math.ceil((v.t_last - v.t_def) / L) - 1) for v in values)


# Feasibility needs no search: refresh and migration move values between rows but never change how
# many rows are occupied, so a mix has no overflow exactly when it has at least peak_live rows.
# Extra thick rows beyond that can still cut refreshes, so the search also tries some slack.


TRACES = [
    ("seq-regs", "traces/seq.csv", r"\.(acc|cnt|dl|pc)$"),
    ("seq-imem", "traces/seq.csv", r"imem"),
    ("linebuf-P3", "traces/linebuf-P3.csv", None),
    ("linebuf-P5", "traces/linebuf-P5.csv", None),
    ("linebuf-P20", "traces/linebuf-P20.csv", None),
    ("vfir2", "traces/vfir2.csv", None),
    ("vfir3", "traces/vfir3.csv", None),
]


def summary():
    edges_us = [0.1, 1.2, 8, 95, 118.8, 2480, 3100, 9650, 1e9]
    print("# interval length histogram (us); edges: thin ff85, thin tt85, thin tt27 x0.8 guard,"
          " thin tt27, thick ff85 x0.8, thick ff85, thick tt x0.8")
    for name, path, only in TRACES:
        vs = load(path, only)
        lens = [(v.t_last - v.t_def) / CLK * 1e6 for v in vs]
        h = [0] * len(edges_us)
        for x in lens:
            for j, e in enumerate(edges_us):
                if x <= e:
                    h[j] += 1
                    break
        zeros = sum(v.value == 0 for v in vs)
        print(f"{name:12s} n={len(vs):6d} span={span(vs)/CLK*1e6:9.1f} us  peak_live={peak_live(vs):4d}"
              f"  max={max(lens):8.1f} us  all-zero={zeros}")
        print("   " + "  ".join(f"<={e:g}:{c}" for e, c in zip(edges_us, h)))


def mixes(guard=0.8, cap=0.10):
    print(f"# best thick/thin row mix per trace and condition; guard {guard}, one bank,"
          f" refresh = read+write = 2 port cycles; bandwidth = 2*ops/span")
    print("# columns: area um2 (Berger columns included), rows thick+thin, refresh+migration ops,"
          " bandwidth fraction")
    for name, path, only in TRACES:
        vs = load(path, only)
        width = max(v.width for v in vs)
        pk = peak_live(vs)
        sp = span(vs)
        flops = pk * width * so.DFF
        print(f"\n## {name}: {len(vs)} values, width {width}, peak live {pk}, span {sp/CLK*1e6:.1f} us;"
              f" flops for peak live: {flops:.0f} um2")
        for cond in CONDS:
            lb = lower_bound_ops(vs, cond, guard)
            # a liveness-blind controller refreshes every row of the mix once per guarded lifetime
            blind = lambda nt, nn: (nt * sp / (LIFE['thick'][cond] * guard)
                                    + nn * sp / (LIFE['thin'][cond] * guard))
            res = []
            step = max(1, pk // 16)
            max_ops = cap * sp / 2
            for n_thin in sorted(set(list(range(0, pk + 1, step)) + [pk])):
                for slack in sorted({0, pk // 8, pk // 4}):
                    nt = max(0, pk - n_thin) + slack
                    s = allocate(vs, make_rows(nt, n_thin, width), cond, guard, max_ops=max_ops)
                    assert not s["overflow"]
                    if s["aborted"]:
                        continue
                    bw = 2 * s["ops"] / sp
                    res.append((area(nt, n_thin, width), nt, n_thin, s["ops"], bw))
            zero = [r for r in res if r[3] == 0]
            capped = [r for r in res if r[4] <= cap]
            allthick = [r for r in res if r[2] == 0]
            best0 = min(zero) if zero else None
            bestc = min(capped) if capped else None
            fmt = lambda r: (f"{r[0]:8.0f} um2  {r[1]:3d}+{r[2]:3d} rows  {r[3]:6d} ops  {r[4]*100:6.2f}%"
                             f"  (liveness-blind: {blind(r[1], r[2]):.0f} ops)" if r else "none")
            print(f"  {cond}: lower bound ops (unlimited thick rows) {lb}")
            print(f"    all thick           : {fmt(min(allthick) if allthick else None)}")
            print(f"    cheapest, no refresh: {fmt(best0)}")
            print(f"    cheapest, bw<={cap:.0%}  : {fmt(bestc)}")
        sys.stdout.flush()


def resident(guard=0.8):
    """Data that never dies (a loaded programme, a per-frame configuration read all frame)."""
    print(f"# resident data: refresh bandwidth of a bank holding it forever, guard {guard},"
          f" 2 port cycles per row refresh")
    for what, rows in (("sequencer imem 4x64x16 bit", 256), ("semiring ring config 848 bit / 32", 27)):
        for kind in ("thick", "thin"):
            for cond in CONDS:
                L = LIFE[kind][cond] * guard
                print(f"  {what:36s} {kind:5s} {cond}: {2 * rows / L * 100:8.3f}% of port cycles")


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "summary"
    {"summary": summary, "mixes": mixes, "resident": resident}[cmd]()
