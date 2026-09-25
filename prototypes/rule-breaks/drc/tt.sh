#!/bin/bash
# Run IHP's main deck the way Tiny Tapeout's precheck does (tt-support-tools precheck/precheck.py,
# klayout_sg13g2(): klayout -b -r .../ihp-sg13g2.drc -rd sg13g2=true -rd input=GDS -rd thr=1
# -rd report=... ; the default table 'main'; any item fails the check).
#   tt.sh GDS NAME stock|upstream
set -o errexit -o nounset
gds=$(realpath "$1"); name=$2; deck=$3
here=$(dirname "$(realpath "$0")")
out=/var/tmp/spice-rule-breaks/drc; mkdir --parents "$out/$name-tt"
cp "$gds" "$out/$name-tt/in.gds"
mounts=(--volume "$HOME/.ciel/ihp-sg13g2/ihp-sg13g2:/pdk:ro")
[ "$deck" = upstream ] && mounts+=(--volume "/var/tmp/spice-rule-breaks/upstream-pdk/ihp-sg13g2/libs.tech/klayout/tech/drc:/pdk/libs.tech/klayout/tech/drc:ro")
nice ionice podman run --rm "${mounts[@]}" --volume "$out/$name-tt:/work" --workdir /work spice-layout:latest \
  klayout -b -r /pdk/libs.tech/klayout/tech/drc/ihp-sg13g2.drc -rd sg13g2=true -rd input=/work/in.gds \
  -rd thr=1 -rd report=/work/report.lyrdb > "$here/$name-tt.log" 2>&1 || echo "klayout exit $?" >> "$here/$name-tt.log"
{ echo "== Tiny Tapeout precheck style (ihp-sg13g2.drc, default table, deck: $deck)"; uv run --quiet python "$here/summary.py" "$out/$name-tt" 2>&1 || true; } | tee "$here/$name-tt.summary.txt"
