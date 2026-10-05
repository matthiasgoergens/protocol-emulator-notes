#!/usr/bin/env bash
# Place and route a block with LibreLane 3.0.14 (IHP sg13g2) in a scratch directory, keeping the GDS.
# Usage: run_pnr.sh <block dir containing librelane.json and its Verilog> <scratch dir> <run tag>
# The block directory is copied, so the checkout is never written to.
set -o errexit -o nounset -o pipefail
BLOCK=$(cd "$1" && pwd)
SCRATCH=$2
TAG=$3
export DOCKER_CONFIG=/var/tmp/claude-notes/dockercfg
mkdir --parents "$SCRATCH"
cp "$BLOCK"/librelane.json "$BLOCK"/*.v "$SCRATCH"/
cd "$SCRATCH"
start=$(date +%s)
nice ionice docker run --rm --user "$(id -u):$(id -g)" \
  --volume /home/matthias/.ciel:/home/matthias/.ciel:ro \
  --volume "$SCRATCH:$SCRATCH" --workdir "$SCRATCH" \
  --env PDK_ROOT=/home/matthias/.ciel/ihp-sg13g2 --env PDK=ihp-sg13g2 --env HOME="$SCRATCH" \
  ghcr.io/librelane/librelane:3.0.14 \
  librelane --manual-pdk --pdk-root /home/matthias/.ciel/ihp-sg13g2 --pdk ihp-sg13g2 --run-tag "$TAG" librelane.json \
  > "librelane_$TAG.log" 2>&1 || status=$?
echo "librelane exit ${status:-0} after $(( $(date +%s) - start )) s, $(date)" | tee --append "librelane_$TAG.log"
