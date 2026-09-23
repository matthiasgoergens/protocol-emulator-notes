#!/usr/bin/env bash
# The packet part of sweep.sh, restarted after the session running it ended (the lock results were complete).
cd "$(dirname "$0")"
B=./_build/default/bench.exe
for c in random coverage dictionary i2s i2s+pulse full restarts4 islands4; do
  nice ionice $B sweep packet "$c" 200000 10 > "results/packet_$c.txt" 2>&1 &
  while [ "$(jobs -r | wc -l)" -ge 2 ]; do sleep 5; done
done
wait
grep --no-filename SUMMARY results/*.txt > results/summary.txt
