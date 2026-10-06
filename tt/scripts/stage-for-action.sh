#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Lay out tt/ the way TinyTapeout/tt-gds-action expects a project: info.yaml, src/, docs/ and test/
# at the root of the current directory, which is made a git repository with a remote.  The action
# hard-codes those root-relative paths and checks tt-support-tools out into ./tt, which would
# collide with this repository's own tt/ (see tt/README.md, "Does the GDS action need its own
# repository?").  harden.sh does the same thing for the local flow.
#   cd WORKSPACE && REPO_URL=https://github.com/OWNER/NAME tt/scripts/stage-for-action.sh CHECKOUT
# CHECKOUT is the directory holding this repository's checkout (a subdirectory of WORKSPACE, not
# WORKSPACE itself).  The core's Verilog is generated into the staged src/ from CHECKOUT.
set -o errexit -o nounset -o pipefail
CHECKOUT=$(cd "${1:?usage: stage-for-action.sh CHECKOUT}" && pwd)
URL=${REPO_URL:?set REPO_URL}
[ "$PWD" != "$CHECKOUT" ] || { echo "CHECKOUT must not be the current directory"; exit 2; }
[ ! -e info.yaml ] || { echo "info.yaml exists here already"; exit 2; }
cp --recursive "$CHECKOUT/tt/info.yaml" "$CHECKOUT/tt/src" "$CHECKOUT/tt/docs" "$CHECKOUT/tt/test" .
"$CHECKOUT/tt/scripts/regen.sh" "$PWD/src/deadline_sequencer_v2.v"
git init --quiet
git remote add origin "$URL.git"
git add info.yaml src docs test
git -c user.name=tt-stage -c user.email=tt-stage@localhost commit --quiet --message "staged tt/ of $(git -C "$CHECKOUT" rev-parse HEAD)"
