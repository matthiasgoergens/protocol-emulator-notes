#!/usr/bin/env bash
# Synthesise the Tiny Tapeout chip (chip_tt, from ../bin/emit.exe) with the Yosys of the pinned
# LibreLane 3.1.0.dev3 image (tools/librelane-tt), to the sg13cmos5l typical liberty of the PDK
# that tt/scripts/harden.sh uses; area-mode abc, flattened; the SRAM macros as black boxes.
#   synth/synth.sh TAG MEMORIES SIZES PROG_WORDS    e.g. synth/synth.sh pe4 macros 1,1,1,1 512
# -> synth/reports/TAG.stat.txt, synth/logs/TAG.log; the Verilog is build output in /var/tmp.
set -o errexit -o nounset -o pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
TAG=${1:?tag} MEM=${2:-macros} SIZES=${3:-1,1,1,1} WORDS=${4:-512}
PDK_ROOT=${PDK_ROOT:-/var/tmp/roundtrip-cmos5l/pdk}
LIB=$PDK_ROOT/ihp-sg13cmos5l/libs.ref/sg13cmos5l_stdcell/lib/sg13cmos5l_stdcell_typ_1p20V_25C.lib
SRAMV=$PDK_ROOT/ihp-sg13cmos5l/libs.ref/sg13cmos5l_sram/verilog
WORK=/var/tmp/chip-top-synth/$TAG
mkdir --parents "$HERE/logs" "$HERE/reports" "$WORK"
(cd "$HERE/.." && nice ionice opam exec --switch=5.3.0 -- dune build --root . ./bin/emit.exe 2>&1)
"$HERE/../_build/default/bin/emit.exe" "$WORK/chip_tt.v" "$MEM" "$SIZES" "$WORDS"
S="read_verilog -lib $SRAMV/RM_IHPSG13_1P_512x16_c2_bm_bist.v $SRAMV/RM_IHPSG13_1P_1024x8_c2_bm_bist.v; \
read_verilog -sv $WORK/chip_tt.v; hierarchy -check -top chip_tt; synth -top chip_tt -flatten; \
dfflibmap -liberty $LIB; abc -liberty $LIB; opt_clean; tee -o $HERE/reports/$TAG.stat.txt stat -liberty $LIB"
until awk '{exit !($1 < 16)}' /proc/loadavg; do sleep 30; done
nice ionice podman run --rm --userns=keep-id --volume "$PDK_ROOT:$PDK_ROOT:ro" --volume "$WORK:$WORK" \
  --volume "$HERE:$HERE" --workdir "$WORK" localhost/librelane-tt:3.1.0.dev3 yosys -p "$S" > "$HERE/logs/$TAG.log" 2>&1
echo "$TAG ($MEM, segments $SIZES, store $WORDS words): $(grep 'Chip area' "$HERE/reports/$TAG.stat.txt")"
