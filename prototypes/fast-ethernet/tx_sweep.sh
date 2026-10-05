#!/bin/bash
# 100BASE-TX receive sweep: the RTL transmitter's line (main.exe txgen 200) through tx_channel.py,
# decoded by main.exe txrx (CDR + RTL receiver). One output line per cell.
# Pad corners: tt vmin 0.10 V, pad threshold at its nominal 0.59 V; ss vmin 0.20 V and the pad
# threshold 0.044 V lower (0.546 V) than the fixed divider assumes; ff vmin 0.05 V, 0.034 V
# higher (0.624 V). Both pads shift together (same die).
here=$(dirname "$(readlink --canonicalize "$0")")
W=/var/tmp/fast-eth/tx
cell() {
  local len=$1 eq=$2 g=$3 corner=$4 osr=$5
  case $corner in tt) vmin=0.10; d=0.0;; ss) vmin=0.20; d=-0.044;; ff) vmin=0.05; d=0.034;; esac
  local f=$W/s-$len-$eq-$g-$corner-$osr.txt
  local ch=$(nice uv run --quiet --with numpy python3 $here/tx_channel.py line=$W/stream.line out=$f len=$len eq=$eq g=$g vmin=$vmin dp=$d dn=$d osr=$osr ppm=200 rj=0.2 amp=0.97 tr=2.9 | tr '\n' ' ')
  local rx=$(nice $here/_build/default/main.exe txrx $f $W/stream.frames $osr | tail --lines=1)
  echo "len $len eq $eq g $g corner $corner osr $osr | $ch| $rx"
}
export -f cell; export here W
for len in 1 2 5 10 20 30 50 100; do for eq in none shelf; do for g in 1 2; do for corner in tt ss ff; do for osr in 2 4; do
  [ "$eq" = shelf ] && [ "$len" -lt 20 ] && continue
  echo "$len $eq $g $corner $osr"
done; done; done; done; done | xargs --max-procs=${J:-3} --max-lines=1 bash -c 'cell "$@"' _
