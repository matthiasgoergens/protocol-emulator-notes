#!/usr/bin/env bash
# Copy the record of a finished harden into results/: corners, metrics, LVS, the tail of the log,
# the routing stats, the configuration, the precheck and the placement factor.
#   synth/collect_harden.sh STAGE OUT_DIR [PRECHECK_DIR] [YOSYS_STAT]
set -o errexit -o nounset -o pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
STAGE=${1:?stage} OUT=${2:?out} PRE=${3:-} STAT=${4:-}
R=$STAGE/runs/wokwi
mkdir --parents "$OUT"
cp "$R/final/metrics.json" "$OUT/metrics.json"
cp "$STAGE/src/config.json" "$OUT/config.json"
cp "$STAGE/src/chip.sdc" "$OUT/chip.sdc" 2>/dev/null || true
cp "$STAGE/stats.md" "$OUT/stats.md"
tail --lines=5 "$STAGE/harden.log" > "$OUT/harden-tail.txt"
grep --no-filename --after-context=1 'Final result' "$R"/*netgen-lvs/netgen-lvs.log > "$OUT/lvs.txt" || true
python3 -c "import json; m = json.load(open('$R/final/metrics.json')); print('design__lvs_error__count', m['design__lvs_error__count'])" >> "$OUT/lvs.txt"
"$HERE/../../../tt/scripts/corner-report.py" "$R" > "$OUT/corners.txt" || true
python3 "$HERE/summary.py" "$R" "$(python3 -c "import json;print(json.load(open('$R/resolved.json'))['CLOCK_PERIOD'])")" > "$OUT/summary.txt"
if [ -n "$PRE" ]; then { head --lines=1 "$PRE/precheck.log" 2>/dev/null; cat "$PRE/results.md"; } > "$OUT/precheck.txt"; fi
if [ -n "$STAT" ]; then python3 "$HERE/factor.py" "$R" "$STAT" "$(basename "$OUT" | sed s/harden-//)" > "$OUT/factor.txt"; fi
ls "$OUT"
