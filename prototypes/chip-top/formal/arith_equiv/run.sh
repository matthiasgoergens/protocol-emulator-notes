#!/usr/bin/env bash
# The PE's prefix adder and comparisons against Hardcaml's operators, for every input: Yosys
# miter and SAT proof (bin/arith_equiv.ml).  formal/arith_equiv/run.sh -> ../../results/arith-equiv.txt
set -o errexit -o nounset -o pipefail
HERE=$(cd "$(dirname "$0")" && pwd); TOP=$HERE/../..
WORK=/var/tmp/chip-top-formal/arith-equiv; mkdir --parents "$WORK"
(cd "$TOP" && nice opam exec --switch=5.3.0 -- dune build --root . ./bin/arith_equiv.exe 2>&1)
"$TOP/_build/default/bin/arith_equiv.exe" prefix "$WORK/prefix.v"
"$TOP/_build/default/bin/arith_equiv.exe" plain "$WORK/plain.v"
sed --in-place 's/module arith/module arith_prefix/' "$WORK/prefix.v"
sed --in-place 's/module arith/module arith_plain/' "$WORK/plain.v"
cp "$HERE/ctl_wrap.v" "$WORK/"
run() { podman run --rm --userns=keep-id --volume "$WORK:$WORK" --workdir "$WORK" localhost/librelane-tt:3.1.0.dev3 yosys -p "$1" 2>&1; }
# verdict EXPECTED SCRIPT: runs Yosys, prints its proof lines, and fails unless the proof line says EXPECTED.
# Yosys exits 1 when a control fails to prove (as it should), so its status is not the verdict; a missing
# image or a crashed Yosys prints no proof line and so fails here instead of passing as "no output"
verdict() {
  local want=$1 out
  out=$(run "$2") || true
  printf '%s\n' "$out" | grep --extended-regexp 'SAT proof finished|Solving problem|ERROR' || true
  printf '%s\n' "$out" | grep --quiet "SAT proof finished - $want" || { echo "NOT RUN or wrong verdict: expected '$want'"; exit 1; }
}
{
  echo "# formal/arith_equiv/run.sh, commit $(git -C "$HERE" rev-parse --short HEAD); $(date --iso-8601=seconds)"
  echo "== prefix against plain (must be PROVED)"
  verdict "no model found: SUCCESS" "read_verilog prefix.v plain.v; miter -equiv -flatten -make_assert arith_plain arith_prefix miter; hierarchy -top miter; sat -verify -prove-asserts miter"
  echo "== control: plain with the carry-in tied to 0 against prefix (must FAIL)"
  verdict "model found: FAIL" "read_verilog prefix.v plain.v ctl_wrap.v; miter -equiv -flatten -make_assert arith_ctl arith_prefix miter; hierarchy -top miter; sat -verify -prove-asserts miter"
} | tee "$TOP/results/arith-equiv.txt"
