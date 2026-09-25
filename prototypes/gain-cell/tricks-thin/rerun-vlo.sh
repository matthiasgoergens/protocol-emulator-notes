#!/bin/sh
# Re-runs every hold result whose data-0 level VLO is above 0 with the corrected level grid
# (cell.py before 11:30 on 2026-09-25 recorded a stored 0 only at levels above VLO). Reads the
# run's environment back from the first line of its results file. Two chains in parallel.
cd "$(dirname "$0")"
list=$(grep --files-with-matches "^# .*run hold-.*--env VLO=0\.[1-9]" results/hold-*.txt | sort)
i=0
for f in $list; do
  run=$(basename "$f" .txt)
  envs=$(head -1 "$f" | grep --only-matching "\-\-env [^ ]*" | sed 's/--env //' | tr '\n' ' ')
  if [ $((i % 2)) -eq 0 ]; then echo "./pod.sh $run cell.py $envs" >> /var/tmp/spice-gc-thin/rerun-a.sh; else echo "./pod.sh $run cell.py $envs" >> /var/tmp/spice-gc-thin/rerun-b.sh; fi
  i=$((i + 1))
done
