#!/bin/sh
# Model vs Hardcaml RTL in lockstep on the DAC system run (setup, pump, both channels), every
# state bit every clock; one simulation at a time, niced, waiting while the load is above 20.
set -e
cd "$(dirname "$0")/sim"
exe=./_build/default/main.exe
for spec in "o2 3000000 8000" "o3 3000000 6000" "o3 1000000 11000" "o4 3000000 3500" "o4 1000000 6000"; do
  while [ "$(cut --delimiter=' ' --fields=1 /proc/loadavg | cut --delimiter=. --fields=1)" -ge 20 ]; do sleep 30; done
  set -- $spec
  echo "== rtl-lockstep $1 clocks $2 amplitude $3"
  nice ionice $exe rtl-lockstep "$1" "$2" "$3"
done
