#!/usr/bin/env bash
# The chip-top test suite.
#
#   ./suite.sh quick    for CI, about two minutes after the build, no PDK: the lockstep and the
#                       planted bugs with the wide generator on a few trials, register coverage
#                       with a floor, the edge-phase test on the Hardcaml reference and its proof
#   ./suite.sh full     the recorded results: everything in quick at full length, at 4 and 8 PEs;
#                       with PDK_ROOT also the edge-phase test in Icarus on the RTL. The gate-level
#                       runs (gate_lockstep.exe, edge_phase.exe gates, sim/edge_plants.sh) need a
#                       harden's GDS and netlist and are listed in README.md section 6.
#
# Heavy steps run niced and wait while the load is high (CHIP_TOP_MAX_LOAD, default 16).
set -o errexit -o nounset -o pipefail
mode=${1:-quick}
here=$(cd "$(dirname "$0")" && pwd)
cd "$here"
exe=$here/_build/default/bin
out=${CHIP_TOP_OUT:-$(mktemp --directory --tmpdir chip-top-suite.XXXXXX)}
mkdir --parents "$out"
max_load=${CHIP_TOP_MAX_LOAD:-16}
# CI has its own opam switch: CHIP_TOP_DUNE=dune there
dune=${CHIP_TOP_DUNE:-opam exec --switch=5.3.0 -- dune}
wait_load() {
  while :; do
    l=$(cut --delimiter=' ' --fields=1 /proc/loadavg)
    if awk -v l="$l" -v m="$max_load" 'BEGIN { exit !(l <= m) }'; then return; fi
    echo "load $l > $max_load, waiting" >&2; sleep 30
  done
}
run() {   # name, command...
  local name=$1; shift
  wait_load
  echo "== $name: $*"
  nice ionice "$@" > "$out/$name.txt" 2>&1 || { echo "FAILED: $name (log $out/$name.txt)"; tail --lines=20 "$out/$name.txt"; exit 1; }
  grep --extended-regexp 'trials with mismatches|planted integration bugs caught|RTL register coverage|^inputs:|equivalent|DIFFERS' "$out/$name.txt" || true
}
# The coverage floor: the share of the register bits that are not provably constant which
# changed. The full runs reach 99.0 % (4 PEs) and 99.1 % (8 PEs); what is left is unreachable by
# design (README section 6).
floor() {   # name, percent
  local pct
  pct=$(sed --quiet 's/^RTL register coverage.*changed of the rest [0-9]* of [0-9]* (\([0-9.]*\) %).*/\1/p' "$out/$1.txt")
  [ -n "$pct" ] || { echo "no coverage line in $out/$1.txt"; exit 1; }
  awk -v p="$pct" -v f="$2" 'BEGIN { if (p + 0 < f) { print "coverage " p " % below the floor " f " %"; exit 1 }; print "coverage " p " % (floor " f " %)" }'
  grep --quiet 'constant yet changed (must be 0): 0' "$out/$1.txt" || { echo "the constant-bit analysis disagrees with the simulation"; exit 1; }
}
$dune build --root . 2>&1 | tail --lines=20
echo "logs in $out"
case $mode in
  quick)
    run lockstep-wide "$exe/lockstep.exe" run 20 12000 1 wide
    run controls-wide "$exe/lockstep.exe" controls 30 12000 wide
    run coverage-pe4 "$exe/lockstep.exe" coverage 1,1,1,1 20 12000 1 "$out/never-pe4.txt" wide
    floor coverage-pe4 95
    run edge-rtl "$exe/edge_phase.exe" rtl 1,1,1,1
    run edge-prove "$exe/edge_phase.exe" prove
    ;;
  full)
    run lockstep "$exe/lockstep.exe" run 400 12000
    run lockstep-wide "$exe/lockstep.exe" run 400 12000 1 wide
    run controls "$exe/lockstep.exe" controls 30 12000
    run controls-wide "$exe/lockstep.exe" controls 30 12000 wide
    run layouts "$exe/lockstep.exe" layouts 40 12000
    run coverage-pe4 "$exe/lockstep.exe" coverage 1,1,1,1 400 12000 1 "$out/never-pe4.txt" wide
    floor coverage-pe4 99
    run coverage-pe8 "$exe/lockstep.exe" coverage 2,2,2,2 400 12000 1 "$out/never-pe8.txt" wide
    floor coverage-pe8 99
    run edge-rtl-pe4 "$exe/edge_phase.exe" rtl 1,1,1,1
    run edge-rtl-pe8 "$exe/edge_phase.exe" rtl 2,2,2,2
    run edge-prove "$exe/edge_phase.exe" prove
    if [ -n "${PDK_ROOT:-}" ]; then
      wait_load
      nice ionice sim/edge_iverilog.sh rtl 2,2,2,2 "$out/iverilog-rtl-pe8" > "$out/iverilog-rtl-pe8.txt" 2>&1 \
        || { echo "FAILED: iverilog-rtl-pe8"; tail --lines=20 "$out/iverilog-rtl-pe8.txt"; exit 1; }
      grep '^inputs:\|unknown outputs' "$out/iverilog-rtl-pe8.txt"
    fi
    ;;
  *) echo "usage: $0 quick|full" >&2; exit 2 ;;
esac
echo "suite $mode: passed"
