#!/usr/bin/env bash
# The kernel's abstract step against Isa2's interpreter, by z3 (README.md section 4,
# kernel_proof.ml): every instruction word, every shape of key, in one process per opcode (one
# z3 each), at most JOBS (default 2) at once, niced, each started only while the 1-minute load
# is below MAXLOAD (18). Then the planted kernel bugs of the step (Kernel.planted_bug 1 to 7),
# each on the opcode it touches: each must give a counterexample.
#   ./kernel_z3.sh            all of it
#   ./kernel_z3.sh proof      the proof only
#   ./kernel_z3.sh bugs       the planted bugs only
# Output: results/kernel-z3.txt (RESULT=FILE: that file). z3 from the venv of ../formal/README.md.
set -o errexit -o nounset -o pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
cd "$HERE"
JOBS=${JOBS:-2}
MAXLOAD=${MAXLOAD:-18}
RESULT=${RESULT:-$HERE/results/kernel-z3.txt}
WORK=${WORK:-/var/tmp/verifier-rtl/kernel-z3}
export PATH=${Z3ENV:-/var/tmp/symbolic-bmc/z3env}/bin:$PATH
mkdir --parents "$WORK"
nice ionice opam exec --switch=5.3.0 -- dune build --root . ./main.exe
cp _build/default/main.exe "$WORK/main.exe"
EXE=$WORK/main.exe
what=${1:-all}

wait_load() {
  while :; do
    l=$(cut --delimiter=' ' --fields=1 /proc/loadavg)
    if awk -v l="$l" -v m="$MAXLOAD" 'BEGIN { exit !(l < m) }'; then return; fi
    echo "load $l >= $MAXLOAD, waiting" >&2; sleep 60
  done
}
run_jobs() {   # lines of "name args..." on stdin
  local running=0 name args
  while read -r name args; do
    wait_load
    # shellcheck disable=SC2086
    (/usr/bin/time --format='# elapsed %e s, max rss %M kB' nice ionice "$EXE" $args > "$WORK/$name.out" 2>&1 || true) &
    running=$((running + 1))
    sleep 5
    if [ "$running" -ge "$JOBS" ]; then wait -n || true; running=$((running - 1)); fi
  done
  wait
}

# opcodes 0..14 one process each; EXT (15) one per sub-operation group
ranges() {
  for op in $(seq 0 14); do printf 'op%02d kernel-z3 %x000 %xfff\n' "$op" "$op" "$op"; done
  for sub in $(seq 0 15); do printf 'ext%02d kernel-z3 f%x00 f%xff\n' "$sub" "$sub" "$sub"; done
}
# planted kernel bugs in the step, each on the words it touches
bugs() {
  echo "bug1 --bug 1 kernel-z3 5000 50ff"     # a wait that proceeds takes one slot less at most: WAITP
  echo "bug2 --bug 2 kernel-z3 5000 50ff"     # a wait that times out takes one slot less: WAITP
  echo "bug3 --bug 3 kernel-z3 3000 30ff"     # LDD loads one less
  echo "bug4 --bug 4 kernel-z3 a000 a0ff"     # JNZ falls through on cnt = 1
  echo "bug5 --bug 5 kernel-z3 f000 f1ff"     # SKNE/SKEQ decided the wrong way
  echo "bug6 --bug 6 kernel-z3 7000 70ff"     # a push-pull SHO assumed driven whatever its enable
  echo "bug7 --bug 7 kernel-z3 6000 6000"     # WAITD takes one slot less
}

if [ "$what" = all ] || [ "$what" = proof ]; then ranges | run_jobs; fi
if [ "$what" = all ] || [ "$what" = bugs ]; then bugs | run_jobs; fi

{
  echo "# command: kernel_z3.sh $*"
  echo "# commit: $(git rev-parse HEAD)$(git diff --quiet HEAD -- . ../sequencer-v2 ../formal/smt.ml || echo ' (with uncommitted changes)')"
  echo "# $(z3 --version)"
  echo "# date: $(date --iso-8601=seconds)"
  echo "== the proof: every word, 8 key shapes each (kernel_proof.ml)"
  for f in $(ranges | cut --delimiter=' ' --fields=1); do
    [ -f "$WORK/$f.out" ] && grep --extended-regexp '^(OPCODE|COUNTEREXAMPLE|UNKNOWN|.*VACUOUS|# elapsed)' "$WORK/$f.out" | sed "s/^# elapsed/# $f: elapsed/"
  done
  echo "== planted kernel bugs in the step: each must give a counterexample"
  for f in $(bugs | cut --delimiter=' ' --fields=1); do
    [ -f "$WORK/$f.out" ] || continue
    n=$(grep --count '^COUNTEREXAMPLE' "$WORK/$f.out" || true)
    desc=$(bugs | grep "^$f " | sed 's/.*# //')
    if [ "$n" -gt 0 ]; then echo "PLANTED kernel $f ($desc): CAUGHT, $(grep '^COUNTEREXAMPLE' "$WORK/$f.out" | head --lines=1)"
    else echo "PLANTED kernel $f ($desc): NOT CAUGHT"; fi
  done
} | tee "$RESULT"
