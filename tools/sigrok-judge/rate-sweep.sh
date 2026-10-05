#!/usr/bin/env bash
# Re-judges the traces as slower logic analysers would have recorded them (sample and hold at the
# analyser's rate), teeth included.  Needs the traces made by run.sh.  -> results/judge-rates.txt
set -o errexit -o nounset -o pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
out=$HERE/results/judge-rates.txt
: > "$out"
sweep() {   # cases, rates...
  local cases=$1; shift
  for r in "$@"; do
    echo "=== cases $cases at $r Hz" >> "$out"
    nice ionice "$HERE/judge.py" --traces "$HERE/traces" --only "$cases" --rate "$r" 2>&1 \
      | grep --invert-match --extended-regexp '^# (command|commit|date)|^protocols with|^  10BASE|^$' >> "$out" || true
  done
}
sweep uart,spi,i2c,ps2 500000 250000 125000
sweep can 10000000 5000000 2500000
sweep usb-ls 12000000 7500000 6000000
sweep spdif 120000000 48000000 24000000
