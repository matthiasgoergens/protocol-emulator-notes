#!/bin/bash
# Usage: submit-when-free.sh RUN_DIR TOP NAME
# Waits until Aristotle accepts a new project (one project in progress at a time on this
# account), submits RUN_DIR/upload with RUN_DIR/prompt.txt, then waits for the result.
set -u
dir=$1 top=$2 name=$3
cd "$dir" || exit 1
while true; do
  aristotle submit --prompt-file prompt.txt --project-dir upload --top "$top" --name "$name" \
    --no-questions --json > submit.json 2> submit.err
  if grep --quiet 'too many projects in progress' submit.json submit.err; then
    echo "$(date --iso-8601=seconds) slot busy, waiting" >> queue.log; sleep 120; continue
  fi
  break
done
id=$(grep --only-matching --max-count=1 -E "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}" submit.json | head --lines=1)
echo "$(date --iso-8601=seconds) submitted id=$id" >> queue.log
[ -n "$id" ] || { echo "no project id" >> queue.log; exit 2; }
aristotle show "$id" --non-interactive > result.json 2> result.err
echo "$(date --iso-8601=seconds) done exit=$?" >> queue.log
aristotle properties "$id" > properties.txt 2>&1
aristotle download "$id" --destination result/ > download.log 2>&1
