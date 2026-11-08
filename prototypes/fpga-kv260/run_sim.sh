#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Everything about the KV260 test bench that can be checked without the board:
#   1. the SRAM stand-ins against IHP's behavioural model (random reads and writes);
#   2. the UART, SPI and I2C demo's frames, exported from the host model;
#   3. the bench (AXI port, player, chip, recorder) simulated with those frames, as the board's
#      processor would drive it, and the recorded run judged by host/check.py;
#   4. synthesis for UltraScale+ with Yosys: block RAMs inferred, no latches.
#
#   ./run_sim.sh [WORK_DIR]       default /var/tmp/fpga-kv260
# Needs the OSS CAD Suite tools on PATH (iverilog, vvp, yosys), opam with the chip-top switch,
# and PDK_ROOT pointing at an IHP-Open-PDK checkout with ihp-sg13cmos5l (for step 1 only).
set -o errexit -o nounset -o pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
W=${1:-/var/tmp/fpga-kv260}
TT=$HERE/../../tt/src
CHIP=$HERE/../chip-top
mkdir --parents "$W/ops"

"$HERE/../../tt/scripts/regen_chip.sh"

if [ -n "${PDK_ROOT:-}" ]; then
  IHP=$PDK_ROOT/ihp-sg13cmos5l/libs.ref/sg13cmos5l_sram/verilog/RM_IHPSG13_1P_core_behavioral_bm_bist.v
  iverilog -g2012 -o "$W/eq.vvp" "$HERE/sim/tb_sram_equiv.v" "$HERE/rtl/sram_fpga.v" "$IHP"
  nice vvp -n "$W/eq.vvp" +seed=7 | tee "$W/sram-equiv.log"
else
  echo "PDK_ROOT unset: skipping the SRAM equivalence check"
fi

(cd "$CHIP" && nice ionice opam exec --switch="${OPAM_SWITCH-5.3.0}" -- dune build --root . ./bin/fpga_ops.exe)
"$CHIP/_build/default/bin/fpga_ops.exe" "$W/ops"

iverilog -g2012 -o "$W/tb.vvp" "$HERE/sim/tb_bench.v" "$HERE/rtl/fpga_axil.v" "$HERE/rtl/fpga_bench.v" \
  "$HERE/rtl/sram_fpga.v" "$TT/chip_project.v" "$TT/chip_tt.v"
nice vvp -n "$W/tb.vvp" +frames="$W/ops/ds.ops" +out="$W/sim-ds" | tee "$W/sim-ds.log"
python3 -I "$HERE/host/check.py" "$W/ops/ds.meta" "$W/sim-ds" | tee "$W/check-sim-ds.txt"

cat > "$W/synth.ys" <<EOF
read_verilog -DSYNTHESIS $HERE/rtl/kv260_core.v $HERE/rtl/fpga_axil.v $HERE/rtl/fpga_bench.v $HERE/rtl/sram_fpga.v $TT/chip_project.v $TT/chip_tt.v
synth_xilinx -family xcup -top kv260_core -flatten
check -assert
stat
EOF
nice ionice yosys -q -l "$W/synth.log" "$W/synth.ys" 2> "$W/synth.stderr"
echo "synthesis (Yosys, UltraScale+), cells:"
grep --extended-regexp '^ +[0-9]+ +(RAMB|URAM|LD|FD)' "$W/synth.log" | awk '{print $2, $1}' | sort --unique
if grep --quiet --extended-regexp '^ +[0-9]+ +LD' "$W/synth.log"; then echo "latches inferred" >&2; exit 1; fi
echo "run_sim: all checks passed; files in $W"
