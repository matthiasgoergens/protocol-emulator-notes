#!/bin/sh
# Runs the lines "NAME|ENVS" of a batch file, P at a time: each is run.sh NAME SCRIPT MODE.
# Usage: batch.sh FILE MODE P [SCRIPT (default gc.py)]
here=$(cd "$(dirname "$0")" && pwd)
script=${4:-gc.py}
grep --invert-match '^#' "$1" |
  xargs --max-procs="${3:-4}" --replace=LINE sh -c 'l="LINE"; n=${l%%|*}; e=${l#*|}; ENVS="$e" '"$here"'/run.sh "$n" '"$script"' '"$2"' > /dev/null'
