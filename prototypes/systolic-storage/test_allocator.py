"""Tests for the toy allocator: two-sided error detection, a planted weak row, and invariants.

uv run --with pytest pytest -q test_allocator.py
"""
import itertools, random

import allocator as a


def _check_columns(width):
    r = a.hamming_parity_bits(width)
    data = [position | (1 << r) for position in a._data_positions(width)]
    parity = [(1 << bit) | (1 << r) for bit in range(r)]
    return data + parity + [1 << r]


def test_check_columns_certify_distance_at_least_four():
    """Nonzero, distinct columns, with no column equal to the sum of two others, certify d >= 4."""
    for width in (8, 12, 16, 32):
        columns = _check_columns(width)
        assert all(columns)
        assert len(columns) == len(set(columns))
        unique = set(columns)
        for i, left in enumerate(columns):
            for right in columns[:i]:
                assert left ^ right not in unique, (width, left, right)


def test_extended_hamming_detects_every_error_up_to_three_8bit():
    """Exhaustive over 8-bit data and every 1-, 2- or 3-bit transition, in either direction."""
    w, cb = 8, a.check_bits(8)
    for data in range(256):
        stored = a.encode(data, w)
        for k in range(1, 4):
            for flips in itertools.combinations(range(w + cb), k):
                got = stored
                for b in flips:
                    got ^= 1 << b
                assert not a.code_valid(got, w), (data, flips)


def test_four_transitions_can_be_undetectable():
    """The guarantee stops at three: this weight-four error is another valid codeword."""
    w = 8
    stored = a.encode(0, w)
    flips = (0, 1, 2, 12)
    got = stored ^ sum(1 << bit for bit in flips)
    assert a.code_valid(got, w)


def test_code_valid_rejects_unused_high_bits():
    stored = a.encode(0x5A, 8)
    assert a.code_valid(stored, 8)
    assert not a.code_valid(stored | (1 << (8 + a.check_bits(8))), 8)


def test_extended_hamming_catches_mixed_direction_error():
    """Control: the code handles both decay directions, unlike a Berger count of zeroes."""
    w = 8
    data = 0b0000_0001
    stored = a.encode(data, w)
    got = stored ^ (1 << 0) ^ (1 << 1)  # one 1->0 and one 0->1
    assert not a.code_valid(got, w)


def test_decay_models_both_directions():
    w = 8
    row = a.Row(0, "thin", true=1.0, profiled=1.0)
    row.bit_spread = [1e9] * (w + a.check_bits(w))
    row.rise_spread = [1e9] * (w + a.check_bits(w))
    row.bit_spread[0] = 1.0
    d = a.Decay("ff85", w)
    one = d.encode(0b1)
    got = d.read(row, one, 0b1, 0, int(a.LIFE_ONE["thin"]["ff85"]) + 1)
    assert (got & 1) == 0 and d.detected == 1 and d.check_only == 0

    row.bit_spread = [1e9] * (w + a.check_bits(w))
    row.rise_spread = [1e9] * (w + a.check_bits(w))
    row.rise_spread[0] = 1.0
    d = a.Decay("ff85", w)
    zero = d.encode(0)
    got = d.read(row, zero, 0, 0, int(a.LIFE_ZERO["thin"]["ff85"]) + 1)
    assert (got & 1) == 1 and d.detected == 1 and d.check_only == 0


def test_decay_detects_one_fall_and_one_rise():
    w = 8
    row = a.Row(0, "thin", true=1.0, profiled=1.0)
    row.bit_spread = [1e9] * (w + a.check_bits(w))
    row.rise_spread = [1e9] * (w + a.check_bits(w))
    row.bit_spread[0] = 1.0
    row.rise_spread[1] = 1.0
    d = a.Decay("ff85", w)
    stored = d.encode(0b01)
    t = max(int(a.LIFE_ONE["thin"]["ff85"]), int(a.LIFE_ZERO["thin"]["ff85"])) + 1
    got = d.read(row, stored, 0b01, 0, t)
    assert got & 0xFF == 0b10
    assert d.corrupt == d.detected == 1 and d.silent == d.check_only == 0


def test_decay_uses_thin_tt85_stored_zero_read_deadline():
    w = 8
    row = a.Row(0, "thin", true=1.0, profiled=1.0)
    row.bit_spread = [1e9] * (w + a.check_bits(w))
    row.rise_spread = [1e9] * (w + a.check_bits(w))
    row.rise_spread[0] = 1.0
    d = a.Decay("tt85", w)
    zero = d.encode(0)
    got = d.read(row, zero, 0, 0, int(a.LIFE_ZERO["thin"]["tt85"]) + 1)
    assert a.LIFE_ZERO["thin"]["tt85"] == 106.9e-6 * a.CLK
    assert (got & 1) == 1 and d.detected == 1 and d.check_only == 0


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
    """One physical bit in a thin row lives 25 % of nominal, while the row is profiled as
    nominal. vfir2 values live 63.4 us; nominal thin at tt/27 C is 118.8 us (95 us with the
    guard), and the physical weak-bit deadline is 29.7 us. Every corrupt read must be flagged
    (no silent corruption), and flags come only from that row. Then promote its row with a 0.25
    profile while retaining the same physical 0.25 bit-spread and re-run: no corruption, no flags."""
    vs = _vfir2()
    weak = 17
    rows = a.make_rows(0, 64, 32, weak=[(weak, 1.0, 1.0)])
    rows[weak].rise_spread = [1e9] * len(rows[weak].rise_spread)
    rows[weak].bit_spread = [1e9] * len(rows[weak].bit_spread)
    rows[weak].bit_spread[0] = 0.25
    assert rows[weak].true == 1.0 and rows[weak].bit_spread[0] == 0.25
    d = a.Decay("tt27", 32)
    a.allocate(vs, rows, "tt27", guard=0.8, decay=d)
    assert d.corrupt > 0, "the planted row should corrupt something"
    assert d.silent == 0
    assert set(d.detect_rows) == {weak}
    print(f"weak row: {d.reads} reads, {d.corrupt} corrupt, {d.detected} flagged, "
          f"{d.check_only} check-only, silent {d.silent}")

    rows = a.make_rows(0, 64, 32, weak=[(weak, 1.0, 0.25)])
    rows[weak].rise_spread = [1e9] * len(rows[weak].rise_spread)
    rows[weak].bit_spread = [1e9] * len(rows[weak].bit_spread)
    rows[weak].bit_spread[0] = 0.25
    assert rows[weak].true == 1.0 and rows[weak].bit_spread[0] == 0.25
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


def test_decayed_refresh_stays_decayed():
    """A refresh writes back what it read. If a bit has decayed by then, the final read must
    still be corrupt (and flagged): a refresh cannot restore lost data. (Found by codex review.)"""
    L = int(a.LIFE["thin"]["ff85"])                    # 60 cycles
    vs = [a.Value("x", 1, 1, 0, 3 * L)]
    rows = a.make_rows(0, 1, 1, weak=[(0, 0.5, 1.0)])
    rows[0].bit_spread = [1e9] * len(rows[0].bit_spread)
    rows[0].bit_spread[0] = 1.0
    rows[0].rise_spread = [1e9] * len(rows[0].rise_spread)
    d = a.Decay("ff85", 1)
    s = a.allocate(vs, rows, "ff85", guard=0.8, decay=d)
    assert s["refreshes"] >= 2
    assert d.corrupt == d.reads and d.silent == 0


def test_row_not_reused_in_its_last_read_cycle():
    """[0,1] and [1,2] overlap in cycle 1, so they need two rows, as peak_live says."""
    vs = [a.Value("a", 8, 1, 0, 1), a.Value("b", 8, 1, 1, 2)]
    assert a.peak_live(vs) == 2
    assert a.allocate(vs, a.make_rows(1, 0, 8), "tt27")["overflow"] == 1
    assert a.allocate(vs, a.make_rows(2, 0, 8), "tt27")["overflow"] == 0


def test_sub_cycle_lifetime_terminates():
    vs = [a.Value("x", 8, 255, 0, 100)]
    rows = a.make_rows(0, 1, 8, weak=[(0, 0.01, 0.01)])
    s = a.allocate(vs, rows, "ff85")
    assert s["refreshes"] == 99
