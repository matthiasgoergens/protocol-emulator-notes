#!/usr/bin/env bash
# Seed sweep for ledger entry 11: which mechanism gets the seeded USB campaign through SET_ADDRESS
# to the planted fault. One campaign at a time, 4 workers.
cd "$(dirname "$0")"
export HWFUZZ_WORKERS=4
for seed in 1 2 3; do
  for c in single full multi vp+conj vp+conj+gated; do
    nice ionice ./_build/default/bench.exe usbfuzz usb-faulty-units "$c" 200000 "$seed" seeded >> results-sweep/usb.txt 2>&1
  done
done
