#!/usr/bin/env python3
"""Print the final metrics that matter for one or more LibreLane runs under synth/runs/<tag>/."""
import json, sys, os, glob
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
def num(m, k, f='{:.1f}'):
    v = m.get(k); return f.format(v) if isinstance(v, (int, float)) else str(v)
for tag in sys.argv[1:]:
    p = f'{ROOT}/synth/runs/{tag}/final/metrics.json'
    if not os.path.exists(p):
        fs = sorted(glob.glob(f'{ROOT}/synth/runs/{tag}/*/or_metrics_out.json'))
        print(f'{tag}: no final metrics; last step with metrics: {os.path.basename(os.path.dirname(fs[-1])) if fs else "none"}'); continue
    m = json.load(open(p))
    print(f'{tag}: die={num(m, "design__die__area", "{:.0f}")} core={num(m, "design__core__area", "{:.0f}")} '
          f'inst={num(m, "design__instance__area", "{:.0f}")} util={num(m, "design__instance__utilization", "{:.3f}")} '
          f'tbuf={num(m, "design__instance__area__class:timing_repair_buffer", "{:.0f}")} wl={num(m, "route__wirelength", "{:.0f}")} '
          f'routeDRC={m.get("route__drc_errors")} magicDRC={m.get("magic__drc_error__count")} klayoutDRC={m.get("klayout__drc_error__count")} '
          f'xor={m.get("design__xor_difference__count")} lvs={m.get("design__lvs_error__count")}')
    for c in ('nom_fast_1p32V_m40C', 'nom_typ_1p20V_25C', 'nom_slow_1p08V_125C'):
        print(f'   {c:22s} setup_ws={num(m, f"timing__setup__ws__corner:{c}", "{:+.2f}")} hold_ws={num(m, f"timing__hold__ws__corner:{c}", "{:+.2f}")} '
              f'clock={num(m, "clock__period", "{:.0f}") if "clock__period" in m else "?"}')
