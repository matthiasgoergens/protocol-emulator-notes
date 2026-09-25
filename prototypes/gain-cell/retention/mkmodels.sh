#!/bin/sh
# A copy of the IHP ngspice models whose MOSFET subcircuits take a threshold offset "dvt"
# (the stock subcircuits hardcode delvto=0). Usage: mkmodels.sh PDK_ROOT DEST
set -e
cp --recursive "$1/libs.tech/ngspice/models" "$2"
cd "$2"
sed --in-place 's/^\(+ w=0.35u l=0.[23][48]u ng=1 m=1 mm_ok=1 .*pre_layout=1\)$/\1 dvt=0/; s/delvto=0$/delvto=dvt/' \
    sg13g2_moshv_mod.lib sg13g2_moslv_mod.lib
grep --count "dvt=0" sg13g2_moshv_mod.lib sg13g2_moslv_mod.lib
