#!/usr/bin/env bash
# Place and route one LibreLane config in the container. Usage: run_pnr.sh <config name> (synth/librelane_<name>.json)
N=$1
export DOCKER_CONFIG=${DOCKER_CONFIG_EMPTY:-/var/tmp/dockercfg-empty}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT/pnr"
nice ionice docker run --rm --user "$(id -u):$(id -g)" \
  --volume ${CIEL_ROOT:-$HOME/.ciel}:${CIEL_ROOT:-$HOME/.ciel}:ro \
  --volume "$ROOT:$ROOT" --workdir "$ROOT/pnr" \
  --env PDK_ROOT=${CIEL_ROOT:-$HOME/.ciel}/ihp-sg13g2 --env PDK=ihp-sg13g2 --env HOME="$ROOT/pnr" \
  ghcr.io/librelane/librelane:3.0.14 \
  librelane --manual-pdk --pdk-root ${CIEL_ROOT:-$HOME/.ciel}/ihp-sg13g2 --pdk ihp-sg13g2 --run-tag "$N" "../synth/librelane_$N.json" > "librelane_$N.log" 2>&1
echo "librelane exit $? $(date)" >> "librelane_$N.log"
