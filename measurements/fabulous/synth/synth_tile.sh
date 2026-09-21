#!/usr/bin/env bash
# Hierarchical sg13g2 synthesis of one FABulous tile; per-module area in the log.
# Usage: synth/synth_tile.sh <TILE> <tile dir> <extra .v files...>
set -euo pipefail
TILE=$1; DIR=$2; shift 2
YOSYS=${YOSYS:-yosys}
LIB=${LIB:?set LIB to the sg13g2 liberty file}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
FILES="${MODELS:-$ROOT/demo/Fabric/models_pack.v}"
for f in "$@"; do FILES="$FILES $DIR/$f"; done
nice ionice "$YOSYS" -q -l "${LOG:-$ROOT/logs/$TILE.log}" -p "
  read_verilog -sv $FILES
  hierarchy -check -top $TILE
  synth -top $TILE ${SYNTH_EXTRA:-}
  techmap -map $ROOT/synth/sg13g2_latchmap.v
  dfflibmap -liberty $LIB
  abc -liberty $LIB
  opt_clean
  stat -liberty $LIB
" > /dev/null 2>&1
python3 - "${LOG:-$ROOT/logs/$TILE.log}" <<'PY'
import re, sys
t = open(sys.argv[1]).read()
blk = t[t.rfind('Printing statistics'):]
for m in re.finditer(r'^=== (\S+) ===\n(.*?)(?=^=== |\Z)', blk, re.M | re.S):
    name, body = m.group(1), m.group(2)
    cells = re.search(r'^\s+(\d+)\s+[0-9.E+]*\s*cells\s*$', body, re.M)
    area = re.search(r'Chip area for (?:top )?module .*?:\s*([0-9.]+)', body)
    print(f"{name:32s} cells={cells.group(1) if cells else '?':>7s} area_um2={float(area.group(1)) if area else 0:12.1f}")
PY
