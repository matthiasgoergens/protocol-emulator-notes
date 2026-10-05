#!/usr/bin/env bash
# The step-56 round-trip set (results/COMMANDS.md, sg13cmos5l/) on the LibreLane 3.1.0.dev3 run.
set -o nounset -o pipefail
B=/home/matthias/prog/janestreet/emulator-wt-librelane-tt/prototypes/postlayout-roundtrip/_build/default
R=/var/tmp/librelane-tt/pnr/runs/seq15ns_cmos5l_ll31
STD=/var/tmp/roundtrip-cmos5l/pdk/ihp-sg13cmos5l/libs.ref/sg13cmos5l_stdcell
M=$STD/verilog/sg13cmos5l_stdcell.v
LEF=$STD/lef/sg13cmos5l_stdcell.lef
RTL=/var/tmp/librelane-tt/pnr/deadline_sequencer.v
O=/var/tmp/librelane-tt/rt
wl() { until awk '{exit !($1 < 16)}' /proc/loadavg; do sleep 30; done; }
run() { local out=$1; shift; wl; echo "== $out: $*"; nice ionice "$@" > "$O/$out" 2>&1; echo "exit $?"; tail --lines=3 "$O/$out"; }
for kind in klayout magic; do
  if [ $kind = klayout ]; then G=$R/final/gds/deadline_sequencer.gds; else G=$R/final/mag_gds/deadline_sequencer.magic.gds; fi
  mkdir --parents $O/$kind/controls
  run $kind/check.log $B/roundtrip_check.exe check $G deadline_sequencer $RTL $M $O/$kind/deadline_sequencer.netlist
  run $kind/compare.log $B/compare_def.exe $G deadline_sequencer $R/final/def/deadline_sequencer.def $R/final/nl/deadline_sequencer.nl.v $LEF
  run $kind/controls.log $B/roundtrip_check.exe controls $G deadline_sequencer $RTL $M $O/$kind/controls 10 1
  run $kind/lockstep_full.log $B/seq_lockstep.exe $G $M 300 2000
  [ $kind = klayout ] || continue
  run $kind/lockstep_generic.log $B/seq_lockstep.exe $G $M 300 2000 --generic
  run $kind/lockstep_gds_controls.log $B/seq_lockstep.exe $G $M 20 2000 $O/$kind/controls/*.gds
  run $kind/lockstep_swaps.log $B/seq_lockstep.exe $G $M 20 2000 --swaps 50 1
  run $kind/powerup.log $B/seq_lockstep.exe $G $M 300 2000 --powerup 0 1
  run $kind/powerup_controls.log $B/seq_lockstep.exe $G $M 20 2000 --powerup hold:0 hold:100
done
echo ALL DONE
