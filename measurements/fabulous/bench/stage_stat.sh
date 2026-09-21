#!/usr/bin/env bash
# Run the benchmark synthesis command up to a given synth_fabulous stage and print the cell census.
# Usage: bench/stage_stat.sh <project> <design> <stop-stage>
ROOT=$(cd "$(dirname "$0")/.." && pwd); PROJ=$(cd "$1" && pwd); D=$2; STOP=$3
"${YOSYS:-yosys}" -q -p "synth_fabulous -top top_wrapper -run :$STOP -extra-plib $ROOT/yosys-fabulous-0.60/prims.v -cells-map $ROOT/yosys-fabulous-0.60/cells_map.v -extra-map $ROOT/yosys-fabulous-0.60/ff_map.v -ff \$_DFF_P_ 0 -ff \$_SDFF_PP?_ 0 -ff \$_SDFFCE_PP?P_ 0; tee -q -o /dev/stdout stat" "$PROJ/user_design/top_wrapper.v" "$PROJ/user_design/$D.v" 2>&1 | grep --extended-regexp '^\s+[0-9]+ +[\$A-Za-z_\\]|ERROR' | sed --quiet 1,14p
