#!/usr/bin/env bash
# The seed sweep behind the heuristics ledger: 10 seeds per configuration, two campaigns at a time.
cd "$(dirname "$0")"
B=./_build/default/bench.exe
jobs=(
  "lock4 random 50000" "lock4 coverage 50000" "lock4 dictionary 50000" "lock4 i2s 50000" "lock4 i2s+pulse 50000" "lock4 full 50000"
  "lock8 full 200000" "lock8 restarts4 200000" "lock8 islands4 200000"
  "packet random 200000" "packet coverage 200000" "packet dictionary 200000" "packet i2s 200000" "packet i2s+pulse 200000"
  "packet full 200000" "packet restarts4 200000" "packet islands4 200000"
)
for j in "${jobs[@]}"; do
  set -- $j
  nice ionice $B sweep "$1" "$2" "$3" 10 > "results/$1_$2.txt" 2>&1 &
  while [ "$(jobs -r | wc -l)" -ge 2 ]; do sleep 5; done
done
wait
grep --no-filename SUMMARY results/*.txt > results/summary.txt
