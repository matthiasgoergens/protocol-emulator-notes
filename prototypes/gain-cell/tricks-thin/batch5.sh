#!/bin/sh
# Giterman-style feedback (NMOS version) with the level shift: parked and worst-case WBL
cd "$(dirname "$0")"
for b in 0 0.1 0.2; do ./pod.sh hold-fb-vlo0.3-bar$b-park cell.py MW=fb VLO=0.3 VBAR=$b WBLH=0.3; done
for b in 0 0.1; do ./pod.sh hold-fb-vlo0.3-bar$b cell.py MW=fb VLO=0.3 VBAR=$b; done
for b in 0 0.1; do ./pod.sh hold-fb-vlo0.2-bar$b-park cell.py MW=fb VLO=0.2 VBAR=$b WBLH=0.2; done
./pod.sh hold-fb-vlo0-park cell.py MW=fb WBLH=0
