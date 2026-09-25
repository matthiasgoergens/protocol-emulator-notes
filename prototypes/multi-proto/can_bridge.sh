#!/usr/bin/env bash
# I2C <-> CAN with master's real CAN firmware, in three passes (the two cores run different ISA
# variants until they are merged, so they are joined through logs):
#   1 master's RX thread receives the requests on its bus model   -> results/can_bridge_rx.log
#   2 this directory's bridge answers them                         -> results/can_bridge_responses.txt
#   3 master's TX thread sends the answers against request traffic -> results/can_bridge_tx.log
#   ./can_bridge.sh [REV]   (default: master); summary in results/can_bridge_fw.txt
set -o errexit -o nounset -o pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
REV=${1:-master}
SNAP=/var/tmp/multi-proto/can-snap-bridge
rm --recursive --force "$SNAP"; mkdir --parents "$SNAP"
TOP=$(git -C "$HERE" rev-parse --show-toplevel)
git -C "$TOP" archive "$REV" prototypes/sequencer-ps2-can prototypes/deadline-sequencer | tar --extract --directory="$SNAP"
D="$SNAP/prototypes/sequencer-ps2-can"
cp "$HERE/can_bridge_events.ml" "$D/"
printf '\n(executable\n (name can_bridge_events)\n (modules can_bridge_events)\n (libraries hardcaml ps2can))\n' >> "$D/dune"
(cd "$D" && nice ionice opam exec --switch=5.3.0 -- dune build ./can_bridge_events.exe)
R="$HERE/results"
{
  echo "built against $(git -C "$TOP" rev-parse "$REV")"
  nice ionice "$D/_build/default/can_bridge_events.exe" rx "$R/can_bridge_rx.log"
  (cd "$HERE" && nice ionice opam exec --switch=5.3.0 -- dune build ./can_bridge.exe && nice ionice ./_build/default/can_bridge.exe firmware "$R/can_bridge_rx.log" "$R/can_bridge_responses.txt")
  nice ionice "$D/_build/default/can_bridge_events.exe" tx "$R/can_bridge_tx.log" "$R/can_bridge_responses.txt"
} | tee "$R/can_bridge_fw.txt"
