#!/usr/bin/env bash
# Event-driven simulation of the real four-clock stage with iverilog: nominal, phase skews, and the
# planted wrong-phase lane (must fail). Output: ../results/iverilog.txt
set -o errexit -o nounset -o pipefail
here=$(cd "$(dirname "$0")" && pwd)
out=/var/tmp/multiphase/iverilog; mkdir --parents "$out"
run() { # name verilog params...
  local name=$1 v=$2; shift 2
  iverilog -g2005 -o "$out/$name.vvp" "$@" "$here/tb_stage.v" "$here/../$v"
  echo "== $name"; nice vvp -n "$out/$name.vvp" | grep --extended-regexp 'PERIOD|mismatch'
}
{
  run nominal-16ns multiphase_stage.v
  run nominal-15ns multiphase_stage.v -Ptb.PERIOD=15000
  run skew-plus-1ns multiphase_stage.v -Ptb.SKEW1=1000 -Ptb.SKEW2=1000 -Ptb.SKEW3=1000
  run skew-mixed-1.5ns multiphase_stage.v -Ptb.SKEW1=1500 -Ptb.SKEW2=-1500 -Ptb.SKEW3=1500
  run control-lane-on-wrong-phase multiphase_stage_fault_lane.v
} | tee "$here/../results/iverilog.txt"
