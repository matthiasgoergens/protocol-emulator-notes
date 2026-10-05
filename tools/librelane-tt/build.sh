#!/usr/bin/env bash
# Build localhost/librelane-tt:3.1.0.dev3 from the Containerfile here (rootless podman; nothing is
# installed on the host) and record the tool versions it contains in versions.txt.
set -o errexit -o nounset -o pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
IMAGE=localhost/librelane-tt:3.1.0.dev3
nice ionice podman build --tag "$IMAGE" --file "$HERE/Containerfile" "$HERE"
podman run --rm "$IMAGE" bash -c '
  librelane --version | grep "^LibreLane"
  echo "Magic $(magic --version)"
  klayout -v
  echo "OpenROAD $(openroad -version)"
  yosys -V
  for p in ${PATH//:/ }; do case $p in /nix/store/*) basename "$(dirname "$p")" | cut --delimiter=- --fields=2-;; esac; done
  python3 --version' > "$HERE/versions.txt"
cat "$HERE/versions.txt"
