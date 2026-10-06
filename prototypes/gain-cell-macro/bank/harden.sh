#!/bin/sh
# Harden the bank gc_bank_32x32 with the pinned LibreLane 3.1.0.dev3 image (tools/librelane-tt) on
# sg13cmos5l. Usage: harden.sh TAG. Stages config.json, ../rtl/gc_bank.v and freshly generated
# array views (../gc_array.py) in /var/tmp/gc-macro/bank/TAG and runs there; the PDK is mounted
# read-only. Run only when no other place-and-route flow runs on this host.
set -e
here=$(cd "$(dirname "$0")" && pwd)
tag=$1
pdk_root=/var/tmp/roundtrip-cmos5l/pdk
stage=/var/tmp/gc-macro/bank/$tag
rm --recursive --force "$stage"
mkdir --parents "$stage/macro"
cp "$here/config.json" "$stage/"
cp "$here/../rtl/gc_bank.v" "$stage/"
(cd "$here/.." && uv run gc_array.py 32 38 "$stage/macro/GC_ARRAY_32x38") > "$stage/gc_array.txt"
start=$(date +%s)
cd "$stage"
nice ionice podman run --rm \
  --volume "$pdk_root:$pdk_root:ro" --volume "$stage:$stage" --workdir "$stage" \
  --env PDK_ROOT="$pdk_root" --env PDK=ihp-sg13cmos5l --env HOME="$stage" \
  localhost/librelane-tt:3.1.0.dev3 \
  librelane --manual-pdk --pdk-root "$pdk_root" --pdk ihp-sg13cmos5l --run-tag "$tag" config.json \
  > "librelane.log" 2>&1 || status=$?
echo "librelane exit ${status:-0} after $(( $(date +%s) - start )) s, $(date)" | tee --append librelane.log
