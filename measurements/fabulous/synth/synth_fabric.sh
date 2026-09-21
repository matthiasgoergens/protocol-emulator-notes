#!/usr/bin/env bash
# Hierarchical sg13g2 synthesis of a whole FABulous project (top: eFPGA_top).
# Usage: synth/synth_fabric.sh <project dir> <log name>
set -euo pipefail
PROJ=$1; NAME=$2
YOSYS=${YOSYS:-yosys}
LIB=${LIB:?set LIB to the sg13g2 liberty file}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
FILES="$ROOT/synth/models_pack_onelatch.v"
TILES=${TILES:-LUT4AB W_IO N_term_single S_term_single}
for f in "$PROJ"/Fabric/*.v; do case $f in *models_pack.v|*BlockRAM_1KB.v) ;; *) FILES="$FILES $f";; esac; done
for t in $TILES; do for f in "$PROJ"/Tile/$t/*.v; do FILES="$FILES $f"; done; done
nice ionice "$YOSYS" -q -l "$ROOT/logs/$NAME.log" -p "
  read_verilog -sv $FILES
  hierarchy -check -top eFPGA_top
  synth -top eFPGA_top ${SYNTH_EXTRA:-}
  techmap -map $ROOT/synth/sg13g2_latchmap.v
  dfflibmap -liberty $LIB
  abc -liberty $LIB
  opt_clean
  stat -liberty $LIB
" > "$ROOT/logs/$NAME.stdout" 2>&1 || { echo "yosys failed, see logs/$NAME.stdout"; exit 1; }
python3 - "$ROOT/logs/$NAME.log" <<'PY'
import sys, re
t = open(sys.argv[1]).read()
blk = t[t.rfind('Printing statistics'):]
i = blk.find('=== design hierarchy ===')
h = blk[i:]
j = h.find('submodules')
print(h[j-1200:j+1500])
print(re.search(r'Chip area for top module.*', h).group(0))
PY
