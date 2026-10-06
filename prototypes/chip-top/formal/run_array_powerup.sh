#!/usr/bin/env bash
# Power-up determinism of the PE array with its reset, and the control without it (array_powerup.sby).
#   formal/run_array_powerup.sh [SIZES]     default 1,1,1,1     -> ../results/array-powerup.txt
set -o errexit -o nounset -o pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
SIZES=${1:-1,1,1,1}
WORK=/var/tmp/chip-top-formal/array-powerup-$SIZES
rm --recursive --force "$WORK"; mkdir --parents "$WORK"
(cd "$HERE/.." && nice ionice opam exec --switch=5.3.0 -- dune build --root . ./bin/emit_array.exe 2>&1)
W=$("$HERE/../_build/default/bin/emit_array.exe" "$WORK/array.v" "$SIZES" clear | cut --delimiter=' ' --fields=1)
"$HERE/../_build/default/bin/emit_array.exe" "$WORK/array_noclear.v" "$SIZES" noclear > /dev/null
cp "$HERE/array_powerup.sv" "$WORK/"
sed "s/__W__/$W/g" "$HERE/array_powerup.sby" > "$WORK/array_powerup.sby"
tasks="clear noclear"
for t in $tasks; do
  timeout 3600 nice ionice podman run --rm --userns=keep-id --volume "$WORK:$WORK" --workdir "$WORK" \
    localhost/librelane-tt:3.1.0.dev3 sby -f array_powerup.sby "$t" > "$WORK/$t.out" 2>&1 || true
done
{
  echo "# formal/run_array_powerup.sh $SIZES: $W state bits per copy; commit $(git -C "$HERE" rev-parse --short HEAD)$(git -C "$HERE" diff --quiet HEAD -- "$HERE/.." "$HERE/../../unified-pe" || echo ' (with uncommitted changes)'); $(date --iso-8601=seconds)"
  for t in $tasks; do
    echo "== $t: $(grep --only-matching 'DONE ([A-Z]*.*' "$WORK/$t.out" || echo 'no result')"
    grep --extended-regexp 'failed assertion|Assert failed|summary: engine|Status: (passed|failed)' "$WORK/$t.out" | sed 's/^SBY [0-9:]* \[[^]]*\] //' || true
  done
} | tee "$HERE/../results/array-powerup.txt"
