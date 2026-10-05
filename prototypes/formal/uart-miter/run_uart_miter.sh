#!/usr/bin/env bash
# Our UART programme against Jane Street's Uart.Tx (README.md, section 7): simulations that
# measure the offsets, then the SymbiYosys tasks of uart_miter.sby, at most JOBS (default 3) at
# once, niced, waiting while the 1-minute load is above 20. Output: ../results/uart-miter.txt.
# Needs: the LibreLane image, the z3 venv (Z3ENV, as run_powerup.sh), and the project-local switch
# with Hardcaml v0.18 for the Tx (build_hobby_tx.sh says how to make it).
set -o errexit -o nounset -o pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
FORMAL=$(dirname "$HERE")
WORK=${WORK:-/var/tmp/formal-hygiene/uart-miter}
Z3ENV=${Z3ENV:-/var/tmp/symbolic-bmc/z3env}
JOBS=${JOBS:-3}
IMAGE=ghcr.io/librelane/librelane:3.0.14
export DOCKER_CONFIG=${DOCKER_CONFIG:-/var/tmp/claude-notes/dockercfg}
mkdir --parents "$WORK/bin" "$FORMAL/results"
cat > "$WORK/bin/z3" <<'Z3'
#!/bin/sh
exec /hostlib/ld-linux-x86-64.so.2 --library-path /hostlib /z3env/bin/z3 "$@"
Z3
chmod +x "$WORK/bin/z3"

OUT=$WORK "$HERE/build_hobby_tx.sh" 20
(cd "$FORMAL" && nice ionice opam exec --switch=5.3.0 -- dune build ./uart_rom.exe ./powerup/emit_core.exe)
"$FORMAL/_build/default/uart_rom.exe" 4 > "$WORK/uart_rom.v"
"$FORMAL/_build/default/uart_rom.exe" 2 stretch > "$WORK/uart_rom_stretch.v"
"$FORMAL/_build/default/uart_rom.exe" 4 > "$WORK/uart_rom_sim4.v"
"$FORMAL/_build/default/powerup/emit_core.exe" "$WORK/core.v"
cp "$HERE/uart_pair.v" "$HERE/uart_miter.sv" "$HERE/uart_miter.sby" "$HERE/tb_pair.v" "$WORK/"

wait_load() {
  while :; do
    local load
    load=$(cut --delimiter=' ' --fields=1 /proc/loadavg)
    if awk -v l="$load" 'BEGIN { exit !(l <= 20) }'; then return; fi
    echo "load $load > 20, waiting" >&2; sleep 60
  done
}
in_container() {
  timeout 7200 nice ionice docker run --rm --user "$(id -u):$(id -g)" --volume "$WORK:/work" --workdir /work \
    --volume "$Z3ENV:/z3env:ro" --volume /usr/lib:/hostlib:ro "$IMAGE" sh -c "PATH=/work/bin:\$PATH; $1"
}

for locked in 1 0; do
  wait_load
  in_container "iverilog -DLOCKED=$locked -o tb$locked.vvp tb_pair.v uart_pair.v uart_rom_sim4.v core.v hobby_uart_tx.v && vvp -n tb$locked.vvp" \
    | grep --invert-match '\$finish' > "$WORK/sim-locked$locked.txt"
done

tasks=${*:-bmc ante constant stretch flip}
running=0
for t in $tasks; do
  (wait_load; in_container "exec sby -f uart_miter.sby $t" > "$WORK/$t.out" 2>&1 || true) &
  running=$((running + 1))
  if [ "$running" -ge "$JOBS" ]; then wait -n || true; running=$((running - 1)); fi
done
wait

{
  echo "# command: uart-miter/run_uart_miter.sh $*"
  echo "# commit: $(git -C "$HERE" rev-parse HEAD)$(git -C "$HERE" diff --quiet HEAD -- "$FORMAL" "$FORMAL/../sequencer-v2" || echo ' (with uncommitted changes)')"
  echo "# hardcaml_hobby_boards: $(git -C "${HOBBY:-/var/tmp/hardcaml_hobby_boards}" rev-parse HEAD)"
  echo "# yosys: $(timeout 300 docker run --rm "$IMAGE" yosys -V 2>/dev/null)"
  echo "# z3: $("$Z3ENV/bin/z3" --version)"
  echo "# date: $(date --iso-8601=seconds)"
  for locked in 1 0; do
    echo "== simulation, 4 bytes 4f a5 3c 81, LOCKED=$locked (iverilog): line edges and bytes taken, by clock"
    cat "$WORK/sim-locked$locked.txt"
  done
  for t in $tasks; do
    echo "== $t"
    grep --extended-regexp 'summary: engine|failed assertion|reached cover|DONE|asserted in frame|No output asserted' "$WORK/$t.out" \
      | sed 's/^SBY [0-9:]* \[[^]]*\] //' || echo "no result (see $WORK/$t.out)"
  done
  echo "== per-task verdicts of the controls (each must FAIL)"
  for t in constant stretch flip; do
    f=$WORK/$t.out
    [ -f "$f" ] || continue
    if grep --quiet 'DONE (FAIL' "$f"; then
      echo "PROPERTY uart-miter-$t: FAILED at step $(grep --only-matching --max-count=1 'failed assertion .* step [0-9]*' "$f" | sed 's/.* step //')"
    elif grep --quiet 'DONE (PASS' "$f"; then echo "PROPERTY uart-miter-$t: PROVED to 840 clocks (abc bmc3)"
    else echo "PROPERTY uart-miter-$t: UNDECIDED (see $f)"; fi
  done
  if [ -f "$WORK/bmc.out" ] && [ -f "$WORK/ante.out" ]; then
    echo "== per-property report: bmc with ante (the antecedent's reachability)"
    "$FORMAL/sby_report.py" "$HERE/uart_miter.sv" "$WORK/bmc.out" "$WORK/ante.out" "to 840 clocks (abc bmc3), 4 bytes, every value" || true
  fi
} | tee "$FORMAL/results/uart-miter.txt"
