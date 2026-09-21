#!/usr/bin/env bash
# Synthesise fpga_pio configurations to IHP sg13g2 standard cells with Yosys.
# Usage: ./synth_sg13g2.sh   (writes logs/<name>.log and results.txt)
set -euo pipefail
YOSYS=${YOSYS:-yosys}
LIB=${LIB:?set LIB to the sg13g2 liberty file}
SRC=${FPGA_PIO_SRC:?set FPGA_PIO_SRC to fpga_pio/src}
NOTES=$(cd "$(dirname "$0")" && pwd)
mkdir --parents "$NOTES/logs"
: > "$NOTES/results.txt"
run() {
  name=$1; top=$2; shift 2
  files="$*"
  log="$NOTES/logs/$name.log"
  if ! nice ionice "$YOSYS" -q -l "$log" -p "
    read_verilog -sv $files
    hierarchy -check -top $top
    synth -top $top -flatten
    dfflibmap -liberty $LIB
    abc -liberty $LIB
    opt_clean
    stat -liberty $LIB
  " > /dev/null 2>&1; then
    echo "$name: FAILED (see logs/$name.log)" >> "$NOTES/results.txt"; return
  fi
  python3 - "$name" "$log" >> "$NOTES/results.txt" <<'PY'
import re, sys
name, log = sys.argv[1], sys.argv[2]
text = open(log).read()
# take the last 'stat' block
block = text[text.rfind('Printing statistics'):]
cells = re.findall(r'^\s+(\d+)\s+cells\s*$', block, re.M)
area = re.findall(r'Chip area for .*?:\s*([0-9.]+)', block)
dff = sum(int(n) for n, c in re.findall(r'^\s+(\d+)\s+(sg13g2_(?:s?df|dl)\w*)\s*$', block, re.M))
mux = sum(int(n) for n, c in re.findall(r'^\s+(\d+)\s+(sg13g2_mux\w*)\s*$', block, re.M))
print(f"{name}: cells={cells[-1] if cells else '?'} area_um2={area[-1] if area else '?'} dffs={dff} muxes={mux}")
PY
}
cd "$SRC"
run isr_only        isr     isr.v
run osr_only        osr     osr.v
run machine_1sm     machine machine.v isr.v osr.v pc.v divider.v decoder.v scratch.v fifo.v
run pio_4sm         pio     pio.v machine.v isr.v osr.v pc.v divider.v decoder.v scratch.v fifo.v
cd "$SRC/top"
run uart_rx_top_4sm top     uart_rx.v ../pio.v ../machine.v ../isr.v ../osr.v ../pc.v ../divider.v ../decoder.v ../scratch.v ../fifo.v
cat "$NOTES/results.txt"
