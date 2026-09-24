#!/usr/bin/env bash
cd "$(dirname "$0")"
export HWFUZZ_WORKERS=4
/usr/bin/time --format="usb-faulty-units control real device seeded next-unit %e s" nice ionice ./_build/default/bench.exe usbfuzz usb-units multi 200000 1 seeded >> results-usb/control.txt 2>&1
