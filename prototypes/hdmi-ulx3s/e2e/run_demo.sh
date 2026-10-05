#!/bin/sh
# End-to-end simulation of the demo variant: the retro console running game field FIELD (one field
# in the ROM, so the picture is static), through the frame buffer, TMDS and serialiser, decoded
# by the independent decoder and compared with demo/expected.ml.
#   e2e/run_demo.sh [sdr|ddr] [FIELD]   -> $OUT/demo-<variant>-<field>/
# The console needs 38 ms to draw its first field at 25 MHz, so the capture skips the first 36 ms
# and covers the frames from 49.5 to 66.3 ms.  Leaves rtl/gen regenerated for the board (8 fields).
set -eu
here=$(cd "$(dirname "$0")/.." && pwd)
variant=${1:-sdr}
field=${2:-30}
out=${OUT:-/var/tmp/hdmi-ulx3s/e2e}/demo-$variant-$field
mkdir --parents "$out"
case $variant in
  sdr) defs=""; serial=hdmi_serial_sdr ;;
  ddr) defs="-DHDMI_DDR"; serial=hdmi_serial_ddr ;;
  *) echo "unknown variant $variant" >&2; exit 2 ;;
esac
cd "$here"
opam exec --switch=5.3.0 -- dune build 2>&1
opam exec --switch=5.3.0 -- dune exec ./demo/gen_packets.exe "$field" 1 "$out/packets.hex"
DEMO_FIELDS=1 DEMO_PACKETS="$out/packets.hex" opam exec --switch=5.3.0 -- dune exec ./bin/emit.exe rtl/gen
git -C "$here" rev-parse HEAD > "$out/commit.txt"
git -C "$here" status --porcelain -- . >> "$out/commit.txt"
iverilog -g2012 $defs -DHDMI_DEMO -DPIX_PHASE_PS=2000 -DSKIP_PS=36000000000 -DBITS=8000000 \
  -DCAPTURE="\"$out/capture.hex\"" -o "$out/tb.vvp" e2e/tb.v e2e/sim_models.v rtl/hdmi_top.v rtl/hdmi_out.v \
  rtl/gen/hdmi_pixel_demo.v rtl/gen/$serial.v rtl/packet_rom.v rtl/frame_buffer.v
nice ionice vvp -n "$out/tb.vvp" | tee "$out/sim.log"
nice ionice opam exec --switch=5.3.0 -- dune exec ./e2e/decode_capture.exe "$out/capture.hex" "$out" "$out/packets.hex" | tee "$out/decode.log"
opam exec --switch=5.3.0 -- dune exec ./bin/emit.exe rtl/gen
