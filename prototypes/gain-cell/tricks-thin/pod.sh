#!/bin/sh
# Run one simulation script in its own work dir: pod.sh RUN SCRIPT [VAR=value ...] [-- args]
# Output goes to results/RUN.txt (stdout) and results/RUN.err (stderr) next to this script.
set -e
here=$(cd "$(dirname "$0")" && pwd)
run=$1; script=$2; shift 2
w=/var/tmp/spice-gc-thin/$run
mkdir --parents "$w"
cp --recursive /var/tmp/spice-gc-thin/osdi "$w/"
cp "$here"/*.py "$w/"
envs=""
while [ $# -gt 0 ] && [ "$1" != "--" ]; do envs="$envs --env $1"; shift; done
[ "$1" = "--" ] && shift
echo "# $(date --iso-8601=seconds) run $run: $script $envs $*  (commit $(git -C "$here" rev-parse --short HEAD))" > "$here/results/$run.txt"
nice ionice --class 3 podman run --rm --volume "$HOME/.ciel/ihp-sg13g2/ihp-sg13g2:/pdk:ro" \
  --volume "$w:/work" --workdir /work $envs spice-retention:latest python3 "$script" "$@" \
  >> "$here/results/$run.txt" 2> "$here/results/$run.err"
