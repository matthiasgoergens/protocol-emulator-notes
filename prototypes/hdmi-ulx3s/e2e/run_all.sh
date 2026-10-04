#!/bin/sh
# All end-to-end runs: both serialisers at two pixel-clock phases, then the negative controls,
# each of which must FAIL.  Summary in $OUT/summary.txt.  Leaves rtl/gen regenerated unmutated.
here=$(cd "$(dirname "$0")/.." && pwd)
out=${OUT:-/var/tmp/hdmi-ulx3s/e2e}
mkdir --parents "$out"
summary="$out/summary.txt"; : > "$summary"
run() {
  expect=$1; shift
  log=$(mktemp --tmpdir=/var/tmp hdmi-e2e.XXXXXX)
  "$here/e2e/run.sh" "$@" > "$log" 2>&1
  if grep --quiet '^E2E PASS' "$log"; then got=pass; else got=fail; fi
  why=$(grep --max-count=1 --extended-regexp 'FAIL|Failure|exception' "$log" | cut --characters=1-150)
  verdict=ok; [ "$got" = "$expect" ] || verdict=UNEXPECTED
  echo "$verdict  expect $expect got $got  $*  $why" | tee --append "$summary"
  rm --force "$log"
}
run pass sdr 0
run pass sdr 2000
run pass ddr 0
run pass ddr 4000
run fail sdr 2000 latency
run fail sdr 2000 xnor
run fail sdr 2000 qm8
run fail sdr 2000 control
run fail ddr 4000 oddr_swap
opam exec --switch=5.3.0 -- dune exec ./bin/emit.exe "$here/rtl/gen" none
