#!/bin/sh
# PMOS storage (read and hold), the bar pulled to 0 during a read, and stacks/feedback combined
# with the level shift
cd "$(dirname "$0")"
./pod.sh read-plv-bar1.2 cell.py MODE=read MS=plv VBAR=1.2 &
./pod.sh read-plv-bar1.0 cell.py MODE=read MS=plv VBAR=1.0 &
./pod.sh read-nlv-bar0.2-rbar0 cell.py MODE=read VBAR=0.2 VLO=0.3 RBAR=0 &
(
for b in 1.2 1.0; do ./pod.sh hold-plv-bar$b cell.py MS=plv VBAR=$b; done
for m in lv2 fb hv; do ./pod.sh hold-$m-vlo0.3-bar0.2 cell.py MW=$m VLO=0.3 VBAR=0.2; done
./pod.sh hold-lv-vlo0.3-bar0.2-park cell.py VLO=0.3 VBAR=0.2 WBLH=0.3
./pod.sh hold-lv-vlo0.2-bar0.1-park cell.py VLO=0.2 VBAR=0.1 WBLH=0.2
./pod.sh hold-lv-vlo0.1-bar0-park cell.py VLO=0.1 VBAR=0 WBLH=0.1
./pod.sh hold-lv-vlo0.1-bar0 cell.py VLO=0.1 VBAR=0
./pod.sh hold-plvw-bar0.3 cell.py MW=plvw VBAR=0.3
./pod.sh hold-plvw-vhi0.9-bar0.3 cell.py MW=plvw VBAR=0.3 VHI=0.9
./pod.sh hold-lv-gd-vlo0.3-bar0.2 cell.py GD=1 VLO=0.3 VBAR=0.2
./pod.sh read-nlv-gd-bar0.2 cell.py MODE=read GD=1 VLO=0.3 VBAR=0.2
) &
wait
