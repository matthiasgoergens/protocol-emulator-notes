#!/usr/bin/env bash
# The edge-phase test in Icarus with every falling-edge flip-flop of a hardened gate netlist moved
# to the rising edge in turn (sim/nl_plants.py); each must be caught, by the test's absolute checks
# or by the comparison with the Hardcaml reference.
#
#   sim/edge_plants.sh SIZES OUTDIR NETLIST.v
set -o errexit -o nounset -o pipefail
sizes=$1 out=$2 nl=$3
here=$(cd "$(dirname "$0")/.." && pwd)
exe=$here/_build/default/bin
pdk=${PDK_ROOT:?PDK_ROOT must point at the PDK}/ihp-sg13cmos5l/libs.ref
sram=$pdk/sg13cmos5l_sram/verilog
mkdir --parents "$out"
python3 "$here/sim/nl_plants.py" "$nl" "$out/nl-plantable.v" > "$out/map.txt"
"$exe/edge_phase.exe" rtl "$sizes" "$out/stim.txt" > "$out/reference.log"
iverilog -g2012 -DFUNCTIONAL -DSTIM="\"$out/stim.txt\"" -DTRACE="\"$out/trace.txt\"" -s edge_tb \
  -o "$out/edge_tb.vvp" "$here/sim/edge_tb.v" "$pdk/sg13cmos5l_stdcell/verilog/sg13cmos5l_udp.v" \
  "$pdk/sg13cmos5l_stdcell/verilog/sg13cmos5l_stdcell.v" "$out/nl-plantable.v" \
  "$sram/RM_IHPSG13_1P_512x16_c2_bm_bist.v" "$sram/RM_IHPSG13_1P_1024x8_c2_bm_bist.v" \
  "$sram/RM_IHPSG13_1P_core_behavioral_bm_bist.v" 2> "$out/iverilog.log"
caught=0 total=0
# the unplanted netlist first: it must pass
vvp -n "$out/edge_tb.vvp" +trace="$out/trace-none.txt" > /dev/null
"$exe/edge_phase.exe" replay "$sizes" "$out/stim.txt" "$out/trace-none.txt" > "$out/replay-none.log" \
  && echo "no plant: passes" || echo "no plant: FAILS"
while read -r k inst role; do
  vvp -n "$out/edge_tb.vvp" +plant="$k" +trace="$out/trace-$k.txt" > /dev/null
  if "$exe/edge_phase.exe" replay "$sizes" "$out/stim.txt" "$out/trace-$k.txt" > "$out/replay-$k.log"; then
    verdict=MISSED
  else
    verdict=caught; caught=$((caught + 1))
  fi
  total=$((total + 1))
  diff=$(grep --only-matching 'compared simulator: [0-9]* half clocks differ' "$out/replay-$k.log")
  res=$(grep '^inputs: ' "$out/replay-$k.log" | sed --quiet '$p')
  echo "plant $k $inst ($role): $verdict; $diff; $res"
  rm --force "$out/trace-$k.txt"
done < "$out/map.txt"
echo "$caught of $total plants caught"
