#!/usr/bin/env bash
# Gate lockstep (two edges, 233c71e reference = the 4-PE harden's RTL) on each macro-pin plant.
set -o nounset
cd /var/tmp/roundtrip-macros/src-233c71e/prototypes/chip-top
M=/var/tmp/roundtrip-cmos5l/pdk/ihp-sg13cmos5l/libs.ref/sg13cmos5l_stdcell/verilog/sg13cmos5l_stdcell.v
D=/var/tmp/roundtrip-macros/pe4/macro-controls
for g in cut_dout cut_addr cut_din short_dout short_addr swap_dout swap_din swap_addr; do
  nice ionice ./_build/default/bin/gate_lockstep.exe $D/$g.gds $M 1,1,1,1 3 8000 7 two-edge > $D/$g.lockstep.log 2>&1
  echo "== $g (exit $?): $(grep -E '^two-edge:' $D/$g.lockstep.log) | $(grep 'read-back through' $D/$g.lockstep.log)"
done
