#!/usr/bin/env bash
# Synthesise one design from rtl/<name>.v to the IHP SG13G2 typical-corner (1.2 V, 25 C) liberty
# with the yosys inside the LibreLane 3.0.14 container (Yosys 0.62), area-mode abc, flattened.
#   ./synth.sh <name> [top]      -> logs/<name>.log, reports/<name>.stat.txt, netlist in /var/tmp
# SYNTH_OPTS adds options to synth (e.g. -booth) and TAG_SUFFIX names the variant.
# Set YOSYS_HOST=1 to use the oss-cad-suite Yosys 0.69+77 (~/prog/janestreet/fabulous-notes) that produced the older logs instead.
set -o errexit -o nounset -o pipefail
NAME=$1; TOP=${2:-$1}
HERE=$(cd "$(dirname "$0")" && pwd)
LIB=/home/matthias/.ciel/ihp-sg13g2/ihp-sg13g2/libs.ref/sg13g2_stdcell/lib/sg13g2_stdcell_typ_1p20V_25C.lib
OUT=/var/tmp/pe-synth/netlists; mkdir --parents "$OUT" "$HERE/logs" "$HERE/reports"
TAG=${YOSYS_HOST:+-y069}${TAG_SUFFIX:-}
SCRIPT="read_verilog -sv rtl/$NAME.v; hierarchy -check -top $TOP; synth -top $TOP -flatten ${SYNTH_OPTS:-}; \
dfflibmap -liberty $LIB; abc -liberty $LIB; opt_clean; \
tee -o reports/$NAME$TAG.stat.txt stat -liberty $LIB; write_verilog -noattr $OUT/$NAME$TAG.v"
cd "$HERE"
if [ -n "${YOSYS_HOST:-}" ]; then
  nice ionice /home/matthias/prog/janestreet/fabulous-notes/oss-cad-suite/bin/yosys -p "$SCRIPT" > "logs/$NAME$TAG.log" 2>&1
else
  export DOCKER_CONFIG=/var/tmp/claude-notes/dockercfg
  nice ionice docker run --rm --user "$(id -u):$(id -g)" \
    --volume /home/matthias/.ciel:/home/matthias/.ciel:ro --volume "$HERE:$HERE" --volume /var/tmp/pe-synth:/var/tmp/pe-synth \
    --workdir "$HERE" ghcr.io/librelane/librelane:3.0.14 yosys -p "$SCRIPT" > "logs/$NAME$TAG.log" 2>&1
fi
grep "Chip area\|sequential elements" "reports/$NAME$TAG.stat.txt"
