#!/bin/sh
# Run pad.py in the spice-retention container: run.sh PART [VAR=value ...]
# PART is dc, noise, walk, sine or all; output goes to ../results/pad-PART.txt
set -e
here=$(cd "$(dirname "$0")" && pwd)
part=$1; shift
w=/var/tmp/scope/spice/$part
mkdir --parents "$w/osdi"
cp /var/tmp/scope/osdi/psp103.osdi "$w/osdi/"
cp "$here/pad.py" "$w/"
envs=""
for e in "$@"; do envs="$envs --env $e"; done
out="$here/../results/pad-$part.txt"
echo "# $(date --iso-8601=seconds) pad.py $part $* (commit $(git -C "$here" rev-parse --short HEAD))" > "$out"
nice ionice --class 3 podman run --rm --volume "$HOME/.ciel/ihp-sg13g2/ihp-sg13g2:/pdk:ro" \
  --volume "$w:/work" --workdir /work $envs spice-retention:latest python3 pad.py "$part" \
  >> "$out" 2> "$w/stderr.txt"
