#!/usr/bin/env bash
cd "$(dirname "$0")"
export HWFUZZ_WORKERS=4
for t in usb-faulty-units usb-faulty usb-units; do
  /usr/bin/time --format="$t seeded %e s" nice ionice ./_build/default/bench.exe usbfuzz "$t" full 200000 1 seeded >> results-usb/seeded.txt 2>&1
done
