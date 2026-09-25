"""Tests for the toy allocator: Berger detection, a planted weak row, and the allocator's invariants.

uv run --with pytest pytest -q test_allocator.py
"""
import itertools, random

import allocator as a


def test_berger_detects_every_unidirectional_error_8bit():
    """Exhaustive over 8-bit data and every set of 1->0 decays in data and check bits."""
    w, cb = 8, a.berger_bits(8)
    for data in range(256):
        stored = data | (a.berger(data, w) << w)
        ones = [b for b in range(w + cb) if (stored >> b) & 1]
        for k in range(1, len(ones) + 1):
            for drop in itertools.combinations(ones, k):
                got = stored
                for b in drop:
                    got &= ~(1 << b)
                d, c = got & 0xFF, got >> w
                assert a.berger(d, w) != c, (data, drop)


def test_berger_misses_a_0_to_1_error():
    """Control: the code is only for one-directional errors. A 1->0 plus a 0->1 in the data
    keeps the count of 0s and passes, so the test above is not vacuous."""
    w = 8
    data = 0b0000_0001
    stored = data | (a.berger(data, w) << w)
    got = (stored & ~1) | 0b10
    assert a.berger(got & 0xFF, w) == got >> w


def _vfir2():
    return a.load("traces/vfir2.csv")[:6000]


def test_clean_rows_no_errors():
    """No weak row: the schedule holds, so no read is corrupt or flagged."""
    vs = _vfir2()
    rows = a.make_rows(0, 64, 32)
    d = a.Decay("tt27", 32)
    s = a.allocate(vs, rows, "tt27", guard=0.8, decay=d)
    assert s["overflow"] == 0 and s["ops"] == 0
    assert d.reads == len(vs) and d.corrupt == 0 and d.detected == 0


def test_planted_weak_row_is_detected_and_promotion_fixes_it():
    """A thin row that really lives 25 % of nominal, but was profiled as nominal. vfir2 values
    live 63.4 us; nominal thin at tt/27 C is 118.8 us (95 us with the guard), the weak row 29.7 us.
    Every corrupt read must be flagged (no silent corruption), and flags come only from that row.
    Then promote the row (profile it as 0.25) and re-run: no corruption, no flags."""
    vs = _vfir2()
    weak = 17
    rows = a.make_rows(0, 64, 32, weak=[(weak, 0.25, 1.0)])
    d = a.Decay("tt27", 32)
    a.allocate(vs, rows, "tt27", guard=0.8, decay=d)
    assert d.corrupt > 0, "the planted row should corrupt something"
    assert d.silent == 0
    assert set(d.detect_rows) == {weak}
    print(f"weak row: {d.reads} reads, {d.corrupt} corrupt, {d.detected} flagged, "
          f"{d.false_alarm} false alarms, silent {d.silent}")

    rows = a.make_rows(0, 64, 32, weak=[(weak, 0.25, 0.25)])
    d2 = a.Decay("tt27", 32)
    s2 = a.allocate(vs, rows, "tt27", guard=0.8, decay=d2)
    assert d2.corrupt == 0 and d2.detected == 0
    print(f"after promotion: {s2['ops']} refresh/migration ops, 0 corrupt")


def test_feasibility_is_peak_live():
    """Refresh and migration never change how many rows are occupied."""
    vs = a.load("traces/linebuf-P5.csv")
    pk = a.peak_live(vs)
    for n_thin in (0, pk // 2, pk):
        s = a.allocate(vs, a.make_rows(pk - n_thin, n_thin, 32), "tt85")
        assert s["overflow"] == 0
    s = a.allocate(vs, a.make_rows(pk - 1, 0, 32), "tt85")
    assert s["overflow"] > 0


def test_values_never_outlive_their_row_in_schedule():
    """With the true lifetime equal to the profiled one, the decay model sees no corruption,
    in the worst condition, with a thin-heavy mix that forces refreshes and migrations."""
    vs = a.load("traces/seq.csv", r"\.(acc|cnt)$")
    d = a.Decay("ff85", 16)
    s = a.allocate(vs, a.make_rows(2, 8, 16), "ff85", guard=0.8, decay=d)
    assert s["ops"] > 0
    assert d.corrupt == 0 and d.detected == 0
