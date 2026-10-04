#!/bin/sh
# Synthesis, place and route, timing and bitstream for hdmi_top on the ULX3S 85F.
#   ./build.sh          250 MHz single-edge serialiser   -> $OUT/hdmi_sdr.bit, reports/sdr/
#   ./build.sh ddr      125 MHz serialiser into ODDRX1F  -> $OUT/hdmi_ddr.bit, reports/ddr/
# Tools from oss-cad-suite (yosys, nextpnr-ecp5, ecppack).  Regenerate rtl/gen first with
#   opam exec --switch=5.3.0 -- dune exec ./bin/emit.exe rtl/gen
set -eu
here=$(cd "$(dirname "$0")" && pwd)
variant=${1:-sdr}
out=${OUT:-/var/tmp/hdmi-ulx3s/build}/$variant
seed=${SEED:-1}
rep="$here/reports/$variant"
mkdir --parents "$out" "$rep"
case $variant in
  sdr) defs=""; serial=hdmi_serial_sdr; pll=pll_sdr ;;
  ddr) defs="-DHDMI_DDR"; serial=hdmi_serial_ddr; pll=pll_ddr ;;
  *) echo "unknown variant $variant" >&2; exit 2 ;;
esac
rtl="$here/rtl"
srcs="$rtl/hdmi_top.v $rtl/$pll.v $rtl/gen/hdmi_pixel.v $rtl/gen/$serial.v"
{ yosys -V; nextpnr-ecp5 --version 2>&1; } > "$rep/tool-versions.txt"
nice ionice yosys -q -l "$rep/yosys.log" -p "read_verilog $defs $srcs; synth_ecp5 -top hdmi_top -json $out/hdmi.json; tee -o $rep/yosys-stat.txt stat"
nice ionice nextpnr-ecp5 --85k --package CABGA381 --speed 6 --seed "$seed" \
  --json "$out/hdmi.json" --lpf "$here/constraints/hdmi.lpf" --textcfg "$out/hdmi.config" \
  --report "$rep/nextpnr-report.json" --log "$rep/nextpnr.log"
nice ecppack --compress "$out/hdmi.config" "$out/hdmi_$variant.bit"
sha256sum "$out/hdmi_$variant.bit" > "$rep/bitstream.sha256"
cat "$rep/bitstream.sha256"
