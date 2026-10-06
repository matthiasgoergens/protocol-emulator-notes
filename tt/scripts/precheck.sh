#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Run Tiny Tapeout's own precheck (tt-support-tools precheck/precheck.py, the step of
# TinyTapeout/tt-gds-action's precheck/action.yml) on a hardened project, on this machine.
#   tt/scripts/precheck.sh STAGE REPORT_DIR [SUBMISSION_ROOT]
#     STAGE            a directory made by harden.sh (has tt/ at the pinned commit and venv/)
#     REPORT_DIR       new directory that receives results.md, results.xml, precheck.log
#     SUBMISSION_ROOT  directory holding info.yaml and tt_submission/ (default STAGE; the action's
#                      tt_submission artifact has the same shape); used to precheck a modified copy
# The action runs `nix-shell --run "python precheck.py --gds .../tt_submission/*.gds* --tech PDK"`,
# with KLayout and Magic from a pinned nixpkgs.  Here the Python packages come from a project-local
# uv venv (precheck/requirements.txt), and `klayout` is a shim that runs the KLayout of the pinned
# LibreLane image (tools/librelane-tt) under rootless podman.  Magic is not on the sg13cmos5l path.
# Nothing is installed on the host and ~/.ciel is not touched.
set -o errexit -o nounset -o pipefail
STAGE=$(cd "${1:?usage: precheck.sh STAGE REPORT_DIR [SUBMISSION_ROOT]}" && pwd)
REPORT_DIR=${2:?usage: precheck.sh STAGE REPORT_DIR [SUBMISSION_ROOT]}
SUBROOT=$(cd "${3:-$STAGE}" && pwd)
export PDK_ROOT=${PDK_ROOT:-/var/tmp/roundtrip-cmos5l/pdk} PDK=ihp-sg13cmos5l
IMAGE=localhost/librelane-tt:3.1.0.dev3
[ ! -e "$REPORT_DIR" ] || { echo "$REPORT_DIR exists; give a new directory"; exit 2; }
podman image exists "$IMAGE" || { echo "build $IMAGE first: tools/librelane-tt/build.sh"; exit 2; }
[ -f "$STAGE/tt/precheck/precheck.py" ] || { echo "no tt-support-tools in $STAGE/tt"; exit 2; }
mkdir --parents "$REPORT_DIR"
REPORT_DIR=$(cd "$REPORT_DIR" && pwd)

# The submission, as `tt_tool.py --create-tt-submission` makes it (the action's step before upload).
if [ ! -d "$SUBROOT/tt_submission" ]; then
  [ "$SUBROOT" = "$STAGE" ] || { echo "no tt_submission in $SUBROOT"; exit 2; }
  (cd "$STAGE" && HOME=$STAGE PATH=$STAGE/venv/bin:$PATH python ./tt/tt_tool.py --create-tt-submission --ihp)
fi

# The action's Python is 3.11 with precheck/requirements.txt.
if [ ! -x "$STAGE/precheck-venv/bin/python" ]; then
  uv venv --quiet --python 3.11 "$STAGE/precheck-venv"
  VIRTUAL_ENV=$STAGE/precheck-venv uv pip install --quiet --requirement "$STAGE/tt/precheck/requirements.txt"
fi

# KLayout of the pinned image, as `klayout` on PATH.
mkdir --parents "$STAGE/precheck-bin"
cat > "$STAGE/precheck-bin/klayout" <<SHIM
#!/bin/sh
exec podman run --rm --volume '$PDK_ROOT:$PDK_ROOT:ro' --volume '$STAGE:$STAGE' \\
  --volume '$SUBROOT:$SUBROOT' --workdir "\$PWD" --env PDK_ROOT='$PDK_ROOT' --env PDK='$PDK' \\
  '$IMAGE' klayout "\$@"
SHIM
chmod +x "$STAGE/precheck-bin/klayout"

until awk '{exit !($1 < 16)}' /proc/loadavg; do sleep 30; done
cd "$STAGE/tt/precheck"
rm --force reports/results.xml reports/results.md
status=0
nice ionice env PATH="$STAGE/precheck-bin:$STAGE/precheck-venv/bin:$PATH" \
  python precheck.py --gds "$SUBROOT"/tt_submission/*.gds* --tech "$PDK" \
  > "$REPORT_DIR/precheck.log" 2>&1 || status=$?
cp reports/results.md reports/results.xml "$REPORT_DIR/" 2>/dev/null || true
echo "precheck exit $status, $(date --iso-8601=seconds)" | tee --append "$REPORT_DIR/precheck.log"
[ -f "$REPORT_DIR/results.md" ] && cat "$REPORT_DIR/results.md"
exit "$status"
