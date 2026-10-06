#!/usr/bin/env bash
# The edge-phase test (bin/edge_phase.ml) in Icarus Verilog, on the RTL or on a hardened gate netlist:
#
#   sim/edge_iverilog.sh rtl   SIZES OUTDIR [CHIP_TT.v]   the Verilog Hardcaml emits (emitted here
#                                                         unless given)
#   sim/edge_iverilog.sh gates SIZES OUTDIR NETLIST.v     e.g. tt_submission/tt_um_chip_top.v
#
# edge_phase.exe writes the stimulus while running the Hardcaml reference, sim/edge_tb.v replays it
# with the inputs changing at T/4 and 3T/4, and edge_phase.exe replay checks the trace: the same
# absolute checks as on the other simulators, and every half clock against the reference.
# Needs PDK_ROOT (sg13cmos5l: the cell models and the SRAM models).
set -o errexit -o nounset -o pipefail
mode=$1 sizes=$2 out=$3
here=$(cd "$(dirname "$0")/.." && pwd)
exe=$here/_build/default/bin
pdk=${PDK_ROOT:?PDK_ROOT must point at the PDK}/ihp-sg13cmos5l/libs.ref
sram=$pdk/sg13cmos5l_sram/verilog
mkdir --parents "$out"
"$exe/edge_phase.exe" rtl "$sizes" "$out/stim.txt" > "$out/reference.log"
macros=("$sram/RM_IHPSG13_1P_512x16_c2_bm_bist.v" "$sram/RM_IHPSG13_1P_1024x8_c2_bm_bist.v"
        "$sram/RM_IHPSG13_1P_core_behavioral_bm_bist.v")
case $mode in
  rtl)
    chip=${4:-$out/chip_tt.v}
    [ -n "${4:-}" ] || "$exe/emit.exe" "$chip" macros "$sizes" 512
    design=("$here/../../tt/src/chip_project.v" "$chip")
    ;;
  gates)
    design=("$pdk/sg13cmos5l_stdcell/verilog/sg13cmos5l_udp.v" "$pdk/sg13cmos5l_stdcell/verilog/sg13cmos5l_stdcell.v" "$4")
    ;;
  *) echo "mode: rtl or gates" >&2; exit 2 ;;
esac
iverilog -g2012 -DFUNCTIONAL -DSTIM="\"$out/stim.txt\"" -DTRACE="\"$out/trace.txt\"" -s edge_tb \
  -o "$out/edge_tb.vvp" "$here/sim/edge_tb.v" "${design[@]}" "${macros[@]}" 2> "$out/iverilog.log"
start=$(date +%s)
vvp -n "$out/edge_tb.vvp" > "$out/vvp.log"
echo "vvp: $(( $(date +%s) - start )) s" >> "$out/vvp.log"
"$exe/edge_phase.exe" replay "$sizes" "$out/stim.txt" "$out/trace.txt" | tee "$out/replay.log"
