# Compiling for memory that forgets (note, 2026-09-25)

The gain-cell memory in `prototypes/gain-cell/` stores bits that expire. This note covers how a
compiler could use such memory when lifetimes are uneven: between corners and temperatures,
between rows, and between cell designs placed deliberately in one array. The measurements are
SPICE on the IHP PDK models, not silicon.

## What the cells measured (worst case unless stated)

The PDK SRAM bit cell is 3.01 µm² (under relaxed SRAM rules); a standard-rule 6T is 3.41 µm²
(`prototypes/sram-cut/`).

| row type | area per bit (strap every 32 columns) | lifetime of a stored 1 |
|---|---|---|
| thick-oxide write, 3T | 2.88 µm² (1.04× the PDK SRAM bit cell) | ≥ 3 ms; 12–20 ms at tt |
| thin-oxide write, 3T | 2.20 µm² (1.37× the PDK SRAM bit cell) | 1.2 µs ff/85 °C; 8 µs tt/85 °C; 120 µs tt/27 °C; about 2 ms ss/27 °C |
| thick write and thick storage transistor | about 3.1 µm² (not drawn) | droop about 2 mV/ms, but needs a sense amplifier to read |

Both drawn row types pass IHP's DRC in one mixed array on shared bit lines
(`drc/v3-ARRAY_MIXED.log`, `lvs/mixed/extracted.cir`).

Four properties shape the compiler's job.
1. **Only 1s decay.** A stored 0 stays below 0.03 V for 10 ms in every corner.
2. **Temperature and corner dominate.** Lifetime varies 100-fold between tt/27 °C and ff/85 °C
   for thin oxide, and a comparable amount between dies.
3. **What leaks differs by design.**
   - In the thick-oxide cell the stored 1 leaks through the storage transistor's thin gate,
     not through the write transistor (`retention/leak.py`).
   - A ±100 mV threshold shift of the write transistor leaves the decay rate unchanged.
   - Gate tunnelling depends on oxide thickness, which varies mostly between dies, so lifetimes
     *within* one array may be fairly uniform. The PDK's mismatch model varies only threshold
     and mobility, so it cannot confirm this; only silicon can.
   - The thin-oxide cell leaks through its write transistor's channel, which mismatch in its
     threshold does move (σ ≈ 28 mV, so a 4σ cell leaks one to two decades more).
4. **A read costs little, and refresh is a read followed by a write.**

## A compiler model

**Each row has a deadline.** A row r holds data valid until `t_write(r) + L(r, T)`. L is the
row's lifetime at the current temperature bin T. The compiler treats rows the way register
allocation treats registers, with one change: an interval may only occupy row r if it is at
most L(r, T) long. A value's interval runs from its definition to its last use.

**Most values need no refresh at all.** Values read for the last time before they expire need
nothing. A systolic pipeline's intermediate values live for a few cycles; a video line buffer
lives one line, 64 µs, which fits even the thin-oxide rows at room temperature. Refresh is the
analogue of spilling: a long-lived value either goes to a row with a long enough L, or gets an
inserted read-write pair. It can also move to another row, which refreshes it for free.

**Heterogeneous rows are a placement choice.** Short intervals go to dense thin-oxide rows,
long ones to thick-oxide rows. The ratio of row types in the array is a design parameter, set
from the interval histogram of the target programs. That makes it the memory version of
choosing register file sizes.

**Refresh bandwidth, where it is needed.** A bank of n rows with lifetime L at clock period t
spends n·t/L of its cycles refreshing. Thin-oxide rows at ff/85 °C in a 32-row bank at 50 MHz
spend 53%; at tt/85 °C 8%; at room temperature under 1%. The energy is about 45 fJ per bit
refreshed, so about 37 nW per bit at worst. Only rows holding live long-lived data need
refreshing, which the compiler knows exactly. That is stronger than a controller's guess at
liveness (Refrint, below).

**Temperature needs a schedule per bin, and a sensor.** Precompile schedules for a few
temperature bins and switch between them, as DVFS does with voltage and frequency tables. The
sensor can be the memory itself. Keep a canary row, written with 1s and read back at the
lifetime the current bin assumes; when it fails, move to the hotter bin's schedule. Heating the
chip makes the reverse move safe to test.

**Detect expiry instead of trusting the schedule.** Every decay error turns a 1 into a 0, so the
errors are one-directional. A Berger code (the count of 0s in the word, stored alongside it)
detects any number of such errors: decay can only raise the count of 0s, while the stored count
can only fall, since its own 1 bits decay too. It costs log₂(n+1) check bits for an n-bit word,
5 for 16. A read that fails the check reports that the data expired, so the scheduler can be
optimistic and fall back on detection. This is the same safety net the DRAM literature reaches
with ECC plus re-testing, but much cheaper, because the error model is one-sided.

**Encode for the asymmetry.** Since only 1s decay, a per-row inversion bit, set when the row is
written, stores whichever polarity has fewer 1s. Sparse or mostly-zero data then lives longer.
Mostly-zero data is common: bitmaps, masks, most video.

## Uneven lifetimes within an array

**Random variation.** No layout can place a random weak cell, so the answer is to measure it.
- **Profile after manufacture:** a built-in test writes 1s, waits, and reads, bisecting the
  wait per row. The result goes into a small per-row table of lifetime classes, which the
  compiler or runtime reads.
- **Do not trust one profile.** The DRAM literature warns that it is not enough: data-pattern
  dependence and variable retention time make cells change class
  ([Liu et al., ISCA 2013][liu13]).
  - All-0 and all-1 patterns alone would miss about 90% of failing cells, a figure for
    commodity DRAM, whose cells couple to their neighbours more than ours.
  - Guard bands alone never converge: 2× catches 85–95% of intermittent cells, and 5× still
    misses some ([Khan et al., SIGMETRICS 2014][khan14]).
- **What works:** static bins plus promotion of a row to a faster bin the moment it is seen to
  fail ([AVATAR, DSN 2015][avatar]), plus error detection. The Berger check above provides the
  "seen to fail" signal for free.

**Position-dependent effects.** These are systematic, so the layout can address them:
- **Array edges:** lithography, stress and well proximity differ at the edges. The standard fix
  is dummy rows and columns.
- **Distance from a ground strap:** the ground bar's resistance raises the source of the
  storage transistors far from a strap, which slows reads there.
- **Nearness to hot logic:** placement, or longer-lived rows next to heat sources.
- **Bit lines that switch often** couple into the storage nodes along them.

For systematic effects, varying the cell design by position works: wider straps, a different
write-transistor length at the edges, a different row type near hot spots. The mixed array
shows the layout supports it, since row pairs of different designs stack freely on one column
pitch. The compiler then sees position-dependent lifetimes and read latencies as known
constants, not measurements.

## Prior art (checked against the papers, except where marked)

- [RAIDR, Liu et al., ISCA 2012][raidr]: retention is long-tailed, with fewer than 1,000 of
  over 10¹¹ cells needing refresh below 256 ms. Binning rows into rate classes cut refreshes
  by 74.6%.
- [Flikker, Liu et al., ASPLOS 2011][flikker]: programmer-classified critical and non-critical
  data in regions refreshed at different rates, saving 20–25% of memory power. It is the
  closest precedent for software-directed placement, but its classification is manual.
- [Refrint, Agrawal et al., HPCA 2013][refrint]: eDRAM cache refresh that skips inactive lines,
  predicting liveness in hardware.
- Emma, Montoye and Reohr (IBM), [US 8,020,073][ibm]: "passive expiration"; data not
  refreshed, with expiry detected on access. A patent, not evaluated in a paper.
- Giterman et al., 3T gain cell in 0.18 µm (IEEE TVLSI 2016): 0.8 ms worst-case retention on a
  single supply, and a 6.97 µm² bit cell, 43% smaller than 6T SRAM there. It stacks metal over
  the cell to add storage capacitance, and holds WBL at VDD/2 when idle. Both apply here.
  (Checked against the paper's text.)
- Giterman et al., 4T gain cell in 65 nm (ISCAS 2014): 8.29 ms at 27 °C and 3.98 ms at 85 °C,
  with a −700 mV write word line. (Checked against the paper's text.)
- MCAIMem (arXiv:2312.03559, 2023): mixes a 6T SRAM cell with seven widened 2T gain cells in
  each 8-bit word, lengthening refresh about 10×. It is the closest precedent for mixing cell
  designs within one array; its numbers are relayed from the survey, not re-checked.

A survey of the refresh-scheduling, eDRAM and gain-cell literature (four search passes, papers
read in full) found nothing that combines all three of:
- compiler-derived value lifetimes;
- per-row retention profiles;
- placement onto gain-cell rows of deliberately different designs.

A patent lead on compiler refresh hints (US 8,108,609 and 8,024,513) is unchecked. Check it
before claiming novelty.

[liu13]: https://users.ece.cmu.edu/~omutlu/pub/dram-retention-time-characterization_isca13.pdf
[khan14]: https://users.ece.cmu.edu/~omutlu/pub/error-mitigation-for-intermittent-dram-failures_sigmetrics14.pdf
[avatar]: https://www.istc-cc.cmu.edu/publications/papers/2015/avatar-dram-refresh_dsn15.pdf
[raidr]: https://users.ece.cmu.edu/~omutlu/pub/raidr-dram-refresh_isca12.pdf
[flikker]: https://www.microsoft.com/en-us/research/wp-content/uploads/2016/02/ASPLOS_2011.pdf
[refrint]: https://iacoma.cs.uiuc.edu/iacoma-papers/PRES/present_hpca13_3.pdf
[ibm]: https://patents.google.com/patent/US8020073B2/en

## Next

- Monte Carlo of the thin-oxide cell, which is where mismatch matters, to give its lifetime
  distribution.
- A sense amplifier. It would make the thick-storage cell readable, and let the others read
  lower levels.
- Metal storage capacitance over the cell, and WBL at VDD/2 when idle.
- A toy allocator: rows with deadlines, a trace of intervals from a real kernel (the video line
  buffer, a systolic pipeline), and the refresh count and row-type mix it needs.
