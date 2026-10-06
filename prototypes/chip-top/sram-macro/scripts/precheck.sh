#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Run Tiny Tapeout's precheck on a stage that scripts/harden.sh hardened:
#   precheck.sh STAGE
# 1. tt_tool.py --create-tt-submission --ihp (as the GDS action does after --harden), in the stage's
#    venv, writing STAGE/tt_submission/;
# 2. tt-support-tools' precheck/precheck.py (the commit harden.sh pinned) on that GDS, with the
#    stage venv's Python modules (klayout 0.29.12 wheel, gdstk, pyyaml) and the `klayout` binary of
#    the pinned LibreLane image (KLayout 0.30.9; the action's precheck installs its own KLayout,
#    tool-versions.json says 0.30.4), run under rootless podman with the stage and PDK mounted at
#    the same paths.  For host load the wrapper adds `-rd threads=PRECHECK_THREADS` (default 4):
#    the SG13CMOS5L deck and the pin-label script read $threads and otherwise use every CPU (the
#    `thr` the precheck passes is not read by either). Thread count does not change DRC results.
set -o errexit -o nounset -o pipefail
STAGE=$(cd "${1:?usage: precheck.sh STAGE}" && pwd)
export PDK_ROOT=${PDK_ROOT:-/var/tmp/roundtrip-cmos5l/pdk} PDK=ihp-sg13cmos5l
IMAGE=localhost/librelane-tt:3.1.0.dev3
THREADS=${PRECHECK_THREADS:-4}
[ -x "$STAGE/venv/bin/python" ] && [ -d "$STAGE/runs/wokwi/final" ] || { echo "$STAGE is not a hardened stage"; exit 2; }
until awk '{exit !($1 < 16)}' /proc/loadavg; do sleep 30; done

cd "$STAGE"
HOME=$STAGE PATH=$STAGE/venv/bin:$PATH nice ionice python ./tt/tt_tool.py --create-tt-submission --ihp \
  > create-tt-submission.log 2>&1
gds=$(ls "$STAGE"/tt_submission/*.gds)

mkdir --parents "$STAGE/precheck-bin"
cat > "$STAGE/precheck-bin/klayout" <<EOF
#!/bin/sh
# klayout from $IMAGE, with -rd threads=$THREADS added.
exec nice ionice podman run --rm --volume "$STAGE:$STAGE" --volume "$PDK_ROOT:$PDK_ROOT:ro" \\
  --workdir "\$PWD" --env PDK_ROOT="$PDK_ROOT" --env PDK="$PDK" $IMAGE klayout -rd threads=$THREADS "\$@"
EOF
chmod +x "$STAGE/precheck-bin/klayout"

cd "$STAGE/tt/precheck"
start=$(date +%s)
PATH=$STAGE/precheck-bin:$STAGE/venv/bin:$PATH nice ionice python precheck.py --gds "$gds" \
  > "$STAGE/precheck.log" 2>&1 || status=$?
echo "precheck exit ${status:-0} after $(( $(date +%s) - start )) s" | tee --append "$STAGE/precheck.log"
cat "$STAGE/tt/precheck/reports/results.md" 2>/dev/null || true
exit "${status:-0}"
