#!/usr/bin/env bash
# Re-run the liberty extraction, synthesis, STA and delay-line arithmetic. The scripts use absolute
# paths under /var/tmp/multiphase/sta (see COMMANDS.txt), so this copies them there and runs them.
set -o errexit -o nounset -o pipefail
here=$(cd "$(dirname "$0")" && pwd)
w=/var/tmp/multiphase/sta; mkdir --parents "$w"
cp "$here"/*.py "$here"/synth.ys "$here"/sta_run.tcl "$w"/
cd "$w"
export DOCKER_CONFIG=/var/tmp/claude-notes/dockercfg
dk() { nice ionice docker run --rm --user "$(id -u):$(id -g)" --volume /home/matthias/.ciel:/home/matthias/.ciel:ro \
  --volume /var/tmp/multiphase:/var/tmp/multiphase --volume "$here/..:$here/..:ro" --workdir "$w" ghcr.io/librelane/librelane:3.0.14 "$@"; }
nice ionice uv run --no-project python3 liberty_delays.py > run_liberty_delays.log
dk yosys -s "$w/synth.ys" > synth.log 2>&1
for p in 15.0 16.67 18.8; do nice ionice uv run --no-project python3 gen_sdc.py "$p" "sta_$(echo "$p" | tr . p).sdc"; done
nice ionice uv run --no-project python3 gen_sta_tcl.py
dk bash -lc 'for c in fast typ slow; do for p in 15p0 16p67 18p8; do sta -exit -no_init sta_${c}_${p}.tcl > sta_${c}_${p}.log 2>&1; done; done'
nice ionice uv run --no-project python3 parse_sta.py
nice ionice uv run --no-project python3 dtc_area.py
cp liberty_delays.txt synth.log sta_summary.txt dtc_area.txt "$here"/
