#!/usr/bin/env bash
# Regenerates every result file of this prototype, one simulation at a time, niced.
#   ./run_all.sh            lockstep + all ported suites
#   ./run_all.sh ports      only the ported suites
# Output: results/lockstep.txt and results/ports/<suite>.txt, each headed by the command, the
# commit and the tool versions; for suites with a recorded result in their own directory, the
# diff against it follows the run (empty = identical).
set -o errexit -o nounset -o pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
cd "$HERE"
B=$HERE/_build/default
P=$HERE/..
wait_load() {
  while :; do
    l=$(cut --delimiter=' ' --fields=1 /proc/loadavg)
    if awk -v l="$l" 'BEGIN { exit !(l <= 20) }'; then return; fi
    echo "load $l > 20, waiting" >&2; sleep 60
  done
}
header() {
  echo "# command: $1"
  echo "# commit: $(git rev-parse HEAD)$(git diff --quiet HEAD -- . || echo ' (with uncommitted changes)')"
  echo "# $(opam exec --switch=5.3.0 -- ocamlfind ocamlopt -version | sed 's/^/ocaml /'), $(opam exec --switch=5.3.0 -- ocamlfind list 2>/dev/null | grep '^hardcaml ' | tr --squeeze-repeats ' ')"
  echo "# date: $(date --iso-8601=seconds)"
}
run() {   # name, recorded-result-or-empty, command...
  local name=$1 rec=$2; shift 2
  wait_load
  local out=results/ports/$name.txt
  { header "$*"; (cd /var/tmp/isa-v2 && nice ionice "$@") 2>&1; echo "exit $?"; } > "$out" || true
  if [ -n "$rec" ]; then
    { echo; echo "# diff against the recorded result $rec (lines starting # and exit lines ignored):";
      diff <(grep --invert-match --extended-regexp '^#|^exit' "$rec") <(grep --invert-match --extended-regexp '^#|^exit' "$out" | sed '/^$/d') \
        && echo "# identical"; } >> "$out" || true
  fi
  echo "$name: $(grep --extended-regexp --max-count=1 'ALL PASS|DEMO PASS|PASS$|FAIL' "$out" | tail --lines=1)"
}
mkdir --parents results/ports /var/tmp/isa-v2
nice ionice opam exec --switch=5.3.0 -- dune build 2>&1
if [ "${1:-all}" = all ]; then
  wait_load
  { header "lockstep2.exe 1000 5000"; nice ionice "$B/lockstep2.exe" 1000 5000; } > results/lockstep.txt 2>&1 || true
  grep --extended-regexp '^lockstep|ALL PASS|FAILURES' results/lockstep.txt
fi
run deadline-sequencer-demo results/ports/original-deadline-sequencer-demo.txt "$B/ports/deadline-sequencer/demo.exe"
run sequencer-ethernet results/ports/original-sequencer-ethernet.txt "$B/ports/sequencer-ethernet/main.exe"
run jtag-swd "$P/proto-jtag-swd/results/wide-all.txt" "$B/ports/jtag-swd/main.exe"
run usb-ls "$P/usb-ls/run-fw-8seeds.log" "$B/ports/usb-ls/main_fw.exe"
run ps2 "$P/sequencer-ps2-can/logs/2026-09-25/ps2.txt" "$B/ports/ps2/ps2_main.exe" 8
run multi-proto-bridge_a "" "$B/ports/multi-proto/bridge_a.exe" all
