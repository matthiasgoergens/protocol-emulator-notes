#!/bin/sh
# KLayout DRC with IHP's sg13cmos5l deck (IHP-Open-PDK 2bbec755, the revision Tiny Tapeout pins),
# run in the pinned LibreLane image (KLayout 0.30.9). Usage: drc.sh GDS TOPCELL NAME
# Writes drc/NAME.log here (every rule with its count, and the verdict); the run directory is /var/tmp/gc-macro/drc/NAME.
# Density is off (--no_density): it is a whole-chip rule, checked by the flow on the test top.
set -e
here=$(cd "$(dirname "$0")" && pwd)
gds=$(realpath "$1"); top=$2; name=$3
pdk=/var/tmp/roundtrip-cmos5l/pdk
run=/var/tmp/gc-macro/drc/$name
rm --recursive --force "$run"
mkdir --parents "$run"
cp "$gds" "$run/in.gds"
nice ionice --class 3 podman run --rm --volume "$pdk:/pdk:ro" --volume "$run:/work" --workdir /work \
  localhost/librelane-tt:3.1.0.dev3 \
  python3 /pdk/ihp-sg13cmos5l/libs.tech/klayout/tech/drc/run_drc.py --path /work/in.gds \
    --topcell "$top" --run_dir /work/out --no_density --mp 4 > "$run/full.log" 2>&1 || true
# the per-table rule counts are in the run directory; keep the summary and every rule line here
{ grep --no-filename --extended-regexp "^Rule |Violated rules|Check Passed|Check Failed|tables selected|KLayout version|IHP-SG13CMOS5L|Running" "$run/full.log" "$run"/out/*.log; } > "$here/drc/$name.log" || true
grep --extended-regexp "Violated rules|Check Passed|Check Failed" "$here/drc/$name.log" || true
