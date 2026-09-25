#!/usr/bin/env bash
# Build can_events.ml against master's prototypes/sequencer-ps2-can (exported read-only with git
# archive, so no worktree is created or touched) and write the analyser's event log.
#   ./can_events.sh [REV]   (default: master) -> results/can_events.log
set -o errexit -o nounset -o pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
REV=${1:-master}
SNAP=/var/tmp/multi-proto/can-snap
rm --recursive --force "$SNAP"; mkdir --parents "$SNAP"
TOP=$(git -C "$HERE" rev-parse --show-toplevel)
git -C "$TOP" archive "$REV" prototypes/sequencer-ps2-can prototypes/deadline-sequencer | tar --extract --directory="$SNAP"
D="$SNAP/prototypes/sequencer-ps2-can"
cp "$HERE/can_events.ml" "$D/"
printf '\n(executable\n (name can_events)\n (modules can_events)\n (libraries hardcaml ps2can))\n' >> "$D/dune"
cd "$D"
nice ionice opam exec --switch=5.3.0 -- dune build ./can_events.exe
nice ionice ./_build/default/can_events.exe "$HERE/results/can_events.log" 3 glitch | tee "$HERE/results/can_events.txt"
nice ionice ./_build/default/can_events.exe "$HERE/results/can_events_noerr.log" 3 none | tee --append "$HERE/results/can_events.txt"
echo "built against $(git -C "$HERE" rev-parse "$REV")" >> "$HERE/results/can_events.txt"
