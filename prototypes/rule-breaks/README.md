# Breaking layout rules in IHP SG13G2: what it buys and what it costs

The question: at IHP's standard rules no static cell gets under 3.4 µm² (`../sram-cut/`), and
the gain cells are 2.20–3.10 µm² (`../gain-cell/`). IHP's own SRAM bit cell (3.01 µm²) passes
DRC only because of an SRAM marker layer (25/0). How much density could we get by breaking rules,
starting with the breaks IHP itself makes, and what would we pay?

**Short answer.**

- **Tier 0: IHP's own values.** These are the values IHP's bit cell uses under its SRAM marker
  (Activ enclosure of Cont 0.02 across a diffusion, poly end cap 0.13). Applied to our gain
  cells they make every variant **14 % smaller**, with no change in the row height:
  - thin 3T: 2.20 → 1.89 µm²;
  - thick-write 3T: 2.88 → 2.48 µm²;
  - all-thick 3T: 3.10 → 2.66 µm².

  Our 6T becomes the PDK cell's 3.01 µm², 12 % smaller.
- **Tier 1** adds the same contact break along the diffusions, for 17–19 %.
- **Tier 2: the most valuable single break.** Relax the thick-oxide keep-out (TGO.a/TGO.b
  0.27 → 0.105) with the read strip kept at 0.30, so the electricals are unchanged. Adding
  Cnt.c 0.02 along the strips and the 0.13 end cap takes the **thick-write cell from 2.88 to
  2.31 µm² (−20 %)**, and to 2.23 µm² (−23 %) with Cnt.f 0.07 as well. That is about the density
  of today's standard-rule thin cell (2.20), with the thick cell's millisecond retention. With
  the 0.20 strip it would be 2.01 µm², but that cell does not read at ss/27 °C.
- **The cost of tier 0 is electrical as well as procedural.** The narrower diffusion makes the
  storage and read transistors W 0.20 instead of 0.30.
  - **It breaks the thick-write cell's read.** At ss/27 °C the written 1 (0.33 V) falls below
    the readable level (0.39 V), even with a 100 ns write and a 20 ns sense. At W 0.30 the margin
    was only 12 mV to begin with.
  - The level-shifted thin cell loses 20 to 35 % of its nominal lifetime (0.93 → 0.73 ms at
    ff/85 °C, with the per-corner bar), and with a fixed bar it fails ss/27 °C.

  **Keeping the read strip at 0.30** gives up the Cnt.c part of tier 0 and keeps only the
  0.13 end cap: 2.10 / 2.75 / 2.96 µm² (−5 %), with unchanged electricals.
- **Tiny Tapeout's precheck would accept every tier drawn here**, if two conditions hold:
  - the array carries the SRAM marker;
  - the PDK is recent enough to have `Cnt.c.SRAM`.

  Its IHP check runs only the main table of the deck. That table does not check Gat.c, NW.c/d,
  TGO.a–e, pSD.i/j or Cnt.f at all.

  Whether IHP would *fabricate* these breaks correctly is another question: its rules say
  standard rules "ensure correct fabrication", and the SRAM rules section is "work in progress".
  That question is for IHP.

Everything below is DRC-checked layout or SPICE (ngspice 44.2, PSP 103), unless marked
*estimate* or *assumption*.

## 1. What the decks actually check (the paperwork, first, because it shapes everything)

| rule set | how it is run | what it checks of interest here | evidence |
|---|---|---|---|
| main table (`ihp-sg13g2.drc`, `feol/`, `beol/`) | `run_drc.py` default; **Tiny Tapeout's precheck** (`klayout -b -r ihp-sg13g2.drc`, default table, any item fails; `deck/tt-precheck-grep.txt`) | Act.a/b, Gat.a/b/d, Cnt.a–e/g, Cnt.c (0.07; 0.05 inside DigiBnd 16/0), M1…, LU.b, TGO.f only. **Not** Gat.c, NW.c/d, TGO.a–e, pSD.i/j, Cnt.f, Act.c | `deck/main-deck-rules.txt`, `drc/*-main.log` ("Executing rule") |
| maximal deck (`sg13g2_maximal.drc`) | `run_drc.py` default, skipped by `--disable_extra_rules` | everything, but under the SRAM marker 25/0 it **exempts** (does not check at all) NW.c, NW.d, Act.c, Gat.c, pSD.e/i/i1/j/j1, Cnt.f, M1.c/c1, Vn.c1 endcaps (`X_Nsram = X.ext_not(SRAM)`) | `deck/sram-exempt-rules.txt` (`deck/sram_rules.py`) |
| precheck set (`run_drc.py --precheck_drc`) | TT's foundry-submission CI (`--precheck_drc --disable_extra_rules`, `deck/tt-precheck-notes.txt`) | widths and spaces only: Act.a/b, Gat.a/b/d, Cnt.a/b, metals, pads. No Cnt.c, Cnt.d, Gat.c, NW, pSD, TGO.a–d | `deck/precheck-mode-rules.txt` |
| upstream main (IHP-Open-PDK 5e6d592e, 2026-09-01) | newer PDK | adds **`Cnt.c.SRAM`: 0.006 inside the SRAM marker** (commit dd6f9eb, 2026-02-15, "fix issues related to sram") | `deck/ihp-cnt-c-sram-commit-dd6f9eb.txt`, `deck/upstream-pdk-commit.txt` |

Consequences, all measured on the PDK's own cell and ours (`drc/pdkcell-*`, `drc/6t-pdk-*`):

- With the local PDK (c4b8b4e, 2026-01-16), **IHP's own bit cell fails the main deck**: 204 ×
  `Cnt.c.digibnd` at 0.02 µm (`drc/pdkcell-mark-stocktt-tt.summary.txt`). With the upstream deck it
  is clean (`drc/pdkcell-mark-upstream-tt.summary.txt`). The TT precheck therefore needs a PDK
  newer than 2026-02-15 for any SRAM-marked cell, IHP's included.
- The SRAM marker is not tied to IHP's cell. Our 6T drawn at the PDK cell's values, with the
  marker and DigiBnd over it, is clean under the upstream main deck (`drc/6t-pdk-mark-upstream-tt.summary.txt`).
- TT's layer allow-list for IHP includes `SRAM.drawing` and `DigiBnd.drawing`; its forbidden list
  is TopMetal2 only (`deck/tt-precheck-notes.txt`, `tt-support-tools/precheck/tech_data.py`).
  TT has no LVS step, and published TT IHP projects instantiate IHP's SRAM macros.
- **DigiBnd (16/0) is a documented, sanctioned relaxation** (layout rules §8.1,
  `deck/layout-rules-excerpts.txt`): Cnt.c 0.05 instead of 0.07, and thick-oxide n-well rules
  NW.c1/d1 0.31 instead of 0.62. It is meant for IHP's digital libraries, but nothing restricts
  it to them.
- **IHP's own tape-in** (layout rules §4.1): critical rules [RD 2] "are checked during tape-in.
  If any of them are violated, the layout is rejected … no waivers are granted". Standard rules
  "ensure correct fabrication". The SRAM layer section is "Work in progress" (§8.3). I infer, but
  have not verified, that `--precheck_drc` approximates [RD 2]. If it does, none of the breaks
  here would be rejected at tape-in; they would simply be at our own risk.

## 2. The rules that set the area (catalogue)

Areas per bit are from the generators (`layout/rule_costs.py` → `layout/rule-costs.txt`):
relaxing one rule at a time from the standard rules, with the Metal1/Metal2 floors included.

| rule | value (standard → relaxed) | protects against | cell: saving per bit |
|---|---|---|---|
| Cnt.c Activ enclosure of Cont, across a diffusion | 0.07 → 0.02 (PDK cell) | Cont→Activ overlay: a contact partly on STI etches into the trench edge, raising contact resistance and junction leakage (the plug reaches below the junction beside it) | thin 0.21 (9.4 %), thick 0.27, all-thick 0.29; 6T 0.21 (6.3 %) |
| Cnt.c along a diffusion (strip ends, dogbone steps) | 0.07 → 0.02 (tier 1; the PDK cell keeps 0.07 here) | same | 0.115 per bit, each gain cell (4–5 %) |
| Gat.c poly end cap | 0.18 → 0.13 (PDK PMOS) / 0.17 (PDK NMOS) | line-end shortening (poly ends pull back by tens of nm with rounding; if the end retreats past the Activ edge, source and drain short through an ungated sliver) | gain cells 0.105–0.15 (4.8 %); 6T 0.02, and 0 below 0.17, because the 6T is then Metal2-bound |
| NW.c / NW.d n-well to P+ / N+ Activ | 0.31 → 0.27 (PDK) → 0.24 (tier 2) | n-well implant straggle and overlay (N+ in p-sub touching the real well edge shorts to VDD); punch-through; latch-up (the parasitic bipolars' base widths); the well-proximity Vt shift | 6T 0.086 each (2.5 %); gain cells none (no n-well) |
| pSD.i / pSD.j pSD to PFET / NFET gate | 0.30 → 0.22 / 0.30 | pSD implant mask overlay counter-doping the LDD next to a gate | follows NW.c/d in the 6T (no area of its own) |
| TGO.a + TGO.b ThickGateOx over / clear of Activ | 0.27 + 0.27 → 0.105 + 0.105 (tier 2); TGO.c/d (0.34 from gates) kept | dual-oxide mask overlay and the wet-etch undercut of the 7.3 nm thick oxide (process spec: TGOX1NW 7.3 nm, thin 2.45 nm); a TGO edge on Activ leaves an oxide step or remnant on diffusion | **thick-write cell 0.35 (12 %)**; others 0 |
| Cnt.f contact to gate | 0.11 → 0.07 (tier 2; the PDK cell keeps 0.11) | contact landing on the spacer or gate under Cont→GatPoly overlay: a gate to source/drain short | 0.042 per bit (1.3–1.9 %) |
| Cnt.d poly enclosure of Cont (the SN pad) | 0.07 → 0.02 (not drawn) | as Cnt.c, on poly; also Cnt.e 0.14 (poly contact to Activ) then binds | up to 0.29–0.36 (*estimate*, ignores Cnt.e); **fails TT's precheck** (main-deck rule) |
| Metal2 two tracks per column (M2.a 0.20, M2.b 0.21) | — | — | the gain cell's x floor 0.82; the 6T's floor 2 × (XC_N + 0.41), which the PDK cell sits exactly on (0.17 end cap) |
| Metal1 (6T y) | — | — | 1.07 rows in both the PDK cell and ours: not broken by anyone |

Why the PDK cell uses 0.17 on the NMOS end cap and not 0.13: its x pitch is set by Metal2 (the
word-line island must keep 0.21 from the VSS track), and 0.17 is exactly where the two meet.
Beyond the PDK cell's rules, the 6T gains little. Below 0.24 the n-well gap can no longer hold
the gate-contact poly pad (Gat.d, Cnt.e) or the Metal1 around it. At 0.20 the stock deck flags
Gat.d, Cnt.e and M1.b (`drc/6t-t2-nw0.24-*` is the drawable limit).

## 3. The tiers, drawn

Generators: `layout/gain_rb.py` and `layout/sram6t_rb.py`, parametrised copies of
`../gain-cell/draw2.py` and `../sram-cut/layout/sram6t.py`. At the standard values they
reproduce the originals' geometry polygon for polygon (checked with a polygon comparison).
Every array was DRC'd four ways (`drc/run.sh`, `drc/tt.sh`, `drc/gain-tiers.sh`):

- the stock main table;
- stock main + maximal;
- a relaxed deck (`deck/mkdeck.py`: the tier's values, **SRAM exemption removed**, so the
  stated values are enforced everywhere);
- the Tiny Tapeout way, with the upstream deck and the SRAM marker plus DigiBnd drawn.

Controls:

- **Positive:** IHP's own cell passes the relaxed PDK-values deck.
- **Negative:** a 6T with a 0.12 end cap fails it with `Gat.c` (`drc/6t-negctl-pdkvaluesdeck.summary.txt`).

Areas are per bit with a strap every 32 columns (gain) or for the core cell (6T).

| tier | cell | µm²/bit | vs standard | violated vs the stock deck (min measured) | relaxed deck | TT style (upstream + marker) |
|---|---|---|---|---|---|---|
| std | 6T | 3.41 | — | none | — | — |
| 0 | 6T (= PDK cell geometry) | **3.01** | −12 % | Cnt.c 0.020; maximal: Gat.c 0.130, NW.c 0.270, NW.d 0.270, pSD.i 0.240 | clean | clean |
| 2 | 6T, NW 0.24 | 2.88 | −16 % | as tier 0, NW.c/d 0.240, pSD.i 0.180 | clean | clean |
| std | thin 3T | 2.20 | — | none | — | — |
| 0 | thin 3T | **1.89** | −14 % | Cnt.c 0.020; maximal: Gat.c 0.130 | clean | clean |
| 1 | thin 3T | 1.79 | −19 % | same | clean | clean |
| 2 | thin 3T | 1.72 | −22 % | + Cnt.f 0.070 | clean | clean |
| std | thick-write 3T | 2.88 | — | none | — | — |
| 0 | thick-write 3T | 2.48 | −14 % | Cnt.c, Gat.c as above | clean | clean |
| 1 | thick-write 3T | 2.38 | −18 % | same | clean | clean |
| 2 (TGO only) | thick-write 3T | 2.08 | −28 % | + TGO.a 0.105, TGO.b | clean | clean |
| 2 | thick-write 3T | 2.01 | −30 % | + Cnt.f 0.070 | clean | clean |
| 0, W 0.30 read strip | thin / thick / all-thick | 2.10 / 2.75 / 2.96 | −5 % | Gat.c 0.130 only (and pSD.j1 before a fix in the all-thick strap) | clean | clean |
| 2, W 0.30 read strip | thin / thick / all-thick | 1.91 / **2.23** / 2.77 | −13 / **−23** / −11 % | Cnt.c 0.020 (along the strips), Cnt.f 0.070, Gat.c 0.130; thick: TGO.a 0.105, TGO.b | clean | clean |
| std | all-thick 3T | 3.10 | — | none | — | — |
| 0 / 1 / 2 | all-thick 3T | 2.66 / 2.57 / 2.49 | −14 / −17 / −20 % | as the thin cell | clean | clean |

The mixed array (thin and thick row pairs on shared bit lines) passes at every tier too
(`drc/gain-mixed-*`). "Stock main" alone, which is the TT check without the marker, flags only
Cnt.c in every tier: with the local PDK and the marker, `Cnt.c.digibnd` (as for IHP's cell).
With the upstream PDK and the marker, nothing. **The TGO and Cnt.f breaks are invisible to TT's
check.**

Not checked: LVS of the relaxed arrays. The DRC-relevant geometry changed, but the connectivity
did not; the generator edits only move shapes.

## 4. Electrical costs (SPICE)

**Tier 0 gain cells: storage and read transistors W 0.20 instead of 0.30** (the narrower strip).
SN capacitance is mostly MS gate, so the write word line's feedthrough lowers the written 1 more,
and the read threshold rises. `sim/cell.py` is `../gain-cell/tricks-thin/cell.py` with a `WMR`
parameter; results are in `sim/results/`, and lifetimes come from `sim/life.py`, as in
`../gain-cell/`.

| cell / scheme | corner | W 0.30 (baseline, `../gain-cell/tricks-thin/results/`) | W 0.20 (tier 0) |
|---|---|---|---|
| level-shifted thin, VLO 0.3 / VBAR 0.1 V fixed, 10 ns sense | ss/27 °C | written 1 0.619 V, reads above 0.556 V → 4.98 ms | written 1 0.567 V, reads above 0.587 V → **fails** (`hold-lv-w20-vlo0.3-bar0.1.txt`) |
| same | ff/85 °C | 1.22 ms idle / 131 µs busy | 975 µs idle / 275 µs busy |
| level-shifted, per-corner bar (VBAR 0 at ss/27, 0.15 at ff/85) | ss/27 °C | 19.6 ms | 12.6 ms |
| same | ff/85 °C | 930 µs (idle and busy) | **732 µs** (`results/lifetime-percorner-w20.txt`) |
| untricked thin, 10 ns sense | worst corner (ff/85 °C) | 1.31 µs | 0.93 µs (`results/lifetime-w20-untricked.txt`) |
| thick-write, 20 ns write, 20 ns sense | ss/27 °C | written 1 0.366 V, reads above 0.354 V → 261 µs | written 1 0.329 V, reads above 0.392 V → **fails** |
| thick-write, 100 ns write, 20 ns sense | ss/27 °C | written 0.418 V → 16.5 ms | written 0.382 V, needs 0.392 V → **fails** (`results/lifetime-thick-tw100-ss27.txt`) |
| thick-write, 20 ns write, 20 ns sense | other corners | ≥ 3.1 ms (`../gain-cell/`) | 5.7–13.4 ms |

So tier 0 is not free for the gain cells. The written 1 is 40–50 mV lower (less SN capacitance
against the same word-line feedthrough), and the readable level is 30–40 mV higher (a weaker
read path). The level-shifted thin cell survives only with the per-corner bar. The thick-write
cell, whose ss/27 °C margin was 12 mV, does not survive at all without a sense amplifier or a
boosted write word line. That is why the recommended tiers keep the read strip at 0.30. Mismatch was not rerun. σVt scales as 1/√(WL), so it is
about 1.2× larger at W 0.20, on margins of tens of millivolts. **This must be run before
committing to tier 0 for the level-shifted cell.**

A layout option that recovers part of this (*not drawn*): only strip A (MS, MR, the RBL
contact) needs 0.20. Strip B, the storage node's own contact, and the write transistor can keep
the standard 0.07 enclosure without changing the x pitch, since strip B is not in the
pitch-setting row. That also keeps the Cnt.c break off the storage node, where extra junction
leakage from a contact over the trench edge would go straight into retention.

**6T at tier 0:** identical devices to the ones already simulated in `../sram-cut/` (PD/PG 0.30,
PU 0.15). No schematic change, so no SPICE change; the cost is only process risk.

**Tier 2, TGO keep-out:** the TGO edge now sits 0.105 µm from Activ on both sides. The gates stay
≥ 0.34 µm inside or outside (TGO.c/TGO.d kept). An oxide edge reaching a transistor channel
needs an overlay error above 0.34 µm, about 20σ at a 45 nm 3σ. The mixed-oxide device ("thick
oxide encroaching on the thin gate") is therefore not the failure mode, and I did not simulate
it. The plausible failure is an oxide remnant on source/drain diffusion after a 0.1 µm overlay
error: a sliver with poor silicide and higher contact resistance, on the SN contact end of strip
B or on the GND bar. Neither is modellable with the PDK decks.

**Tier 2, NW 0.24 (6T):** latch-up is not modelled by the PDK. The PDK has no well-proximity
parameters: the PSP instance lines carry no SCA/SCB/SCC, so WPE is not in these models either.
The PDK cell already sits at 0.27 with a tap row every 16 rows
(`../sram-cut/pdk-cell/refs2.txt`); a 6T at tier 0 or tier 2 should copy that rather than our
tap row every 36 rows. A 1.20 µm tap row per 16 rows of 1.07 µm adds 7 % (*estimate*):
3.01 → ~3.22 µm² at tier 0 and 2.88 → ~3.08 µm² at tier 2. Tier 2 keeps its 4 % over tier 0 only
if taps every 16 rows are enough at 0.24, which nobody has checked.

## 5. Yield (arithmetic with stated assumptions, `yield/yield.py` → `yield/yield.txt`)

- **Overlay-driven breaks fail whole dies, not bits.** Overlay error is mostly systematic per
  field, so row sparing cannot absorb it. The figures below assume a 45 nm 3σ overlay (my
  recollection of the ITRS figure for the 130 nm node; *not re-checked*) and a 0.03 µm minimum
  clearance for contact to gate (*assumption*). On those inputs:
  - Cnt.f at 0.07 loses about 0.8 % of dies (4.5 % at 60 nm 3σ);
  - Cnt.f at 0.11 loses 1e-7;
  - the TGO keep-out at 0.105, with the edge landing only on diffusion, loses about 1e-12.
- **Cnt.c at 0.02 is not a yield question for IHP's process** in the hard sense. IHP's
  production bit cell does it and the upstream deck allows 0.006. The contact then routinely
  straddles the trench edge, which costs contact resistance and junction leakage. That matters
  for a storage node, not for a bit line.
- **Random per-bit failures are absorbed by row mapping** (per-row profiling, Berger check).
  With 256 rows of 256 bits:
  - a per-bit failure probability of 1e-5 costs 0.65 rows (168 bits, 0.26 % of 64 kbit);
  - 1e-4 costs 6.5 rows (1657 bits, 2.5 %);
  - 1e-3 costs 23 %.

  I have no silicon number for p under these breaks. Poly line-end pull-back at a 0.13 end cap
  (Gat.c) is the one random-type failure among them, and IHP ships it in every bit cell.
- Column faults (bit-line shorts) are not mapped by the compiler model and would cost columns.

## 6. Summary

| tier | cells | µm²/bit | gain vs standard | what breaks | electrical / yield penalty | TT precheck | verdict |
|---|---|---|---|---|---|---|---|
| 0 | 6T | 3.01 | 12 % | Cnt.c 0.02, Gat.c 0.13–0.17, NW.c/d 0.27, pSD.i 0.24 | none by schematic; IHP's own values | passes with the marker and a PDK ≥ 2026-02-15 | as good as IHP's cell, but still 1.6× the tier-0 thin gain cell |
| 0 | thin 3T | 1.89 | 14 % | Cnt.c 0.02 across, Gat.c 0.13 | W 0.20 read path: level shift survives only with the per-corner bar (0.73 ms ff/85); MC not rerun | same | **worth it** if the MC holds; keep Cnt.c off the SN contact |
| 0 | thick-write 3T | 2.48 | 14 % | same | **does not read at ss/27 °C** (W 0.20) | same | no; with the 0.30 read strip 2.75 (−5 %) |
| 1 | gain cells | 1.79 / 2.38 / 2.57 | 17–19 % | + Cnt.c 0.02 along strips | as tier 0, plus contacts at strip ends over the trench edge | same | small extra gain; put it only on non-storage contacts |
| 2, 0.30 read strip | thick-write 3T | **2.31** (TGO) / 2.23 (+ Cnt.f) | **20 / 23 %** | TGO.a/b 0.105 (gates kept 0.34), Cnt.c 0.02 along strips, Gat.c 0.13, [Cnt.f 0.07] | none in SPICE (same devices); TGO: an oxide remnant on diffusion only (≥ 0.34 µm to any gate); Cnt.f: ~1 % of dies at 45 nm 3σ (*assumption*) | passes (TT checks neither TGO nor Cnt.f) | **the most valuable break**: thick-oxide retention at the density of today's thin cell |
| 2, 0.20 strip | thick-write 3T | 2.01 | 30 % | as above + Cnt.c 0.02 across | does not read at ss/27 °C | passes | no, unless a sense amplifier |
| 2 | thin 3T | 1.72 | 22 % | + Cnt.f 0.07 | Cnt.f die loss as above | passes | marginal over tier 1 |
| 2 | 6T | 2.88 | 16 % | NW.c/d 0.24, pSD.i 0.18 | latch-up and WPE unmodelled; would want taps every 16 rows | passes | not worth it |
| — | Cnt.d 0.02 (SN pad) | — | ≤ 9–14 % (*estimate*) | Cnt.d, then Cnt.e | — | **fails** (main-deck rule) | out |

**The most valuable break, and its price.** For the thick-write cell, move the ThickGateOx edge
to the middle of the 0.21 µm gap between the write strip and the thin-oxide bar (TGO.a/TGO.b
0.27 → 0.105), keeping every gate 0.34 µm from the edge. On its own, at the standard rules, this
takes 2.88 → 2.54 µm² (−12 %; `layout/rule-costs-w30.txt`). With the small tier-1 breaks and the
0.30 read strip, it reaches 2.31 µm². The price:

- an oxide-edge placement margin of 0.105 µm instead of 0.27;
- no gate is ever at risk;
- no SPICE-visible effect;
- TT's check does not see it.

The real price is that IHP has not qualified it, and only IHP can say whether their dual-oxide
etch leaves remnants or steps within 0.1 µm of an edge.

## Open questions (for IHP, or for Jane Street's contact there)

1. Is `--precheck_drc` the [RD 2] critical rule set? If so, is everything outside it "at the
   designer's risk", or does IHP screen standard-rule violations on MPW anyway?
2. Is the SRAM marker's relaxation (Cnt.c.SRAM 0.006, and the maximal deck's exemptions)
   qualified only for `RM_IHPSG13_1P_BITKIT_CELL`'s geometry? For example, is there OPC or
   retargeting keyed on 25/0 that other shapes would not get? Would IHP object to a user cell
   under 25/0 on a direct MPW?
3. What is the physical basis of TGO.a/TGO.b 0.27? Is it overlay, the wet-etch undercut, or
   the thick-oxide LDD implant set by the same mask? Is a TGO edge on STI 0.1 µm from Activ safe
   when no gate is within 0.34 µm?
4. Overlay (3σ) for GatPoly→Cont, Activ→Cont and TGO→Activ in SG13G2, and the spacer width. These
   decide Cnt.f and the TGO margin, instead of my recalled ITRS figure.
5. Which PDK version will the next TT IHP shuttle's precheck use? `Cnt.c.SRAM` needs ≥ 2026-02-15.

## Surprises

- The deck TT runs does not check the rules that set most of our area: Gat.c, NW.c/d, TGO.a–d
  and Cnt.f are maximal-deck only. Everything in tier 2 passes TT's precheck with no marker at
  all, except Cnt.c.
- On the PDK version in this project, IHP's own bit cell fails the main deck (Cnt.c.digibnd);
  the fix only arrived upstream on 2026-02-15.
- The PDK cell is Metal2-bound in x, so a smaller end cap on its NMOS buys nothing.
- DigiBnd is a sanctioned marker that halves the thick-oxide n-well rules (0.62 → 0.31). A
  thick-oxide 6T (*estimate* ~7.4 µm² in `../sram-cut/`) would drop to roughly 5.3 µm² with it,
  legally. Not drawn.

## Files

- `deck/`: rule-set analysis (`sram_rules.py`, `sram-exempt-rules*.txt`, `main-deck-rules.txt`,
  `precheck-mode-rules.txt`), `mkdeck.py` (relaxed decks), TT precheck notes and the IHP commit.
- `layout/`: `gain_rb.py` and `sram6t_rb.py` (tiers via `standard`, `pdk`, `pdk:key=value,...`;
  markers `sram,digi`), `rule_costs.py` → `rule-costs.txt`.
- `drc/`: `run.sh` (main alone, main + maximal, optionally precheck; stock, upstream or a
  relaxed deck), `tt.sh` (the TT invocation), `gain-tiers.sh`, `summary.py` (per-rule counts and
  the smallest measured distance). Every `*.summary.txt` and log is cited above; the relaxed decks
  are built in `/var/tmp/spice-rule-breaks/decks/` by the `mkdeck.py` lines recorded in each
  deck's `CHANGES.txt` (tier values listed in this README).
- `sim/`: `cell.py`, `life.py`, `pod.sh`, `tier0*.sh`, `results/`.
- `yield/`: `yield.py`, `yield.txt`.
- `review/`: the adversarial review.
