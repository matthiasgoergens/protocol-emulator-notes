#!/usr/bin/env bash
# Route one benchmark design on one FABulous project and summarise nextpnr's result.
# Usage: bench/run_bench.sh <project dir> <design name>   (bench/<design>.v must exist)
# Synthesis follows the Yosys 0.60 synth_fabulous script (plain abc, LUTFF cell mapping) because the
# Yosys 0.69 synth_fabulous emits generic cells that FABulous 2.2's nextpnr packer does not accept.
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
PROJ=$(cd "$1" && pwd); D=$2
export PATH=${FABULOUS_BIN:?set FABULOUS_BIN to the venv bin with FABulous}:${OSS_CAD_SUITE_BIN:?set OSS_CAD_SUITE_BIN to a suite with Yosys 0.69 and nextpnr-generic}:$PATH
FAB=$ROOT/yosys-fabulous-0.60
cp "$ROOT/bench/$D.v" "$PROJ/user_design/$D.v"
mkdir --parents "$ROOT/bench/results"
LOG="$ROOT/bench/results/$(basename "$PROJ")_$D.log"
nice ionice "$ROOT/.venv/bin/FABulous" -p "$PROJ" run "gen_user_design_wrapper user_design/$D.v user_design/top_wrapper.v" > "$LOG" 2>&1
sed --in-place --regexp-extended "s/^($D user_design_i \().*/\1.clk(clk), .io_in(IO_1_bidirectional_frame_config_pass_O), .io_out(IO_1_bidirectional_frame_config_pass_I), .io_oeb(IO_1_bidirectional_frame_config_pass_T));/" "$PROJ/user_design/top_wrapper.v"
grep --quiet "io_in(IO_1" "$PROJ/user_design/top_wrapper.v" || { echo "wrapper patch failed for $D"; exit 1; }
JSON="$PROJ/user_design/$D.json"
nice ionice yosys -q -l "$ROOT/bench/results/$(basename "$PROJ")_${D}_yosys.log" -p "
  read_verilog -DCOMPLEX_DFF -lib $FAB/prims.v
  read_verilog $PROJ/user_design/top_wrapper.v $PROJ/user_design/$D.v
  hierarchy -check -top top_wrapper
  proc; flatten; tribuf -logic; deminout
  opt -nodffe -nosdff; fsm; opt; wreduce; peepopt; opt_clean
  alumacc; share; opt; memory -nomap; opt_clean
  opt -fast -mux_undef -undriven -fine; memory_map; opt -undriven -fine
  techmap; opt -fast
  dfflegalize -cell \$_DFF_P_ 0 -cell \$_DFFE_PP_ 0 -cell \$_SDFF_PP?_ 0 -cell \$_SDFFCE_PP?P_ 0
  techmap -map $FAB/ff_map.v
  abc -lut 4; opt -fast
  techmap -D LUT_K=4 -map $FAB/cells_map.v; clean
  read_verilog -DCOMPLEX_DFF -lib $FAB/prims.v
  hierarchy -check; stat
  write_json $JSON" > /dev/null 2>&1 || { echo "$(basename "$PROJ") $D: yosys failed"; exit 1; }
NPNR="$PROJ/user_design/${D}_npnr_log.txt"
FAB_ROOT=$PROJ nice ionice nextpnr-generic --uarch fabulous --json "$JSON" -o fasm="$PROJ/user_design/$D.fasm" --log "$NPNR" > /dev/null 2>&1
rc=$?
python3 - "$(basename "$PROJ")" "$D" "$rc" "$NPNR" <<'PY'
import re, sys, os
proj, d, rc, npnr = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4]
t = open(npnr).read() if os.path.exists(npnr) else ''
util = dict(re.findall(r'Info:\s+(\w+):\s+(\d+/\s*\d+)', t))
routed = 'Routing complete' in t
err = re.findall(r'ERROR: (.*)', t)
wl = re.findall(r'wirelen = (\d+)', t)
fmax = re.findall(r'Max frequency for clock[^:]*: ([0-9.]+ MHz)', t)
print(f"{proj:8s} {d:12s} rc={rc} routed={routed} LC={util.get('FABULOUS_LC', '?').replace(' ', '')} IO={util.get('IO_1_bidirectional_frame_config_pass', '?').replace(' ', '')} "
      f"wirelen={wl[-1] if wl else '?'} fmax={fmax[-1] if fmax else '?'} err={err[0][:80] if err else ''}")
PY
