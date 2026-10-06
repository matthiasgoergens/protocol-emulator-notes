#!/usr/bin/env bash
# OpenSTA, from the pinned LibreLane image, on a finished run: one corner, many paths per endpoint,
# so that paths behind the single worst start point are visible too.
#   synth/sta.sh RUN_DIR CORNER OUT.rpt [extra tcl]
# RUN_DIR is runs/<tag> of a LibreLane run; CORNER e.g. nom_slow_1p08V_125C. Writes OUT.rpt with
# report_checks -group_path_count 3000 -endpoint_path_count 4 -unique_paths_to_endpoint.
set -o errexit -o nounset -o pipefail
RUN=$(cd "${1:?run}" && pwd) CORNER=${2:?corner} OUT=$(realpath "${3:?out}") EXTRA=${4:-}
PDK_ROOT=${PDK_ROOT:-/var/tmp/roundtrip-cmos5l/pdk}
P=$PDK_ROOT/ihp-sg13cmos5l/libs.ref
case $CORNER in
  *slow*) sc=slow_1p08V_125C; mc=slow_1p08V_125C ;;
  *fast*) sc=fast_1p32V_m40C; mc=fast_1p32V_m55C ;;
  *) sc=typ_1p20V_25C; mc=typ_1p20V_25C ;;
esac
TCL=$(mktemp --tmpdir=/var/tmp sta.XXXXXX.tcl)
cat > "$TCL" <<T
read_liberty $P/sg13cmos5l_stdcell/lib/sg13cmos5l_stdcell_$sc.lib
read_liberty $P/sg13cmos5l_sram/lib/RM_IHPSG13_1P_512x16_c2_bm_bist_$mc.lib
read_liberty $P/sg13cmos5l_sram/lib/RM_IHPSG13_1P_1024x8_c2_bm_bist_$mc.lib
read_verilog $RUN/final/nl/tt_um_chip_top.nl.v
link_design tt_um_chip_top
read_spef $RUN/final/spef/nom/tt_um_chip_top.nom.spef
read_sdc $RUN/final/sdc/tt_um_chip_top.sdc
$EXTRA
report_checks -path_delay max -group_path_count 3000 -endpoint_path_count 4 -unique_paths_to_endpoint -fields {fanout cap slew} -digits 3 > $OUT
report_wns > $OUT.wns
T
podman run --rm --userns=keep-id --volume "$PDK_ROOT:$PDK_ROOT:ro" --volume "$RUN:$RUN:ro" \
  --volume /var/tmp:/var/tmp localhost/librelane-tt:3.1.0.dev3 sta -no_splash -exit "$TCL" > "$OUT.log" 2>&1
rm --force "$TCL"
cat "$OUT.wns"
