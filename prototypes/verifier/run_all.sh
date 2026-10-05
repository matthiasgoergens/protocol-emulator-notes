#!/usr/bin/env bash
# Regenerates every file in results/ (README.md cites them), one job at a time, niced, waiting
# while the 1-minute load is above 20. Each file starts with its command, commit and date.
#   ./run_all.sh            all of them
#   ./run_all.sh NAME       one of: selftest planted precision sweep compose mutants random controls
#                           kernel-bugs certs
set -o errexit -o nounset -o pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
cd "$HERE"
mkdir --parents results
nice ionice opam exec --switch=5.3.0 -- dune build --root . ./main.exe
EXE=./_build/default/main.exe
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
  echo "# $(opam exec --switch=5.3.0 -- ocamlfind ocamlopt -version 2>/dev/null | sed 's/^/ocamlopt /')"
  echo "# date: $(date --iso-8601=seconds)"
}
run() {
  local name=$1; shift
  wait_load
  echo "== $name" >&2
  { header "main.exe $*"; /usr/bin/time --format='# elapsed %e s, max rss %M kB' nice ionice "$EXE" "$@" 2>&1; } > "results/$name.txt" 2>&1 \
    || { echo "FAILED: $name (results/$name.txt)" >&2; return 1; }
  tail --lines=3 "results/$name.txt" >&2
}
what=${1:-all}
status=0
for job in selftest planted precision sweep compose mutants random controls kernel-bugs certs; do
  if [ "$what" != all ] && [ "$what" != "$job" ]; then continue; fi
  case $job in
    random) run random random 3000 || status=1 ;;
    certs)
      rm --recursive --force /var/tmp/verifier-certs
      run ledger certs /var/tmp/verifier-certs || status=1
      grep --invert-match '^#' results/ledger.txt | grep --invert-match '^$' > results/ledger.only || true
      mkdir --parents results/certs
      for n in uart_b16_n3 spi_p16_n2 i2c_q4_n2_l4095 deadline_ldd20 watchdog; do
        cp /var/tmp/verifier-certs/$n.cert results/certs/ 2>/dev/null || true
      done
      run ledger-check ledger-check results/ledger.txt || status=1 ;;
    *) run "$job" "$job" || status=1 ;;
  esac
done
exit $status
