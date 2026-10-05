#!/usr/bin/env bash
# Builds hobby_uart_tx.v, Jane Street's Uart.Tx as Verilog, from an unmodified checkout of
# github.com/janestreet/hardcaml_hobby_boards (MIT; nothing of it is committed here).
#   HOBBY   the checkout (default /var/tmp/hardcaml_hobby_boards; cloned there if missing)
#   SWITCH  an opam switch with hardcaml and ppx_hardcaml v0.18~preview (the upstream sources need
#           v0.18): a project-local switch, e.g.
#             opam switch create /var/tmp/formal-hygiene/hobby-switch ocaml-base-compiler.5.3.0 \
#               --repositories=janestreet-bleeding,default --no-install
#             opam install --switch=/var/tmp/formal-hygiene/hobby-switch dune hardcaml ppx_hardcaml ppx_jane
#           (janestreet-bleeding = git+https://github.com/janestreet/opam-repository.git)
#   OUT     output directory (default /var/tmp/formal-hygiene/uart-miter)
# Usage: build_hobby_tx.sh [CLOCKS_PER_BIT]
set -o errexit -o nounset -o pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
HOBBY=${HOBBY:-/var/tmp/hardcaml_hobby_boards}
SWITCH=${SWITCH:-/var/tmp/formal-hygiene/hobby-switch}
OUT=${OUT:-/var/tmp/formal-hygiene/uart-miter}
[ -d "$HOBBY" ] || git clone --depth 1 https://github.com/janestreet/hardcaml_hobby_boards.git "$HOBBY"
B=$OUT/build
mkdir --parents "$B"
for f in uart.ml uart.mli uart_intf.ml uart_types.ml uart_types.mli; do ln --symbolic --force "$HOBBY/src/$f" "$B/$f"; done
cp "$HERE/emit_hobby_tx.ml" "$B/"
echo '(lang dune 3.17)' > "$B/dune-project"
cat > "$B/dune" <<'DUNE'
(executable
 (name emit_hobby_tx)
 (libraries base stdio hardcaml)
 (preprocess (pps ppx_hardcaml ppx_jane)))
DUNE
(cd "$B" && nice ionice opam exec --switch="$SWITCH" -- dune build --root . ./emit_hobby_tx.exe)
"$B/_build/default/emit_hobby_tx.exe" "${1:-20}" > "$OUT/hobby_uart_tx.v"
echo "built $OUT/hobby_uart_tx.v from $HOBBY at $(git -C "$HOBBY" rev-parse HEAD)"
