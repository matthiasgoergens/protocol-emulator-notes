#!/bin/sh
# The emulator test bench with HDMI output added (EMU_HDMI): ../hdmi-ulx3s/rtl/hdmi_out.v, 125 MHz
# DDR serialiser, test pattern.  ./build_hdmi.sh demo shows the retro console's game instead.
# Outputs in /var/tmp/fpga-ulx3s/build-hdmi[-demo], reports in reports/hdmi[-demo]/.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
hd="$here/../hdmi-ulx3s"
demo=${1:-}
tag=hdmi${demo:+-demo}
out=${OUT:-/var/tmp/fpga-ulx3s/build-$tag}
rep="$here/reports/$tag"
mkdir -p "$out" "$rep"
rtl="$here/rtl"
defs="-DEMU_HDMI -DHDMI_DDR"
pixel="$hd/rtl/gen/hdmi_pixel.v"
if [ -n "$demo" ]; then
  (cd "$hd" && opam exec --switch=5.3.0 -- dune exec ./demo/gen_packets.exe "${DEMO_FIRST:-24}" 8 "$out/packets.hex")
  defs="$defs -DHDMI_DEMO"
  pixel="$hd/rtl/gen/hdmi_pixel_demo.v $hd/rtl/packet_rom.v $hd/rtl/frame_buffer.v"
fi
srcs="$rtl/ulx3s_top.v $rtl/emu_core.v $rtl/pll_60_48.v $rtl/gen/deadline_sequencer.v $rtl/gen/pin_streamer.v $rtl/gen/pin_sampler.v $rtl/gen/usb_fs_device.v $hd/rtl/hdmi_out.v $hd/rtl/pll_ddr.v $pixel $hd/rtl/gen/hdmi_serial_ddr.v"
cd "$out"
{ git -C "$here" rev-parse HEAD; git -C "$here" status --porcelain -- . ../hdmi-ulx3s; } > "$rep/commit.txt"
nice ionice yosys -q -l "$rep/yosys.log" -p "read_verilog $defs $srcs; synth_ecp5 -top ulx3s_top -json $out/ulx3s_hdmi.json; tee -o $rep/yosys-stat.txt stat"
nice ionice nextpnr-ecp5 --85k --package CABGA381 --speed 6 --seed "${SEED:-1}" \
  --json "$out/ulx3s_hdmi.json" --lpf "$here/constraints/ulx3s.lpf" --lpf "$here/constraints/hdmi_extra.lpf" \
  --textcfg "$out/ulx3s_hdmi.config" --report "$rep/nextpnr-report.json" --log "$rep/nextpnr.log"
nice ecppack --compress "$out/ulx3s_hdmi.config" "$out/ulx3s_$tag.bit"
sha256sum "$out/ulx3s_$tag.bit" > "$rep/bitstream.sha256"
cat "$rep/bitstream.sha256"
