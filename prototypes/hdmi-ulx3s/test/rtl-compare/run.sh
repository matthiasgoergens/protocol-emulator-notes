#!/bin/sh
# Verilog-level cycle identity of the Delayed rewrite (test/test_latency.ml does the same under
# Cyclesim for the pattern; the demo instantiates Verilog memories, which Cyclesim cannot run).
#   test/rtl-compare/run.sh [BASE]   (BASE: commit holding the old rtl/gen, default 7cf2f05)
# Output: $OUT (default /var/tmp/latency-adopt/rtl-compare)/{pattern,demo}.log
set -eu
here=$(cd "$(dirname "$0")/../.." && pwd)
base=${1:-7cf2f05}
out=${OUT:-/var/tmp/latency-adopt/rtl-compare}
mkdir --parents "$out/new"
cd "$here"
opam exec --switch=5.3.0 -- dune build 2>&1
opam exec --switch=5.3.0 -- dune exec ./bin/emit.exe "$out/new"
for m in hdmi_pixel hdmi_pixel_demo; do
  git show "$base:prototypes/hdmi-ulx3s/rtl/gen/$m.v" | sed "s/^module $m (/module ${m}_old (/" > "$out/${m}_old.v"
done
# the demo's packet ROM: 8 fields from game field 24, as the board build
opam exec --switch=5.3.0 -- dune exec ./demo/gen_packets.exe 24 8 "$out/packets.hex"
{ git rev-parse HEAD; git status --porcelain -- .; echo "old from $base"; iverilog -V 2>&1 | head -1; } > "$out/commit.txt"
tb=test/rtl-compare/tb_compare.v
iverilog -g2012 -DOLD=hdmi_pixel_old -DNEW=hdmi_pixel -DCYCLES=900000 -o "$out/pattern.vvp" \
  $tb "$out/hdmi_pixel_old.v" "$out/new/hdmi_pixel.v"
(cd "$out" && nice ionice vvp -n pattern.vvp | tee pattern.log)
# negative control of the comparison: the end-to-end "latency" mutant must differ from the old design
mkdir --parents "$out/mutant"
opam exec --switch=5.3.0 -- dune exec ./bin/emit.exe "$out/mutant" latency
iverilog -g2012 -DOLD=hdmi_pixel_old -DNEW=hdmi_pixel -DCYCLES=900000 -o "$out/mutant.vvp" \
  $tb "$out/hdmi_pixel_old.v" "$out/mutant/hdmi_pixel.v"
(cd "$out" && nice ionice vvp -n mutant.vvp | tee mutant.log)
# the console draws its first field after about 950,000 clocks; 2,500,000 covers that and
# three and a half 640x480 frames of a filled frame buffer
iverilog -g2012 -DOLD=hdmi_pixel_demo_old -DNEW=hdmi_pixel_demo -DCYCLES=2500000 -o "$out/demo.vvp" \
  $tb "$out/hdmi_pixel_demo_old.v" "$out/new/hdmi_pixel_demo.v" rtl/packet_rom.v rtl/frame_buffer.v
(cd "$out" && nice ionice vvp -n demo.vvp | tee demo.log)
