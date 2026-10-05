#!/usr/bin/env python3
"""Parse the nine sta_<corner>_<period>.log files into sta_summary.txt:
worst setup/hold slack + critical path endpoints, and the per-lane
clock-to-pin delay table (max/min, rise/fall) with the lane spread."""
import re
import glob
import json

CORNERS = ["fast", "typ", "slow"]
PERIODS = ["15p0", "16p67", "18p8"]
PERIOD_NS = {"15p0": 15.0, "16p67": 16.67, "18p8": 18.8}

out_lines = []


def p(s=""):
    out_lines.append(s)


def parse_log(path):
    text = open(path).read()
    worst_setup = float(re.search(r'WORST_SETUP_SLACK\s+([-\d.]+)', text).group(1))
    worst_hold = float(re.search(r'WORST_HOLD_SLACK\s+([-\d.]+)', text).group(1))

    # report_checks -group_count 3 prints the 3 worst paths PER PATH GROUP
    # (one group per phase clock), not the 3 worst overall -- so the true
    # global critical path is whichever printed path's slack matches
    # sta::worst_slack, found across ALL groups.
    max_section = text.split('--- report_checks -path_delay max')[1].split('--- report_checks -path_delay min')[0]
    min_section = text.split('--- report_checks -path_delay min')[1].split('--- worst slacks')[0]

    def find_path_matching_slack(section, target_slack):
        blocks = re.split(r'\nStartpoint:', section)[1:]
        for b in blocks:
            b = 'Startpoint:' + b
            sp = re.search(r'Startpoint:\s*(\S+)', b)
            ep = re.search(r'Endpoint:\s*(\S+)', b)
            sl = re.search(r'([-\d.]+)\s+slack', b)
            if sp and ep and sl and abs(float(sl.group(1)) - target_slack) < 5e-4:
                return sp.group(1), ep.group(1)
        return None, None

    worst_setup = float(re.search(r'WORST_SETUP_SLACK\s+([-\d.]+)', text).group(1))
    worst_hold = float(re.search(r'WORST_HOLD_SLACK\s+([-\d.]+)', text).group(1))
    crit_start, crit_end = find_path_matching_slack(max_section, worst_setup)
    hold_start, hold_end = find_path_matching_slack(min_section, worst_hold)

    # per-lane sections
    lane_blocks = re.split(r'\nLANE net=', text)[1:]
    lanes = {}
    for blk in lane_blocks:
        header = blk.splitlines()[0]
        m = re.match(r'(\S+) phase=(\S+) port=(\S+) inst=(\S+)', header)
        net, phase, port, inst = m.groups()
        vals = {}
        for tag in ["MAXRISE", "MAXFALL", "MINRISE", "MINFALL"]:
            m2 = re.search(tag + r':.*?\n(.*?)(?=\n  (?:MAXRISE|MAXFALL|MINRISE|MINFALL):|\Z)', blk, re.S)
            sub = m2.group(1) if m2 else ""
            # "data arrival time" is an ABSOLUTE time referenced to the
            # launching clock edge's own absolute position in the period
            # (e.g. ph3 launches at 0.75*P), not a pure propagation delay.
            # Subtract the launch-edge time (the first row: "clock <ph> (rise
            # edge)") to get the true clock(edge)-to-pin propagation delay.
            clk_edge = re.search(r'^\s*([-\d.]+)\s+[-\d.]+\s+clock \S+ \(rise edge\)', sub, re.M)
            da = re.search(r'\n\s*([-\d.]+)\s+data arrival time', sub)
            if clk_edge and da:
                vals[tag] = float(da.group(1)) - float(clk_edge.group(1))
            else:
                vals[tag] = None
        lanes[(net, phase, port)] = vals
    return dict(worst_setup=worst_setup, worst_hold=worst_hold,
                crit_start=crit_start, crit_end=crit_end, crit_slack=worst_setup,
                hold_start=hold_start, hold_end=hold_end, lanes=lanes)


results = {}
for corner in CORNERS:
    for period in PERIODS:
        path = f"/var/tmp/multiphase/sta/sta_{corner}_{period}.log"
        results[(corner, period)] = parse_log(path)

p("=" * 100)
p("STA summary: worst setup/hold slack and critical-path endpoints per corner/period")
p("=" * 100)
p(f"{'corner':6s} {'period_ns':>9s} {'setup_slack':>12s} {'hold_slack':>11s}  critical_setup_path (start -> end)                 critical_hold_path (start -> end)")
for corner in CORNERS:
    for period in PERIODS:
        r = results[(corner, period)]
        p(f"{corner:6s} {PERIOD_NS[period]:9.2f} {r['worst_setup']:12.4f} {r['worst_hold']:11.4f}  "
          f"{r['crit_start']} -> {r['crit_end']:20s}  {r['hold_start']} -> {r['hold_end']}")

p("\n" + "=" * 100)
p("Per-lane clock(phase)-to-pin delay (clock-to-Q + XOR tree), ns; spread = max(all 32 numbers) - min(all 32 numbers) per corner/period")
p("=" * 100)
lane_order = [
    ("_144", "ph0", "pin[0]"), ("_134", "ph1", "pin[0]"), ("_124", "ph2", "pin[0]"), ("_114", "ph3", "pin[0]"),
    ("_18", "ph0", "pin[1]"), ("_14", "ph1", "pin[1]"), ("_12", "ph2", "pin[1]"), ("_10", "ph3", "pin[1]"),
]
for corner in CORNERS:
    for period in PERIODS:
        r = results[(corner, period)]
        p(f"\n-- corner={corner} period={PERIOD_NS[period]}ns --")
        p(f"{'lane_net':8s} {'phase':5s} {'port':7s} {'maxrise':>8s} {'maxfall':>8s} {'minrise':>8s} {'minfall':>8s}")
        all_vals = []
        for key in lane_order:
            v = r['lanes'].get(key)
            if v is None:
                p(f"{key[0]:8s} {key[1]:5s} {key[2]:7s}  MISSING")
                continue
            p(f"{key[0]:8s} {key[1]:5s} {key[2]:7s} {v['MAXRISE']:8.4f} {v['MAXFALL']:8.4f} {v['MINRISE']:8.4f} {v['MINFALL']:8.4f}")
            all_vals += [v['MAXRISE'], v['MAXFALL'], v['MINRISE'], v['MINFALL']]
        # spread computed on the max-path numbers only (the "static lane mismatch"
        # that matters for a TDC / phase-interpolator budget), separately for
        # pin[0] and pin[1], and combined.
        max_vals_pin0 = [r['lanes'][k]['MAXRISE'] for k in lane_order if k[2] == 'pin[0]' and r['lanes'].get(k)] + \
                         [r['lanes'][k]['MAXFALL'] for k in lane_order if k[2] == 'pin[0]' and r['lanes'].get(k)]
        max_vals_pin1 = [r['lanes'][k]['MAXRISE'] for k in lane_order if k[2] == 'pin[1]' and r['lanes'].get(k)] + \
                         [r['lanes'][k]['MAXFALL'] for k in lane_order if k[2] == 'pin[1]' and r['lanes'].get(k)]
        all_max_vals = max_vals_pin0 + max_vals_pin1
        p(f"  lane spread (max-path, rise&fall) pin[0]: {max(max_vals_pin0)-min(max_vals_pin0):.4f} ns "
          f"  pin[1]: {max(max_vals_pin1)-min(max_vals_pin1):.4f} ns"
          f"  both pins combined: {max(all_max_vals)-min(all_max_vals):.4f} ns")

with open("/var/tmp/multiphase/sta/sta_summary.txt", "w") as f:
    f.write("\n".join(out_lines) + "\n")
print("\n".join(out_lines))
