#!/usr/bin/env bash
# Regenerates every result file of the toolchain, one job at a time, niced, waiting while the
# machine's 1-minute load is above 16. Each file is headed by its command, the commit and the date.
#   ./run_all.sh     build; round trip; docs drift; examples (traces and certificates); sigrok judge
# Needs opam switch 5.3.0 (Hardcaml v0.17); the judge needs podman and uv, and iverilog.
set -o errexit -o nounset -o pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
cd "$HERE"
wait_load() {
  while :; do
    l=$(cut --delimiter=' ' --fields=1 /proc/loadavg)
    if awk -v l="$l" 'BEGIN { exit !(l <= 16) }'; then return; fi
    echo "load $l > 16, waiting" >&2; sleep 60
  done
}
header() {
  echo "# command: $1"
  echo "# commit: $(git rev-parse HEAD)$(git diff --quiet HEAD -- . ../../prototypes || echo ' (with uncommitted changes)')"
  echo "# date: $(date --iso-8601=seconds)"
}
run() {   # result file, command...
  local out=$1; shift
  wait_load
  { header "$*"; nice ionice "$@" 2>&1; echo "exit $?"; } > "results/$out" || true
  echo "$out: $(grep --extended-regexp 'ALL|FAIL|DRIFT' "results/$out" | tail --lines=1)"
}
mkdir --parents results
wait_load
nice ionice opam exec --switch=5.3.0 -- dune build --root . 2>&1
B=_build/default
run roundtrip.txt "$B/test/roundtrip.exe" 2000
run docs-drift.txt "$B/test/docs_drift.exe"
run examples.txt "$B/test/examples.exe"
run judge.txt ./test/judge_examples.py
