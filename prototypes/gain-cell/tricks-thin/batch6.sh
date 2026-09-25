#!/bin/sh
# write activity on the column: WBL at VDD a fraction D of the time, parked at VLO otherwise
cd "$(dirname "$0")"
for d in 0.01 0.1 0.5; do ./pod.sh hold-lv-vlo0.3-bar0.1-duty$d cell.py VLO=0.3 VBAR=0.1 WBLH=duty:$d:10 TMAX=0.5u CORNERS=mos_ff,mos_tt TEMPS=85; done
