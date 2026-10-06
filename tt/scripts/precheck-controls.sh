#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Planted controls for precheck.sh: copies of a hardened submission with one deliberate error each,
# which Tiny Tapeout's precheck must reject.  If a control passes, the precheck cannot see that class
# of error (or this script did not plant it), and a clean result on the real GDS means less.
#   tt/scripts/precheck-controls.sh STAGE OUT_DIR [quick|full] [CONTROL...]
# STAGE is a harden.sh directory that precheck.sh has already run on (it needs precheck-venv).
# Everything happens in copies under OUT_DIR; STAGE is only read.
# quick: the KLayout SG13CMOS5L DRC (about 19 minutes on this GDS) is switched off in the copy of
#        precheck.py, so only the controls that need not that deck are meaningful: pin-name,
#        boundary, forbidden-layer, top-name, layer.
# full:  the unmodified precheck; use for the control that needs the deck: drc-sliver.
set -o errexit -o nounset -o pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
STAGE=$(cd "${1:?usage: precheck-controls.sh STAGE OUT_DIR [quick|full] [CONTROL...]}" && pwd)
OUT=${2:?usage}; MODE=${3:-quick}; shift 3 || shift $#
CONTROLS=${*:-pin-name boundary forbidden-layer top-name layer}
[ ! -e "$OUT" ] || { echo "$OUT exists; give a new directory"; exit 2; }
mkdir --parents "$OUT"; OUT=$(cd "$OUT" && pwd)
PY=$STAGE/precheck-venv/bin/python
[ -x "$PY" ] || { echo "run precheck.sh on $STAGE first"; exit 2; }

# A stage of our own: tt-support-tools copied, the DRC deck switched off in quick mode.
mkdir --parents "$OUT/stage"
cp --recursive "$STAGE/tt" "$OUT/stage/tt"
if [ "$MODE" = quick ]; then
  "$PY" - "$OUT/stage/tt/precheck/precheck.py" <<'PYEOF'
import sys
p = sys.argv[1]; s = open(p).read()
old = '"check": lambda: klayout_sg13cmos5l(gds_file),\n            "techs": ["ihp-sg13cmos5l"],'
assert s.count(old) == 1
open(p, "w").write(s.replace(old, '"check": lambda: klayout_sg13cmos5l(gds_file),\n            "techs": [],'))
PYEOF
fi

plant() {  # plant CONTROL SRC_SUBMISSION_DIR DST_SUBMISSION_DIR
  "$PY" - "$1" "$2" "$3" <<'PYEOF'
import re, shutil, sys, gdstk
kind, src, dst = sys.argv[1:]
shutil.copytree(src, dst)
gds = f"{dst}/tt_um_seqv2.gds"; lef = f"{dst}/tt_um_seqv2.lef"
if kind == "pin-name":    # a LEF pin that the template DEF does not have
    s = open(lef).read(); assert "PIN uo_out[0]" in s
    open(lef, "w").write(s.replace("PIN uo_out[0]", "PIN uo_out[9]").replace("END uo_out[0]", "END uo_out[9]"))
    sys.exit()
lib = gdstk.read_gds(gds); top = lib.top_level()[0]
if kind == "boundary":    # Metal1 shape 50 um right of and above the prBoundary
    bb = top.bounding_box(); top.add(gdstk.rectangle((bb[1][0] + 50, bb[1][1] + 50), (bb[1][0] + 60, bb[1][1] + 60), layer=8, datatype=0))
elif kind == "forbidden-layer":   # TopMetal1 drawing, inside the boundary
    top.add(gdstk.rectangle((10, 10), (20, 20), layer=126, datatype=0))
elif kind == "layer":     # a layer number that is not in the shuttle's list
    top.add(gdstk.rectangle((10, 10), (20, 20), layer=200, datatype=7))
elif kind == "top-name":  # top cell renamed
    top.name = "tt_um_wrong"
elif kind == "drc-sliver":  # 0.05 um wide Metal1 inside the boundary (minimum width is 0.16 um)
    top.add(gdstk.rectangle((100, 100), (100.05, 110), layer=8, datatype=0))
else:
    raise SystemExit(f"unknown control {kind}")
lib.write_gds(gds)
PYEOF
}

for c in $CONTROLS; do
  mkdir --parents "$OUT/$c"
  cp "$STAGE/info.yaml" "$OUT/$c/info.yaml"
  plant "$c" "$STAGE/tt_submission" "$OUT/$c/tt_submission"
  status=0
  "$HERE/precheck.sh" "$OUT/stage" "$OUT/$c/report" "$OUT/$c" > "$OUT/$c.out" 2>&1 || status=$?
  echo "control $c: precheck exit $status ($( [ "$status" = 0 ] && echo 'PASSED: control NOT detected' || echo 'rejected, as it should be'))" | tee --append "$OUT/summary.txt"
  grep --extended-regexp '^\| .*(❌|✅)' "$OUT/$c/report/results.md" | tee --append "$OUT/summary.txt" >/dev/null || true
done
