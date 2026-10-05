#!/bin/sh
# Checks that the instrumented sequencer is the prototype's current one, in two ways.
# 1. isa.ml and compiler.ml must be symlinks to ../../deadline-sequencer/ (they used to be
#    copies, and a copy went stale when the prototype gained quarter-clock outputs and the I2C
#    clock-stretching fix).
# 2. The committed ../traces/seq.csv must be what the current source produces (the run is
#    deterministic), so a change to the sequencer or its compiler that is not followed by
#    regenerating the trace fails here.
set -e
cd "$(dirname "$0")"
for f in isa.ml compiler.ml; do
  test "$(readlink "$f")" = "../../deadline-sequencer/$f" || { echo "$f is not a symlink to ../../deadline-sequencer/$f"; exit 1; }
  test -e "$f" || { echo "$f: dangling symlink"; exit 1; }
done
echo "sources are the prototype's"
opam exec --switch=5.3.0 -- dune build --root . ./trace.exe
./_build/default/trace.exe | cmp - ../traces/seq.csv || { echo "../traces/seq.csv is stale: rerun trace.exe"; exit 1; }
echo "traces/seq.csv matches the current source"
