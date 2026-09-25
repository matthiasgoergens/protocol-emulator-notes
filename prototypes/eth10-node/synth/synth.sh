#!/usr/bin/env bash
# Yosys area of the generic blocks against the sg13g2 typical liberty, the same recipe as
# ../pin-sampler (synth -flatten, dfflibmap, abc, stat).
set -o errexit -o nounset -o pipefail
cd "$(dirname "$0")"
lib=/home/matthias/prog/janestreet/pio-area-notes/sg13g2/sg13g2_stdcell_typ_1p20V_25C.lib
yosys=/home/matthias/prog/janestreet/fabulous-notes/oss-cad-suite/bin/yosys
for top in edge_sampler1 edge_sampler4 crc_unit systolic_matcher_en eth_rx_path4; do
  mod=$(grep --max-count=1 --only-matching --extended-regexp "^module [a-z0-9_]+" "$top.v" | cut --delimiter=' ' --fields=2)
  nice ionice "$yosys" -p "read_verilog $top.v; hierarchy -check -top $mod; synth -top $mod -flatten; dfflibmap -liberty $lib; abc -liberty $lib; opt_clean; stat -liberty $lib" > "$top.log" 2>&1
  printf '%-22s %s  %s\n' "$top" "$(grep --only-matching --extended-regexp "Chip area for module .*: [0-9.]+" "$top.log" | grep --only-matching --extended-regexp "[0-9.]+$")" \
    "$(grep --extended-regexp "^ +[0-9]+ +cells$|Number of cells" "$top.log" | tee /dev/null | sed --quiet '$p')"
done
