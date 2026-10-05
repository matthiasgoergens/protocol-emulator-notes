#!/bin/sh
# Synthesis, place and route, timing and bitstream for hdmi_top on the ULX3S 85F.
#   ./build.sh          250 MHz single-edge serialiser   -> $OUT/hdmi_sdr.bit, reports/sdr/
#   ./build.sh ddr      125 MHz serialiser into ODDRX1F  -> $OUT/hdmi_ddr.bit, reports/ddr/
#   ./build.sh ddr demo the retro console's game instead of the pattern (-DHDMI_DEMO): game fields
#                       DEMO_FIRST (24) .. +7 in the packet ROM -> reports/ddr-demo/
# Tools from oss-cad-suite (yosys, nextpnr-ecp5, ecppack).  Regenerate rtl/gen first with
#   opam exec --switch=5.3.0 -- dune exec ./bin/emit.exe rtl/gen
set -eu
here=$(cd "$(dirname "$0")" && pwd)
variant=${1:-sdr}
demo=${2:-}
tag=$variant${demo:+-demo}
out=${OUT:-/var/tmp/hdmi-ulx3s/build}/$tag
seed=${SEED:-1}
rep="$here/reports/$tag"
mkdir --parents "$out" "$rep"
case $variant in
  sdr) defs=""; serial=hdmi_serial_sdr; pll=pll_sdr ;;
  ddr) defs="-DHDMI_DDR"; serial=hdmi_serial_ddr; pll=pll_ddr ;;
  *) echo "unknown variant $variant" >&2; exit 2 ;;
esac
rtl="$here/rtl"
srcs="$rtl/hdmi_top.v $rtl/hdmi_out.v $rtl/$pll.v $rtl/gen/hdmi_pixel.v $rtl/gen/$serial.v"
if [ -n "$demo" ]; then
  # the ROM is read by $readmemh("packets.hex") relative to yosys's working directory, $out
  (cd "$here" && opam exec --switch=5.3.0 -- dune exec ./demo/gen_packets.exe "${DEMO_FIRST:-24}" 8 "$out/packets.hex")
  defs="$defs -DHDMI_DEMO"
  srcs="$rtl/hdmi_top.v $rtl/hdmi_out.v $rtl/$pll.v $rtl/gen/hdmi_pixel_demo.v $rtl/gen/$serial.v $rtl/packet_rom.v $rtl/frame_buffer.v"
fi
cd "$out"
{ yosys -V; nextpnr-ecp5 --version 2>&1; } > "$rep/tool-versions.txt"
{ git -C "$here" rev-parse HEAD; git -C "$here" status --porcelain -- .; } > "$rep/commit.txt"
nice ionice yosys -q -l "$rep/yosys.log" -p "read_verilog $defs $srcs; synth_ecp5 -top hdmi_top -json $out/hdmi.json; tee -o $rep/yosys-stat.txt stat"
nice ionice nextpnr-ecp5 --85k --package CABGA381 --speed 6 --seed "$seed" \
  --json "$out/hdmi.json" --lpf "$here/constraints/hdmi.lpf" --textcfg "$out/hdmi.config" \
  --report "$rep/nextpnr-report.json" --log "$rep/nextpnr.log"
nice ecppack --compress "$out/hdmi.config" "$out/hdmi_$tag.bit"
sha256sum "$out/hdmi_$tag.bit" > "$rep/bitstream.sha256"
cat "$rep/bitstream.sha256"
