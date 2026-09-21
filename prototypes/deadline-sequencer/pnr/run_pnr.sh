#!/usr/bin/env bash
# Place and route the deadline sequencer in the LibreLane container at the period given in librelane.json.
export DOCKER_CONFIG=/var/tmp/claude-notes/dockercfg
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT/pnr"
nice ionice docker run --rm --user "$(id -u):$(id -g)" \
  --volume /home/matthias/.ciel:/home/matthias/.ciel:ro \
  --volume "$ROOT:$ROOT" --workdir "$ROOT/pnr" \
  --env PDK_ROOT=/home/matthias/.ciel/ihp-sg13g2 --env PDK=ihp-sg13g2 --env HOME="$ROOT/pnr" \
  ghcr.io/librelane/librelane:3.0.14 \
  librelane --manual-pdk --pdk-root /home/matthias/.ciel/ihp-sg13g2 --pdk ihp-sg13g2 --run-tag seq15ns ../librelane.json > librelane_seq15ns.log 2>&1
echo "librelane exit $? $(date)" >> librelane_seq15ns.log
