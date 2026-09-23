#!/usr/bin/env bash
# USB milestones: with checksum repair, without (raw line), and against the planted fault.
# 2 workers and one campaign at a time: the host is busy.
cd "$(dirname "$0")"
export HWFUZZ_WORKERS=2
for t in usb usb-raw usb-faulty; do
  nice ionice ./_build/default/bench.exe usbfuzz "$t" full 5000 1 >> results-usb/milestones.txt 2>&1
done
