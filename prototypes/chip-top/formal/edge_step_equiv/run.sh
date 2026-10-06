#!/usr/bin/env bash
# Equivalence of the edge sampler's sub-sample step after the 2026-10-06 timing change against its
# plain form (bin/edge_step.ml), for every input and configuration: Yosys miter and SAT proof.
#   formal/edge_step_equiv/run.sh  -> ../../results/edge-step-equiv.txt
set -o errexit -o nounset -o pipefail
HERE=$(cd "$(dirname "$0")" && pwd); TOP=$HERE/../..
WORK=/var/tmp/chip-top-formal/edge-step-equiv; mkdir --parents "$WORK"
(cd "$TOP" && nice opam exec --switch=5.3.0 -- dune build --root . ./bin/edge_step.exe 2>&1)
"$TOP/_build/default/bin/edge_step.exe" new "$WORK/new.v"
"$TOP/_build/default/bin/edge_step.exe" plain "$WORK/plain.v"
cp "$HERE/ctl_wrap.v" "$WORK/"
sed --in-place 's/module edge_step/module edge_step_new/' "$WORK/new.v"
sed --in-place 's/module edge_step/module edge_step_plain/' "$WORK/plain.v"
run() { podman run --rm --userns=keep-id --volume "$WORK:$WORK" --workdir "$WORK" localhost/librelane-tt:3.1.0.dev3 yosys -p "$1" 2>&1; }
{
  echo "# formal/edge_step_equiv/run.sh, commit $(git -C "$HERE" rev-parse --short HEAD); $(date --iso-8601=seconds)"
  echo "== new against plain (must be PROVED)"
  run "read_verilog new.v plain.v; miter -equiv -flatten -make_assert edge_step_plain edge_step_new miter; hierarchy -top miter; sat -verify -prove-asserts -show-ports miter" \
    | grep --extended-regexp 'SAT proof finished|Solving problem|ERROR' || true
  echo "== control: new against plain with s_holdoff + 1 in place of s_holdoff (must FAIL)"
  run "read_verilog new.v; read_verilog ctl_wrap.v; read_verilog plain.v; miter -equiv -flatten -make_assert edge_step_ctlw edge_step_new miter; hierarchy -top miter; sat -verify -prove-asserts miter" \
    | grep --extended-regexp 'SAT proof finished|Solving problem|ERROR|failed' || true
} | tee "$TOP/results/edge-step-equiv.txt"
