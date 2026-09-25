#!/usr/bin/env bash
# Reproduce every result in results/: build, the block checks, the ARP/ping demo judged by the
# scapy host stack, the busy run, and the planted-fault controls. Takes a few minutes.
set -o errexit -o nounset -o pipefail
cd "$(dirname "$0")"
out=results
mkdir --parents "$out/demo"
nice ionice opam exec --switch=5.3.0 -- dune build 2>&1
exe=./_build/default/main.exe
nice "$exe" tx > "$out/tx.txt" 2>&1
{ nice "$exe" crc; nice "$exe" sampler; nice "$exe" rx; } > "$out/rx.txt" 2>&1
host() { nice uv run --quiet --with scapy python host_stack.py "$@"; }
{
  echo "== directed and random requests (seed 1)"
  host gen "$out/demo/requests-1.txt" 1 20
  nice "$exe" node "$out/demo/requests-1.txt" "$out/demo/replies-1.txt"
  host check "$out/demo/requests-1.txt" "$out/demo/replies-1.txt"
  echo "== directed and 100 random requests (seed 2)"
  host gen "$out/demo/requests-2.txt" 2 100
  nice "$exe" node "$out/demo/requests-2.txt" "$out/demo/replies-2.txt"
  host check "$out/demo/requests-2.txt" "$out/demo/replies-2.txt"
  echo "== busy: requests 20 us apart"
  nice "$exe" node-busy "$out/demo/requests-1.txt" "$out/demo/replies-busy.txt" 20
  echo "== planted faults (each must FAIL at the host stack)"
  nice "$exe" node-controls "$out/demo/requests-1.txt" "$out/demo"
  for k in 0 1 2 3 4; do
    echo "-- control $k"
    host check "$out/demo/requests-1.txt" "$out/demo/replies-control$k.txt" > "$out/demo/check-control$k.txt" || true
    grep --extended-regexp --max-count=3 "FAIL" "$out/demo/check-control$k.txt" || true
    grep "verdict" "$out/demo/check-control$k.txt"
  done
} > "$out/demo.txt" 2>&1
grep --extended-regexp "PASS|FAIL|caught|MISSED|verdict" "$out"/tx.txt "$out"/rx.txt "$out"/demo.txt
