#!/bin/sh
# End-to-end simulation: the generated Verilog and hdmi_top.v under iverilog with ideal clocks,
# the four serial lanes captured, decoded by the independent decoder, compared with the pattern.
#   e2e/run.sh [sdr|ddr] [pixel-clock phase in ps] [mutant]
#     -> $OUT/<variant>-<phase>[-<mutant>]/{capture.hex,*.png,*.log}
# mutant: none, or a negative control: latency, xnor, qm8, control (see bin/emit.ml), or
# oddr_swap (the simulated ODDRX1F sends D1 first; ddr only).  rtl/gen is regenerated, and left
# in the mutated state if a mutant is given: rerun without one before building.
set -eu
here=$(cd "$(dirname "$0")/.." && pwd)
variant=${1:-sdr}
phase=${2:-0}
mutant=${3:-none}
suffix=""; [ "$mutant" = none ] || suffix="-$mutant"
out=${OUT:-/var/tmp/hdmi-ulx3s/e2e}/$variant-$phase$suffix
emit_mutant=$mutant; extra=""
[ "$mutant" = oddr_swap ] && { emit_mutant=none; extra="-DODDR_SWAP"; }
bits=${BITS:-9000000}
mkdir --parents "$out"
case $variant in
  sdr) defs=""; serial=hdmi_serial_sdr ;;
  ddr) defs="-DHDMI_DDR"; serial=hdmi_serial_ddr ;;
  *) echo "unknown variant $variant" >&2; exit 2 ;;
esac
cd "$here"
opam exec --switch=5.3.0 -- dune build 2>&1
opam exec --switch=5.3.0 -- dune exec ./bin/emit.exe rtl/gen "$emit_mutant"
git -C "$here" rev-parse HEAD > "$out/commit.txt"
git -C "$here" status --porcelain -- . >> "$out/commit.txt"
iverilog -g2012 $defs $extra -DPIX_PHASE_PS="$phase" -DBITS="$bits" -DCAPTURE="\"$out/capture.hex\"" \
  -o "$out/tb.vvp" e2e/tb.v e2e/sim_models.v rtl/hdmi_top.v rtl/gen/hdmi_pixel.v rtl/gen/$serial.v
nice ionice vvp -n "$out/tb.vvp" | tee "$out/sim.log"
nice ionice opam exec --switch=5.3.0 -- dune exec ./e2e/decode_capture.exe "$out/capture.hex" "$out" | tee "$out/decode.log"
