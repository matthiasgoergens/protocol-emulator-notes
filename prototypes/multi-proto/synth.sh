#!/usr/bin/env bash
# Synthesise the base sequencer and the mailbox variants to the IHP SG13G2 typical-corner liberty
# with the Yosys inside the LibreLane 3.0.14 container (Yosys 0.62), area-mode abc, flattened,
# the same script as ../pe-synth/synth.sh. The base core is re-synthesised here with the same
# Yosys so the difference is like for like (its README's 17,300 um2 came from Yosys 0.69).
#   ./synth.sh   -> logs/<name>.log, reports/<name>.stat.txt
set -o errexit -o nounset -o pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
LIB=/home/matthias/.ciel/ihp-sg13g2/ihp-sg13g2/libs.ref/sg13g2_stdcell/lib/sg13g2_stdcell_typ_1p20V_25C.lib
mkdir --parents "$HERE/logs" "$HERE/reports"
cp "$HERE/../deadline-sequencer/deadline_sequencer.v" "$HERE/rtl/deadline_sequencer.v"
export DOCKER_CONFIG=/var/tmp/claude-notes/dockercfg
for f in deadline_sequencer seq_mb_p6_d1 seq_mb_p6_d2 seq_mb_p6_d4 seq_mb_p7_d2; do
  top=$(grep --max-count=1 "^module " "$HERE/rtl/$f.v" | sed 's/module \([a-z0-9_]*\).*/\1/')
  S="read_verilog -sv rtl/$f.v; hierarchy -check -top $top; synth -top $top -flatten; \
dfflibmap -liberty $LIB; abc -liberty $LIB; opt_clean; tee -o reports/$f.stat.txt stat -liberty $LIB"
  nice ionice docker run --rm --user "$(id -u):$(id -g)" \
    --volume /home/matthias/.ciel:/home/matthias/.ciel:ro --volume "$HERE:$HERE" \
    --workdir "$HERE" ghcr.io/librelane/librelane:3.0.14 yosys -p "$S" > "logs/$f.log" 2>&1
  echo "$f $(grep 'Chip area' reports/$f.stat.txt)"
  grep --ignore-case "sequential\|dfrbp" "reports/$f.stat.txt" || true
done
