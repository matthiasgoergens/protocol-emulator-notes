#!/usr/bin/env bash
# Regenerates the result files README.md cites, one job at a time, niced, waiting while the
# 1-minute load is 16 or more. Each file starts with its command, commit and date.
#   ./run_all.sh            every job
#   ./run_all.sh JOB...     some of: uart spi i2c i2c-target spi-target chip judge verifier
set -o errexit -o nounset -o pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
cd "$HERE"
mkdir --parents results
wait_load() {
  while :; do
    l=$(cut --delimiter=' ' --fields=1 /proc/loadavg)
    if awk -v l="$l" 'BEGIN { exit !(l < 16) }'; then return; fi
    echo "load $l >= 16, waiting" >&2; sleep 60
  done
}
header() {
  echo "# command: $1"
  echo "# commit: $(git -C "$ROOT" rev-parse HEAD)$(git -C "$ROOT" diff --quiet HEAD -- prototypes/protocol-roles prototypes/sequencer-v2 prototypes/chip-top prototypes/verifier tools/sigrok-judge || echo ' (with uncommitted changes)')"
  echo "# date: $(date --iso-8601=seconds)"
}
build() { nice ionice opam exec --switch=5.3.0 -- dune build --root "$1" "$2" 2>&1; }
run_to() {   # file, directory, command...
  local file=$1 dir=$2; shift 2
  wait_load
  echo "== $file" >&2
  { header "$*"; (cd "$dir" && /usr/bin/time --format='# elapsed %e s, max rss %M kB' nice ionice "$@") 2>&1; } > "$file" \
    || { echo "FAILED: $file" >&2; return 1; }
  tail --lines=2 "$file" >&2
}
jobs=("$@")
[ ${#jobs[@]} -eq 0 ] && jobs=(uart spi i2c i2c-target spi-target chip judge verifier)
status=0
build "$HERE" ./main.exe
for job in "${jobs[@]}"; do
  case $job in
    uart|spi|i2c|i2c-target|spi-target)
      run_to "results/$job.txt" "$HERE" ./_build/default/main.exe "$job" || status=1 ;;
    chip)
      build "$ROOT/prototypes/chip-top" ./bin/roles.exe
      for p in uart spi i2c i2c-target spi-target; do
        if "$ROOT/prototypes/chip-top/_build/default/bin/roles.exe" list | grep --quiet --line-regexp "$p"; then
          run_to "$ROOT/prototypes/chip-top/results/roles-$p-spec.txt" "$ROOT/prototypes/chip-top" ./_build/default/bin/roles.exe "$p" || status=1
          run_to "$ROOT/prototypes/chip-top/results/roles-$p-rtl.txt" "$ROOT/prototypes/chip-top" env DEMO_DRIVER=rtl ./_build/default/bin/roles.exe "$p" || status=1
        fi
      done ;;
    judge)
      T=$ROOT/tools/sigrok-judge/traces/roles
      rm --recursive --force "$T" && mkdir --parents "$T"
      wait_load
      nice ionice ./_build/default/main.exe dump "$T" > /dev/null
      wait_load
      { "$ROOT/tools/sigrok-judge/judge.py" --only roles 2>&1; } > "$ROOT/tools/sigrok-judge/results/judge-roles.txt" || status=1
      tail --lines=1 "$ROOT/tools/sigrok-judge/results/judge-roles.txt" >&2 ;;
    verifier)
      wait_load
      (cd "$ROOT/prototypes/verifier" && ./run_all.sh selftest && ./run_all.sh planted && ./run_all.sh sweep && ./run_all.sh certs) || status=1 ;;
    *) echo "unknown job $job" >&2; status=1 ;;
  esac
done
exit $status
