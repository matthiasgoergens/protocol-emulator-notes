#!/usr/bin/env bash
# Planted faults in the quarter-clock ISA extension of ../deadline-sequencer/sequencer.ml: the
# lockstep test (interpreter against RTL, pin_sub compared every cycle) must fail on each mutant.
# Restores the original file afterwards. Output: results/isa-controls.txt
set -o errexit -o nounset -o pipefail
here=$(cd "$(dirname "$0")" && pwd)
seq="$here/../deadline-sequencer"
backup=$(mktemp --tmpdir=/var/tmp sequencer.ml.XXXXXX)
cp "$seq/sequencer.ml" "$backup"
trap 'cp "$backup" "$seq/sequencer.ml"; rm --force "$backup"' EXIT
run() { (cd "$seq" && nice ionice opam exec --switch=5.3.0 -- dune exec ./main.exe 2>&1 | grep --extended-regexp 'lockstep|ALL|FAILURES') || true; }
{
  echo "unmutated:"; run
  for m in 's/(of_int ~width:2 p <: q_reg.value)/(of_int ~width:2 p <=: q_reg.value)/' \
           's/(concat_msb \[ nib; select acc 7 4 \])/(concat_msb [ rev4 nib; select acc 7 4 ])/' \
           's/pin_out_n <-- with_pin_bit sho_bit; sub_q <-- q/pin_out_n <-- with_pin_bit sho_bit/'; do
    cp "$backup" "$seq/sequencer.ml"; sed --in-place "$m" "$seq/sequencer.ml"
    if cmp --silent "$seq/sequencer.ml" "$backup"; then echo "mutation did not apply: $m"; exit 1; fi
    echo "mutant $m:"; run
  done
} | tee "$here/results/isa-controls.txt"
