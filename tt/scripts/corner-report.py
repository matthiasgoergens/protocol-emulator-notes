#!/usr/bin/env -S uv run --no-project --python 3.12 python
# SPDX-License-Identifier: Apache-2.0
"""Report setup and hold timing per corner from a finished LibreLane run directory.

    corner-report.py RUN_DIR [--json] [--require typ,slow,fast]

Reads RUN_DIR/final/metrics.json (or RUN_DIR itself if it is a metrics.json file) and prints,
for every corner, the worst setup and hold slack, the violation counts and the register-to-
register slacks, so that a pass at the typical corner cannot hide a failure at the others.

Exit status: 0 all required corners present and no violation; 1 a violation; 2 the file could
not be read, or a required corner is missing, or no per-corner keys exist at all (a report that
found nothing must not look like a clean one).

This script does not run LibreLane or any other tool; it only reads the metrics file.
Per-corner reporting as a practice is credited to joshvern/pinscript-cmos5l-feasibility
(Apache-2.0); no code was copied from there. The metric key names are LibreLane's.
"""
import argparse
import json
import math
import re
import sys
from pathlib import Path

# metric -> short column name; keys look like "timing__setup__ws__corner:nom_typ_1p20V_25C"
COLUMNS = [
    ("timing__setup__ws", "setup ws"),
    ("timing__hold__ws", "hold ws"),
    ("timing__setup_vio__count", "setup vio"),
    ("timing__hold_vio__count", "hold vio"),
    ("timing__setup_r2r__ws", "setup r2r ws"),
    ("timing__hold_r2r__ws", "hold r2r ws"),
]
KEY = re.compile(r"^(timing__[a-z0-9_]+)__corner:(.+)$")
# LibreLane names the three IHP corners nom_typ_..., nom_slow_..., nom_fast_...
ALIASES = {"typ": "_typ_", "slow": "_slow_", "fast": "_fast_"}


def load(path: Path) -> dict:
    p = path / "final" / "metrics.json" if path.is_dir() else path
    with open(p) as f:
        return json.load(f)


def per_corner(metrics: dict) -> dict:
    corners: dict = {}
    for key, value in metrics.items():
        m = KEY.match(key)
        if m:
            corners.setdefault(m.group(2), {})[m.group(1)] = value
    return corners


def fmt(v) -> str:
    if v is None:
        return "-"
    if isinstance(v, float) and math.isinf(v):
        return "inf"
    if isinstance(v, int):
        return str(v)
    return f"{v:.3f}"


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("run_dir", type=Path)
    ap.add_argument("--json", action="store_true", help="print the per-corner table as JSON")
    ap.add_argument("--require", default="typ,slow,fast",
                    help="comma-separated corners that must be present (typ, slow, fast, or a full name)")
    args = ap.parse_args()
    try:
        corners = per_corner(load(args.run_dir))
    except (OSError, json.JSONDecodeError) as e:
        print(f"corner-report: cannot read metrics: {e}", file=sys.stderr)
        return 2
    if not corners:
        print("corner-report: no per-corner timing keys in the metrics file; refusing to report "
              "a clean result (was the run finished, and did it reach the post-PnR STA step?)",
              file=sys.stderr)
        return 2

    missing = []
    for want in filter(None, args.require.split(",")):
        needle = ALIASES.get(want, want)
        if not any(needle in name for name in corners):
            missing.append(want)

    violations = []
    rows = []
    for name in sorted(corners):
        c = corners[name]
        rows.append((name, [c.get(k) for k, _ in COLUMNS]))
        for k in ("timing__setup_vio__count", "timing__hold_vio__count"):
            if c.get(k):
                violations.append(f"{name}: {k} = {c[k]}")
        for k in ("timing__setup__ws", "timing__hold__ws"):
            if c.get(k) is not None and c[k] < 0:
                violations.append(f"{name}: {k} = {c[k]}")

    if args.json:
        print(json.dumps({n: dict(zip([k for k, _ in COLUMNS], v)) for n, v in rows},
                         indent=2, allow_nan=True))
    else:
        width = max(len(n) for n, _ in rows)
        print(f"{'corner':<{width}}  " + "  ".join(f"{h:>12}" for _, h in COLUMNS))
        for n, vals in rows:
            print(f"{n:<{width}}  " + "  ".join(f"{fmt(v):>12}" for v in vals))
        print("slacks in ns; negative = violated; r2r inf = no register-to-register path")
    for v in violations:
        print(f"VIOLATION {v}", file=sys.stderr)
    for m in missing:
        print(f"MISSING corner {m!r} (have: {', '.join(sorted(corners))})", file=sys.stderr)
    if missing:
        return 2
    return 1 if violations else 0


if __name__ == "__main__":
    sys.exit(main())
