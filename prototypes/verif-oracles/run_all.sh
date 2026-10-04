#!/usr/bin/env bash
# Regenerates every result file of verif-oracles, one run at a time, niced, waiting while the
# machine's 1-minute load is above 20. Each file is headed by the command, the commit and the
# tool versions.
set -o errexit -o nounset -o pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
cd "$HERE"
B=$HERE/_build/default
wait_load() {
  while :; do
    l=$(cut --delimiter=' ' --fields=1 /proc/loadavg)
    if awk -v l="$l" 'BEGIN { exit !(l <= 20) }'; then return; fi
    echo "load $l > 20, waiting" >&2; sleep 60
  done
}
header() {
  echo "# command: $*"
  echo "# commit: $(git rev-parse HEAD)$(git diff --quiet HEAD -- . || echo ' (with uncommitted changes)')"
  echo "# $(opam exec --switch=5.3.0 -- ocamlfind ocamlopt -version | sed 's/^/ocaml /'), $(opam exec --switch=5.3.0 -- ocamlfind list 2>/dev/null | grep '^hardcaml ' | tr --squeeze-repeats ' ')"
  echo "# date: $(date --iso-8601=seconds)"
}
run() {   # result-name, command...
  local out=results/$1.txt; shift
  wait_load
  { header "$@"; nice ionice "$@" 2>&1; echo "exit $?"; } > "$out" || true
  echo "wrote $out: $(grep --extended-regexp 'PASS|FAIL' "$out" | tail --lines=1)"
}
wait_load
nice ionice opam exec --switch=5.3.0 -- dune build --root . 2>&1
run crc-maths $B/crc/crc_oracle.exe maths
run crc-pe $B/crc/crc_oracle.exe pe 50
run crc-split $B/crc/crc_oracle.exe split
run crc-shared-faults $B/crc/crc_oracle.exe shared-faults 20
run crc-blind-spot $B/crc/crc_oracle.exe blind 20
$B/crc/crc_oracle.exe zlib-vectors /var/tmp/verif-oracles-zlib-vectors.txt > /dev/null
run crc-zlib uv run --no-project python crc/zlib_check.py /var/tmp/verif-oracles-zlib-vectors.txt
run stall-ethernet $B/stall/eth_stall.exe
run stall-i2c-stretch $B/stall/i2c_stretch.exe
run stall-jtag-swd $B/stall-wide/jtag_swd_stall.exe
if [ -x "$B/hazard/hazard.exe" ]; then run hazard $B/hazard/hazard.exe; fi
