#!/usr/bin/env bash
set -o nounset
M=/var/tmp/roundtrip-cmos5l/pdk/ihp-sg13cmos5l/libs.ref/sg13cmos5l_stdcell/verilog/sg13cmos5l_stdcell.v
G8=/var/tmp/chip-top-harden/pe8-apart/runs/wokwi/final/gds/tt_um_chip_top.gds
G4=/var/tmp/chip-top-harden/pe4-apart/runs/wokwi/final/gds/tt_um_chip_top.gds
CUR=/home/matthias/prog/janestreet/emulator-wt-roundtrip-macros/prototypes/chip-top/_build/default/bin/gate_lockstep.exe
OLD=/var/tmp/roundtrip-macros/src-233c71e/prototypes/chip-top/_build/default/bin/gate_lockstep.exe
R=/var/tmp/roundtrip-macros/runs
wait_load() { until [ $(awk '{print int($1)}' /proc/loadavg) -lt 15 ]; do sleep 10; done; }
wait_load; (uptime; echo "reference: this branch's sources (reproduce the hardened 8-PE chip_tt.v)"; nice ionice $CUR $G8 $M 2,2,2,2 8 25000 1 two-edge; echo exit $?) > $R/pe8-two-edge.log 2>&1
wait_load; (uptime; nice ionice $CUR $G8 $M 2,2,2,2 4 10000 2 single-edge; echo exit $?) > $R/pe8-single-edge.log 2>&1
wait_load; (uptime; nice ionice $OLD $G4 $M 1,1,1,1 4 10000 2 single-edge; echo exit $?) > $R/pe4-single-edge.log 2>&1
wait_load; (uptime; echo "control: the 4-PE GDS (hardened from 233c71e) against this branch's sources"; nice ionice $CUR $G4 $M 1,1,1,1 4 10000 3 two-edge; echo exit $?) > $R/pe4-vs-current-sources.log 2>&1
echo queue2 done
