#!/bin/sh
# Harden the test top gc_test_top around the bank macro, with the pinned LibreLane 3.1.0.dev3
# image on sg13cmos5l. Usage: harden.sh TAG. Stages config.json, ../rtl/gc_test_top.v and the
# bank views in ../views into /var/tmp/gc-macro/top/TAG. Run only when no other flow runs.
set -e
here=$(cd "$(dirname "$0")" && pwd)
tag=$1
pdk_root=/var/tmp/roundtrip-cmos5l/pdk
stage=/var/tmp/gc-macro/top/$tag
rm --recursive --force "$stage"
mkdir --parents "$stage/macro"
cp "$here/config.json" "$here/../rtl/gc_test_top.v" "$stage/"
cp "$here"/../views/gc_bank_32x32* "$stage/macro/"
start=$(date +%s)
cd "$stage"
nice ionice podman run --rm \
  --volume "$pdk_root:$pdk_root:ro" --volume "$stage:$stage" --workdir "$stage" \
  --env PDK_ROOT="$pdk_root" --env PDK=ihp-sg13cmos5l --env HOME="$stage" \
  localhost/librelane-tt:3.1.0.dev3 \
  librelane --manual-pdk --pdk-root "$pdk_root" --pdk ihp-sg13cmos5l --run-tag "$tag" config.json \
  > "librelane.log" 2>&1 || status=$?
echo "librelane exit ${status:-0} after $(( $(date +%s) - start )) s, $(date)" | tee --append librelane.log
