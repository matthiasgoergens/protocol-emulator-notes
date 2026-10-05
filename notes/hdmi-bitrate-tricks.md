# HDMI/DVI from the chip despite the bit-rate limit: tricks (brainstorm, 2026-10-05)

Reading and thinking only. Nothing here was built or measured on a monitor. Labels: **[P]** primary
(read the source or ran the tool here), **[S]** secondary (web search summary or memory; verify
before relying on it).

## The problem in numbers

Four bit slots per clock per pin give 4 x f Mbit/s per lane. TMDS needs 10 bits per pixel per lane,
so pixel clock = 0.4 x chip clock (one bit per quarter-clock slot):

| Chip clock | Bit rate | Pixel clock | 800x525 refresh |
| --- | --- | --- | --- |
| 60.85 MHz (plan) | 243.4 Mbit/s | 24.34 MHz | 57.95 Hz |
| 62.5 MHz | 250 | 25.000 | 59.52 Hz |
| 62.9375 MHz | 251.75 | 25.175 (nominal) | 59.94 Hz |
| 63.0 MHz | 252 | 25.2 | 60.0 Hz |

(arithmetic run in a shell). The gap is 3.4 %: from 60.85 to 62.9375 MHz. With 10 slots per pixel,
a pixel is 2.5 clocks, so two pixels are 5 clocks = five nibbles; the 10-to-4 gearbox repeats every
5 clocks. The clock lane (0000011111) is 5 slots high, 5 low, a slow signal from the same sequence.

## Ranked tricks

### 1. Keep 60.85 MHz and choose timing totals that make 24.34 MHz an exact 60 Hz mode (cheapest)

Pixel clock 24.34 MHz with totals 780 x 520 gives 60.01 Hz (24.34e6 / 405,600). Blanking shrinks
from 160 to 140 pixels horizontally (e.g. 16/64/60) and from 45 to 40 lines vertically
(e.g. 10/2/28). The sink measures hsync (31.2 kHz) and vsync from the sync pulses, so it sees an
ordinary-looking 640x480 at 60 Hz, only with a pixel clock 3.3 % under 25.175.
- Standards already walk this road **[P]**: `cvt 640 480 60` (VESA CVT) prints pclk 23.75 MHz, and
  `cvt -r 640 480 60` (reduced blanking) prints 23.50 MHz (modeline 640 688 720 800 / 480 483 487
  494). So 640x480 below 25 MHz is a defined VESA mode, though a sink's HDMI/DVI receiver may still
  refuse it; the EDID-listed CVT-RB mode over a TMDS link is the case to test.
- Unknown: the TMDS receiver's lock range. The HDMI spec says the TMDS clock is at least 25 MHz and
  that formats below that must use pixel repetition **[S]** (web search summary of HDMI 1.3/1.4).
  DVI receiver chips are typically specified from 25 MHz **[S]**, but the PLL usually has margin.
- Backlog item already exists: test a 24 MHz pixel clock on real monitors with the ULX3S build.
  Add 24.34 MHz with 780x520, a CVT-RB 23.5 MHz mode, and a capture dongle (dongles, scalers and
  TV chips are the pickiest sinks).

### 2. Overclock to 62.5 MHz or 62.9375 MHz (3 % to 3.4 %)

Pixel clock 25.000 MHz (already the ULX3S build's clock) or exact 25.175. PicoDVI ran 25.2 MHz,
and the ULX3S/Gergo design 25.000 **[P]**, and every monitor tried took them. Exact 62.9375 MHz is
from the RP2350 (clock supplied by it): PLL ratios are unverified. Cost: timing closure at +3.4 %
(STA slack at 60 MHz was large for the stage: +2.05 ns worst setup **[P]** from the multiphase README, but the
sequencer has not been checked at 63 MHz), and the pad question, now at 3.97 ns pulses instead of
4.11 ns. Asking Jane Street is on the backlog. Combine with 1: a 62.5 MHz clock with 800x525 totals
is the 25.000 MHz mode that is known to work on monitors.

### 3. Pad-relief: share edges across two pins and combine outside (if the pad is the limit)

TMDS words are transition-minimised, so the pin sees fewer edges than bit slots (the
minimum-transition stage keeps at most about four transitions in the eight data bits **[S]**,
memory of the DVI flowchart; measure it on the 52-word palette, which is a small exhaustive
calculation). What the pad must pass is the shortest pulse, one bit: 4 ns. Sending edges
alternately on pin A and pin B and XORing them on a board (74LVC1G86-class gate) means each pin
sees pulses of at least two bit times (about 8 ns, 125 MHz toggling) and the board gate sees the
rest. The on-chip stage already does exactly that XOR with four lanes, so it is the same structure
moved outside the pad. Cost: a daughter board with a gate per lane (or an RZ + OR scheme), and
extra output pins (16 outputs on Tiny Tapeout: 3 lanes x 2 + clock = 7 plus the complement pins if
driven differentially). Only useful if pad simulation says the 4 ns pulse is the problem and
8 ns is fine. Does not help the clock-grid problem.

### 4. Edge-placement mode with the delay line: decouple pixel clock from chip clock

Generate TMDS as edges, not bits: an NCO (like the FM transmitter's `nco.ml` **[P]** in
`prototypes/multiphase`) computes each edge's time from a 25.175 MHz pixel phase, the delay-line
DTC places it with about 50 to 100 ps taps, and the four-phase lanes supply the coarse part. Then
the pixel clock is exactly 25.175 MHz while the chip stays at 60.85 MHz; the bit slot (3.97 ns)
is shorter than the quarter-clock (4.11 ns) so slots are not on the quarter grid. Edge budget:
about 9.7 edge capacity per pin per pixel (4 per clock x 2.42 clocks) against at most about 6
transitions in a 10-bit word **[S]**. Problems, honestly:
- The pad still sees the 3.97 ns pulses; pad speed is unchanged.
- With quarter-period delay lines, lane p can only place its edge within quarter p, so two edges
  in neighbouring bit slots can collide in one quarter window about once per 29 bits in a
  0101... run (drift 0.14 ns per slot against a 4.11 ns window; my arithmetic). Palette selection
  (choose words with no dense transition runs) can avoid it; a whole-period line (7,800 um2 per lane **[P]**)
  avoids it by hardware.
- Large area and a calibration problem, for 3 % of rate. Only worth it if trick 1 fails on real
  monitors and the overclock is refused.
- Upside: also serves other fractional-clock protocols.

### 5. Standard modes with low TMDS clock: none exist (dead end, but checked)

- Lowest standard TMDS clock: 640x480p60 at 25.175/25.2 MHz (CEA-861 format 1) **[S]**.
- 720x480i/576i and 240p/288p have 13.5 MHz pixel clocks; HDMI transmits them with pixel
  repetition at a TMDS clock of 27 MHz **[S]**, i.e. 270 Mbit/s, higher than 640x480. So 480i with
  repetition is worse.
- A non-repeated 13.5 MHz TMDS clock (135 Mbit/s, trivially in reach: 2 slots per clock) is
  below the 25 MHz minimum. Sinks that lock would be rare; test cheaply with the dongle. If a
  sink accepts 12 to 13.5 MHz, the whole problem disappears (240p/480i over DVI). I found no
  evidence either way.

### 6. Do less than 640x480 per second: low-frame-rate modes (PicoDVI precedent)

PicoDVI runs 1280x720 "30 Hz" as 720p60 timing at half the pixel clock (37.1 MHz instead of
74.25), commenting that this is "commonly accepted" **[P]** (`software/libdvi/dvi_timing.c`). That
supports sinks tolerating a non-standard rate of vertical refresh at an in-range TMDS clock. It
does not help below 25 MHz, but it supports the dimension "totals and refresh may be unusual".
With the pixel clock fixed near 24.34 MHz, a 30 Hz mode of 800x525 doubled to 1600x525... is
not useful; keep 60 Hz.

### 7. Hybrid fallback: the chip makes pixels, the RP2350 serialises

If pads or monitors refuse everything: the chip streams palette indices at about 24 MHz on 16
output pins (5 bits per channel plus syncs, or 3 x 6 bits if the bidirectional pins allow) and the
RP2350 turns them into DVI with its HSTX peripheral and TMDS encoder (secondary, from memory of
the RP2350 datasheet; the multiphase README lists HSTX as unverified **[P]**). It loses the "video
from the chip alone" story, but keeps the video generator on the chip. Last resort.

## Dropped ideas (and why)

- **More pins per lane, bit-interleaved.** Interleaving two half-rate pins needs a mux at bit rate
  outside; the XOR variant (trick 3) is the only version that works. Splitting bits across pins
  does not reduce the pulse width.
- **Only some lanes at full rate.** TMDS lanes must all run at the same rate and be aligned; the
  blue lane carries syncs. Driving a grey picture from one stream into red and green saves pins,
  not rate.
- **Sub-quarter-clock slots (5 slots per clock)** would raise the bit rate to 304 Mbit/s;
  pad-limited and not needed.

## What transfers from PicoDVI (Luke Wren) [P: README, `libdvi/*.c`, `*.pio`, `tmds_table_gen.py`]

- Bit clock = system clock = 252 MHz on RP2040, 10 cycles per pixel, PIO shifting one bit per
  cycle. The clock lane is a slow signal from the same PIO side-set pattern (the 2-bit
  side-set drives the true and complement pins of each lane: `out pc, 1 side 0b10` /
  `side 0b01`). Our equivalent: complement pin pairs, or the board gate.
- Monitors: 252 MHz bit clock (25.2 MHz) takes VGA on "every monitor" tried; scope eye-mask
  tests passed at 252 Mbit/s and 372 Mbit/s (720p30) with *GPIO pads*, reduced drive strength
  and slew, 8 resistors as the coupling circuit. This is evidence that general-purpose pads can
  do about 250 Mbit/s; it is not evidence about IHP's pads.
- The project used bit clocks within about 0.1 to 0.5 % of nominal (252.0 vs 251.75, 354.0 vs
  355.25, 372 vs 371.25 MHz) for PLL convenience. It never went 3 % low, so it supplies no evidence for trick 1.
- Stateless TMDS: encode x then x XOR 1 from zero disparity and the pair has net zero disparity,
  so the encoder is a lookup table of pairs (7 bits per channel at half horizontal resolution).
  Their table generator is an exact transcription of the DVI flowchart. This is the same idea
  as our balanced palette; the pair trick gives 128 levels per channel at half resolution
  where our single-word palette gives 52 levels at full resolution. A mixed table (pair
  entries for flat areas) is possible. Either way it removes the encoder, not the rate problem.
- Bring-up trick: run at 12 MHz and use a UART-framed variant (10 bits plus start and stop) to
  capture the TMDS stream on a logic analyser. We can do the same: run the chip at about 1/20
  clock with the stream, decode it with `prototypes/hdmi-ulx3s/indep/`.
- Control symbols are pre-doubled in words (`dvi_ctrl_syms`) and the empty scanline is a pair of
  DC-balanced symbols repeated via a DMA ring; for us, the sequencer can loop a 5-clock pattern.
- The RP2350 version of the same library (the Readme's preview) uses SIO TMDS encoders and
  HSTX is not in this tree; I did not look for it.

## Suggested order of work

1. Pad simulation result decides whether 4 ns pulses are possible at all (gates 2, 3, 4).
2. In parallel, monitor test with ULX3S at 24.34 MHz / 780x520 (trick 1), CVT-RB 23.5 MHz, 25.000 MHz,
   and, as a long shot, 13.5 MHz TMDS (trick 5). Several monitors, one capture dongle, one
   TV or scaler. Log which sink takes which clock.
3. If trick 1 works on most sinks: stay at 60.85 MHz, no overclock, the NTSC clock plan unharmed.
4. If not: ask about 62.5 MHz; if refused, consider trick 4 (delay line) or trick 7.
