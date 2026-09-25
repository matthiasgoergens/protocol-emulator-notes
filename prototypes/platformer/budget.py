# /// script
# requires-python = ">=3.11"
# ///
"""Line-packet bandwidth and where tile patterns should live, with the sources of every input.
    uv run budget.py > results/budget.txt"""

CLK = 53.203425e6                  # 12 x PAL fsc
LINE_CLOCKS = 3404                 # vprog.ml (851 sequencer slots)
LINE_US = LINE_CLOCKS / CLK * 1e6
FIELD_MS = 312 * LINE_CLOCKS / CLK * 1e3
ENTRY_BITS = 19                    # video.ml: 3-bit tag + 16-bit data
NIBBLE_CLOCKS = 2                  # sim.ml: pin sampler, clocked mode, 4 pins, one strobe edge per 2 clocks
ENTRY_CLOCKS = 5 * NIBBLE_CLOCKS   # 19 bits in five nibbles

# storage costs (../systolic-storage/results/storage_options.txt, periphery estimated from standard cells)
GC_THICK_UM2_PER_BIT = {256 * 32: 33777 / 8192, 128 * 32: 17992 / 4096, 32 * 16: 3802 / 512, 32 * 32: 6153 / 1024}
FLOP_UM2 = 48.99                   # dfrbpq_1, the same file
LATCH_UM2_PER_BIT = 46.3           # latch register file, same file
THICK_LIFE_WORST_US = 3100.0       # thick 3T at ff/85 C, same file (lower bound)
THIN_LIFE_TT27_US = 118.8          # thin 3T at tt/27 C, same file
PUMPED_LIFE_WORST_MS = 368.0       # ../gain-cell/tricks-thick/README.md, all-thick + pumped WWL + 1 fF (not drawn)

print(f"line {LINE_CLOCKS} clocks = {LINE_US:.2f} us; field 312 lines = {FIELD_MS:.2f} ms\n")

print("== Line packet per visible line (scene.ml encode; counts in entries of 19 bits)")
fixed = 1 + 2 * 5 + 15 * (1 + 3) + 1        # PIXELS, 2 tile records of 5, 15 x (WAIT + 3-word record), END
lut = 1 + 4                                  # rolling colour-table refresh, sim.ml
for nspr in (0, 4, 8, 16):
    n = fixed + lut + 5 * nspr
    print(f"  {nspr:2d} sprite cells: {n:3d} entries = {n * ENTRY_BITS / 8:6.1f} bytes; host link busy {n * ENTRY_CLOCKS} of {LINE_CLOCKS} clocks ({100 * n * ENTRY_CLOCKS / LINE_CLOCKS:.0f} %)")
cap = LINE_CLOCKS // ENTRY_CLOCKS
print(f"  link capacity at one nibble per {NIBBLE_CLOCKS} clocks: {cap} entries per line "
      f"({4 / NIBBLE_CLOCKS * CLK / 8 / 1e6:.1f} MB/s of payload bits)")
print(f"  the special-purpose console: 54 bytes per line (../retro-console/console.ml)")
peak = (fixed + lut + 5 * 16) * ENTRY_BITS / 8 / (LINE_US * 1e-6) / 1e6
print(f"  peak (16 sprites on every visible line): {peak:.2f} MB/s\n")

print("== Where tile patterns live")
lb_bits = 2 * 256 * ENTRY_BITS
print(f"  (a) streamed per line into a ping-pong line buffer (chosen): {lb_bits} bits "
      f"(2 banks x 256 x {ENTRY_BITS}); a value lives at most 2 lines = {2 * LINE_US:.0f} us")
print(f"      thick gain cells at {GC_THICK_UM2_PER_BIT[256 * 32]:.2f} um2/bit (256x32 bank): {lb_bits * GC_THICK_UM2_PER_BIT[256 * 32]:,.0f} um2;"
      f" lifetime {THICK_LIFE_WORST_US:.0f} us worst >> {2 * LINE_US:.0f} us: no refresh ever")
print(f"      thin cells: {THIN_LIFE_TT27_US} us at tt/27 C < {2 * LINE_US:.0f} us: too short even at room temperature")
print(f"      flops instead: {lb_bits * FLOP_UM2:,.0f} um2")
for ntiles in (64, 128):
    bits = ntiles * 256 * 2
    area = bits * GC_THICK_UM2_PER_BIT[256 * 32]
    words = bits // 32
    rate = words / (0.8 * THICK_LIFE_WORST_US * 1e-6)
    print(f"  (b) on-chip cache of {ntiles} tiles (16x16, 2 bpp): {bits} bits = {area:,.0f} um2 in thick gain cells"
          f" (+ tile map or per-line indices)")
    print(f"      each tile row is read once per frame ({FIELD_MS:.1f} ms) but lives >= {THICK_LIFE_WORST_US / 1000:.1f} ms:"
          f" reads cannot keep it alive; refresh {rate / 1e6:.2f} M words/s = {100 * rate / CLK:.2f} % of a 32-bit port")
    print(f"      with the pumped all-thick cell ({PUMPED_LIFE_WORST_MS:.0f} ms worst, not drawn, needs a 2.2 V word-line pump and a sense amplifier):"
          f" a rewrite-on-read keeps on-screen tiles alive, off-screen ones expire after {PUMPED_LIFE_WORST_MS / FIELD_MS:.0f} fields;"
          f" or the host re-sends the whole set every {PUMPED_LIFE_WORST_MS * 0.8 / FIELD_MS:.0f} fields = {bits / 8 / (PUMPED_LIFE_WORST_MS * 0.8 / FIELD_MS * 312):.1f} bytes per line")
    print(f"  (c) the same {ntiles} tiles in flops: {bits * FLOP_UM2:,.0f} um2")
print(f"  (d) a 16-tile flop cache: {16 * 512 * FLOP_UM2:,.0f} um2")
print(f"  RP2350 SRAM: 520 KB; 128 tiles are {128 * 256 * 2 // 8} bytes of it\n")

print("== Colour lookup table (64 x 14 bits)")
bits = 64 * 14
print(f"  {bits} bits: flops {bits * FLOP_UM2:,.0f} um2; latches {bits * LATCH_UM2_PER_BIT:,.0f} um2;"
      f" thick gain cells {bits * GC_THICK_UM2_PER_BIT[32 * 32]:,.0f} um2 (32x32 bank estimate)")
print(f"  read every pixel, but the 3T read does not restore: the host rewrites 4 entries per line,"
      f" all 64 every 16 lines = {16 * LINE_US / 1000:.2f} ms < {THICK_LIFE_WORST_US / 1000:.1f} ms (sim.ml measures the oldest entry read)")
