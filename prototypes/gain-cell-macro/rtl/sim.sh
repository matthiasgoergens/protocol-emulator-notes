#!/bin/sh
# Simulates the bank both ways with Icarus Verilog and compares the two read traces.
# Writes results/sim-*.txt here. Needs iverilog (host).
set -e
here=$(cd "$(dirname "$0")" && pwd)
std=/var/tmp/roundtrip-cmos5l/pdk/ihp-sg13cmos5l/libs.ref/sg13cmos5l_stdcell/verilog/sg13cmos5l_stdcell.v
w=/var/tmp/gc-macro/sim
mkdir --parents "$w" "$here/results"
cd "$w"
# only the two cells the RTL instantiates (the full file needs UDPs the PDK does not ship here)
awk '/^module sg13cmos5l_(ebufn_2|nand4_1) /,/^endmodule/' "$std" > cells.v
std=$w/cells.v
iverilog -g2012 -DTRACE=\"trace_rtl.txt\" -o rtl.vvp "$here/tb_bank.v" "$here/gc_bank.v" "$here/gc_array_beh.v" "$std"
vvp -n rtl.vvp > "$here/results/sim-rtl.txt"
iverilog -g2012 -DBEH -DTRACE=\"trace_beh.txt\" -o beh.vvp "$here/tb_bank.v" "$here/gc_bank_beh.v"
vvp -n beh.vvp > "$here/results/sim-beh.txt"
# planted timing fault: a 7 ns clock gives a 14 ns write pulse, below the 20 ns the cell needs
iverilog -g2012 -DPERIOD=7.0 -DTRACE=\"trace_fast.txt\" -o fast.vvp "$here/tb_bank.v" "$here/gc_bank.v" "$here/gc_array_beh.v" "$std"
vvp -n fast.vvp > "$here/results/sim-rtl-7ns-clock.txt" || true
{
  echo "rtl:  $(grep --count . trace_rtl.txt) reads traced; beh: $(grep --count . trace_beh.txt)"
  # the RTL run has one extra read at the end (check 6, the planted decay); compare the rest
  n=$(grep --count . trace_beh.txt)
  if sed --quiet "1,${n}p" trace_rtl.txt | cmp --silent - trace_beh.txt; then echo "first $n reads identical (time, rdata, rerr)"; else echo "TRACES DIFFER"; sed --quiet "1,${n}p" trace_rtl.txt | diff - trace_beh.txt | sed --quiet '1,20p'; fi
  echo "random-read mismatches: rtl $(grep --count 'random read row' "$here/results/sim-rtl.txt") beh $(grep --count 'random read row' "$here/results/sim-beh.txt")"
  echo "7 ns clock: $(grep --count 'SHORT WRITE' "$here/results/sim-rtl-7ns-clock.txt") short writes reported"
} > "$here/results/sim-compare.txt"
grep --extended-regexp '^(PASS|FAIL)|check' "$here/results/sim-rtl.txt" "$here/results/sim-beh.txt"; cat "$here/results/sim-compare.txt"
