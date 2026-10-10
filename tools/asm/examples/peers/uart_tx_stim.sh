#!/usr/bin/env bash
# Regenerates ../uart_rx.stim: Alex Forencich's uart_tx (tools/peers/vendor/verilog-uart, checked
# against its SHA256SUMS) sends 48 69 21 0a 00 ff 55 a5 back to back at 64 clocks a bit, in
# Icarus Verilog. Usage: examples/peers/uart_tx_stim.sh (from anywhere).
set -o errexit -o nounset -o pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
VENDOR=$HERE/../../../peers/vendor/verilog-uart
(cd "$VENDOR" && sha256sum --check --quiet SHA256SUMS)
TMP=$(mktemp --directory --tmpdir=/var/tmp uart-stim.XXXXXX)
trap 'rm --recursive --force "$TMP"' EXIT
iverilog -g2005 -o "$TMP/sim" "$VENDOR/uart_tx.v" "$HERE/uart_tx_stim.v"
nice ionice vvp "$TMP/sim" "+OUT=$HERE/../uart_rx.stim" > /dev/null
echo "wrote $HERE/../uart_rx.stim ($(grep --count --invert-match '^#' "$HERE/../uart_rx.stim") changes)"
