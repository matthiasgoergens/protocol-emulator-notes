#!/usr/bin/env bash
# Place and route one design with LibreLane 3.0.14 (its container) on IHP SG13G2.
#   pnr/run_pnr.sh <design> [period_ns] [core_util_pct]
# The run directory is /var/tmp/pe-synth/pnr/<tag> (large); final-metrics.json, the flow log and
# the config are copied to pnr-metrics/<tag>/. LibreLane does its own Yosys synthesis.
set -o errexit -o nounset -o pipefail
NAME=$1; PERIOD=${2:-20}; UTIL=${3:-65}
TAG=${NAME}_${PERIOD}ns_u${UTIL}
HERE=$(cd "$(dirname "$0")/.." && pwd)
RUN=/var/tmp/pe-synth/pnr/$TAG; mkdir --parents "$RUN" "$HERE/pnr-metrics/$TAG"
cp "$HERE/rtl/$NAME.v" "$RUN/"
cat > "$RUN/config.json" <<JSON
{
  "DESIGN_NAME": "$NAME",
  "VERILOG_FILES": ["dir::$NAME.v"],
  "CLOCK_PORT": "clock",
  "CLOCK_PERIOD": $PERIOD,
  "FP_SIZING": "relative",
  "FP_CORE_UTIL": $UTIL,
  "PL_TARGET_DENSITY_PCT": $((UTIL + 5)),
  "RUN_KLAYOUT_XOR": false,
  "RUN_MAGIC_DRC": false,
  "RUN_KLAYOUT_DRC": false,
  "RUN_LVS": false,
  "RUN_IRDROP_REPORT": false
}
JSON
export DOCKER_CONFIG=/var/tmp/claude-notes/dockercfg
set +o errexit
nice ionice docker run --rm --user "$(id -u):$(id -g)" \
  --volume /home/matthias/.ciel:/home/matthias/.ciel:ro \
  --volume "$RUN:$RUN" --workdir "$RUN" \
  --env PDK_ROOT=/home/matthias/.ciel/ihp-sg13g2 --env PDK=ihp-sg13g2 --env HOME="$RUN" \
  ghcr.io/librelane/librelane:3.0.14 \
  librelane --manual-pdk --pdk-root /home/matthias/.ciel/ihp-sg13g2 --pdk ihp-sg13g2 --run-tag "$TAG" config.json > "$RUN/librelane.log" 2>&1
RC=$?
echo "librelane exit $RC $(date --iso-8601=seconds)" >> "$RUN/librelane.log"
cp "$RUN/config.json" "$HERE/pnr-metrics/$TAG/"
cp "$RUN/librelane.log" "$HERE/pnr-metrics/$TAG/"
cp "$RUN/runs/$TAG/06-yosys-synthesis/reports/stat.rpt" "$HERE/pnr-metrics/$TAG/librelane-synth-stat.rpt" 2>/dev/null || true
cp "$RUN/runs/$TAG/final/metrics.json" "$HERE/pnr-metrics/$TAG/final-metrics.json" 2>/dev/null || true
exit $RC
