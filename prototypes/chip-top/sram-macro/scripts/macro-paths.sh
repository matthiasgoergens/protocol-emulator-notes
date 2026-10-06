#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Worst reported setup (max.rpt) and hold (min.rpt) paths that start or end at a macro instance,
# per corner, from a LibreLane run's post-PnR STA step.  macro-paths.sh RUN_DIR [INSTANCE_REGEX]
run=${1:?usage: macro-paths.sh RUN_DIR [INSTANCE_REGEX]}; re=${2:-sram}
for d in "$run"/*-openroad-stapostpnr/nom_*; do
  c=$(basename "$d")
  for k in max min; do
    echo "== $c $k (slack, start -> end)"
    awk '/^Startpoint/{s=$2} /^Endpoint/{e=$2} /slack \(/{print $1, s, "->", e}' "$d/$k.rpt" \
      | grep --extended-regexp "$re" | sort --numeric-sort | head --lines=3
  done
done
