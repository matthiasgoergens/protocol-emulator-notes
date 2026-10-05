#!/usr/bin/env bash
# Regenerates results/bmc.txt (the bounded model checks, task 2) and results/kind2.txt (Kind 2 on
# the exported models, task 3), one job at a time, niced, waiting while the 1-minute load is
# above 20. Kind 2 runs three engines (BMC, k-induction, IC3) to keep its load to about four
# cores. The equivalence runs (task 4) are equiv/run_equiv.sh.
#   SMT_SOLVER   z3 binary (default: z3 on PATH; README.md says how to get one without root)
#   KIND2        Kind 2 binary (default: kind2 on PATH)
#   BMC_SMT_LOG  if set, a directory that receives the SMT-LIB sent for each run
set -o errexit -o nounset -o pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
cd "$HERE"
mkdir --parents results
nice ionice opam exec --switch=5.3.0 -- dune build ./main.exe
Z3=${SMT_SOLVER:-z3}
KIND2=${KIND2:-kind2}
wait_load() {
  while :; do
    l=$(cut --delimiter=' ' --fields=1 /proc/loadavg)
    if awk -v l="$l" 'BEGIN { exit !(l <= 20) }'; then return; fi
    echo "load $l > 20, waiting" >&2; sleep 60
  done
}
header() {
  echo "# command: $1"
  echo "# commit: $(git rev-parse HEAD)$(git diff --quiet HEAD -- . ../sequencer-v2 ../deadline-sequencer || echo ' (with uncommitted changes)')"
  echo "# $("$Z3" --version)"
  echo "# date: $(date --iso-8601=seconds)"
}
what=${1:-all}
if [ "$what" = all ] || [ "$what" = bmc ]; then
  { header "main.exe (every scenario)"
    for s in a a-planted a-protocols a-spi8 b b-planted c-planted c-induction c-induction-planted \
             c-induction-no-ownership c-induction-ldb-owned c-induction-ldb-owned-overlap \
             e e-bank e-bank-planted e-planted-steal d d-planted d-anytime c; do
      wait_load
      SMT_SOLVER=$Z3 nice ionice ./_build/default/main.exe "$s"
    done; } 2>&1 | tee results/bmc.txt
fi
if [ "$what" = all ] || [ "$what" = kind2 ]; then
  ./_build/default/main.exe kind2-export
  { header "kind2 on kind2/*.lus"; echo "# $("$KIND2" --version)"
    for f in kind2/*.lus; do
      wait_load
      echo "== $f"
      start=$(date +%s.%N)
      nice ionice "$KIND2" --z3_bin "$(command -v "$Z3")" --smt_solver Z3 --color false --enable BMC --enable IND --enable IC3IA --timeout 900 "$f" 2>&1 \
        | grep --extended-regexp "^<|valid|invalid|unknown|timeout|k=" || true
      printf 'wall %.1f s\n' "$(echo "$(date +%s.%N) - $start" | bc)"
    done; } 2>&1 | tee results/kind2.txt
fi
