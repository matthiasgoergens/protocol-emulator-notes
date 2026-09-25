#!/bin/sh
# WBL parked at the data-0 level between writes (an idle column), every level-shift combination
cd "$(dirname "$0")"
for v in 0.1 0.2 0.3 0.4; do for b in 0 0.1 0.2 0.3; do
  [ -f results/hold-lv-vlo$v-bar$b-park.txt ] && continue
  ./pod.sh hold-lv-vlo$v-bar$b-park cell.py VLO=$v VBAR=$b WBLH=$v
done; done
