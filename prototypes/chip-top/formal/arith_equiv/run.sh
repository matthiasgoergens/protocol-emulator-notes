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
{
  echo "# formal/arith_equiv/run.sh, commit $(git -C "$HERE" rev-parse --short HEAD); $(date --iso-8601=seconds)"
  echo "== prefix against plain (must be PROVED)"
  run "read_verilog prefix.v plain.v; miter -equiv -flatten -make_assert arith_plain arith_prefix miter; hierarchy -top miter; sat -verify -prove-asserts miter" \
    | grep --extended-regexp 'SAT proof finished|Solving problem|ERROR' || true
  echo "== control: plain with the carry-in tied to 0 against prefix (must FAIL)"
  run "read_verilog prefix.v plain.v ctl_wrap.v; miter -equiv -flatten -make_assert arith_ctl arith_prefix miter; hierarchy -top miter; sat -verify -prove-asserts miter" \
    | grep --extended-regexp 'SAT proof finished|Solving problem|ERROR' || true
} | tee "$TOP/results/arith-equiv.txt"
