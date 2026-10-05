#!/usr/bin/env bash
# Place and route a block with LibreLane 3.0.14 in its container, in a scratch directory, keeping the GDS.
# Usage: run_pnr.sh <block dir containing librelane.json and its Verilog> <scratch dir> <run tag> [PDK]
#   PDK is ihp-sg13g2 (the default, from ciel under ~/.ciel/ihp-sg13g2) or ihp-sg13cmos5l, the
#   variant the Tiny Tapeout IHP shuttle uses.  ciel 3.0's ihp-sg13 releases do not include the
#   revision Tiny Tapeout pins, so for sg13cmos5l PDK_ROOT must point at a checkout made with
#   TinyTapeout/tt-gds-action's install_sg13cmos5l.sh (branch ihp-cmos5l; IHP-Open-PDK 2bbec755).
# The block directory is copied, so the checkout is never written to; the PDK is mounted read-only.
set -o errexit -o nounset -o pipefail
BLOCK=$(cd "$1" && pwd)
SCRATCH=$2
TAG=$3
PDK=${4:-ihp-sg13g2}
case $PDK in
  ihp-sg13g2) PDK_ROOT=${PDK_ROOT:-/home/matthias/.ciel/ihp-sg13g2} ;;
  ihp-sg13cmos5l) PDK_ROOT=${PDK_ROOT:?set PDK_ROOT to a tt-gds-action style ihp-sg13cmos5l checkout} ;;
  *) echo "unknown PDK $PDK"; exit 2 ;;
esac
[ -f "$PDK_ROOT/$PDK/libs.tech/librelane/config.tcl" ] || { echo "no $PDK under $PDK_ROOT"; exit 2; }
export DOCKER_CONFIG=/var/tmp/claude-notes/dockercfg
mkdir --parents "$SCRATCH"
cp "$BLOCK"/librelane.json "$BLOCK"/*.v "$SCRATCH"/
cd "$SCRATCH"
if [ "$PDK" = ihp-sg13cmos5l ]; then
  # The PDK's Magic techfile requires Magic 8.3.657; LibreLane 3.0.14 ships 8.3.623, and its
  # Magic.StreamOut sat at 100% CPU with an empty log for 13 minutes (4 s on sg13g2).  The GDS
  # comes from KLayout (PRIMARY_GDSII_STREAMOUT_TOOL), so the Magic GDS is switched off (the design LEF from Magic is still
  # needed by Odb.CheckDesignAntennaProperties).
  python3 -c 'import json,sys; c=json.load(open(sys.argv[1])); c.update(RUN_MAGIC_STREAMOUT=False); json.dump(c,open(sys.argv[1],"w"),indent=2)' librelane.json
fi
start=$(date +%s)
nice ionice docker run --rm --user "$(id -u):$(id -g)" \
  --volume "$PDK_ROOT:$PDK_ROOT:ro" \
  --volume "$SCRATCH:$SCRATCH" --workdir "$SCRATCH" \
  --env PDK_ROOT="$PDK_ROOT" --env PDK="$PDK" --env HOME="$SCRATCH" \
  ghcr.io/librelane/librelane:3.0.14 \
  librelane --manual-pdk --pdk-root "$PDK_ROOT" --pdk "$PDK" --run-tag "$TAG" librelane.json \
  > "librelane_$TAG.log" 2>&1 || status=$?
echo "librelane ($PDK) exit ${status:-0} after $(( $(date +%s) - start )) s, $(date)" | tee --append "librelane_$TAG.log"
