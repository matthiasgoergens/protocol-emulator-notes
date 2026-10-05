#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Regenerate tt/src/deadline_sequencer_v2.v from the Hardcaml source in prototypes/sequencer-v2.
#   tt/scripts/regen.sh            overwrite tt/src/deadline_sequencer_v2.v
#   tt/scripts/regen.sh --check    write nothing; exit 1 and show a diff if the committed file differs
# The idea of failing on drift between committed generated Verilog and its generator is from
# TeslaCoilerOW/ttihp-protocol-emulator ("make check-generated"); this is our own implementation.
set -o errexit -o nounset -o pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
SEQ=$HERE/../../prototypes/sequencer-v2
COMMITTED=$HERE/../src/deadline_sequencer_v2.v
SWITCH=${OPAM_SWITCH:-5.3.0}
SCRATCH=$(mktemp --directory --tmpdir=/var/tmp tt-regen.XXXXXX)
trap 'rm --recursive --force "$SCRATCH"' EXIT
(cd "$SEQ" && nice ionice opam exec --switch="$SWITCH" -- dune build --root . ./emit2.exe 2>&1)
"$SEQ/_build/default/emit2.exe" "$SCRATCH/generated.v"
# An empty or tiny output would make a vacuous "match"; refuse it.
lines=$(wc --lines < "$SCRATCH/generated.v")
if [ "$lines" -lt 1000 ]; then echo "regen: generator produced only $lines lines" >&2; exit 2; fi
case ${1:-} in
  --check)
    if diff --unified "$COMMITTED" "$SCRATCH/generated.v" > "$SCRATCH/drift.diff"; then
      echo "check-generated: OK, $COMMITTED matches the Hardcaml source ($lines lines)"
    else
      head --lines=40 "$SCRATCH/drift.diff"
      echo "check-generated: FAIL, committed Verilog differs from what Hardcaml generates; run tt/scripts/regen.sh" >&2
      exit 1
    fi ;;
  "") cp "$SCRATCH/generated.v" "$COMMITTED"; echo "regen: wrote $COMMITTED ($lines lines)" ;;
  *) echo "usage: regen.sh [--check]" >&2; exit 64 ;;
esac
