#!/bin/sh
# Four-phase variant of the ULX3S build (EMU_MULTIPHASE): sequencer pins 0 and 1 through
# prototypes/multiphase's stage, clocked from four PLL phases of 60 MHz.
#   GEN=<dir with deadline_sequencer.v and multiphase_stage.v> ./build_multiphase.sh
# GEN defaults to rtl/gen, which has the right files once this branch is merged with master (the
# sub-slot sequencer and ../multiphase). Outputs in /var/tmp/fpga-ulx3s/build-mp, reports in
# reports/multiphase/.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
gen=${GEN:-$here/rtl/gen}
out=${OUT:-/var/tmp/fpga-ulx3s/build-mp}
rep="$here/reports/multiphase"
mkdir -p "$out" "$rep"
rtl="$here/rtl"
srcs="$rtl/ulx3s_top.v $rtl/emu_core.v $rtl/pll_60_48.v $rtl/pll_4phase_example.v $gen/deadline_sequencer.v $gen/multiphase_stage.v $rtl/gen/pin_streamer.v $rtl/gen/pin_sampler.v $rtl/gen/usb_fs_device.v"
nice ionice yosys -q -l "$rep/yosys.log" -p "read_verilog -DEMU_MULTIPHASE $srcs; synth_ecp5 -top ulx3s_top -json $out/ulx3s_mp.json; tee -o $rep/yosys-stat.txt stat"
nice ionice nextpnr-ecp5 --85k --package CABGA381 --speed 6 --seed "${SEED:-1}" \
  --json "$out/ulx3s_mp.json" --lpf "$here/constraints/ulx3s.lpf" --textcfg "$out/ulx3s_mp.config" \
  --report "$rep/nextpnr-report.json" --log "$rep/nextpnr.log"
nice ecppack --compress "$out/ulx3s_mp.config" "$out/ulx3s_mp.bit"
sha256sum "$out/ulx3s_mp.bit" > "$rep/bitstream.sha256"
cat "$rep/bitstream.sha256"
