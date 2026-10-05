#!/usr/bin/env bash
# Regenerates the pin traces from the prototypes' simulations (interpreter and RTL in lockstep where the
# prototype has both), then runs the judge.  Everything is niced and waits while the load is above 20.
#   ./run.sh              traces, then the judge at the simulated rate  -> results/judge.txt
#   ./run.sh --rate 250000   the same, resampled as a slower analyser would see it
# Needs opam switch 5.3.0 (Hardcaml v0.17), podman and uv.
set -o errexit -o nounset -o pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
TRACES=$HERE/traces
mkdir --parents "$TRACES/spdif" "$HERE/results"
wait_load() {
  while :; do
    l=$(cut --delimiter=' ' --fields=1 /proc/loadavg)
    if awk -v l="$l" 'BEGIN { exit !(l <= 20) }'; then return; fi
    echo "load $l > 20, waiting" >&2; sleep 60
  done
}
build_and_dump() {   # prototype directory, executable, arguments...
  local dir=$1 exe=$2; shift 2
  wait_load
  (cd "$ROOT/prototypes/$dir" && nice ionice opam exec --switch=5.3.0 -- dune build "./$exe.exe" 2>&1 \
     && nice ionice "./_build/default/$exe.exe" "$@")
}
build_and_dump deadline-sequencer demo dump "$TRACES"
build_and_dump sequencer-ps2-can ps2_dump "$TRACES"
build_and_dump sequencer-ps2-can can_dump "$TRACES"
build_and_dump usb-ls usb_dump "$TRACES"
# S/PDIF: the chip's transmitter captures that prototypes/spdif already writes for its own sigrok check
wait_load
(cd "$ROOT/prototypes/spdif" && nice ionice opam exec --switch=5.3.0 -- dune build ./main.exe 2>&1 \
   && nice ionice ./_build/default/main.exe tx > /dev/null)
cp "$ROOT"/prototypes/spdif/results/sigrok/tx-44k1-60000.{bin,expected} "$ROOT"/prototypes/spdif/results/sigrok/control-44k1-60000.{bin,expected} "$TRACES/spdif/"
podman run --rm localhost/sigrok-judge:0.7.2-1 sigrok-cli --version > "$HERE/results/sigrok-version.txt"
podman run --rm localhost/sigrok-judge:0.7.2-1 sigrok-cli --list-supported > "$HERE/results/sigrok-decoders.txt" 2>/dev/null
"$HERE/judge.py" --ps2-quirk > "$HERE/results/ps2-decoder-quirk.txt"
out=$HERE/results/judge${1:+-rate-${2:-x}}.txt
wait_load
"$HERE/judge.py" --traces "$TRACES" "$@" 2>&1 | tee "$out"
