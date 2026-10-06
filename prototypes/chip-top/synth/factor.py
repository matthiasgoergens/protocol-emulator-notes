#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""The whole-chip placement factor (gap G13 of notes/architecture-v0.md) from one harden.

    synth/factor.py RUN_DIR YOSYS_STAT [TAG]

RUN_DIR is a LibreLane run directory (<stage>/runs/wokwi); YOSYS_STAT the area-mode synthesis of
the same Verilog (synth/synth.sh), the quantity section 6 of the note multiplies by its factor.
Prints the standard-cell area after place and route, its growth over synthesis, the core, the
macros, the utilisation, and the factor the run demonstrates: the core area the logic was given
(core minus macros and their halo), over the synthesised area. That is an upper bound on the
factor the design needs, met at the density the run used; the lower bound is the growth alone
(no white space)."""
import json, re, sys
from pathlib import Path

run, stat = Path(sys.argv[1]), Path(sys.argv[2])
tag = sys.argv[3] if len(sys.argv) > 3 else run.parent.parent.name
m = json.load(open(run / "final" / "metrics.json"))
synth = float(re.search(r"Chip area for module '\\chip_tt': ([0-9.]+)", stat.read_text()).group(1))
core = m["design__core__area"]
std = m["design__instance__area__stdcell"]
macros = m.get("design__instance__area__macros", 0)
halo = 0.10 * macros
given = core - macros - halo
def g(k):
    return m.get(k)
print(f"{tag}: synthesised {synth:,.0f} um2; after PnR {std:,.0f} um2 of standard cells "
      f"(growth {std / synth:.2f}); core {core:,.0f}, macros {macros:,.0f} (+10 % halo); "
      f"standard-cell utilisation {g('design__instance__utilization__stdcell'):.3f}")
print(f"  factor demonstrated: (core - macros - halo) / synthesised = {given / synth:.2f} "
      f"(an upper bound: the logic fitted in that area); growth alone = {std / synth:.2f} (a lower bound)")
for k in ["route__drc_errors", "magic__drc_error__count", "design__lvs_error__count", "antenna__violating__nets",
          "timing__setup__ws", "timing__hold__ws", "timing__setup__ws__corner:nom_slow_1p08V_125C",
          "timing__hold__ws__corner:nom_fast_1p32V_m40C", "design__instance__count__stdcell",
          "design__instance__count__hold_buffer", "design__instance__count__class:timing_repair_buffer",
          "route__wirelength"]:
    if k in m:
        print(f"  {k} {m[k]}")
