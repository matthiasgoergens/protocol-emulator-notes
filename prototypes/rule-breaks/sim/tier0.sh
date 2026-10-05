#!/bin/sh
# Tier 0 (PDK bit-cell values) makes strip A 0.20 wide: storage and read transistors W 0.20
# instead of 0.30. Same runs as the gain-cell baselines (../../gain-cell/tricks-thin/results/:
# read-nlv-bar0, read-nlv-bar0.1-vlo0.3, hold-lv-vlo0, hold-hv-vlo0, hold-lv-vlo0.3-bar0.1-v2,
# hold-lv-vlo0.3-bar0.1-park-v2) with WMS=WMR=0.20.
cd "$(dirname "$0")"
./pod.sh read-w20-bar0 cell.py MODE=read VBAR=0 VLO=0 WMS=0.20 WMR=0.20 &
./pod.sh read-w20-bar0.1-vlo0.3 cell.py MODE=read VBAR=0.1 VLO=0.3 LUMP=1 WMS=0.20 WMR=0.20 &
./pod.sh hold-lv-w20-vlo0 cell.py VLO=0 VBAR=0 WMS=0.20 WMR=0.20 &
./pod.sh hold-hv-w20-vlo0 cell.py MW=hv WMS=0.20 WMR=0.20 &
./pod.sh hold-lv-w20-vlo0.3-bar0.1 cell.py VLO=0.3 VBAR=0.1 WMS=0.20 WMR=0.20 &
./pod.sh hold-lv-w20-vlo0.3-bar0.1-park cell.py VLO=0.3 VBAR=0.1 WBLH=0.3 WMS=0.20 WMR=0.20 &
wait
