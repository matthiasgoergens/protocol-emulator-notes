#!/usr/bin/env bash
# Power-up determinism of the v2 core (README.md, section 5): SymbiYosys in the LibreLane
# container (Yosys 0.62), abc pdr for the proofs, smtbmc with z3 for the bounded run and the
# covers. At most JOBS (default 3) sby runs at once, niced, waiting while the 1-minute load is
# above 20.
#   ./run_powerup.sh                 every task of powerup.sby
#   ./run_powerup.sh r1 u_cfg ...    those tasks
# Output: ../results/powerup.txt; work directories under $WORK.
# z3 inside the container: the host's z3 from the z3-solver wheel (README.md, "Running it"), run
# through the host's dynamic loader, because the container has no /lib64. Set Z3ENV to the venv.
set -o errexit -o nounset -o pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
FORMAL=$(dirname "$HERE")
WORK=${WORK:-/var/tmp/formal-hygiene/powerup}
Z3ENV=${Z3ENV:-/var/tmp/symbolic-bmc/z3env}
JOBS=${JOBS:-3}
IMAGE=ghcr.io/librelane/librelane:3.0.14
export DOCKER_CONFIG=${DOCKER_CONFIG:-/var/tmp/claude-notes/dockercfg}
mkdir --parents "$WORK/bin" "$FORMAL/results"
cat > "$WORK/bin/z3" <<'EOF'
#!/bin/sh
exec /hostlib/ld-linux-x86-64.so.2 --library-path /hostlib /z3env/bin/z3 "$@"
EOF
chmod +x "$WORK/bin/z3"

(cd "$FORMAL" && nice ionice opam exec --switch=5.3.0 -- dune build ./powerup/emit_core.exe)
EMIT=$FORMAL/_build/default/powerup/emit_core.exe
"$EMIT" "$WORK/core.v"
for g in cfg dl inbox prev_pins host_tag; do "$EMIT" "$WORK/core-$g.v" "$g"; done
cp "$HERE/powerup.sv" "$HERE/powerup.sby" "$WORK/"

all_tasks=$(sed --quiet '/^\[tasks\]/,/^\[/{/^[a-z]/s/ .*//p}' "$HERE/powerup.sby")
tasks=${*:-$all_tasks}

wait_load() {
  while :; do
    l=$(cut --delimiter=' ' --fields=1 /proc/loadavg)
    if awk -v l="$l" 'BEGIN { exit !(l <= 20) }'; then return; fi
    echo "load $l > 20, waiting" >&2; sleep 60
  done
}

run_task() {
  local t=$1
  wait_load
  timeout 7200 nice ionice docker run --rm --user "$(id -u):$(id -g)" \
    --volume "$WORK:/work" --workdir /work \
    --volume "$Z3ENV:/z3env:ro" --volume /usr/lib:/hostlib:ro \
    "$IMAGE" sh -c 'PATH=/work/bin:$PATH; exec sby -f powerup.sby "$1"' sby "$t" > "$WORK/$t.out" 2>&1 || true
}

running=0
for t in $tasks; do
  run_task "$t" &
  running=$((running + 1))
  if [ "$running" -ge "$JOBS" ]; then wait -n || true; running=$((running - 1)); fi
done
wait

{
  echo "# command: powerup/run_powerup.sh $*"
  echo "# commit: $(git -C "$HERE" rev-parse HEAD)$(git -C "$HERE" diff --quiet HEAD -- "$FORMAL" "$FORMAL/../sequencer-v2" || echo ' (with uncommitted changes)')"
  echo "# yosys: $(timeout 300 docker run --rm "$IMAGE" yosys -V 2>/dev/null)"
  echo "# z3: $("$Z3ENV/bin/z3" --version)"
  echo "# date: $(date --iso-8601=seconds)"
  for t in $all_tasks; do
    [ -f "$WORK/$t.out" ] || continue
    echo "== $t"
    grep --extended-regexp 'summary: engine|failed assertion|reached cover|unreached cover|DONE|Property proved|Time =' "$WORK/$t.out" \
      | sed 's/^SBY [0-9:]* \[[^]]*\] //' || echo "no result (see $WORK/$t.out)"
    trace=$WORK/powerup_$t/engine_0/trace.vcd
    if [ -f "$trace" ]; then
      echo "counterexample, both copies (step 0 is the first clock; clear is high in the first RESET_CLOCKS steps):"
      "$HERE/vcd_table.py" "$trace" clear imem_addr_a imem_addr_b imem_a imem_b pin_out_a pin_out_b cfg_out_a cfg_out_b
    fi
  done
  echo "== per-task verdicts (every assertion of powerup.sv at once; the antecedent covers are those of r1 below, on the same miter)"
  for t in $all_tasks; do
    case $t in cover|r1) continue ;; esac
    f=$WORK/$t.out
    [ -f "$f" ] || continue
    if grep --quiet 'DONE (PASS' "$f"; then
      echo "PROPERTY powerup-$t: PROVED $(grep --quiet 'mode bmc' "$WORK/powerup_$t/config.sby" 2>/dev/null && echo 'to 12 clocks (smtbmc)' || echo 'unbounded (abc pdr)')"
    elif grep --quiet 'DONE (FAIL' "$f"; then
      echo "PROPERTY powerup-$t: FAILED at step $(grep --only-matching --max-count=1 'failed assertion .* step [0-9]*' "$f" | sed 's/.* step //') ($(grep --only-matching 'failed assertion [^ ]*' "$f" | sed 's/failed assertion //' | sort --unique | tr '\n' ' '))"
    else
      echo "PROPERTY powerup-$t: UNDECIDED (see $f)"
    fi
  done
  if [ -f "$WORK/r1.out" ] && [ -f "$WORK/cover.out" ]; then
    echo "== per-property report: r1 (proof) with cover (antecedents)"
    "$FORMAL/sby_report.py" "$HERE/powerup.sv" "$WORK/r1.out" "$WORK/cover.out" "unbounded (abc pdr), one-clock reset" || true
  fi
} | tee "$FORMAL/results/powerup.txt"
