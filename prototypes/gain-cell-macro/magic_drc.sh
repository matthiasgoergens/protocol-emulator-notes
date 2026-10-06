#!/bin/sh
# Magic DRC (the sg13cmos5l techfile of IHP-Open-PDK 2bbec755, Magic 8.3.674 in the pinned
# LibreLane image) on one GDS cell, flattened, as LibreLane's Magic.DRC sees a macro.
# Usage: magic_drc.sh GDS TOPCELL NAME; writes drc/NAME.magic.log here.
set -e
here=$(cd "$(dirname "$0")" && pwd)
gds=$(realpath "$1"); top=$2; name=$3
pdk=/var/tmp/roundtrip-cmos5l/pdk
run=/var/tmp/gc-macro/magic/$name
rm --recursive --force "$run"; mkdir --parents "$run"; cp "$gds" "$run/in.gds"
cat > "$run/drc.tcl" <<TCL
gds read /work/in.gds
load $top
select top cell
drc euclidean on
drc style drc(full)
drc check
drc catchup
set n [drc list count total]
puts "MAGIC_DRC_TOTAL \$n"
foreach {why boxes} [drc listall why] { puts "MAGIC_DRC_RULE [llength \$boxes] \$why" }
quit -noprompt
TCL
nice ionice --class 3 podman run --rm --volume "$pdk:/pdk:ro" --volume "$run:/work" --workdir /work \
  localhost/librelane-tt:3.1.0.dev3 \
  magic -dnull -noconsole -rcfile /pdk/ihp-sg13cmos5l/libs.tech/magic/ihp-sg13cmos5l.magicrc /work/drc.tcl \
  < /dev/null > "$run/magic.log" 2>&1 || true
grep --extended-regexp 'MAGIC_DRC|rror' "$run/magic.log" > "$here/drc/$name.magic.log" || true
cat "$here/drc/$name.magic.log"
