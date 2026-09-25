#!/bin/sh
# level shift with the bar below the data-0 level; park variants with the level shift
cd "$(dirname "$0")"
for v in 0.2 0.3 0.4; do for b in 0 0.1 0.2 0.3; do
  [ "$v" = "$b" ] && continue
  ./pod.sh hold-lv-vlo$v-bar$b cell.py VLO=$v VBAR=$b
done; done
