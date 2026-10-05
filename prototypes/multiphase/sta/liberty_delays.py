#!/usr/bin/env python3
"""
Extract NLDM delay-table data for a handful of sg13g2 standard cells from the
three IHP SG13G2 liberty corners, and compute:
  - fanout-of-one (FO1) chain delays for buf_1, buf_2, inv_1, the three
    dlygate4sd*_1 cells, with self-consistent input-transition iteration,
  - clock-to-Q / setup / hold for the DFF cells at a representative
    slew/load,
  - per-arc (A vs B, rise/fall) delay of xor2_1 at a representative
    slew/load.

Only a small, targeted brace-matching + recursive-descent parser is used
(no external liberty-parsing package, no network access needed) since we
only need ~11 cells out of a 1.7 MB library file.

Wire allowance: a small additional load of WIRE_CAP_FF femtofarad is added
on top of the cell's own input pin capacitance to emulate a short local
wire from the driving stage to the fanout-of-one load. This is a stated
approximation, not a measurement.
"""
import re
import sys
import math

WIRE_CAP_FF = 2.0  # extra load capacitance, in fF, stated wire allowance

LIB_DIR = "/home/matthias/.ciel/ihp-sg13g2/ihp-sg13g2/libs.ref/sg13g2_stdcell/lib"
CORNERS = {
    "fast_1p32V_m40C": f"{LIB_DIR}/sg13g2_stdcell_fast_1p32V_m40C.lib",
    "typ_1p20V_25C":   f"{LIB_DIR}/sg13g2_stdcell_typ_1p20V_25C.lib",
    "slow_1p08V_125C": f"{LIB_DIR}/sg13g2_stdcell_slow_1p08V_125C.lib",
}

TARGET_CELLS = [
    "sg13g2_buf_1",
    "sg13g2_buf_2",
    "sg13g2_inv_1",
    "sg13g2_dlygate4sd1_1",
    "sg13g2_dlygate4sd2_1",
    "sg13g2_dlygate4sd3_1",
    "sg13g2_xor2_1",
    "sg13g2_mux2_1",
    "sg13g2_mux4_1",
    "sg13g2_dfrbp_1",
    "sg13g2_dfrbpq_1",
]

# ---------------------------------------------------------------------------
# Tiny liberty tokenizer / recursive-descent parser (only what we need)
# ---------------------------------------------------------------------------

TOKEN_RE = re.compile(r'"[^"]*"|[A-Za-z_][A-Za-z0-9_.\[\]/+-]*|[-+]?[0-9]*\.[0-9]+(?:[eE][-+]?[0-9]+)?|[-+]?[0-9]+(?:[eE][-+]?[0-9]+)?|[{}();:,]')


def strip_comments(text):
    return re.sub(r'/\*.*?\*/', '', text, flags=re.S)


def strip_quotes(tok):
    if len(tok) >= 2 and tok[0] == '"' and tok[-1] == '"':
        return tok[1:-1]
    return tok


class Group:
    __slots__ = ("name", "args", "children", "attrs")

    def __init__(self, name, args):
        self.name = name
        self.args = args
        self.children = []
        self.attrs = {}

    def find_all(self, name):
        return [c for c in self.children if isinstance(c, Group) and c.name == name]

    def find(self, name):
        r = self.find_all(name)
        return r[0] if r else None

    def attr(self, name, default=None):
        v = self.attrs.get(name)
        return v[0] if v else default


def tokenize(text):
    return TOKEN_RE.findall(text)


def parse_group(tokens, pos):
    name = tokens[pos]
    pos += 1
    assert tokens[pos] == '(', (name, tokens[pos:pos + 5])
    pos += 1
    args = []
    while tokens[pos] != ')':
        if tokens[pos] == ',':
            pos += 1
            continue
        args.append(strip_quotes(tokens[pos]))
        pos += 1
    pos += 1  # skip ')'
    if tokens[pos] == '{':
        pos += 1
        g = Group(name, args)
        while tokens[pos] != '}':
            ident = tokens[pos]
            if tokens[pos + 1] == '(':
                child, pos = parse_group(tokens, pos)
                g.children.append(child)
            elif tokens[pos + 1] == ':':
                pos += 2
                val_tokens = []
                while tokens[pos] != ';':
                    val_tokens.append(tokens[pos])
                    pos += 1
                pos += 1  # skip ';'
                val = strip_quotes(val_tokens[0]) if len(val_tokens) == 1 else " ".join(val_tokens)
                g.attrs.setdefault(ident, []).append(val)
            else:
                raise ValueError(f"unexpected token sequence at {tokens[pos:pos+5]}")
        pos += 1  # skip '}'
        return g, pos
    elif tokens[pos] == ';':
        pos += 1
        g = Group(name, args)  # complex attribute treated as a leaf group
        g.attrs['__value__'] = args
        return g, pos
    else:
        raise ValueError(f"unexpected token after ')': {tokens[pos]}")


def extract_top_block(text, group_kind, name):
    m = re.search(r'\b' + re.escape(group_kind) + r'\s*\(\s*' + re.escape(name) + r'\s*\)\s*\{', text)
    if not m:
        return None
    start = m.end() - 1
    depth = 0
    i = start
    n = len(text)
    in_str = False
    while i < n:
        c = text[i]
        if c == '"':
            in_str = not in_str
        elif not in_str:
            if c == '{':
                depth += 1
            elif c == '}':
                depth -= 1
                if depth == 0:
                    return text[m.start():i + 1]
        i += 1
    raise ValueError("unbalanced braces")


def parse_cell_block(block_text):
    toks = tokenize(block_text)
    g, pos = parse_group(toks, 0)
    assert pos == len(toks)
    return g


def get_header_units(text):
    tu = re.search(r'\btime_unit\s*:\s*"([^"]+)"', text)
    cu = re.search(r'\bcapacitive_load_unit\s*\(\s*([-+0-9.eE]+)\s*,\s*([A-Za-z]+)\s*\)', text)
    return tu.group(1) if tu else None, (cu.group(1), cu.group(2)) if cu else None


def load_cell(corner_path, cell_name, cache_text):
    text = cache_text[corner_path]
    block = extract_top_block(text, "cell", cell_name)
    if block is None:
        return None
    return parse_cell_block(block)


# ---------------------------------------------------------------------------
# NLDM table lookup with bilinear interpolation
# ---------------------------------------------------------------------------

def parse_table_values(rows):
    return [[float(x.strip()) for x in row.split(',')] for row in rows]


def get_table(pin_group, subgroup_name, related_pin=None, when=None, require_no_when=False):
    """Find a timing() group (optionally filtered by related_pin / when) inside
    a pin group, and return its subgroup_name table as (index1, index2, values)."""
    for tg in pin_group.find_all('timing'):
        rp = tg.attr('related_pin')
        if related_pin is not None and rp != related_pin:
            continue
        has_when = 'when' in tg.attrs
        if require_no_when and has_when:
            continue
        if when is not None and tg.attr('when') != when:
            continue
        sub = tg.find(subgroup_name)
        if sub is None:
            continue
        idx1 = sub.find('index_1')
        idx2 = sub.find('index_2')
        vals = sub.find('values')
        if idx1 is None or vals is None:
            continue
        index1 = [float(x.strip()) for x in idx1.attrs['__value__'][0].split(',')]
        index2 = [float(x.strip()) for x in idx2.attrs['__value__'][0].split(',')] if idx2 else [0.0]
        raw_rows = vals.attrs['__value__']
        matrix = parse_table_values(raw_rows)
        return index1, index2, matrix
    return None


def bilinear(index1, index2, matrix, x, y):
    """index1 -> rows, index2 -> cols (liberty convention: index_1 = input
    transition varies down rows, index_2 = load varies across columns)."""
    def clamp_locate(axis, v):
        n = len(axis)
        if n == 1:
            return 0, 0, 0.0
        if v <= axis[0]:
            return 0, 1, 0.0
        if v >= axis[-1]:
            return n - 2, n - 1, 1.0
        for i in range(n - 1):
            if axis[i] <= v <= axis[i + 1]:
                frac = (v - axis[i]) / (axis[i + 1] - axis[i])
                return i, i + 1, frac
        return n - 2, n - 1, 1.0

    r0, r1, fr = clamp_locate(index1, x)
    c0, c1, fc = clamp_locate(index2, y)
    v00 = matrix[r0][c0]
    v01 = matrix[r0][c1]
    v10 = matrix[r1][c0]
    v11 = matrix[r1][c1]
    v0 = v00 + (v01 - v00) * fc
    v1 = v10 + (v11 - v10) * fc
    return v0 + (v1 - v0) * fr


# ---------------------------------------------------------------------------
# Cell property helpers
# ---------------------------------------------------------------------------

def pin_input_capacitance(cell_group, pin_name):
    p = None
    for pg in cell_group.find_all('pin'):
        if pg.args[0] == pin_name:
            p = pg
            break
    if p is None:
        return None
    c = p.attr('capacitance')
    return float(c) if c is not None else None


def cell_area(cell_group):
    a = cell_group.attr('area')
    return float(a) if a is not None else None


def output_pin(cell_group):
    for pg in cell_group.find_all('pin'):
        if pg.attr('direction') == 'output':
            return pg
    return None


def input_pins(cell_group):
    return [pg for pg in cell_group.find_all('pin') if pg.attr('direction') == 'input' and not pg.attrs.get('clock')]


def clock_pin(cell_group):
    for pg in cell_group.find_all('pin'):
        if pg.attrs.get('clock'):
            return pg
    return None


def data_pin(cell_group):
    for pg in cell_group.find_all('pin'):
        if pg.attr('direction') == 'input' and not pg.attrs.get('clock') and pg.args[0] not in ('RESET_B', 'SET_B'):
            return pg
    return None


# ---------------------------------------------------------------------------
# Self-consistent FO1 chain delay
# ---------------------------------------------------------------------------

def fo1_load(cell_group, in_pin_name):
    cin = pin_input_capacitance(cell_group, in_pin_name)
    return cin + WIRE_CAP_FF / 1000.0  # WIRE_CAP_FF is fF, liberty cap unit is pF


def self_consistent_noninverting(cell_group, in_pin, out_pin, load_pf, seed=0.1, iters=60, tol=1e-6):
    """Non-inverting cell (buf, dlygate): input-rise -> output-rise and
    input-fall -> output-fall, so iterate the rise loop and the fall loop
    independently to a fixed point."""
    def loop(cell_table_name, trans_table_name):
        t = seed
        for _ in range(iters):
            idx1, idx2, m = get_table(out_pin, trans_table_name, related_pin=in_pin.args[0])
            t_new = bilinear(idx1, idx2, m, t, load_pf)
            if abs(t_new - t) < tol:
                t = t_new
                break
            t = t_new
        idx1, idx2, m = get_table(out_pin, cell_table_name, related_pin=in_pin.args[0])
        delay = bilinear(idx1, idx2, m, t, load_pf)
        return t, delay

    t_rise_ss, d_rise = loop('cell_rise', 'rise_transition')
    t_fall_ss, d_fall = loop('cell_fall', 'fall_transition')
    return t_rise_ss, d_rise, t_fall_ss, d_fall


def self_consistent_inverting(cell_group, in_pin, out_pin, load_pf, seed=0.1, iters=80, tol=1e-6):
    """Inverting cell (inv_1): input-rise -> output-fall -> (next stage)
    input-fall -> output-rise -> ... alternate to a 2-cycle fixed point."""
    t_rise = seed  # magnitude of a rising-edge transition entering a stage
    t_fall = seed  # magnitude of a falling-edge transition entering a stage
    idx1f, idx2f, mf = get_table(out_pin, 'fall_transition', related_pin=in_pin.args[0])
    idx1r, idx2r, mr = get_table(out_pin, 'rise_transition', related_pin=in_pin.args[0])
    for _ in range(iters):
        new_fall = bilinear(idx1f, idx2f, mf, t_rise, load_pf)   # input rises -> output falls
        new_rise = bilinear(idx1r, idx2r, mr, t_fall, load_pf)   # input falls -> output rises
        if abs(new_fall - t_fall) < tol and abs(new_rise - t_rise) < tol:
            t_fall, t_rise = new_fall, new_rise
            break
        t_fall, t_rise = new_fall, new_rise
    idx1cf, idx2cf, mcf = get_table(out_pin, 'cell_fall', related_pin=in_pin.args[0])
    idx1cr, idx2cr, mcr = get_table(out_pin, 'cell_rise', related_pin=in_pin.args[0])
    d_fall = bilinear(idx1cf, idx2cf, mcf, t_rise, load_pf)   # t_pHL: input-rise -> output-fall
    d_rise = bilinear(idx1cr, idx2cr, mcr, t_fall, load_pf)   # t_pLH: input-fall -> output-rise
    return t_rise, t_fall, d_rise, d_fall


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    out_lines = []

    def p(s=""):
        print(s)
        out_lines.append(s)

    cache_text = {}
    for corner, path in CORNERS.items():
        with open(path) as f:
            cache_text[path] = strip_comments(f.read())

    tu, cu = get_header_units(cache_text[CORNERS['typ_1p20V_25C']])
    p("=" * 100)
    p("Liberty units (all three corners share the same units)")
    p(f"  time_unit            = {tu}")
    p(f"  capacitive_load_unit = {cu[0]} {cu[1]}")
    p(f"  Wire allowance added on top of FO1 self-load: {WIRE_CAP_FF} fF")
    p("=" * 100)

    cells = {}
    for corner, path in CORNERS.items():
        cells[corner] = {}
        for cn in TARGET_CELLS:
            g = load_cell(path, cn, cache_text)
            cells[corner][cn] = g
            if g is None:
                p(f"WARNING: cell {cn} not found in corner {corner}")

    # --- Areas ---------------------------------------------------------
    p("\n--- Cell areas (um^2), same across corners (physical layout) ---")
    p(f"{'cell':28s} {'area_um2':>10s}")
    for cn in TARGET_CELLS:
        g = cells['typ_1p20V_25C'].get(cn)
        if g is None:
            continue
        p(f"{cn:28s} {cell_area(g):10.4f}")

    # --- FO1 chain delays for buffer-like cells -------------------------
    chain_cells = ["sg13g2_buf_1", "sg13g2_buf_2", "sg13g2_inv_1",
                   "sg13g2_dlygate4sd1_1", "sg13g2_dlygate4sd2_1", "sg13g2_dlygate4sd3_1"]
    p("\n--- Self-consistent fanout-of-1 (own input cap + wire allowance) chain delay ---")
    p("(iterate output transition -> next-stage input transition to convergence)")
    p(f"{'cell':28s} {'corner':18s} {'load_pF':>9s} {'t_in_r':>8s} {'t_in_f':>8s} {'d_rise':>8s} {'d_fall':>8s} {'d_avg':>8s}")
    fo1_results = {}
    for cn in chain_cells:
        for corner in CORNERS:
            g = cells[corner][cn]
            ip = input_pins(g)[0]
            op = output_pin(g)
            load_pf = fo1_load(g, ip.args[0])
            if cn == "sg13g2_inv_1":
                t_r, t_f, d_r, d_f = self_consistent_inverting(g, ip, op, load_pf)
            else:
                t_r, d_r, t_f, d_f = self_consistent_noninverting(g, ip, op, load_pf)
            davg = (d_r + d_f) / 2.0
            fo1_results[(cn, corner)] = dict(load_pf=load_pf, t_rise=t_r, t_fall=t_f,
                                              d_rise=d_r, d_fall=d_f, d_avg=davg)
            p(f"{cn:28s} {corner:18s} {load_pf:9.5f} {t_r:8.4f} {t_f:8.4f} {d_r:8.4f} {d_f:8.4f} {davg:8.4f}")

    # --- FF timing: clock-to-Q, setup, hold -----------------------------
    p("\n--- Flip-flop timing (representative slew/load) ---")
    ff_cells = ["sg13g2_dfrbp_1", "sg13g2_dfrbpq_1"]
    rep_load_pf = fo1_load(cells['typ_1p20V_25C']['sg13g2_buf_1'], 'A')  # representative external load
    p(f"(representative load = buf_1 FO1 load = {rep_load_pf:.5f} pF;"
      f" representative clock/data transition = self-consistent buf_1 rise transition per corner)")
    p(f"{'cell':20s} {'corner':18s} {'ckQ_rise':>9s} {'ckQ_fall':>9s} {'setup_r':>9s} {'setup_f':>9s} {'hold_r':>9s} {'hold_f':>9s}")
    ff_results = {}
    for cn in ff_cells:
        for corner in CORNERS:
            g = cells[corner].get(cn)
            if g is None:
                continue
            rep_trans = fo1_results[("sg13g2_buf_1", corner)]["t_rise"]
            qpin = None
            for pg in g.find_all('pin'):
                if pg.args[0] == 'Q':
                    qpin = pg
                    break
            dpin = data_pin(g)
            ckq_r = get_table(qpin, 'cell_rise', related_pin='CLK')
            ckq_f = get_table(qpin, 'cell_fall', related_pin='CLK')
            d_r = bilinear(*ckq_r, rep_trans, rep_load_pf)
            d_f = bilinear(*ckq_f, rep_trans, rep_load_pf)
            # setup/hold are constraint tables on the D pin, indexed by
            # (constrained-pin transition, related-pin(clock) transition)
            su = get_table(dpin, 'rise_constraint', related_pin='CLK')
            su_f = get_table(dpin, 'fall_constraint', related_pin='CLK')
            # rising_constraint tables use timing_type setup_rising/hold_rising
            # distinguished by which timing() group; re-query explicitly:
            setup_r = setup_f = hold_r = hold_f = None
            for tg in dpin.find_all('timing'):
                if tg.attr('related_pin') != 'CLK':
                    continue
                tt = tg.attr('timing_type')
                rc = tg.find('rise_constraint')
                fc = tg.find('fall_constraint')
                if tt == 'setup_rising':
                    if rc:
                        idx1 = [float(x) for x in rc.find('index_1').attrs['__value__'][0].split(',')]
                        idx2 = [float(x) for x in rc.find('index_2').attrs['__value__'][0].split(',')]
                        m = parse_table_values(rc.find('values').attrs['__value__'])
                        setup_r = bilinear(idx1, idx2, m, rep_trans, rep_trans)
                    if fc:
                        idx1 = [float(x) for x in fc.find('index_1').attrs['__value__'][0].split(',')]
                        idx2 = [float(x) for x in fc.find('index_2').attrs['__value__'][0].split(',')]
                        m = parse_table_values(fc.find('values').attrs['__value__'])
                        setup_f = bilinear(idx1, idx2, m, rep_trans, rep_trans)
                elif tt == 'hold_rising':
                    if rc:
                        idx1 = [float(x) for x in rc.find('index_1').attrs['__value__'][0].split(',')]
                        idx2 = [float(x) for x in rc.find('index_2').attrs['__value__'][0].split(',')]
                        m = parse_table_values(rc.find('values').attrs['__value__'])
                        hold_r = bilinear(idx1, idx2, m, rep_trans, rep_trans)
                    if fc:
                        idx1 = [float(x) for x in fc.find('index_1').attrs['__value__'][0].split(',')]
                        idx2 = [float(x) for x in fc.find('index_2').attrs['__value__'][0].split(',')]
                        m = parse_table_values(fc.find('values').attrs['__value__'])
                        hold_f = bilinear(idx1, idx2, m, rep_trans, rep_trans)
            ff_results[(cn, corner)] = dict(ckq_r=d_r, ckq_f=d_f, setup_r=setup_r, setup_f=setup_f,
                                             hold_r=hold_r, hold_f=hold_f)
            def fmt(v):
                return f"{v:9.4f}" if v is not None else f"{'n/a':>9s}"
            p(f"{cn:20s} {corner:18s} {d_r:9.4f} {d_f:9.4f} {fmt(setup_r)} {fmt(setup_f)} {fmt(hold_r)} {fmt(hold_f)}")

    # --- xor2_1 per-arc A vs B ------------------------------------------
    p("\n--- xor2_1 per-arc delay: input A vs input B, rise/fall, at representative slew/load ---")
    p("(representative slew = self-consistent buf_1 rise transition per corner;"
      f" load = buf_1 FO1 load {rep_load_pf:.5f} pF; using the unconditional ('no when') timing arc per input)")
    p(f"{'corner':18s} {'A_rise':>8s} {'A_fall':>8s} {'B_rise':>8s} {'B_fall':>8s} {'|A-B| rise':>11s} {'|A-B| fall':>11s}")
    xor_results = {}
    for corner in CORNERS:
        g = cells[corner]['sg13g2_xor2_1']
        xpin = output_pin(g)
        rep_trans = fo1_results[("sg13g2_buf_1", corner)]["t_rise"]
        a_r = bilinear(*get_table(xpin, 'cell_rise', related_pin='A', require_no_when=True), rep_trans, rep_load_pf)
        a_f = bilinear(*get_table(xpin, 'cell_fall', related_pin='A', require_no_when=True), rep_trans, rep_load_pf)
        b_r = bilinear(*get_table(xpin, 'cell_rise', related_pin='B', require_no_when=True), rep_trans, rep_load_pf)
        b_f = bilinear(*get_table(xpin, 'cell_fall', related_pin='B', require_no_when=True), rep_trans, rep_load_pf)
        xor_results[corner] = dict(a_r=a_r, a_f=a_f, b_r=b_r, b_f=b_f)
        p(f"{corner:18s} {a_r:8.4f} {a_f:8.4f} {b_r:8.4f} {b_f:8.4f} {abs(a_r-b_r):11.4f} {abs(a_f-b_f):11.4f}")

    # dump everything needed by dtc_area.txt computation as a small python-literal
    p("\n--- machine-readable summary (for dtc_area.txt) ---")
    import json
    dump = {
        "fo1": {f"{cn}|{corner}": v for (cn, corner), v in fo1_results.items()},
        "area": {cn: cell_area(cells['typ_1p20V_25C'][cn]) for cn in TARGET_CELLS if cells['typ_1p20V_25C'].get(cn)},
    }
    p(json.dumps(dump, indent=2))

    with open("liberty_delays.txt", "w") as f:
        f.write("\n".join(out_lines) + "\n")
    with open("liberty_delays.json", "w") as f:
        json.dump(dump, f, indent=2)


if __name__ == "__main__":
    main()
