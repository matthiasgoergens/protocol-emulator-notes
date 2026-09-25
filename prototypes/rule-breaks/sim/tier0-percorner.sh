#!/bin/sh
# Tier 0 (W 0.20 storage/read) with the per-corner bar of the level-shifted scheme
# (../../gain-cell/README.md: VBAR 0 V at ss/27 C, 0.15 V at ff/85 C; VLO 0.3 V): the two corners
# that bound it. Baselines at W 0.30: ../../gain-cell/tricks-thin/results/read-nlv-bar0.15-vlo0.3.txt,
# hold-lv-vlo0.3-bar0.15*.txt, read-nlv-bar0.txt with hold-lv-vlo0.3-bar0*.txt.
cd "$(dirname "$0")"
./pod.sh read-w20-bar0-vlo0.3-ss27 cell.py MODE=read VBAR=0 VLO=0.3 LUMP=1 WMS=0.20 WMR=0.20 CORNERS=mos_ss TEMPS=27 &
./pod.sh hold-lv-w20-vlo0.3-bar0-ss27 cell.py VLO=0.3 VBAR=0 WMS=0.20 WMR=0.20 CORNERS=mos_ss TEMPS=27 &
./pod.sh read-w20-bar0.15-vlo0.3-ff85 cell.py MODE=read VBAR=0.15 VLO=0.3 LUMP=1 WMS=0.20 WMR=0.20 CORNERS=mos_ff TEMPS=85 &
./pod.sh hold-lv-w20-vlo0.3-bar0.15-ff85 cell.py VLO=0.3 VBAR=0.15 WMS=0.20 WMR=0.20 CORNERS=mos_ff TEMPS=85 &
./pod.sh hold-lv-w20-vlo0.3-bar0.15-park-ff85 cell.py VLO=0.3 VBAR=0.15 WBLH=0.3 WMS=0.20 WMR=0.20 CORNERS=mos_ff TEMPS=85 &
wait
