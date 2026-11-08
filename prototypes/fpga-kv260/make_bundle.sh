#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Pack what a board run needs that is not in the repository, so that whoever has the board needs
# neither OCaml nor the PDK: the chip's generated Verilog (tt/src/chip_tt.v, build output, never
# committed), the demo's frames and metadata, and the simulation's recorded run of those frames,
# which a board run should reproduce exactly.
#
#   ./make_bundle.sh [WORK_DIR]     after ./run_sim.sh WORK_DIR; writes WORK_DIR/kv260-bundle-<commit>.tar.gz
set -o errexit -o nounset -o pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
W=${1:-/var/tmp/fpga-kv260}
commit=$(git -C "$HERE" rev-parse --short=12 HEAD)
if ! git -C "$HERE" diff --quiet HEAD -- "$HERE" "$HERE/../chip-top" "$HERE/../../tt"; then
  echo "uncommitted changes under fpga-kv260, chip-top or tt: commit first, so the bundle names a commit" >&2
  exit 1
fi
B=$W/kv260-bundle-$commit
rm --recursive --force "$B"
mkdir --parents "$B"
cp "$HERE/../../tt/src/chip_tt.v" "$B/"
cp "$W/ops/ds.ops" "$W/ops/ds.meta" "$B/"
for s in info samples trace; do cp "$W/sim-ds.$s" "$B/sim-ds.$s"; done
cp "$W/check-sim-ds.txt" "$B/"
cat > "$B/README.txt" <<EOF
KV260 test bench bundle, from protocol-emulator-notes commit $commit.

chip_tt.v      the chip's Verilog, generated from prototypes/chip-top by tt/scripts/regen_chip.sh;
               copy it to tt/src/ in a checkout of that commit before running vivado/build.tcl
ds.ops         the UART, SPI and I2C demo as player frames (prototypes/chip-top/bin/fpga_ops.ml)
ds.meta        what host/check.py expects of that demo
sim-ds.*       the simulated run of ds.ops (prototypes/fpga-kv260/run_sim.sh); a board run with
               nothing on the I2C pins should give identical files:
                 diff sim-ds.trace board-ds.trace
check-sim-ds.txt  host/check.py's verdict on the simulated run
EOF
(cd "$B" && sha256sum -- * > SHA256SUMS)
tar --create --gzip --file "$B.tar.gz" --directory "$W" "kv260-bundle-$commit"
echo "wrote $B.tar.gz"
