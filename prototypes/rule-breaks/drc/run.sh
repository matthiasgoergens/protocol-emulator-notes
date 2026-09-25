#!/bin/bash
# DRC one layout with IHP's deck in the spice-layout container, twice: the main table alone
# (what Tiny Tapeout's precheck runs: ihp-sg13g2.drc with the default table) and the main table
# plus the maximal deck (run_drc.py's default). Optionally a third run with --precheck_drc
# (IHP's minimal foundry precheck set, as in TT's foundry-submission CI).
#   run.sh GDS TOPCELL NAME [DECKDIR|stock|upstream] [precheck]
# DECKDIR: a copy of libs.tech/klayout/tech/drc with edited rule values, mounted over the stock one.
# upstream: IHP-Open-PDK main of 2026-09-01 (5e6d592e), sparse clone in /var/tmp/spice-rule-breaks.
# Results: /var/tmp/spice-rule-breaks/drc/NAME-{main,full,precheck}/; logs and summaries here.
set -o errexit -o nounset
gds=$(realpath "$1"); top=$2; name=$3; deck=${4:-stock}; pre=${5:-}
here=$(dirname "$(realpath "$0")")
out=/var/tmp/spice-rule-breaks/drc
mkdir --parents "$out"
cp "$gds" "$out/$name.gds"
mounts=(--volume "$HOME/.ciel/ihp-sg13g2/ihp-sg13g2:/pdk:ro")
case "$deck" in
  stock) ;;
  upstream) mounts+=(--volume "/var/tmp/spice-rule-breaks/upstream-pdk/ihp-sg13g2/libs.tech/klayout/tech/drc:/pdk/libs.tech/klayout/tech/drc:ro") ;;
  *) mounts+=(--volume "$(realpath "$deck"):/pdk/libs.tech/klayout/tech/drc:ro") ;;
esac
runs=("main:--disable_extra_rules" "full:")
[ -n "$pre" ] && runs+=("precheck:--precheck_drc --disable_extra_rules --no_offgrid")
: > "$here/$name.summary.txt"
for r in "${runs[@]}"; do
  tag=${r%%:*}; opts=${r#*:}
  rm --recursive --force "$out/$name-$tag"
  # shellcheck disable=SC2086
  nice ionice podman run --rm "${mounts[@]}" --volume "$out:/work" --workdir /pdk/libs.tech/klayout/tech/drc \
    spice-layout:latest python3 run_drc.py --path="/work/$name.gds" --topcell="$top" --run_dir="/work/$name-$tag" \
    --no_density --run_mode=flat $opts > "$here/$name-$tag.log" 2>&1 || true
  verdict=$(grep --only-matching "Violated rules are.*\|DRC Check Passed.*" "$here/$name-$tag.log" | head --lines=1)
  { echo "== $tag (deck: $deck, options: ${opts:-none}): $verdict"; uv run --quiet python "$here/summary.py" "$out/$name-$tag" 2>&1 || true; } >> "$here/$name.summary.txt"
done
cat "$here/$name.summary.txt"
