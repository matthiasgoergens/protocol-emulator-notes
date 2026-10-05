#!/usr/bin/env bash
# Post-layout round trip for one block, after place and route:
#   1. the cell-model interpreter agrees with the liberty functions (every cell, exhaustively);
#   2. extract the gate-level netlist from the GDS and check its structure against the RTL ports
#      (exactly one driver per net, no floating input, every clock pin on the clock tree);
#   3. plant cuts and shorts in copies of the GDS and require every effective one to be caught;
#   4. if the block has a lockstep executable, run the extracted netlist against the RTL.
# Usage: roundtrip.sh GDS TOP RTL.v OUTDIR [LOCKSTEP_EXE RUNS CYCLES]
set -o errexit -o nounset -o pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
GDS=$1 TOP=$2 RTL=$3 OUT=$4
STD=${PDK_ROOT:-$HOME/.ciel/ihp-sg13g2}/ihp-sg13g2/libs.ref/sg13g2_stdcell
MODELS=$STD/verilog/sg13g2_stdcell.v
LIBERTY=$STD/lib/sg13g2_stdcell_typ_1p20V_25C.lib
BIN=$HERE/_build/default
mkdir --parents "$OUT/controls"
(cd "$HERE" && opam exec --switch=5.3.0 -- dune build)
"$BIN/test_cells.exe" "$MODELS" "$LIBERTY" > "$OUT/test_cells.log"
tail --lines=1 "$OUT/test_cells.log"
nice ionice "$BIN/roundtrip_check.exe" check "$GDS" "$TOP" "$RTL" "$MODELS" "$OUT/$TOP.netlist" > "$OUT/check.log"
grep --extended-regexp '^(extract|STRUCTURE)' "$OUT/check.log"
nice ionice "$BIN/roundtrip_check.exe" controls "$GDS" "$TOP" "$RTL" "$MODELS" "$OUT/controls" 5 1 > "$OUT/controls.log"
tail --lines=1 "$OUT/controls.log"
grep --quiet '^controls: \([0-9]*\) of \1 ' "$OUT/controls.log" || { echo "a planted fault was missed"; exit 1; }
if [ $# -ge 7 ]; then
  nice ionice "$5" "$GDS" "$MODELS" "$6" "$7" > "$OUT/lockstep.log"
  tail --lines=1 "$OUT/lockstep.log"
fi
