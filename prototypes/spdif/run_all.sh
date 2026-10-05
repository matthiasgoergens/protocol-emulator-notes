#!/usr/bin/env bash
# Regenerates the result files, one simulation at a time, niced, waiting while the load is above 20.
#   ./run_all.sh                 every suite
#   ./run_all.sh tx controls     only the named suites
# Output: results/<suite>.txt, each headed by the command, the commit and the tool versions.
set -o errexit -o nounset -o pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
cd "$HERE"
mkdir --parents results
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
nice ionice opam exec --switch=5.3.0 -- dune build 2>&1
run() {   # name, arguments...
  local name=$1; shift
  wait_load
  { header "main.exe $*"; nice ionice ./_build/default/main.exe "$@" 2>&1; echo "exit $?"; } > "results/$name.txt" || true
  tail --lines=1 "results/$name.txt" | sed "s/^/$name: /"
  grep --quiet '^ALL CHECKS PASS' "results/$name.txt" || echo "$name: checks failed, see results/$name.txt"
}
want() { [ $# -eq 0 ] && return 0; for w in "${SUITES[@]}"; do [ "$w" = "$1" ] && return 0; done; return 1; }
SUITES=("$@")
if [ ${#SUITES[@]} -eq 0 ]; then SUITES=(pacer tx controls roundtrip jitter tolerance rx demo sigrok); fi
for s in "${SUITES[@]}"; do
  case $s in
    pacer) run pacer pacer ;;
    tx) run tx tx ;;
    controls) run controls controls ;;
    roundtrip) run roundtrip roundtrip ;;
    jitter) run jitter jitter ;;
    tolerance) run tolerance tolerance ;;
    rx) run rx-random rx 40 2026 ;;
    demo) run demo demo 1.0 ;;
    sigrok) wait_load; { header "sigrok_check.sh"; ./sigrok_check.sh 2>&1; echo "exit $?"; } > results/sigrok.txt || true; tail --lines=2 results/sigrok.txt ;;
    *) echo "unknown suite $s" >&2; exit 2 ;;
  esac
done
