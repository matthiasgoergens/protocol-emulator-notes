#!/usr/bin/env bash
# Synthesise pe16x.v with the same flow as ../../pe-synth/synth.sh (YOSYS_HOST=1 variant):
# oss-cad-suite Yosys 0.69+77, synth -flatten, dfflibmap, area-mode abc, IHP SG13G2 typical liberty.
# The baseline, ring_cell16 with the same Yosys, is ../../pe-synth/reports/ring_cell16-y069.stat.txt.
#   ./synth.sh [TAG DEFINES...]   e.g. ./synth.sh nolut NO_LUT
set -o errexit -o nounset -o pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
LIB=/home/matthias/.ciel/ihp-sg13g2/ihp-sg13g2/libs.ref/sg13g2_stdcell/lib/sg13g2_stdcell_typ_1p20V_25C.lib
TAG=${1:-full}; shift || true
DEFS=""; for d in "$@"; do DEFS="$DEFS -D$d"; done
cd "$HERE"; mkdir --parents reports
nice ionice /home/matthias/prog/janestreet/fabulous-notes/oss-cad-suite/bin/yosys -p "read_verilog -sv $DEFS pe16x.v; \
hierarchy -check -top pe16x; synth -top pe16x -flatten; dfflibmap -liberty $LIB; abc -liberty $LIB; opt_clean; \
tee -o reports/pe16x-$TAG-y069.stat.txt stat -liberty $LIB" > reports/pe16x-$TAG.log 2>&1
printf "%-10s " "$TAG"; grep "Chip area" reports/pe16x-$TAG-y069.stat.txt
