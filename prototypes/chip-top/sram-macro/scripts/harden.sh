#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Harden a Tiny Tapeout project directory for the sg13cmos5l shuttle the way
# TinyTapeout/tt-gds-action (branch ihp-cmos5l) does. A copy of tt/scripts/harden.sh that takes the
# project directory as an argument and generates no Verilog; everything else (pins, image, PDK,
# load gate) is unchanged.
#   harden.sh PROJECT STAGE [CONFIG]
#     PROJECT  a directory with info.yaml, src/ and docs/ (e.g. prototypes/chip-top/sram-macro)
#     STAGE    a new scratch directory, e.g. /var/tmp/chip-top-sram/run1
#     CONFIG   optional: a file that replaces src/config.json in the stage (variants/*.json)
# Needs: the image (tools/librelane-tt/build.sh), uv, and PDK_ROOT pointing at an ihp-sg13cmos5l
# checkout from the action's install_sg13cmos5l.sh (IHP-Open-PDK 2bbec755); the default is the copy
# in /var/tmp/roundtrip-cmos5l/pdk.
# The project is copied into STAGE, which is made a throwaway git repository because tt_tool.py
# records the commit and remote; the project directory is never written to.
set -o errexit -o nounset -o pipefail
PROJECT=$(cd "${1:?usage: harden.sh PROJECT STAGE [CONFIG]}" && pwd)
STAGE=${2:?usage: harden.sh PROJECT STAGE [CONFIG]}
CONFIG=${3:-}
[ -z "$CONFIG" ] || CONFIG=$(cd "$(dirname "$CONFIG")" && pwd)/$(basename "$CONFIG")
export PDK_ROOT=${PDK_ROOT:-/var/tmp/roundtrip-cmos5l/pdk} PDK=ihp-sg13cmos5l
# Pins, as tt-gds-action 3412659 (ihp-cmos5l) resolves them on 2026-10-05.
TOOLS_REPO=https://github.com/TinyTapeout/tt-support-tools.git
TOOLS_REV=d66cf179e7bc4d296362ab7e2e3b344dc3c4f665   # branch ihp-sg13cmos5l, the action's tools-ref
LIBRELANE_VERSION=3.1.0.dev3
IMAGE=localhost/librelane-tt:$LIBRELANE_VERSION
[ -f "$PDK_ROOT/ihp-sg13cmos5l/libs.tech/librelane/config.tcl" ] || { echo "no ihp-sg13cmos5l under $PDK_ROOT"; exit 2; }
podman image exists "$IMAGE" || { echo "build $IMAGE first: tools/librelane-tt/build.sh"; exit 2; }
[ ! -e "$STAGE" ] || { echo "$STAGE exists; give a new directory"; exit 2; }
mkdir --parents "$STAGE"
STAGE=$(cd "$STAGE" && pwd)

# The project: info.yaml, src/ and docs/, in a throwaway repository.
cp --recursive "$PROJECT/info.yaml" "$PROJECT/src" "$PROJECT/docs" "$STAGE/"
[ -z "$CONFIG" ] || cp "$CONFIG" "$STAGE/src/config.json"
# Host-load cap, not part of the design: OpenROAD would otherwise start one thread per host CPU
# (32 here). Only the stage's copy of config.json gets the key.
THREADS=${HARDEN_THREADS:-6}
sed --in-place "0,/^{/s//{\n  \"OPENROAD_THREADS\": $THREADS,/" "$STAGE/src/config.json"
grep --quiet "\"OPENROAD_THREADS\": $THREADS," "$STAGE/src/config.json" || { echo "could not set OPENROAD_THREADS"; exit 2; }
git -C "$STAGE" init --quiet
git -C "$STAGE" remote add origin https://github.com/local/tt-harden-stage.git
git -C "$STAGE" add info.yaml src docs
git -C "$STAGE" -c user.name=tt-harden -c user.email=tt-harden@localhost commit --quiet --message "stage"

# tt-support-tools at the pinned commit, as the action's checkout step puts it in ./tt.
git -C "$STAGE" clone --quiet "$TOOLS_REPO" tt
git -C "$STAGE/tt" checkout --quiet "$TOOLS_REV"

# The action's Python: 3.11, tt-support-tools' requirements and librelane from PyPI (the host side
# only; every EDA tool runs in the image).
uv venv --quiet --python 3.11 "$STAGE/venv"
VIRTUAL_ENV=$STAGE/venv uv pip install --quiet --requirement "$STAGE/tt/requirements.txt" "librelane==$LIBRELANE_VERSION"

# librelane --dockerized mounts $HOME and PDK_ROOT into the container.  HOME is the stage, so only
# the stage and the PDK are visible; the engine wrapper restores the real HOME for podman itself,
# whose image store lives there.
cat > "$STAGE/podman-real-home" <<EOF
#!/bin/sh
# LibreLane's own fallback thread count (KLayout, STA) is _OPENLANE_MAX_CORES or the CPU count.
if [ "\$1" = run ]; then shift; set -- run --env _OPENLANE_MAX_CORES=$THREADS "\$@"; fi
HOME='$HOME' exec podman "\$@"
EOF
chmod +x "$STAGE/podman-real-home"
cd "$STAGE"
run() {
  until awk '{exit !($1 < 16)}' /proc/loadavg; do sleep 30; done
  HOME=$STAGE PATH=$STAGE/venv/bin:$PATH \
    LIBRELANE_CONTAINER_ENGINE=$STAGE/podman-real-home LIBRELANE_IMAGE_OVERRIDE=$IMAGE \
    nice ionice python ./tt/tt_tool.py "$@" --ihp
}
run --create-user-config > create-user-config.log 2>&1
start=$(date +%s)
run --harden > harden.log 2>&1 || status=$?
echo "harden exit ${status:-0} after $(( $(date +%s) - start )) s" | tee --append harden.log
[ "${status:-0}" = 0 ] || exit "$status"
run --print-stats > stats.md 2>&1
echo "run directory: $STAGE/runs/wokwi; summary in $STAGE/stats.md"
