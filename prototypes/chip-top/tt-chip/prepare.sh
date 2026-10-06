#!/usr/bin/env bash
# Generate src/chip_tt.v for this project directory (build output, git-ignored) and copy the
# wrapper from tt/src. Arguments as tt/scripts/regen_chip.sh after OUT.
set -o errexit -o nounset -o pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
cp "$HERE/../../../tt/src/chip_project.v" "$HERE/src/chip_project.v"
"$HERE/../../../tt/scripts/regen_chip.sh" "$HERE/src/chip_tt.v" "$@"
