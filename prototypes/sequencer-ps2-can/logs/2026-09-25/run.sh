#!/usr/bin/env bash
# Reproduces every number in README.md. Run from prototypes/sequencer-ps2-can.
set -o errexit -o nounset -o pipefail
D=logs/2026-09-25
nice ionice opam exec --switch=5.3.0 -- dune build
{ echo "commit: $(git rev-parse HEAD)"; echo "ocaml: $(opam exec --switch=5.3.0 -- ocamlfind ocamlopt -version)";
  echo "hardcaml: $(opam exec --switch=5.3.0 -- ocamlfind list 2>/dev/null | grep '^hardcaml ' || true)"; date --iso-8601=seconds; } > $D/provenance.txt
./_build/default/lockstep.exe 300 > $D/lockstep.txt
./_build/default/lockstep.exe 300 shared >> $D/lockstep.txt
./_build/default/dbg/crc/crccheck.exe > $D/crccheck.txt
nice ./_build/default/ps2_main.exe 8 > $D/ps2.txt 2>&1 || true
nice ./_build/default/can_main.exe 20 > $D/can-500k.txt 2>&1 || true
nice ./_build/default/can_main.exe 12 27 20 3 > $D/can-556k.txt 2>&1 || true
nice ./_build/default/can_main.exe 12 24 18 2 > $D/can-625k.txt 2>&1 || true
nice ./_build/default/can_main.exe 12 23 17 1 > $D/can-652k.txt 2>&1 || true
SHARED_CFG=1 nice ./_build/default/can_main.exe 8 > $D/can-500k-shared-cfg.txt 2>&1 || true
echo done > $D/done.txt
