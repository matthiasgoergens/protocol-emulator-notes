#!/usr/bin/env bash
# Synthesise the PCS blocks (Verilog from `main.exe verilog DIR`) to the IHP SG13G2 typical
# liberty (1.2 V, 25 C) with the oss-cad-suite Yosys used by ../pe-synth (YOSYS_HOST flow there),
# flattened, area-mode abc. Output: synth/<name>.stat.txt and logs in /var/tmp/fast-eth/synth.
set -o errexit -o nounset -o pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
LIB=/home/matthias/.ciel/ihp-sg13g2/ihp-sg13g2/libs.ref/sg13g2_stdcell/lib/sg13g2_stdcell_typ_1p20V_25C.lib
RTL=${RTL:-/var/tmp/fast-eth/rtl}; LOG=/var/tmp/fast-eth/synth; mkdir --parents "$LOG"
YOSYS=/home/matthias/prog/janestreet/fabulous-notes/oss-cad-suite/bin/yosys
for name in fx_tx fx_rx tx_tx tx_rx; do
  nice ionice "$YOSYS" -p "read_verilog $RTL/$name.v; hierarchy -check -top $name; synth -top $name -flatten; \
dfflibmap -liberty $LIB; abc -liberty $LIB; opt_clean; tee -o $HERE/$name.stat.txt stat -liberty $LIB" > "$LOG/$name.log" 2>&1
  echo "$name: $(grep 'Chip area' $HERE/$name.stat.txt | tail --lines=1) $(grep --ignore-case 'sequential' $HERE/$name.stat.txt | tail --lines=1)"
done
