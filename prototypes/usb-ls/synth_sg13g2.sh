#!/usr/bin/env bash
# Area of the low-speed USB pieces on IHP sg13g2 (typical corner), the same Yosys flow as the
# other prototypes: flatten, map flip-flops and logic to the liberty file, report.
# Usage: YOSYS=... LIB=... ./synth_sg13g2.sh   (writes synth/<top>.log and synth/results.txt)
set -euo pipefail
YOSYS=${YOSYS:-yosys}
LIB=${LIB:?set LIB to sg13g2_stdcell_typ_1p20V_25C.lib}
cd "$(dirname "$0")"
mkdir --parents synth
: > synth/results.txt
for top in usb_ls_device deadline_sequencer deadline_sequencer_ls crc_usb16 crc_prog usb_ls_firmware_system; do
  log=synth/$top.log
  nice ionice "$YOSYS" -q -l "$log" -p "read_verilog $top.v; hierarchy -check -top $top; synth -top $top -flatten; dfflibmap -liberty $LIB; abc -liberty $LIB; opt_clean; stat -liberty $LIB" > /dev/null
  python3 - "$top" "$log" >> synth/results.txt <<'PY'
import re, sys
name, log = sys.argv[1], sys.argv[2]
text = open(log).read()
block = text[text.rfind('Printing statistics'):]
cells = re.findall(r'^\s+(\d+)\s+\S+\s+cells\s*$', block, re.M)
area = re.findall(r'Chip area for .*?:\s*([0-9.]+)', block)
dff = sum(int(n) for n, a, c in re.findall(r'^\s+(\d+)\s+(\S+)\s+(sg13g2_(?:s?df|dl)\w*)\s*$', block, re.M))
print(f"{name}: cells={cells[-1] if cells else '?'} area_um2={area[-1] if area else '?'} flops={dff}")
PY
done
cat synth/results.txt
