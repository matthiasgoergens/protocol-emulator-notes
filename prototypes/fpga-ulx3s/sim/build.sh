#!/bin/sh
# Build the Verilator model of emu_core with its board harness.
#   sim/build.sh [CLKS_PER_BIT]   (default 8: a fast host link; the board uses 60 at 60 MHz)
# Needs oss-cad-suite's verilator on PATH and a host C++ compiler.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
cpb=${1:-8}
rtl="$here/../rtl"
out="$here/obj_dir_cpb$cpb"
nice ionice verilator --cc --exe --build -O2 --trace -Wno-fatal -Wno-lint -Wno-style \
  --top-module emu_core -GCLKS_PER_BIT="$cpb" --Mdir "$out" \
  "$rtl/emu_core.v" "$rtl/gen/deadline_sequencer.v" "$rtl/gen/pin_streamer.v" "$rtl/gen/pin_sampler.v" \
  "$here/sim_main.cpp" -o Vemu_sim
echo "built $out/Vemu_sim"
