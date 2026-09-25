#!/bin/sh
# Synthesis, place and route, timing and bitstream for the ULX3S 85F, with the open toolchain.
#   ./build.sh            -> /var/tmp/fpga-ulx3s/build/ulx3s.bit, reports in reports/
# Tools from oss-cad-suite on PATH (yosys, nextpnr-ecp5, ecppack). Runs niced, one job.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
out=${OUT:-/var/tmp/fpga-ulx3s/build}
seed=${SEED:-1}
mkdir -p "$out" "$here/reports"
rtl="$here/rtl"
srcs="$rtl/ulx3s_top.v $rtl/emu_core.v $rtl/pll_60_48.v $rtl/gen/deadline_sequencer.v $rtl/gen/pin_streamer.v $rtl/gen/pin_sampler.v $rtl/gen/usb_fs_device.v"
{ yosys -V; nextpnr-ecp5 --version 2>&1; } > "$here/reports/tool-versions.txt"
nice ionice yosys -q -l "$here/reports/yosys.log" -p "read_verilog $srcs; synth_ecp5 -top ulx3s_top -json $out/ulx3s.json; tee -o $here/reports/yosys-stat.txt stat"
nice ionice nextpnr-ecp5 --85k --package CABGA381 --speed 6 --seed "$seed" \
  --json "$out/ulx3s.json" --lpf "$here/constraints/ulx3s.lpf" --textcfg "$out/ulx3s.config" \
  --report "$here/reports/nextpnr-report.json" --log "$here/reports/nextpnr.log"
nice ecppack --compress "$out/ulx3s.config" "$out/ulx3s.bit"
sha256sum "$out/ulx3s.bit" > "$here/reports/bitstream.sha256"
cat "$here/reports/bitstream.sha256"
