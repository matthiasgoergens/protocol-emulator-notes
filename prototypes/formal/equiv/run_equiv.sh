#!/usr/bin/env bash
# Bounded equivalence of the v2 RTL (sequencer2.ml) and the specification (isa2.ml as a circuit),
# with Yosys's SAT-based BMC in the LibreLane container (the image of
# ../../deadline-sequencer/pnr/run_pnr.sh). One Yosys run at a time, niced, waiting while the
# machine's 1-minute load is above 20.
#   ./run_equiv.sh clean DEPTH...       the real RTL: no mismatch up to each depth
#   ./run_equiv.sh bugs DEPTH           every planted bug of Sequencer2.bugs at one depth
#   ./run_equiv.sh bug DEPTH "DESC"     one planted bug, with its decoded counterexample
# Output: ../results/equiv-*.txt; Verilog, Yosys scripts and logs under $WORK.
set -o errexit -o nounset -o pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
FORMAL=$(dirname "$HERE")
MITER=$FORMAL/_build/default/equiv/miter.exe
WORK=${WORK:-/var/tmp/symbolic-bmc/equiv}
IMAGE=ghcr.io/librelane/librelane:3.0.14
export DOCKER_CONFIG=${DOCKER_CONFIG:-/var/tmp/claude-notes/dockercfg}
mkdir --parents "$WORK" "$FORMAL/results"
(cd "$FORMAL" && nice ionice opam exec --switch=5.3.0 -- dune build ./equiv/miter.exe)

wait_load() {
  while :; do
    l=$(cut --delimiter=' ' --fields=1 /proc/loadavg)
    if awk -v l="$l" 'BEGIN { exit !(l <= 20) }'; then return; fi
    echo "load $l > 20, waiting" >&2; sleep 60
  done
}

# yosys_bmc NAME VERILOG DEPTH: prints "NAME depth D: PROVED|COUNTEREXAMPLE|TIMEOUT|ERROR, T s, V variables"
yosys_bmc() {
  local name=$1 v=$2 depth=$3
  cat > "$WORK/$name.ys" <<EOF
read_verilog $(basename "$v")
prep -flatten -top miter
sat -seq $depth -prove mismatch 0 -set-init-zero -show-inputs -show-outputs -timeout 7200
EOF
  wait_load
  local t0 t1 status
  t0=$(date +%s.%N)
  timeout 8000 nice ionice docker run --rm --user "$(id -u):$(id -g)" --volume "$WORK:/work" --workdir /work "$IMAGE" \
    yosys -q -l "$name.log" "$name.ys" > "$WORK/$name.out" 2>&1 || true
  t1=$(date +%s.%N)
  if grep --quiet "no model found: SUCCESS" "$WORK/$name.log" 2>/dev/null; then status=PROVED
  elif grep --quiet "model found: FAIL" "$WORK/$name.log" 2>/dev/null; then status=COUNTEREXAMPLE
  elif grep --quiet --ignore-case "timeout" "$WORK/$name.log" 2>/dev/null; then status=TIMEOUT
  else status=ERROR; fi
  local vars
  vars=$(grep --only-matching --extended-regexp "Solving problem with [0-9]+ variables and [0-9]+ clauses" "$WORK/$name.log" 2>/dev/null | sed 's/Solving problem with //' || true)
  printf '%s depth %s: %s, %.0f s (%s)\n' "$name" "$depth" "$status" "$(echo "$t1 - $t0" | bc)" "$vars"
}

header() {
  echo "# command: run_equiv.sh $*"
  echo "# commit: $(git -C "$HERE" rev-parse HEAD)$(git -C "$HERE" diff --quiet HEAD -- "$FORMAL" "$FORMAL/../sequencer-v2" || echo ' (with uncommitted changes)')"
  echo "# yosys: $(timeout 300 docker run --rm "$IMAGE" yosys -V 2>/dev/null)"
  echo "# date: $(date --iso-8601=seconds)"
}

mode=${1:?usage}; shift
case $mode in
  clean)
    out=$FORMAL/results/equiv-clean.txt
    { header clean "$@"; "$MITER" "$WORK/miter-clean.v";
      for d in "$@"; do (cd "$WORK" && yosys_bmc "clean-$d" "$WORK/miter-clean.v" "$d"); done; } | tee "$out" ;;
  bugs)
    depth=$1
    out=$FORMAL/results/equiv-bugs-depth$depth.txt
    { header bugs "$@";
      "$MITER" --list | while IFS= read -r desc; do
        slug=$(echo "$desc" | tr --complement --squeeze-repeats 'a-zA-Z0-9' '-' | sed 's/-$//')
        "$MITER" "$WORK/miter-$slug.v" "$desc"
        (cd "$WORK" && yosys_bmc "bug-$slug-$depth" "$WORK/miter-$slug.v" "$depth") | sed "s|^|[$desc] |"
      done; } | tee "$out" ;;
  bug)
    depth=$1 desc=$2
    slug=$(echo "$desc" | tr --complement --squeeze-repeats 'a-zA-Z0-9' '-' | sed 's/-$//')
    out=$FORMAL/results/equiv-bug-$slug.txt
    { header bug "$@"; "$MITER" "$WORK/miter-$slug.v" "$desc";
      (cd "$WORK" && yosys_bmc "bug-$slug-$depth" "$WORK/miter-$slug.v" "$depth");
      echo "counterexample (step 1 clears; then one thread per step):";
      "$MITER" --decode "$WORK/bug-$slug-$depth.log"; } | tee "$out" ;;
esac
