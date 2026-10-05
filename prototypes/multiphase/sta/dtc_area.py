#!/usr/bin/env python3
"""Arithmetic area estimate for a programmable delay line + thermometer-code
TDC, built from sg13g2 standard cells, using the FO1 chain delays and cell
areas measured by liberty_delays.py.

Tap count is sized so that the chain covers the target interval (one full
period, or one quarter period) even at the FAST corner, since fast silicon
gives the smallest per-tap delay and therefore needs the MOST taps to reach
a given total delay. This is a plain arithmetic estimate: no wire
parasitics, no decoder logic for the select lines, no layout effects.
"""
import json
import math

with open("/var/tmp/multiphase/sta/liberty_delays.json") as f:
    LIB = json.load(f)

AREA = LIB["area"]
FO1 = LIB["fo1"]

TARGETS_MHZ = {"60MHz": 1000.0 / 60.0, "50MHz": 1000.0 / 50.0}  # period in ns
TAP_CELLS = ["sg13g2_buf_1", "sg13g2_dlygate4sd1_1"]
CORNERS = [("fast", "fast_1p32V_m40C"), ("typ", "typ_1p20V_25C"), ("slow", "slow_1p08V_125C")]
FF_CELL = "sg13g2_dfrbp_1"

out = []


def p(s=""):
    out.append(s)
    print(s)


def mux_tree_count(n, radix):
    """Number of radix-input muxes to build an n:1 mux tree
    (n-1)/(radix-1) merges, rounded up."""
    if n <= 1:
        return 0
    return math.ceil((n - 1) / (radix - 1))


p("=" * 100)
p("Programmable delay-line + thermometer-code TDC: arithmetic area estimate")
p("(N sized from the FAST corner's FO1 tap delay -- the worst case for tap count;")
p(" resolution then reported at all three corners for that fixed N; no wire")
p(" parasitics, no select-line decoder logic, no layout effects included)")
p("=" * 100)

for tap_cell in TAP_CELLS:
    tap_area = AREA[tap_cell]
    for target_name, period in TARGETS_MHZ.items():
        for coverage_name, coverage_frac in [("full period", 1.0), ("quarter period", 0.25)]:
            target_ns = period * coverage_frac
            fast_delay = FO1[f"{tap_cell}|fast_1p32V_m40C"]["d_avg"]
            n_taps = math.ceil(target_ns / fast_delay)
            p(f"\n--- tap cell={tap_cell}  target={target_name} ({period:.4f} ns period)  "
              f"coverage={coverage_name} ({target_ns:.4f} ns) ---")
            p(f"  FAST-corner tap delay = {fast_delay*1000:.2f} ps -> N = ceil({target_ns:.4f}/{fast_delay:.4f}) = {n_taps} taps")
            p(f"  {'corner':6s} {'tap_delay_ps':>13s} {'total_delay_ns':>15s} {'margin_ns':>10s}")
            for clabel, ckey in CORNERS:
                d = FO1[f"{tap_cell}|{ckey}"]["d_avg"]
                total = d * n_taps
                p(f"  {clabel:6s} {d*1000:13.2f} {total:15.4f} {total-target_ns:10.4f}")

            tap_chain_area = n_taps * tap_area
            ff_area = n_taps * AREA[FF_CELL]
            mux2_n = mux_tree_count(n_taps, 2)
            mux4_n = mux_tree_count(n_taps, 4)
            mux2_area = mux2_n * AREA["sg13g2_mux2_1"]
            mux4_area = mux4_n * AREA["sg13g2_mux4_1"]
            p(f"  area: tap chain ({n_taps}x{tap_cell}) = {tap_chain_area:.2f} um^2")
            p(f"        sampling flops ({n_taps}x{FF_CELL}) = {ff_area:.2f} um^2")
            p(f"        mux2-tree ({mux2_n}x mux2_1) = {mux2_area:.2f} um^2  -> total (mux2 variant) = {tap_chain_area+ff_area+mux2_area:.2f} um^2")
            p(f"        mux4-tree ({mux4_n}x mux4_1) = {mux4_area:.2f} um^2  -> total (mux4 variant) = {tap_chain_area+ff_area+mux4_area:.2f} um^2")

with open("/var/tmp/multiphase/sta/dtc_area.txt", "w") as f:
    f.write("\n".join(out) + "\n")
