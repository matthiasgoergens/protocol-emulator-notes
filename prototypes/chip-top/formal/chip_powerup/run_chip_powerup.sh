#!/usr/bin/env bash
# Power-up determinism of the whole chip (chip_powerup.sv), with its controls.
#   formal/chip_powerup/run_chip_powerup.sh [TASK...]     default: bmc noreset plant:cfgreg_00 plant:seg0_ctrl plant:link_state prove
# TASK is prove, bmc or noreset (chip_powerup.sby), or plant:REG: REG loses its reset (the
# "if (reset_sync) REG <= ...; else" branch is deleted) and the bmc task must then FAIL.
# CHIP_TT=path uses that chip_tt.v instead of regenerating it (e.g. a harden stage's src/chip_tt.v);
# either way its sha256 is recorded.  -> ../../results/chip-powerup.txt
set -o errexit -o nounset -o pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../../../.." && pwd)
WORK=/var/tmp/chip-top-formal/chip-powerup
DEPTH=${DEPTH:-24}
TASKS=${*:-bmc noreset plant:cfgreg_00 plant:seg0_ctrl plant:link_state prove}
mkdir --parents "$WORK"
if [ -n "${CHIP_TT:-}" ]; then
  cp "$CHIP_TT" "$WORK/chip_tt.v"
else
  "$REPO/tt/scripts/regen_chip.sh" "$WORK/chip_tt.v"
fi
python3 "$HERE/stub_sram.py" "$WORK/chip_tt.v" "$WORK/chip_pu.v" > /dev/null
cp "$HERE/chip_powerup.sv" "$WORK/"
sed "s/__DEPTH__/$DEPTH/g" "$HERE/chip_powerup.sby" > "$WORK/chip_powerup.sby"

run() {  # run DIR TASK
  timeout 7200 nice ionice podman run --rm --userns=keep-id --volume "$WORK:$WORK" --workdir "$1" \
    localhost/librelane-tt:3.1.0.dev3 sby -f chip_powerup.sby "$2" > "$1/$2.out" 2>&1 || true
}
for t in $TASKS; do
  case $t in
    plant:*)
      reg=${t#plant:}; dir=$WORK/plant-$reg
      rm --recursive --force "$dir"; mkdir --parents "$dir"
      cp "$WORK/chip_powerup.sv" "$WORK/chip_powerup.sby" "$dir/"
      python3 - "$WORK/chip_pu.v" "$dir/chip_pu.v" "$reg" <<'EOF'
import re, sys
src, dst, reg = sys.argv[1:]
s = open(src).read()
s, n = re.subn(r"if \(reset_sync\)\s*" + reg + r" <= [^;]+;\s*else\s*", "", s)
assert n == 1, (reg, n)
open(dst, "w").write(s)
EOF
      run "$dir" bmc; mv "$dir/bmc.out" "$WORK/$t.out" ;;
    *) run "$WORK" "$t" ;;
  esac
done
{
  echo "# formal/chip_powerup/run_chip_powerup.sh $TASKS: depth $DEPTH half clocks for bmc; chip_tt.v sha256 $(sha256sum "$WORK/chip_tt.v" | cut --delimiter=' ' --fields=1)${CHIP_TT:+ (from $CHIP_TT)}; commit $(git -C "$HERE" rev-parse --short HEAD)$(git -C "$HERE" diff --quiet HEAD -- "$HERE/../.." || echo ' (with uncommitted changes)'); $(date --iso-8601=seconds)"
  for t in $TASKS; do
    echo "== $t: $(grep --only-matching 'DONE ([A-Z]*.*' "$WORK/$t.out" || echo 'no result')"
    grep --extended-regexp 'summary: (engine|Elapsed clock)' "$WORK/$t.out" | sed 's/^SBY [0-9:]* \[[^]]*\] //' || true
  done
} | tee "$HERE/../../results/chip-powerup.txt"
