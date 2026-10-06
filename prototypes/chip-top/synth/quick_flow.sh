#!/usr/bin/env bash
# A partial LibreLane run of the Tiny Tapeout harden, for timing experiments: the same merged
# configuration as tt/scripts/harden.sh, but only up to a step, with optional configuration
# overrides and the Verilog regenerated from this checkout.
#   synth/quick_flow.sh BASE NEW SIZES TO_STEP [OVERRIDES.json]
# BASE is a finished harden stage (tt/scripts/harden.sh STAGE) whose tt-support-tools, venv and
# config_merged.json are reused; NEW is a new directory; TO_STEP a LibreLane step id such as
# OpenROAD.STAPrePNR, OpenROAD.STAMidPNR-3 (after global routing) or OpenROAD.STAPostPNR.
# OVERRIDES is a JSON object merged over config_merged.json.
set -o errexit -o nounset -o pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
BASE=$(cd "${1:?base stage}" && pwd) NEW=${2:?new dir} SIZES=${3:?sizes} TO=${4:?to step} OVR=${5:-}
export PDK_ROOT=${PDK_ROOT:-/var/tmp/roundtrip-cmos5l/pdk}
IMAGE=localhost/librelane-tt:3.1.0.dev3
[ ! -e "$NEW" ] || { echo "$NEW exists"; exit 2; }
mkdir --parents "$NEW/src"; NEW=$(cd "$NEW" && pwd)
cp --recursive "$BASE/tt" "$NEW/tt"
cp "$BASE"/src/*.v "$BASE"/src/*.tcl "$BASE/src/config_merged.json" "$NEW/src/"
# constraints files from this checkout's tt/src (the base stage may predate them)
cp "$HERE"/../../../tt/src/*.sdc "$NEW/src/" 2>/dev/null || true
"$HERE/../../../tt/scripts/regen_chip.sh" "$NEW/src/chip_tt.v" macros "$SIZES" 512
if [ -n "$OVR" ]; then
  python3 - "$NEW/src/config_merged.json" "$OVR" <<'PY'
import json, sys
c = json.load(open(sys.argv[1])); o = json.load(open(sys.argv[2]))
c.update({k: v for k, v in o.items() if k != "//"})
json.dump(c, open(sys.argv[1], "w"), indent=2)
PY
  cp "$OVR" "$NEW/overrides.json"
fi
cat > "$NEW/podman-real-home" <<P
#!/bin/sh
HOME='$HOME' exec podman "\$@"
P
chmod +x "$NEW/podman-real-home"
cd "$NEW"; mkdir --parents runs/quick
until awk '{exit !($1 < 16)}' /proc/loadavg; do sleep 30; done
start=$(date +%s)
HOME=$NEW PATH=$BASE/venv/bin:$PATH LIBRELANE_CONTAINER_ENGINE=$NEW/podman-real-home LIBRELANE_IMAGE_OVERRIDE=$IMAGE \
  nice ionice python -m librelane --dockerized --pdk-root "$PDK_ROOT" --pdk ihp-sg13cmos5l --manual-pdk \
  --run-tag quick --force-run-dir runs/quick --to "$TO" src/config_merged.json > flow.log 2>&1 || status=$?
echo "quick flow to $TO: exit ${status:-0} after $(( $(date +%s) - start )) s" | tee --append flow.log
exit "${status:-0}"
