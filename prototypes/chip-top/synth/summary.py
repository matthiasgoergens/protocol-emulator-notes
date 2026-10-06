#!/usr/bin/env python3
"""One line per corner of a LibreLane run's post-PnR timing, and its cell and buffer counts.
  synth/summary.py RUN_DIR [CLOCK_PERIOD]"""
import json, os, re, sys
run = sys.argv[1]
sta = [d for d in sorted(os.listdir(run)) if d.endswith("openroad-stapostpnr")]
m = json.load(open(os.path.join(run, sta[-1], "state_out.json")))["metrics"]
period = float(sys.argv[2]) if len(sys.argv) > 2 else None
print(f"{'corner':22s} {'setup ws':>9s} {'setup vio':>9s} {'hold ws':>8s} {'hold vio':>8s}" + ("  best period" if period else ""))
for c in ["nom_slow_1p08V_125C", "nom_typ_1p20V_25C", "nom_fast_1p32V_m40C"]:
    ws = m.get(f"timing__setup__ws__corner:{c}"); hw = m.get(f"timing__hold__ws__corner:{c}")
    sv = m.get(f"timing__setup_vio__count__corner:{c}"); hv = m.get(f"timing__hold_vio__count__corner:{c}")
    extra = f"  {period - ws:8.2f} ns ({1000 / (period - ws):.1f} MHz)" if period else ""
    print(f"{c:22s} {ws:+9.3f} {sv:9d} {hw:+8.3f} {hv:8d}{extra}")
nl = open(os.path.join(run, "final/nl/tt_um_chip_top.nl.v")).read() if os.path.exists(os.path.join(run, "final/nl/tt_um_chip_top.nl.v")) else ""
if not nl:
    for d in sorted(os.listdir(run), reverse=True):
        p = os.path.join(run, d, "tt_um_chip_top.nl.v")
        if os.path.exists(p):
            nl = open(p).read(); break
cells = re.findall(r"^\s*(sg13cmos5l_\w+)\s+(\S+)\s*\(", nl, re.M)
real = [c for c in cells if not re.search(r"fill|decap|tap|antenna", c[0])]
hold = sum(1 for c in cells if c[1].startswith("hold"))
print(f"cells (no fill/decap/tap/antenna) {len(real)}, hold buffers {hold}, "
      f"flip-flops {sum(1 for c in cells if 'dfrbp' in c[0])}, "
      f"design area {m.get('design__instance__area__stdcell', m.get('design__instance__area', 0)):.0f} um2, "
      f"wire length {m.get('route__wirelength', 0)} um, DRC {m.get('route__drc_errors', '?')}")
