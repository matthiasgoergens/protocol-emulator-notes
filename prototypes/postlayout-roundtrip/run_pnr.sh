#!/usr/bin/env bash
# Place and route a block with LibreLane in its container, in a scratch directory, keeping the GDS.
# Usage: [LIBRELANE=3.0.14|3.1.0.dev3] run_pnr.sh <block dir with librelane.json and its Verilog> <scratch dir> <run tag> [PDK]
#   PDK is ihp-sg13g2 (the default, from ciel under ~/.ciel/ihp-sg13g2) or ihp-sg13cmos5l, the
#   variant the Tiny Tapeout IHP shuttle uses.  ciel 3.0's ihp-sg13 releases do not include the
#   revision Tiny Tapeout pins, so for sg13cmos5l PDK_ROOT must point at a checkout made with
#   TinyTapeout/tt-gds-action's install_sg13cmos5l.sh (branch ihp-cmos5l; IHP-Open-PDK 2bbec755).
# LIBRELANE picks the container: 3.0.14 (ghcr.io/librelane/librelane:3.0.14 under docker, which made
#   every sg13g2 result in README.md) or 3.1.0.dev3 (localhost/librelane-tt:3.1.0.dev3 under rootless
#   podman, built from tools/librelane-tt/Containerfile: the LibreLane Tiny Tapeout's ihp-cmos5l action
#   uses).  The default is 3.0.14 for sg13g2 and 3.1.0.dev3 for sg13cmos5l, which 3.0.14 cannot finish
#   (tools/librelane-tt/README.md says why).
# The block directory is copied, so the checkout is never written to; the PDK is mounted read-only.
set -o errexit -o nounset -o pipefail
BLOCK=$(cd "$1" && pwd)
SCRATCH=$2
TAG=$3
PDK=${4:-ihp-sg13g2}
case $PDK in
  ihp-sg13g2) PDK_ROOT=${PDK_ROOT:-/home/matthias/.ciel/ihp-sg13g2}; LIBRELANE=${LIBRELANE:-3.0.14} ;;
  ihp-sg13cmos5l) PDK_ROOT=${PDK_ROOT:?set PDK_ROOT to a tt-gds-action style ihp-sg13cmos5l checkout}
    LIBRELANE=${LIBRELANE:-3.1.0.dev3} ;;
  *) echo "unknown PDK $PDK"; exit 2 ;;
esac
[ -f "$PDK_ROOT/$PDK/libs.tech/librelane/config.tcl" ] || { echo "no $PDK under $PDK_ROOT"; exit 2; }
case $LIBRELANE in
  3.0.14) export DOCKER_CONFIG=/var/tmp/claude-notes/dockercfg
    ENGINE=(docker run --user "$(id -u):$(id -g)"); IMAGE=ghcr.io/librelane/librelane:3.0.14 ;;
  3.1.0.dev3) # rootless podman: root in the container is this user outside, so files stay ours
    ENGINE=(podman run); IMAGE=localhost/librelane-tt:3.1.0.dev3
    podman image exists "$IMAGE" || { echo "build $IMAGE first: tools/librelane-tt/build.sh"; exit 2; } ;;
  *) echo "unknown LIBRELANE $LIBRELANE"; exit 2 ;;
esac
mkdir --parents "$SCRATCH"
cp "$BLOCK"/librelane.json "$BLOCK"/*.v "$SCRATCH"/
cd "$SCRATCH"
if [ "$PDK" = ihp-sg13cmos5l ] && [ "$LIBRELANE" = 3.0.14 ]; then
  # The PDK's Magic techfile requires Magic 8.3.657; LibreLane 3.0.14 ships 8.3.623, and its
  # Magic.StreamOut sat at 100% CPU with an empty log for 13 minutes (4 s on sg13g2).  The GDS
  # comes from KLayout (PRIMARY_GDSII_STREAMOUT_TOOL), so the Magic GDS is switched off (the design LEF from Magic is still
  # needed by Odb.CheckDesignAntennaProperties).
  python3 -c 'import json,sys; c=json.load(open(sys.argv[1])); c.update(RUN_MAGIC_STREAMOUT=False); json.dump(c,open(sys.argv[1],"w"),indent=2)' librelane.json
fi
start=$(date +%s)
nice ionice "${ENGINE[@]}" --rm \
  --volume "$PDK_ROOT:$PDK_ROOT:ro" \
  --volume "$SCRATCH:$SCRATCH" --workdir "$SCRATCH" \
  --env PDK_ROOT="$PDK_ROOT" --env PDK="$PDK" --env HOME="$SCRATCH" \
  "$IMAGE" \
  librelane --manual-pdk --pdk-root "$PDK_ROOT" --pdk "$PDK" --run-tag "$TAG" librelane.json \
  > "librelane_$TAG.log" 2>&1 || status=$?
echo "librelane $LIBRELANE ($PDK) exit ${status:-0} after $(( $(date +%s) - start )) s, $(date)" | tee --append "librelane_$TAG.log"
