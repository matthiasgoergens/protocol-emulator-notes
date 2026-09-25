#!/bin/sh
# Runs one simulation in its own scratch directory and saves its output under results/.
# Usage: run.sh NAME SCRIPT [ARGS...]   (environment variables are passed into the container
# through ENVS="VAR1=x VAR2=y")
# Each run gets /var/tmp/spice-gc-thick/NAME, since the scripts write netlists by fixed names.
set -e
name=$1; script=$2; shift 2
here=$(cd "$(dirname "$0")" && pwd)
work=/var/tmp/spice-gc-thick/$name
mkdir --parents "$work"
cp --recursive /var/tmp/spice-gc-thick/osdi "$work/"
[ -d /var/tmp/spice-gc-thick/models-dvt ] && cp --recursive /var/tmp/spice-gc-thick/models-dvt "$work/"
cp "$here/$script" "$work/"
envargs=""
for e in $ENVS; do envargs="$envargs --env $e"; done
{
  echo "# $script $* ENVS=$ENVS  commit $(git -C "$here" rev-parse --short HEAD)  $(date --iso-8601=seconds)"
  # shellcheck disable=SC2086
  nice ionice --class 3 podman run --rm $envargs \
    --volume "$HOME/.ciel/ihp-sg13g2/ihp-sg13g2:/pdk:ro" --volume "$work:/work" --workdir /work \
    spice-retention:latest python3 "$script" "$@"
} 2>&1 | tee "$here/results/$name.txt"
