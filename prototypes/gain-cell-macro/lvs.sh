#!/bin/sh
# KLayout LVS with IHP's sg13cmos5l deck (IHP-Open-PDK 2bbec755), in the pinned LibreLane image.
# Usage: lvs.sh GDS NETLIST TOPCELL NAME [extra run_lvs.py options]
# Writes lvs/NAME.log here and keeps the extracted netlist as lvs/NAME.extracted.cir; the run
# directory is /var/tmp/gc-macro/lvs/NAME.
set -e
here=$(cd "$(dirname "$0")" && pwd)
gds=$(realpath "$1"); net=$(realpath "$2"); top=$3; name=$4; shift 4
pdk=/var/tmp/roundtrip-cmos5l/pdk
run=/var/tmp/gc-macro/lvs/$name
rm --recursive --force "$run"
mkdir --parents "$run"
cp "$gds" "$run/in.gds"; cp "$net" "$run/in.cir"
nice ionice --class 3 podman run --rm --volume "$pdk:/pdk:ro" --volume "$run:/work" --workdir /work \
  localhost/librelane-tt:3.1.0.dev3 \
  python3 /pdk/ihp-sg13cmos5l/libs.tech/klayout/tech/lvs/run_lvs.py --layout /work/in.gds \
    --netlist /work/in.cir --topcell "$top" --run_dir /work/out "$@" > "$here/lvs/$name.log" 2>&1 || true
ext=$(find "$run/out" -name '*_extracted.cir' | head --lines=1)
[ -n "$ext" ] && cp "$ext" "$here/lvs/$name.extracted.cir"
grep --extended-regexp -i "congratulations|don't match|do not match|mismatch|netlists match|LVS.*(clean|fail|pass)" "$here/lvs/$name.log" || true
