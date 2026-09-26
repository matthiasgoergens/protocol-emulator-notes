#!/usr/bin/env bash
# Synthesise the v2 core (rtl/deadline_sequencer_v2.v, from ../emit2.exe: no debug ports, programme
# store and data bank outside) to the IHP SG13G2 typical-corner liberty with the Yosys inside the
# LibreLane 3.0.14 container (Yosys 0.62), area-mode abc, flattened: the script of
# ../../multi-proto/synth.sh, whose re-synthesis of the base core with the same Yosys gave
# 17,262.7 um2 (../../multi-proto/results/synth-summary.txt), the like-for-like baseline.
# Machine-specific inputs: LIB points to this machine's IHP SG13G2 checkout and DOCKER_CONFIG to
# its Docker configuration. Adjust those two paths elsewhere; the pinned IHP toolchain contract
# (LibreLane 3.0.14, Yosys 0.62, SG13G2 typical liberty) stays unchanged.
#   ./synth.sh   -> logs/deadline_sequencer_v2.log, reports/deadline_sequencer_v2.stat.txt
set -o errexit -o nounset -o pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
LIB=/home/matthias/.ciel/ihp-sg13g2/ihp-sg13g2/libs.ref/sg13g2_stdcell/lib/sg13g2_stdcell_typ_1p20V_25C.lib
mkdir --parents "$HERE/logs" "$HERE/reports"
cd "$HERE"
export DOCKER_CONFIG=/var/tmp/claude-notes/dockercfg
f=deadline_sequencer_v2
S="read_verilog -sv rtl/$f.v; hierarchy -check -top $f; synth -top $f -flatten; \
dfflibmap -liberty $LIB; abc -liberty $LIB; opt_clean; tee -o reports/$f.stat.txt stat -liberty $LIB"
nice ionice docker run --rm --user "$(id -u):$(id -g)" \
  --volume /home/matthias/.ciel:/home/matthias/.ciel:ro --volume "$HERE:$HERE" \
  --workdir "$HERE" ghcr.io/librelane/librelane:3.0.14 yosys -p "$S" > "logs/$f.log" 2>&1
echo "$f $(grep 'Chip area' reports/$f.stat.txt)"
grep --ignore-case "sequential\|dfrbp\|dfrbpq" "reports/$f.stat.txt" || true
