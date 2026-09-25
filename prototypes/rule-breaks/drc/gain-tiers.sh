#!/bin/bash
# Draw the gain-cell arrays at one tier of rule values and DRC them: the stock deck (main table
# alone = Tiny Tapeout's precheck set, and main + maximal), the tier's relaxed deck (SRAM
# exemption removed, so the stated values are checked everywhere), and the Tiny Tapeout way with
# the upstream deck and the SRAM marker (plus DigiBnd) drawn over the array.
#   gain-tiers.sh NAME RULES DECKDIR
set -o errexit -o nounset
name=$1; rules=$2; deck=$3
here=$(dirname "$(realpath "$0")"); G=$here/../layout/gain_rb.py; W=/var/tmp/spice-rule-breaks/work
cd $W
uv run --quiet --with gdstk python $G "$rules" none gain_${name}_nomark.gds 8 2 4 thin 0.13 narrow thick 0.45 narrow allthick 0.45 narrow > $here/gain-$name-areas.txt
uv run --quiet --with gdstk python $G "$rules" none /dev/null 8 2 32 thin 0.13 narrow thick 0.45 narrow allthick 0.45 narrow | grep "^3T" >> $here/gain-$name-areas.txt
uv run --quiet --with gdstk python $G "$rules" sram,digi gain_${name}_mark.gds 8 2 4 thin 0.13 narrow thick 0.45 narrow allthick 0.45 narrow > /dev/null
uv run --quiet --with gdstk python split.py gain_${name}_nomark; uv run --quiet --with gdstk python split.py gain_${name}_mark
cd $here
for t in 3T_thin_L13n 3T_thick_L45n 3T_allthick_L45n MIXED; do
  n=gain-$(echo $t | tr 'A-Z_' 'a-z-')-$name
  ./run.sh $W/gain_${name}_nomark_ARRAY_$t.gds ARRAY_$t $n-nomark stock > /dev/null
  ./run.sh $W/gain_${name}_nomark_ARRAY_$t.gds ARRAY_$t $n-relaxeddeck $deck > /dev/null
  ./tt.sh $W/gain_${name}_mark_ARRAY_$t.gds $n-mark-upstream upstream > /dev/null
done
