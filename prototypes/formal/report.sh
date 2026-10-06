#!/usr/bin/env bash
# One line per property and per cover, from the result files of every engine (README.md,
# "Per-property report"): the bounded model checks and induction steps (results/bmc.txt), power-up
# determinism (results/powerup.txt) and the UART miter (results/uart-miter.txt). Writes
# results/summary.txt; runs nothing. Planted faults and controls are marked, so that FAILED or
# VACUOUS there is the expected answer and PROVED would be the alarm.
set -o errexit -o nounset -o pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
cd "$HERE"
section() {   # title, file, planted-pattern
  echo "== $1 ($2)"
  if [ ! -f "$2" ]; then echo "  (no result file)"; return; fi
  grep --extended-regexp '^(PROPERTY|COVER|DECLARATION)|^  COVER' "$2" | sed 's/^  //' | while IFS= read -r line; do
    if [[ $line =~ $3 ]]; then echo "  [control] $line"; else echo "  $line"; fi
  done
}
{
  echo "# command: report.sh (from the result files; nothing re-run)"
  echo "# commit: $(git rev-parse HEAD)$(git diff --quiet HEAD -- . || echo ' (with uncommitted changes)')"
  echo "# date: $(date --iso-8601=seconds)"
  echo "# not here: section 3 (Kind 2, results/kind2.txt), section 4 (RTL against specification,"
  echo "#   results/equiv-*.txt; its non-vacuity evidence is the 28 of 28 planted bugs); the whole-system"
  echo "#   a-protocols, which no longer finishes, is replaced by its split (Findings 4, results/a-protocols.txt)"
  section "bounded model checks and induction steps" results/bmc.txt 'planted|without-ownership|may-write|declared-0-only'
  section "a-protocols, split (Findings 4)" results/a-protocols.txt 'planted'
  section "power-up determinism" results/powerup.txt 'u_cfg|u_dl|vacuity_control'
  section "UART miter against hardcaml_hobby_boards Uart.Tx" results/uart-miter.txt 'constant|stretch|flip'
} > results/summary.txt.tmp
counts=$(grep --extended-regexp '^  PROPERTY' results/summary.txt.tmp | sed --regexp-extended 's/.*: (PROVED|FAILED|VACUOUS|UNDECIDED|ERROR).*/\1/' | sort | uniq --count | tr '\n' ' ')
controls=$(grep --extended-regexp '^  \[control\] PROPERTY' results/summary.txt.tmp | sed --regexp-extended 's/.*: (PROVED|FAILED|VACUOUS|UNDECIDED|ERROR).*/\1/' | sort | uniq --count | tr '\n' ' ')
cp results/summary.txt.tmp results/summary.txt
{
  echo "== totals"
  echo "  properties: $counts"
  echo "  controls (planted faults, must not be PROVED): $controls"
} >> results/summary.txt
rm --force results/summary.txt.tmp
cat results/summary.txt
