#!/usr/bin/env bash
# Longer USB campaigns: 200,000 executions each, 4 workers, one at a time.
cd "$(dirname "$0")"
export HWFUZZ_WORKERS=4
for t in usb usb-faulty; do
  /usr/bin/time --format="$t %e s" nice ionice ./_build/default/bench.exe usbfuzz "$t" full 200000 1 >> results-usb/long2.txt 2>&1
done
