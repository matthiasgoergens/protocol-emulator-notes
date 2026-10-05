#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Generate the sequencer-v2 core's Verilog from its Hardcaml source (prototypes/sequencer-v2).
# The Verilog is build output and is not committed: tt/test/Makefile and
# prototypes/sequencer-v2/synth/synth.sh call this before they read it.
#   tt/scripts/regen.sh [OUT]   default OUT: tt/src/deadline_sequencer_v2.v
# OUT is replaced only when its contents change, so make does not rebuild needlessly.
# OPAM_SWITCH names the opam switch to build in (default 5.3.0, this machine's); set it empty to
# use the current environment, as CI does.
set -o errexit -o nounset -o pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
SEQ=$HERE/../../prototypes/sequencer-v2
OUT=${1:-$HERE/../src/deadline_sequencer_v2.v}
SWITCH=${OPAM_SWITCH-5.3.0}
SCRATCH=$(mktemp --directory --tmpdir="${TMPDIR:-/var/tmp}" tt-regen.XXXXXX)
trap 'rm --recursive --force "$SCRATCH"' EXIT
(cd "$SEQ" && nice ionice opam exec ${SWITCH:+--switch="$SWITCH"} -- dune build --root . ./emit2.exe 2>&1)
"$SEQ/_build/default/emit2.exe" "$SCRATCH/generated.v"
# A tiny output means a broken generator; refuse it rather than hand a stub to the flow.
lines=$(wc --lines < "$SCRATCH/generated.v")
if [ "$lines" -lt 1000 ]; then echo "regen: generator produced only $lines lines" >&2; exit 2; fi
if cmp --silent "$SCRATCH/generated.v" "$OUT" 2>/dev/null; then
  echo "regen: $OUT up to date ($lines lines)"
else
  cp "$SCRATCH/generated.v" "$OUT"; echo "regen: wrote $OUT ($lines lines)"
fi
