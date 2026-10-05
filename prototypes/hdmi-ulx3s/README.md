# HDMI (DVI) output for the ULX3S, in Hardcaml

A 640x480@60 DVI output on the ULX3S's GPDI connector, so the video demos can be shown on an
ordinary monitor: a TMDS encoder and serialiser in Hardcaml, a test-pattern bitstream, a variant
showing the retro console's game, and the same block added to the emulator test bench
(`../fpga-ulx3s`). Plain DVI signalling (no HDMI data islands, so no sound), which HDMI sinks
accept. Nothing here has run on a board yet; the bring-up steps are in `../fpga-ulx3s/BRINGUP.md`,
step 11.

The design follows Gergo Erdi's Clash design for the same board (clash-flappysquare, branch
`ulx3s-hdmi`, MIT licence; `notes/prior-art-erdi-kmett.md` section 1.2), re-implemented rather than
translated, and cross-checked against it. The fpga4fun Verilog on that repository's master branch
has no licence and was not used.

## Results

| Check | Result |
| --- | --- |
| Encoder against the independent DVI model, all 256 values x 9 disparity states, 4 control codes | identical words and disparity on all 2,304 + 36 cases |
| Encoder: `decode(encode x) = x`, words in the 460-word valid set, counter = disparity of the words sent | all pass |
| Encoder: running disparity over a 1,000,000-word random stream, measured from the words | within -8..+8 (max 8) |
| Encoder planted bugs (4) | each caught; see below |
| End to end, 250 MHz single-edge and 125 MHz DDR, pixel clock in phase and offset | first complete frame identical to the pattern on every pixel; timing H 640/16/96/48, V 480/10/2/33, both syncs negative |
| End to end planted bugs (5) | each caught |
| End to end, retro console game (field 30) through the frame buffer, both serialisers | last complete frame identical to `demo/expected.ml` on every pixel |
| Place and route, 125 MHz DDR (chosen) | bit clock 195 MHz, pixel clock 80 MHz: passes; demo 183 / 45 MHz |
| Place and route, 250 MHz single-edge | bit clock 225 MHz at seed 1, 195 to 202 MHz at seeds 2 to 5: fails |

Evidence: `test/test_tmds.exe` output in `results/test_tmds.txt`, the end-to-end summaries and
decoder logs in `results/e2e/` (with `decoded.png` and `expected.png` for four of the passing
runs; each run's `commit.txt` names the commit it was measured on, ce7b884), build reports in
`reports/`.

## Build results

yosys 0.69+77 and nextpnr-0.11.1-30 (oss-cad-suite), LFE5U-85F CABGA381 speed 6, seed 1; reports
in `reports/<variant>/`, bitstreams in `/var/tmp/hdmi-ulx3s/build/`.

| Variant | FFs | LUT4/carry | DP16KD | bit clock fmax | pixel clock fmax |
| --- | --- | --- | --- | --- | --- |
| `./build.sh ddr` (test pattern) | 203 | 971 | 0 | 195.1 MHz, needs 125 | 80.0 MHz, needs 25 |
| `./build.sh ddr demo` | 1,549 | 2,501 | 81 | 182.7 MHz | 44.7 MHz |
| `./build.sh sdr` | 211 | 935 | 0 | **224.6 MHz, needs 250: fails** | 82.3 MHz |
| `../fpga-ulx3s/build_hdmi.sh` (emulator + HDMI) | 2,001 | 3,917 | 18 | 277.3 MHz | 84.8 MHz; 60 MHz core 67.0, USB 85.6 |
| `../fpga-ulx3s/build_hdmi.sh demo` | 3,347 | 5,435 | 99 | 264.8 MHz | 48.3 MHz; core 61.5, USB 85.6 |

Each uses one EHXPLLL (two with the emulator), 4 ODDRX1F in the DDR builds, and 14 I/O
(51 with the emulator). The worst pixel-to-bit-clock path nextpnr reports (unconstrained, as it does
not relate the two PLL outputs) is 1.8 to 2.0 ns, against the 24 ns (DDR) the synchroniser leaves.
In the emulator-with-demo build the 60 MHz core passes with only 0.4 ns of slack (61.5 MHz).

**Why DDR.** The 250 MHz single-edge serialiser fails timing at every seed tried (seed 1 after
taking the blinker's 27-bit comparison off the critical path, which had held it at 172 MHz).
Worse, its last flip-flop is placed in the fabric, not in the I/O cell, so each lane reaches its pad
over a different, untimed route (up to 3.0 ns in the seed-1 build), which is most of a 4 ns bit. The
DDR variant's ODDRX1F sits in the I/O cell of each pad, so the four lanes leave with matched
timing, and the fabric runs at half the rate with 70 MHz to spare. The single-edge variant is
kept, simulated, as the comparison.

## The TMDS encoder (`hw/tmds.ml`)

Written from the DVI 1.0 flowchart (section 3.2.2, figure 3-5) and control-code table (3.3.3): a
registered Mealy machine with one disparity accumulator, Gergo's shape. Bit 0 of a word is the
first on the wire. The accumulator is five bits: the running disparity takes the even values
-8..+8, and +8 does not fit in four signed bits.

### The independent model (`indep/`)

Written by a separate agent from the DVI 1.0 PDF alone, with no access to this encoder or to any
other TMDS source (`indep/NOTES.txt` records the PDF's URL and sha256, and the spec's ambiguities:
the PDF's flowchart loses its branch labels in text extraction, and the control codes are printed
first-bit-first, the reverse of an integer literal). It provides a decoder, a reference encoder, the
set of valid data words (460, as the specification says), word alignment from control-code runs,
and frame and timing recovery from three lanes. It has its own tests and eight planted mutants
(`dune test indep`).

### Tests and planted bugs (`test/test_tmds.ml`)

| encoder | vs reference | round trip | invalid words | counter vs words | control | stream bound | max running disparity |
| --- | --- | --- | --- | --- | --- | --- | --- |
| faithful | 0 | 0 | 0 | 0 | 0 | 0 | 8 |
| XOR/XNOR rule tests d[1] (Gergo) | 270 | 0 | 270 | 0 | 0 | 0 | 8 |
| 2 q_m[8] correction inverted (Gergo) | 1,632 | 0 | 0 | 1,632 | 0 | 729,392 | 276 |
| control code 01 sends 10 | 0 | 0 | 0 | 0 | 9 | 0 | 8 |
| no DC balancing | 816 | 0 | 0 | 2 | 0 | 951,769 | 4,556 |

No mutant is caught by the round trip: a DVI decoder needs only bits 8 and 9 to undo stage 1 and
stage 2, so it decodes all of them correctly. What catches them is comparison with the reference,
the valid-word set, the counter-versus-wire check, and the disparity bound.

### Cross-check against Gergo's encoder (`crosscheck/`)

`GergoTMDS.hs` transliterates his `tmdsEncode1` into plain Haskell (Clash's `Signed 4` as an `Int`
wrapped to -8..7; built with ghc, table in `gergo-table.txt`), and `gergo_check.exe` runs the table
through the independent model:

- every word decodes to the right value (0 failures in 2,048 pairs);
- 240 words are outside the 460 that a DVI encoder produces: his XOR/XNOR choice tests bit 1 of the
  pixel (`testBit d 1`) where the flowchart tests D[0] = 0;
- in both DC-balancing branches the 2 q_m[8] term is applied with q_m[8] inverted (`if tag1 then 0
  else 2`, against the flowchart's `2*q_m[8]`), so the accumulator stops tracking the wire: 1,430 of
  2,048 steps differ from the disparity of the word sent, and over the same 1,000,000-word stream
  the running disparity reaches 466 instead of 8. `Signed 4` also cannot hold +8.

So his encoder produces pictures that any sink decodes correctly but does not keep DC balance;
on DC-coupled HDMI links this probably does not matter in practice, which fits his design working
on monitors. Those three readings of the Clash source were also put to a second model family
(codex, gpt-6-luna), asked to refute them; it confirmed all three, with worked examples (0x1B for
the XNOR rule; 0xFF and 0x00 for the counter). We did not run Clash itself; the transliteration is
the evidence.

## The output path

- **Timing** (`hw/video_timing.ml`): 640x480@60 as CEA-861 format 1 and VESA DMT: H 16/96/48,
  V 10/2/33, 800 x 525, both syncs negative. Gergo's `RetroClash.VGA640x480` uses V 11/2/31 with
  a line counter of type `Index 524`, so his frames have 524 lines, one short of the standard;
  monitors evidently lock to it. We use the standard values. The pixel clock is 25.000 MHz
  (59.52 Hz) instead of 25.175 MHz, as Gergo's.
- **Pixel domain** (`hw/hdmi.ml`): raster -> pixel source (with a latency the syncs are delayed
  by) -> three encoders; blue carries HSYNC and VSYNC as c0 and c1.
- **Serialiser** (`hw/serialiser.ml`), four lanes, the fourth carrying the pixel clock as the
  constant word `0b00000_11111` through the same shift registers (Gergo routes the clock itself to
  the pin through a black box). Two variants, both simulated end to end:
  - 10:1 at 250 MHz, one bit per clock, plain output flip-flops (Gergo's choice);
  - 5:1 at 125 MHz, two bits per clock into ECP5 `ODDRX1F` (D0 first: Amaranth's ECP5 DDR buffer
    maps its rising-edge bit to D0). This is the one we use; see "Why DDR" above.
- **Clock crossing.** nextpnr does not relate two PLL outputs, so the transfer of the words from
  the pixel to the bit domain is safe by construction: the pixel domain flips a toggle with every
  word, the bit domain synchronises it through two flip-flops, arms on its first change and loads
  every n cycles from a counter. The load lands 3 to 4 bit clocks after the words change and at
  least 1 bit clock (125 MHz) or 6 (250 MHz) before the next change; metastability in the first
  flip-flop can move the arming by one cycle, which that window absorbs. A sticky "slip" LED lights
  if a later toggle arrives more than a cycle away from where the counter expects it. Simulated
  with the pixel edge exactly on a bit-clock edge (phase 0) and half a bit period away.
- **PLL** (`rtl/pll_sdr.v`, `rtl/pll_ddr.v`, generated by `ecppll`, oss-cad-suite): 25 MHz in;
  SDR: VCO 500 MHz, CLKOP / 2 = 250 MHz (feedback), CLKOS / 20 = 25 MHz with an 18 degree
  (2 ns) offset; DDR: VCO 625 MHz, CLKOP / 5 = 125 MHz (feedback), CLKOS / 25 = 25 MHz with a
  36 degree (4 ns) offset. Gergo's `clock.v` uses VCO 500 MHz: CLKOP / 4 = 125 MHz as feedback,
  CLKOS / 2 = 250 MHz, CLKOS2 / 20 = 25 MHz. The offsets keep pixel edges away from bit-clock
  edges; the design does not depend on them.
- **Pins** (`constraints/hdmi.lpf`): `gpdi_dp[0..3]` = blue A16, green A14, red A12, clock A17,
  `IO_TYPE=LVCMOS33D`, so the I/O buffer drives `gpdi_dn` (B16, C14, A13, B18) as the complement.
  Gergo drives both pins of each pair from fabric instead.
- **`wifi_gpio0` tied high**, as in Gergo's top ("keeps the board from rebooting"); copied as a
  habit, the mechanism not traced on the schematic.
- **LEDs**: 0 and 1 blink at 1 Hz from the pixel and the bit clock (Gergo's standing first check,
  now in `BRINGUP.md`), 2 PLL locked, 3 serialiser armed, 4 slip.

## End-to-end simulation (`e2e/`)

`e2e/run.sh sdr|ddr PHASE_PS [MUTANT]` simulates `hdmi_top.v` and the generated Verilog under
iverilog, with ideal clocks and an `ODDRX1F` model, samples the four pads once per bit time
(9,000,000 bit times, 2.1 frames), and `decode_capture.exe` decodes them with the independent
model: word alignment from control codes (the same on all lanes), the clock lane's word in every
slot, strict decoding (words outside the valid set are errors), running disparity within 8 on
every lane, timing measured from the stream, and the first complete frame compared pixel for
pixel with `Test_pattern.reference`; both are written as PNG. `e2e/run_all.sh` runs the four good
configurations and five negative controls, which must fail:

| control | caught by |
| --- | --- |
| pattern latency declared 0 (syncs one pixel off) | frame mismatch |
| Gergo's XOR/XNOR rule | strict decoding: invalid word |
| Gergo's q_m[8] correction | running disparity 646 on blue |
| wrong control code | inconsistent HSYNC period |
| ODDRX1F bit order swapped | lanes align differently (no alignment on two) |

The XNOR-rule control passes every image check: only the strict decoder sees it.

The test pattern (`hw/test_pattern.ml`): colour bars; r = x, g = y, b = x xor y (every byte on
every channel); a one-pixel checkerboard (a pixel slip or swapped bits destroy it); a grey ramp;
and a one-pixel white border (an off-by-one in the porches loses an edge).

## The retro console on HDMI (`demo/`, `-DHDMI_DEMO`)

`../retro-console/console.ml` (the chip's video generator, linked unchanged) runs on the 25 MHz
pixel clock, so a field takes 42.5 ms. The CPU's part, `game.ml`'s 54-byte packet per line, is
precomputed into a ROM (8 fields, looping; 103,680 bytes) and fed exactly as the console's own
testbench feeds it. Each console pixel is sampled at the middle of its 10 clocks into a 256 x 256
frame buffer, which the 640x480 raster reads at 2 x 2, centred (512 x 480, black side borders).
Colours come from an approximate palette (luma to Y, hue to a fixed-saturation angle, BT.601),
not from the composite path. `e2e/run_demo.sh` simulates one static field (game field 30) for
68 ms and compares the last complete frame with `demo/expected.ml`: the console's reference line
model (from `../retro-console/main.ml`, where it is checked against the RTL), the palette and the
scaling.

A second-family review (codex, gpt-6-luna) of the clock crossing, ODDRX1F use, PLLs, resets, TMDS
details and the demo addressing, asked for what would fail on the board, found no defect; it named
as unproven what only the board can show: lock, the real PLL phase, the pseudo-differential pads,
and whether a given monitor accepts 25.000 MHz.

## Files

| Path | What |
| --- | --- |
| `hw/` | Hardcaml: `tmds.ml`, `video_timing.ml`, `test_pattern.ml`, `serialiser.ml`, `hdmi.ml` |
| `indep/` | the independent DVI model and its tests |
| `test/test_tmds.ml` | encoder against the model, mutants |
| `crosscheck/` | Gergo's encoder, transliterated, and the comparison |
| `bin/emit.ml` | writes `rtl/gen/*.v` |
| `rtl/hdmi_out.v`, `rtl/hdmi_top.v` | the HDMI block, and the stand-alone top |
| `rtl/pll_*.v`, `rtl/packet_rom.v`, `rtl/frame_buffer.v` | PLLs, demo memories |
| `constraints/hdmi.lpf`, `build.sh`, `reports/` | build and its reports |
| `e2e/` | testbench, simulation models, capture decoder, scripts |
| `demo/` | console (symlinks), packet generator, HDMI source, expected frame |
| `results/` | evidence |

Commands (from this directory; oss-cad-suite on `PATH`):

```
opam exec --switch=5.3.0 -- dune build && opam exec --switch=5.3.0 -- dune test
opam exec --switch=5.3.0 -- dune exec ./test/test_tmds.exe
opam exec --switch=5.3.0 -- dune exec ./crosscheck/gergo_check.exe crosscheck/gergo-table.txt
e2e/run_all.sh; e2e/run_demo.sh sdr 30
./build.sh sdr; ./build.sh ddr; ./build.sh ddr demo
../fpga-ulx3s/build_hdmi.sh            # the emulator test bench with HDMI added
```
