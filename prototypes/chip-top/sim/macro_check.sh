#!/usr/bin/env bash
# The SRAM macros' FUNCTIONAL models against the core's behavioural memory (sim/macro_tb.v).
set -o errexit -o nounset -o pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
V=${PDK_ROOT:-/var/tmp/roundtrip-cmos5l/pdk}/ihp-sg13cmos5l/libs.ref/sg13cmos5l_sram/verilog
OUT=$(mktemp --directory --tmpdir=/var/tmp chip-macro-check.XXXXXX)
iverilog -g2012 -DFUNCTIONAL -o "$OUT/tb" "$HERE/macro_tb.v" "$V/RM_IHPSG13_1P_512x16_c2_bm_bist.v" \
  "$V/RM_IHPSG13_1P_1024x8_c2_bm_bist.v" "$V/RM_IHPSG13_1P_core_behavioral_bm_bist.v"
nice vvp -n "$OUT/tb"
echo "control (expect differences): the same reads against a read-first memory"
iverilog -g2012 -DFUNCTIONAL -DCONTROL_READ_FIRST -o "$OUT/tbc" "$HERE/macro_tb.v" "$V/RM_IHPSG13_1P_512x16_c2_bm_bist.v" \
  "$V/RM_IHPSG13_1P_1024x8_c2_bm_bist.v" "$V/RM_IHPSG13_1P_core_behavioral_bm_bist.v"
nice vvp -n "$OUT/tbc" | grep macro
