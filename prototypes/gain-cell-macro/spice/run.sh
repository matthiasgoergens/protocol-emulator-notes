#!/bin/sh
# Run one simulation script from ../../gain-cell/retention/ (or from here) in the spice-retention
# container, against one PDK:
#   PDK=cmos5l  IHP-Open-PDK 2bbec755 (the revision Tiny Tapeout pins for sg13cmos5l), with PSP 103
#               compiled by openvaf-r from that revision's psp103.va (103.8.2);
#   PDK=g2old   the ciel IHP-Open-PDK c4b8b4e5 and the PSP 103 (103.6) build that every result in
#               ../../gain-cell/ was made with (read-only mount; used to reproduce an old number).
# Usage: [PDK=cmos5l] [ENVS="A=1 B=2"] run.sh NAME SCRIPT [ARGS...]
# Output: results/NAME.txt here, with the command, the PDK and the commit on its first line.
set -e
here=$(cd "$(dirname "$0")" && pwd)
name=$1; script=$2; shift 2
pdk=${PDK:-cmos5l}
work=/var/tmp/gc-macro/spice/$name
mkdir --parents "$work/osdi" "$here/results"
if [ "$pdk" = cmos5l ]; then
  root=/var/tmp/roundtrip-cmos5l/pdk; sub=ihp-sg13cmos5l
  cp /var/tmp/gc-macro/osdi-cmos5l/psp103.osdi "$work/osdi/"
else
  root=$(realpath "$HOME/.ciel/ihp-sg13g2/ihp-sg13g2/.."); sub=ihp-sg13g2
  cp /var/tmp/spice-gc-thin/osdi/psp103.osdi "$work/osdi/"
fi
if [ -f "$here/$script" ]; then cp "$here/$script" "$work/"; else cp "$here/../../gain-cell/retention/$script" "$work/"; fi
# GMIN=x adds gmin=x to every .options line of the copied script. PSP 103.8.2 (the cmos5l
# revision) adds gmin * V across each source and drain junction (PSP103_module.include line 1726),
# with gmin taken from the simulator (ngspice's default 1e-12 S); PSP 103.6 did not.
if [ -n "$GMIN" ]; then sed --in-place "s/^\.options /.options gmin=$GMIN /" "$work/$(basename "$script")"; fi
# SED='expr' applies one sed expression to the copied script (e.g. to extend a list of levels).
if [ -n "$SED" ]; then sed --in-place "$SED" "$work/$(basename "$script")"; fi
envargs=""
for e in $ENVS; do envargs="$envargs --env $e"; done
{
  echo "# $script $* ENVS=$ENVS GMIN=${GMIN:-default} SED=${SED:-none} PDK=$pdk ($(cat "$root/$sub/SOURCES" 2>/dev/null || echo "$root")) commit $(git -C "$here" rev-parse --short HEAD) $(date --iso-8601=seconds)"
  # shellcheck disable=SC2086
  nice ionice --class 3 podman run --rm $envargs \
    --volume "$root:/pdkroot:ro" --volume "$work:/work" --workdir /work \
    spice-retention:latest sh -c "ln -s /pdkroot/$sub /pdk && python3 $script $*"
} > "$here/results/$name.txt" 2>&1
