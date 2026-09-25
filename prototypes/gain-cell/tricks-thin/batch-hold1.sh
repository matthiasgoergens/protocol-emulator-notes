#!/bin/sh
# first hold matrix: level shift, stacks, WBL parking (see NOTES in README of tricks-thin)
cd "$(dirname "$0")"
for v in 0 0.1 0.2 0.3 0.4; do ./pod.sh hold-lv-vlo$v cell.py VLO=$v VBAR=$v; done
for m in hv lv2 lvhv hvlv lv2g fb; do ./pod.sh hold-$m-vlo0 cell.py MW=$m; done
for p in 0.1 0.2 0.3 0.6; do ./pod.sh hold-lv-park$p cell.py WBLH=$p; done
