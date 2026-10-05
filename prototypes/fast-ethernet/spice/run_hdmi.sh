#!/bin/bash
# Pad speed batch for HDMI and faster Ethernet (2026-10-05): bit-rate eyes into 5/10 pF, an HDMI
# pair with 270 or 120 ohm series resistors, and IOPadIn at 125 MHz. At most 2 simulations at
# once; each waits while the 1-minute load average is above 20 (shared host).
here=$(dirname "$(readlink --canonicalize "$0")")
cases=${CASES:-"rcap10_r120 rcap10_r240 rcap10_r250 rcap5_r250 hdmi_270_r120 hdmi_270_r240 hdmi_270_r250 hdmi_120_r120 hdmi_120_r250 inf_125 inac_300_125 inac_600_125 inac_300_62.5"}
for c in $cases; do for k in tt ss ff; do for t in 27 85; do echo "$c $k $t"; done; done; done |
  xargs --max-procs=2 --max-lines=1 bash -c '
    while [ "$(cut --delimiter=" " --fields=1 /proc/loadavg | cut --delimiter=. --fields=1)" -ge 20 ]; do sleep 30; done
    d=/var/tmp/fast-eth/pads/$0-$1-$2; rm --recursive --force $d
    python3 '"$here"'/padsim.py $0 $1 $2 $d'
