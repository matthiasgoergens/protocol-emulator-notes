#!/bin/sh
# Build the Verilator model of emu_core with its board harness.
#   sim/build.sh [CLKS_PER_BIT] [plain|mp|mp-fault]
#   (default 8: a fast host link; the board uses 60 at 60 MHz)
#   With "mp": the four-phase build (EMU_MULTIPHASE), into obj_dir_mp_cpbN.
#   With "mp-fault": the same with EMU_FAULT_DROP_QUAD planted (negative control), obj_dir_mpfault_cpbN.
# Needs oss-cad-suite's verilator on PATH and a host C++ compiler.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
cpb=${1:-8}
variant=${2:-plain}
rtl="$here/../rtl"
defs=""; extra=""; tag=""
case "$variant" in
  plain) ;;
  mp) defs="-DEMU_MULTIPHASE"; extra="$rtl/gen/multiphase_stage.v"; tag="mp_" ;;
  mp-fault) defs="-DEMU_MULTIPHASE -DEMU_FAULT_DROP_QUAD"; extra="$rtl/gen/multiphase_stage.v"; tag="mpfault_" ;;
  *) echo "unknown variant $variant" >&2; exit 2 ;;
esac
out="$here/obj_dir_${tag}cpb$cpb"
nice ionice verilator --cc --exe --build -O2 --trace -Wno-fatal -Wno-lint -Wno-style $defs \
  ${defs:+-CFLAGS "$defs"} \
  --top-module emu_core -GCLKS_PER_BIT="$cpb" --Mdir "$out" \
  "$rtl/emu_core.v" "$rtl/gen/deadline_sequencer.v" "$rtl/gen/pin_streamer.v" "$rtl/gen/pin_sampler.v" $extra \
  "$here/sim_main.cpp" -o Vemu_sim
echo "built $out/Vemu_sim"
