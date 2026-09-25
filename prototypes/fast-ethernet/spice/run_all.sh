#!/bin/bash
# Runs every pad case at every corner, at most 4 simulations at once (the host is shared).
# Output: /var/tmp/fast-eth/pads/<case>-<corner>-<temp>/{tb.cir,io.spi,ngspice.log,out.dat}
set -o nounset
here=$(dirname "$(readlink --canonicalize "$0")")
cases=${CASES:-"toggle eye_cap5 eye_cap10 eye_sfp eye_tx in_dc in_full in_ac_300_0 in_ac_150_0 in_ac_75_0"}
for c in $cases; do for k in tt ss ff; do for t in 27 85; do
  echo "$c $k $t"
done; done; done | xargs --max-procs=4 --max-lines=1 bash -c 'python3 '"$here"'/padsim.py $0 $1 $2 /var/tmp/fast-eth/pads/$0-$1-$2'
