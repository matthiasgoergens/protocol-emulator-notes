#!/usr/bin/env bash
# Synthesise one area probe to the IHP SG13G2 typical-corner (1.2 V, 25 C) liberty with the Yosys
# inside the LibreLane 3.0.14 container (Yosys 0.62), area-mode abc, flattened: the same flow as
# ../pe-synth/synth.sh, so the numbers compare with pe16 (6,586 um2 there).
#   ./synth.sh TAG FILE TOP "DEFINES" "CHPARAM"
#     DEFINES: e.g. "-DNO_POP -DNO_WIN"; CHPARAM: e.g. "-set W 32 -set N 8"
#   -> logs/TAG.log, reports/TAG.stat.txt
set -o errexit -o nounset -o pipefail
TAG=$1; FILE=$2; TOP=$3; DEFS=${4:-}; CHP=${5:-}
HERE=$(cd "$(dirname "$0")" && pwd)
LIB=/home/matthias/.ciel/ihp-sg13g2/ihp-sg13g2/libs.ref/sg13g2_stdcell/lib/sg13g2_stdcell_typ_1p20V_25C.lib
mkdir --parents "$HERE/logs" "$HERE/reports"
CHCMD=""
if [ -n "$CHP" ]; then CHCMD="chparam $CHP $TOP;"; fi
SCRIPT="read_verilog -sv $DEFS rtl/$FILE; $CHCMD hierarchy -check -top $TOP; synth -top $TOP -flatten; \
dfflibmap -liberty $LIB; abc -liberty $LIB; opt_clean; \
tee -o reports/$TAG.stat.txt stat -liberty $LIB"
cd "$HERE"
export DOCKER_CONFIG=/var/tmp/claude-notes/dockercfg
nice ionice docker run --rm --user "$(id -u):$(id -g)" \
  --volume /home/matthias/.ciel:/home/matthias/.ciel:ro --volume "$HERE:$HERE" \
  --workdir "$HERE" ghcr.io/librelane/librelane:3.0.14 yosys -p "$SCRIPT" > "logs/$TAG.log" 2>&1
printf '%-28s ' "$TAG"; grep "Chip area" "reports/$TAG.stat.txt"
