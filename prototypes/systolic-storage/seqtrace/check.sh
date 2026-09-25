#!/bin/sh
# The copies must match the prototype they instrument.
set -e
cd "$(dirname "$0")"
cmp isa.ml ../../deadline-sequencer/isa.ml
cmp compiler.ml ../../deadline-sequencer/compiler.ml
echo "copies match"
