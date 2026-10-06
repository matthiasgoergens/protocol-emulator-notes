#!/usr/bin/env bash
# Certificates on the RTL (README.md, section 8): for each job, main.exe rtl writes the image's
# certificate and the SymbiYosys check generated from it (../rtl.ml); SymbiYosys runs it on the
# v2 core's Verilog (../../formal/powerup/emit_core.exe, the Verilog of tt/src) in the LibreLane
# container (Yosys 0.62): abc pdr for the unbounded proof, abc bmc3 for the reachability of the
# antecedent (the certificate's last state) and of every final state. At most JOBS (default 2)
# sby runs at once, niced, each started only while the 1-minute load is below MAXLOAD (18).
#   rtl/run_rtl.sh             every job
#   rtl/run_rtl.sh JOB...      those jobs (names below)
# Output: ../results/rtl.txt (with RESULT=FILE, that file); work directories under $WORK.
set -o errexit -o nounset -o pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
VERIFIER=$(dirname "$HERE")
FORMAL=$VERIFIER/../formal
WORK=${WORK:-/var/tmp/verifier-rtl/rtl}
Z3ENV=${Z3ENV:-/var/tmp/symbolic-bmc/z3env}
JOBS=${JOBS:-2}
MAXLOAD=${MAXLOAD:-18}
RESULT=${RESULT:-$VERIFIER/results/rtl.txt}
IMAGE=ghcr.io/librelane/librelane:3.0.14
export DOCKER_CONFIG=${DOCKER_CONFIG:-/var/tmp/claude-notes/dockercfg}
mkdir --parents "$WORK/bin"
cat > "$WORK/bin/z3" <<'EOF'
#!/bin/sh
exec /hostlib/ld-linux-x86-64.so.2 --library-path /hostlib /z3env/bin/z3 "$@"
EOF
chmod +x "$WORK/bin/z3"

(cd "$VERIFIER" && nice ionice opam exec --switch=5.3.0 -- dune build --root . ./main.exe)
(cd "$FORMAL" && nice ionice opam exec --switch=5.3.0 -- dune build --root . ./powerup/emit_core.exe)
MAIN=$VERIFIER/_build/default/main.exe
EMIT=$FORMAL/_build/default/powerup/emit_core.exe
"$EMIT" "$WORK/core.v"
for i in 0 1 2; do "$EMIT" "$WORK/core-mutant$i.v" "mutant:$i"; done

# job | image | main.exe rtl options | core | expected
#   pass: every property PROVED and its antecedent reachable; fail: some property FAILED
JOBLIST='
deadline|deadline_ldd20||core|pass
uart|uart_b16_n3||core|pass
spi|spi_p16_n2||core|pass
i2c|i2c_q4_n1_l7||core|pass
deadline-gap-narrowed|deadline_ldd20|--gap 1 2..21|core|fail
i2c-gap-narrowed|i2c_q4_n1_l7|--gap 4 1..6|core|fail
uart-gap-shifted|uart_b16_n3|--gap 2 15|core|fail
uart-data-shifted|uart_b16_n3|--data-shift|core|fail
spi-data-shifted|spi_p16_n2|--data-shift|core|fail
uart-mutant-waitd-early|uart_b16_n3||core-mutant0|fail
deadline-mutant-wait-fail-early|deadline_ldd20||core-mutant1|fail
i2c-mutant-wait-fail-early|i2c_q4_n1_l7||core-mutant1|fail
spi-mutant-sho-lsb-first|spi_p16_n2||core-mutant2|fail
'
field() { echo "$1" | cut --delimiter='|' --fields="$2"; }
all_jobs=$(echo "$JOBLIST" | sed '/^$/d' | cut --delimiter='|' --fields=1)
jobs_wanted=${*:-$all_jobs}

wait_load() {
  while :; do
    l=$(cut --delimiter=' ' --fields=1 /proc/loadavg)
    if awk -v l="$l" -v m="$MAXLOAD" 'BEGIN { exit !(l < m) }'; then return; fi
    echo "load $l >= $MAXLOAD, waiting" >&2; sleep 60
  done
}

# prepare a job's directory and sby file; print the sby tasks to run
prepare() {
  local job=$1 line img opts core expect dir depth finals sdepth
  line=$(echo "$JOBLIST" | grep "^$job|")
  img=$(field "$line" 2); opts=$(field "$line" 3); core=$(field "$line" 4); expect=$(field "$line" 5)
  dir=$WORK/$job
  rm --recursive --force "$dir"; mkdir --parents "$dir"
  # shellcheck disable=SC2086
  "$MAIN" rtl "$img" "$dir" $opts > "$dir/generate.txt"
  cp "$WORK/$core.v" "$dir/core.v"
  depth=$(cat "$dir/depth"); finals=$(cat "$dir/finals"); sdepth=$(cat "$dir/slots_depth")
  {
    echo "[tasks]"
    echo "prove"
    if [ "$expect" = pass ]; then
      echo "slots"
      echo "reach_done reach"
      for f in $finals; do echo "reach_fin_$f reach"; done
    fi
    echo
    echo "[options]"
    echo "prove: mode prove"
    # no trace replay: yosys-smtbmc cannot map abc's witness back onto this design ("signal
    # not found in design" for a port of the core); abc names the failing output and its frame,
    # and the model's design_aiger.ywa names the outputs
    echo "prove: aigsmt none"
    if [ "$expect" = pass ]; then
      echo "slots: mode bmc"
      echo "slots: depth $sdepth"
      echo "slots: aigsmt none"
      echo "reach: mode bmc"
      echo "reach: depth $depth"
      echo "reach: aigsmt none"
    fi
    echo
    echo "[engines]"
    echo "prove: abc pdr"
    if [ "$expect" = pass ]; then echo "slots: abc bmc3"; echo "reach: abc bmc3"; fi
    echo
    echo "[script]"
    echo "read -formal core.v"
    echo "prove: read -formal cert_check.sv"
    if [ "$expect" = pass ]; then
      echo "slots: read -formal -DSLOTS cert_check.sv"
      echo "reach_done: read -formal -DREACH=done cert_check.sv"
      for f in $finals; do echo "reach_fin_$f: read -formal -DREACH=fin_$f cert_check.sv"; done
    fi
    echo "prep -top cert_check"
    echo
    echo "[files]"
    echo "core.v"
    echo "cert_check.sv"
  } > "$dir/cert.sby"
  sed --quiet '/^\[tasks\]/,/^$/{/^[a-z]/{s/ .*//;p}}' "$dir/cert.sby"
}

run_task() {
  local job=$1 task=$2
  wait_load
  timeout 7200 nice ionice docker run --rm --user "$(id -u):$(id -g)" \
    --volume "$WORK/$job:/work" --volume "$WORK/bin:/zbin:ro" --workdir /work \
    --volume "$Z3ENV:/z3env:ro" --volume /usr/lib:/hostlib:ro \
    "$IMAGE" sh -c 'PATH=/zbin:$PATH; exec sby -f cert.sby "$1"' sby "$task" > "$WORK/$job/$task.out" 2>&1 || true
}

pairs=()
for j in $jobs_wanted; do
  for t in $(prepare "$j"); do pairs+=("$j:$t"); done
done
running=0
for pt in "${pairs[@]}"; do
  run_task "${pt%%:*}" "${pt#*:}" &
  running=$((running + 1))
  sleep 20   # let the load average see the new run before the next one is started
  if [ "$running" -ge "$JOBS" ]; then wait -n || true; running=$((running - 1)); fi
done
wait

# the step at which a reach task's negated antecedent failed, or "" if it held to the depth
reach_step() {
  local f=$1
  if grep --quiet 'DONE (FAIL' "$f"; then grep --only-matching --max-count=1 'asserted in frame [0-9]*' "$f" | sed 's/.* //'
  else echo ""; fi
}

{
  echo "# command: rtl/run_rtl.sh $*"
  echo "# commit: $(git -C "$HERE" rev-parse HEAD)$(git -C "$HERE" diff --quiet HEAD -- "$VERIFIER" "$VERIFIER/../sequencer-v2" "$FORMAL/powerup" || echo ' (with uncommitted changes)')"
  echo "# yosys: $(timeout 300 docker run --rm "$IMAGE" yosys -V 2>/dev/null)"
  echo "# z3: $("$Z3ENV/bin/z3" --version)"
  echo "# date: $(date --iso-8601=seconds)"
  for j in $jobs_wanted; do
    line=$(echo "$JOBLIST" | grep "^$j|")
    img=$(field "$line" 2); opts=$(field "$line" 3); core=$(field "$line" 4); expect=$(field "$line" 5)
    dir=$WORK/$j
    echo "== $j: image $img, main.exe rtl $img DIR $opts, core $core.v; expected: $expect"
    cat "$dir/generate.txt"
    grep --extended-regexp 'summary: engine|Assert failed|failed assertion|DONE|Elapsed clock' "$dir/prove.out" \
      | sed 's/^SBY [0-9:]* \[[^]]*\] //' || echo "no result (see $dir/prove.out)"
    labels=$(grep --only-matching --extended-regexp '[a-z_]+: assert' "$dir/cert_check.sv" | sed 's/: assert//' | grep --invert-match --extended-regexp '^(reach|slots)$')
    if grep --quiet 'DONE (PASS' "$dir/prove.out"; then
      if [ -f "$dir/reach_done.out" ]; then s=$(reach_step "$dir/reach_done.out"); else s=""; fi
      for l in $labels; do
        if [ -n "$s" ]; then echo "PROPERTY $j-$l: PROVED unbounded (abc pdr); antecedent ${l}_ante reachable (step $s)"
        elif [ -f "$dir/reach_done.out" ] && grep --quiet 'DONE (PASS' "$dir/reach_done.out"; then
          echo "PROPERTY $j-$l: VACUOUS unbounded (abc pdr); antecedent ${l}_ante unreachable within $(cat "$dir/depth") clocks"
        else echo "PROPERTY $j-$l: UNDECIDED (proof passed, antecedent not decided)"; fi
      done
      if [ -f "$dir/slots.out" ]; then
        if grep --quiet 'DONE (PASS' "$dir/slots.out"; then
          if [ -n "$s" ]; then echo "PROPERTY $j-slots: PROVED to $(cat "$dir/slots_depth") clocks (abc bmc3), past every event's slot (rtl.ml); antecedent slots_ante reachable (step $s)"
          else echo "PROPERTY $j-slots: VACUOUS to $(cat "$dir/slots_depth") clocks; antecedent unreachable"; fi
        elif grep --quiet 'DONE (FAIL' "$dir/slots.out"; then
          echo "PROPERTY $j-slots: FAILED at step $(grep --only-matching --max-count=1 'asserted in frame [0-9]*' "$dir/slots.out" | sed 's/.* //')"
        else echo "PROPERTY $j-slots: UNDECIDED (see $dir/slots.out)"; fi
      fi
      for f in $(cat "$dir/finals"); do
        [ -f "$dir/reach_fin_$f.out" ] || continue
        s=$(reach_step "$dir/reach_fin_$f.out")
        if [ -n "$s" ]; then echo "COVER $j-final_$f: REACHABLE (step $s)"
        elif grep --quiet 'DONE (PASS' "$dir/reach_fin_$f.out"; then echo "COVER $j-final_$f: UNREACHABLE within $(cat "$dir/depth") clocks"
        else echo "COVER $j-final_$f: UNDECIDED"; fi
      done
    elif grep --quiet 'DONE (FAIL' "$dir/prove.out"; then
      out=$(grep --only-matching --max-count=1 --extended-regexp 'Output [0-9]+ of miter .* asserted in frame [0-9]+' "$dir/prove.out")
      idx=$(echo "$out" | sed 's/Output \([0-9]*\) .*/\1/'); step=$(echo "$out" | sed 's/.* //')
      name=$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["asserts"][int(sys.argv[2])][0].lstrip("\\"))' \
        "$dir/cert_prove/model/design_aiger.ywa" "$idx")
      echo "PROPERTY $j-$name: FAILED at step $step (abc pdr)"
    else
      echo "PROPERTY $j: UNDECIDED (see $dir/prove.out)"
    fi
  done
} | tee "$RESULT"
