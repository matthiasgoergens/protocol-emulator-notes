#!/bin/sh
# Run pad2.py PART in the spice-retention container: run2.sh PART [VAR=value ...]
# Summary to ../results/pad2-PART.txt; waveforms stay in /var/tmp/scope/spice2/PART
# (collect.py packs them into ../results/pad-waves.npz).
set -e
here=$(cd "$(dirname "$0")" && pwd)
part=$1; shift
w=/var/tmp/scope/spice2/$part
mkdir --parents "$w/osdi"
cp /var/tmp/scope/osdi/psp103.osdi "$w/osdi/"
cp "$here/pad.py" "$here/pad2.py" "$w/"
envs=""
for e in "$@"; do envs="$envs --env $e"; done
out="$here/../results/pad2-$part.txt"
echo "# $(date --iso-8601=seconds) pad2.py $part $* (commit $(git -C "$here" rev-parse --short HEAD))" > "$out"
nice ionice --class 3 podman run --rm --volume "$HOME/.ciel/ihp-sg13g2/ihp-sg13g2:/pdk:ro" \
  --volume "$w:/work" --workdir /work $envs spice-retention:latest python3 pad2.py "$part" \
  >> "$out" 2> "$w/stderr.txt"
