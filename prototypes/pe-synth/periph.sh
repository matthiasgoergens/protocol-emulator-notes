#!/usr/bin/env bash
# Synthesise the gain-cell bank periphery (rtl/gc_periph.v) for the bank shapes the systolic
# study uses, with the LibreLane 3.0.14 container's Yosys 0.62 (as synth.sh).
#   ./periph.sh -> logs/gc_periph_<R>x<C>.log, reports/gc_periph_<R>x<C>.stat.txt
set -o errexit -o nounset -o pipefail
HERE=$(cd "$(dirname "$0")" && pwd); cd "$HERE"
LIB=/home/matthias/.ciel/ihp-sg13g2/ihp-sg13g2/libs.ref/sg13g2_stdcell/lib/sg13g2_stdcell_typ_1p20V_25C.lib
export DOCKER_CONFIG=/var/tmp/claude-notes/dockercfg
# rows cols address-bits: the task's 32x64; the study's 128x32 and 32x16 banks with Berger
# columns (38 and 21 columns); an 8-word bank of 16+5 columns (the per-PE idea in the README)
for shape in "32 64 5" "128 38 7" "32 21 5" "8 21 3"; do
  set -- $shape; R=$1; C=$2; A=$3; N=gc_periph_${R}x${C}
  S="read_liberty -lib $LIB; read_verilog -sv rtl/gc_periph.v; chparam -set ROWS $R -set COLS $C -set AW $A gc_periph; \
hierarchy -check -top gc_periph; synth -top gc_periph -flatten; dfflibmap -liberty $LIB; abc -liberty $LIB; opt_clean; \
tee -o reports/$N.stat.txt stat -liberty $LIB"
  nice ionice docker run --rm --user "$(id -u):$(id -g)" \
    --volume /home/matthias/.ciel:/home/matthias/.ciel:ro --volume "$HERE:$HERE" --workdir "$HERE" \
    ghcr.io/librelane/librelane:3.0.14 yosys -p "$S" > logs/$N.log 2>&1
  echo "$N $(grep 'Chip area' reports/$N.stat.txt)"
done
