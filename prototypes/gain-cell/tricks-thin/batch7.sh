#!/bin/sh
# finer grid around the best fixed bar: bars 0.05 and 0.15, data-0 levels 0.25 and 0.35
cd "$(dirname "$0")"
for b in 0.05 0.15; do ./pod.sh read-nlv-bar$b cell.py MODE=read VBAR=$b VLO=0.3 LUMP=1; done
for v in 0.25 0.3 0.35; do for b in 0.05 0.1 0.15; do
  [ -f results/hold-lv-vlo$v-bar$b-park.txt ] || ./pod.sh hold-lv-vlo$v-bar$b-park cell.py VLO=$v VBAR=$b WBLH=$v
  [ -f results/hold-lv-vlo$v-bar$b.txt ] || ./pod.sh hold-lv-vlo$v-bar$b cell.py VLO=$v VBAR=$b
done; done
