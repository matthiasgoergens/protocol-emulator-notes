#!/usr/bin/env bash
# Rewrites the copy of Make's body inside isa2.ml's Spec (see the comment above Spec in isa2.ml).
set -o errexit -o nounset -o pipefail
cd "$(dirname "$0")"
awk --assign write=1 --file specialise.awk isa2.ml > isa2.ml.new
mv isa2.ml.new isa2.ml
awk --file specialise.awk isa2.ml > /dev/null && echo "isa2.ml: Spec is a verbatim copy of Make's body"
