#!/usr/bin/env bash
# 16-input runs, one process per topology; each depth gets 600 s of solver rounds, each
# topology at most 3 hours in total (CaDiCaL cannot be interrupted mid-solve).
cd "$(dirname "$0")"
for spec in "line 16" "ring 16" "ring+rand1 12" "ring+rand2 12" "hypercube 12" "rand3 12" "rand4 12"; do
  set -- $spec
  timeout 3h nice ionice uv run search.py "$1" 16 "$2" 600 > "out/$1_n16.log" 2> "out/$1_n16.err" &
done
wait
