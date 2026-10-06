#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Generate the combined chip's Verilog (module chip_tt) from prototypes/chip-top's Hardcaml.
# Build output, never committed, as regen.sh does for the sequencer core.
#   tt/scripts/regen_chip.sh [OUT] [MEMORIES] [SEGMENT_SIZES] [PROG_WORDS]
#   defaults: tt/src/chip_tt.v macros 1,1,1,1 512
# OUT is replaced only when its contents change. OPAM_SWITCH as in regen.sh.
set -o errexit -o nounset -o pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
CHIP=$HERE/../../prototypes/chip-top
OUT=${1:-$HERE/../src/chip_tt.v}
MEM=${2:-macros} SIZES=${3:-1,1,1,1} WORDS=${4:-512}
SWITCH=${OPAM_SWITCH-5.3.0}
SCRATCH=$(mktemp --directory --tmpdir="${TMPDIR:-/var/tmp}" tt-regen-chip.XXXXXX)
trap 'rm --recursive --force "$SCRATCH"' EXIT
(cd "$CHIP" && nice ionice opam exec ${SWITCH:+--switch="$SWITCH"} -- dune build --root . ./bin/emit.exe 2>&1)
"$CHIP/_build/default/bin/emit.exe" "$SCRATCH/generated.v" "$MEM" "$SIZES" "$WORDS"
lines=$(wc --lines < "$SCRATCH/generated.v")
if [ "$lines" -lt 1000 ]; then echo "regen_chip: generator produced only $lines lines" >&2; exit 2; fi
if cmp --silent "$SCRATCH/generated.v" "$OUT" 2>/dev/null; then
  echo "regen_chip: $OUT up to date ($lines lines)"
else
  cp "$SCRATCH/generated.v" "$OUT"; echo "regen_chip: wrote $OUT ($lines lines)"
fi
