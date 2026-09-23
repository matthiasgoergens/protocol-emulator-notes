# Semiring ring: one simple cell, three effects

The first thing to build from `notes/prior-art-triage.md`. Sixteen cells in a ring. Each cell holds a 24-bit signed value and updates once per pixel from the old values:

    r_i <- sat (op_i x y),  op in {add, sub, max, min}
    x = r_i or r_(i+1..i+4)
    y = r_(i+1..i+4) or a constant

The CPU loads all 16 values before every line: 48 bytes, shifted straight through the cell registers during horizontal blanking, so the state is not stored twice. Operations, sources and constants are per frame. Four sign bits pick an entry in a 16-entry lookup table. An entry is either a colour or "use the ramp", which is a clamped, shifted distance read from one cell. Timing and colour output are the PAL console's.

## One configuration, three shapes

All three shapes are drawn in the same frame by one configuration (`Model.cfg_of_scene`):

| Cells | Shape | How it works |
|---|---|---|
| 0–1 | Filled ellipse | Second-order forward differencing along the line. The host computes each line's starting value, including the y term. |
| 2–5 | Cubic wiggle band | Third-order differences in 16.16 fixed point. Two copies of F offset by ±w share one difference chain, and the band is F + w ≥ 0 > F − w. |
| 6–13 | Glow around three moving centres | Three quadratic distance fields, combined with `min` (min-plus), then shown through the ramp. Where glows overlap they merge instead of adding. |

Each glow source sits at a different pipeline depth behind the `min` cells. The host compensates by starting that source a pixel or two ahead.

The host also keeps lines that never reach the wiggle band out of saturation. It moves their starting value towards zero while the band stays out of reach, and the model counts saturating results so that a scene which leaves the exact range cannot pass silently.

## Checks

- **Model against direct evaluation** (`main.exe check 60`): no forward differencing, no pipeline. Zero of 3,686,400 pixels differ, with zero saturations.
- **Planted faults** (`main.exe controls`): all five are caught. The mismatches range from 19,453 to 463,254 pixels over 10 frames. The faults are:
  - one wrong operation;
  - one wrong source;
  - two wrong constants;
  - a band reading the wrong difference.
- **Content check:** the histogram shows all three shapes present.
- **RTL against the model** (`main.exe rtlcheck 3`): zero of 184,320 samples differ. A min-to-max fault planted in the RTL changes 9,123 samples.
- **TV path:** `main.exe dump 48 reel`, then `uv run ../retro-console/console_tv.py frames reel`, gives `out/reel.gif` and `out/stills.png`. All three shapes decode cleanly.
  - Circles look wide because PAL pixels at 256 across are wider than tall. The host can correct this in its coefficients.

## Area (Yosys 0.69, sg13g2 typical corner)

- **First version: 203,611 µm².** Each cell had a separate adder, subtractor and two comparators. The log is in `out/separate-units/`.
- **Current version: 169,641 µm².** Each cell has one adder with conditional inversion, and the sign of x − y decides max and min.

For comparison, the whole retro console is 94,319 µm². So the ring is 1.8 times the console, or about a quarter of the 0.7 mm² budget.

Where the area goes: 1,277 flip-flops come to about 63k µm², and 848 of them are configuration bits. Most of the remaining logic is the two 5-way, 24-bit source multiplexers per cell.

Cheaper designs not yet tried:

- sharing adders across the 10 clocks of a pixel;
- fewer source options;
- narrower cells where 24 bits are not needed (only the wiggle needs them);
- latches or an SRAM macro for the configuration.
