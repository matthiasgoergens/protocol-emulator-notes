#!/usr/bin/env bash
# Second oracle: sigrok's own spdif protocol decoder (libsigrokdecode 0.5.3, sigrok-cli 0.7.2 from
# Debian trixie, in a rootless container built from /var/tmp/spdif/sigrok/Containerfile) on the
# chip transmitter's pin captures written by `main.exe tx` (one byte per sample at four samples
# per transmitter clock). main.exe sigrok-compare checks its annotations against the subframes sent.
set -o errexit -o nounset -o pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
cd "$HERE/results/sigrok"
IMAGE=localhost/spdif-sigrok:latest
if ! podman image exists "$IMAGE"; then
  echo "building $IMAGE"
  printf 'FROM docker.io/library/debian:trixie-slim\nRUN apt-get update && apt-get install --yes --no-install-recommends sigrok-cli libsigrokdecode4 && rm -rf /var/lib/apt/lists/*\n' \
    | podman build --tag "$IMAGE" --file - . >&2
fi
podman run --rm "$IMAGE" sigrok-cli --version | sed --quiet '1p;/libsigrokdecode/p'
status=0
for bin in tx-*.bin control-*.bin; do
  base=${bin%.bin}
  rate=$(sed --quiet 's/^# samplerate //p' "$base.expected")
  nice ionice podman run --rm --volume "$PWD:/w:Z" "$IMAGE" \
    sigrok-cli -I "binary:numchannels=1:samplerate=$rate" -i "/w/$bin" -P spdif:data=0 -A spdif > "$base.ann"
  if [[ $base == control-* ]]; then
    # planted fault: the comparison must fail
    if "$HERE/_build/default/main.exe" sigrok-compare "$base.ann" "$base.expected"; then echo "CONTROL NOT CAUGHT: $base"; status=1
    else echo "control $base: caught (comparison failed, as it must)"; fi
  else
    "$HERE/_build/default/main.exe" sigrok-compare "$base.ann" "$base.expected" || status=1
  fi
done
exit $status
