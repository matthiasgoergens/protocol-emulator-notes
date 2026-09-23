#!/usr/bin/env bash
cd "$(dirname "$0")"
export HWFUZZ_WORKERS=4
/usr/bin/time --format="usb-faulty-units seeded multi-i2s subsets %e s" nice ionice ./_build/default/bench.exe usbfuzz usb-faulty-units full 200000 1 seeded >> results-usb/multi2.txt 2>&1
