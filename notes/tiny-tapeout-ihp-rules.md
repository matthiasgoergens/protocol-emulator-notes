# Tiny Tapeout on IHP SG13G2 — layout, macro, analog and I/O rules

Research notes for a design on the IHP shuttles (ttihp25a/25b/26a/26b and
later). Sources are TinyTapeout's own GitHub org (`gh api`/`curl` against
`api.github.com` and `raw.githubusercontent.com`, 2026-09-25), the
tinytapeout.com docs site (fetched with `curl`+`w3m -dump`, 2026-09-25), and
IHP's `IHP-Open-PDK` repo. Everything is dated 2026-09-25 unless stated
otherwise; TT's docs and precheck rules do change between shuttles, so treat
anything not tied to a specific shuttle repo as "current at the time of
writing".

Confidence key: **[hard]** = read directly out of the tool/precheck source
code that enforces the rule; **[doc]** = stated on tinytapeout.com or in a
repo README/FAQ; **[example]** = inferred from a real, taped-out project;
**[inferred]** = my own reasoning, not directly sourced; **[sketchy]** =
forum/Discord-grade, flagged as such.

## 1. Metal layers on IHP SG13G2

Source: `tt-support-tools/precheck/tech_data.py`
(https://github.com/TinyTapeout/tt-support-tools/blob/main/precheck/tech_data.py,
fetched 2026-09-25). This is the file the automated precheck action actually
imports, not a description of it.

**[hard]** The full set of layers a submitted GDS is allowed to use at all,
`valid_layers_ihp_sg13g2` (tech_data.py:59-79), includes `Metal1`...`Metal5`,
`Via1`...`Via4`, `TopVia1`, `TopMetal1`, and also `MIM`/`Vmim`, `ThickGateOx`,
`SRAM` (marker layers), `NoRCX.*`, `Recog.*`, `DigiBnd`, `RES`, `Varicap`,
`isoNWell`, etc. `TopMetal2` is **not** in this list except for
`TopMetal2.nofill`.

**[hard]** `forbidden_layers["ihp-sg13g2"]` (tech_data.py:179-183) explicitly
bans `TopMetal2.drawing`, `TopMetal2.pin`, `TopMetal2.label`. The precheck
`klayout_checks()` function (precheck.py:176-183) fails the whole check if any
of these are found anywhere in the GDS. So: **Metal1–Metal5 and TopMetal1 are
free for user tiles (digital or analog), TopMetal2 is fully off-limits.**

This is the IHP-specific analogue of the well-known sky130 rule ("no met5",
`forbidden_layers["sky130A"] = met5.*`) — on IHP, the layer TT's own chip-level
power grid reserves is one level up, TopMetal2 instead of Metal5. The
tinytapeout.com Analog Specs page's "you are not allowed to use metal 5... used
by Tiny Tapeout's power grid" sentence
(https://tinytapeout.com/specs/analog/, fetched 2026-09-25) is explicitly
scoped "Specifications and limitations - sky130A" on that page — it is not the
IHP rule, and the page does not restate it for IHP; the actual IHP rule only
exists in the precheck source, not the prose docs.

**[hard]** Power pin rule for IHP, `power_pins_layer`/`power_pins_min_width`
(tech_data.py:189-197): power pins must be on **TopMetal1**, minimum width
**2.1 µm** (2100 in the file's units) — vs. sky130's met4/1.2µm and gf180's
Metal4/0.8µm. This matches what a real taped-out project does: the
`kianv-sv32-tt-linux-soc` LibreLane config comments its custom PDN script as
"SRAM power pins on Metal4, connect Metal4 -> TopMetal1"
(https://github.com/splinedrive/kianv-sv32-tt-linux-soc/blob/main/src/config.json,
line 72, fetched 2026-09-25) — i.e. macro-internal straps on Metal4, stepped up
to TopMetal1 to meet the TT power-pin-layer rule.

**[hard]** The digital-tile floorplan DEF templates
(`tt-support-tools/tech/ihp-sg13g2/def/tt_block_1x1_pgvdd.def`, fetched
2026-09-25) define **routing tracks up to and including TopMetal2**
(`TRACKS ... LAYER TopMetal2`), confirming TopMetal2 is reserved grid
infrastructure that TT's own floorplan uses, not something withheld for no
reason. Digital tile-boundary signal pins (clk, ui_in, uo_out, uio_*) in that
same template sit on **Metal4** — a plain digital LibreLane/OpenLane project's
I/O never needs to touch Metal5/TopMetal1/TopMetal2 at all; those only come
into play if you build custom macros/power straps yourself.

**[doc]** One IHP tile = 202.08 × 154.98 µm
(`tech/ihp-sg13g2/tile_sizes.yaml`, fetched 2026-09-25).

**No explicit "vertical stripe" width/pitch rule is documented for IHP** the
way there is for sky130 analog power pins (sky130: "vertical stripes on met4,
≥1.2µm wide, start within bottom 10µm, extend to top 10µm" —
https://tinytapeout.com/specs/analog/). For IHP the only numeric constraint I
found in source is the 2.1µm minimum width on TopMetal1
(tech_data.py:196); I did not find a documented start/extend geometry
constraint for IHP power pins specifically — **not verified**, flag this as an
open question if it matters for your layout.

## 2. Custom hand-drawn macros inside a digital (LibreLane/OpenLane) project

**Yes — this is supported, has real IHP examples, and precheck does not
special-case it.**

**[hard]** LibreLane/OpenLane's `MACROS` config block (`config.json`) is the
supported mechanism: it takes `gds`, `lef`, `lib`, `nl` (netlist) and `spice`
file paths plus per-instance `location`/`orientation`, and lets you hard-place
any pre-built macro (including a hand-drawn GDS) among the synthesised
standard cells. `gh search code` across the TinyTapeout org turns up dozens of
real examples using this (`"MACROS":` in `config.json`), e.g.
`tt05-dffram-example`, `tt_um_urish_skullfet` (hand-drawn "SkullFET" inverter
macro), and several IHP ones.

**[example, real taped-out IHP shuttle]** `tt_um_kianv_sv32_soc` on
**ttihp-26a** (a real, currently-manufacturing shuttle, not a template or
staging repo) instantiates **IHP's own hardened SRAM compiler macros**
(`RM_IHPSG13_1P_512x64_c2_bm_bist`, 64x64/256x64 variants) as `MACROS` inside
an otherwise LibreLane-synthesised RISC-V SoC. Source:
https://github.com/splinedrive/kianv-sv32-tt-linux-soc/blob/main/src/config.json
(fetched 2026-09-25); built output at
https://github.com/TinyTapeout/tinytapeout-ihp-26a/tree/main/projects/tt_um_kianv_sv32_soc.
The config also documents the two problems you'd expect from mixing hand/hard
macros with a P&R flow, and how the project worked around them:
- `"ERROR_ON_MAGIC_DRC": false` — "SRAM macros have inherent DRC violations in
  Magic" (comment in the config). Note this only disables *LibreLane's own*
  Magic-DRC gate inside that project's build; TT's shuttle-integration
  precheck still runs the IHP foundry `ihp-sg13g2.drc` deck via KLayout on the
  final merged GDS regardless (see below) — the project cannot skip that.
- `"MAGIC_EXT_ABSTRACT_CELLS": ["RM_IHPSG13_.*"]` — LVS/extraction treats the
  SRAM macro as a black box rather than trying to re-extract transistors
  inside it, avoiding false LVS mismatches on a macro whose internals Magic
  doesn't understand.

**[example]** Other IHP-26a projects with embedded SRAM/registers as compiled
blocks: `tt_um_aksp_mbist_mbisr` (256×8 embedded SRAM + BIST/repair),
`tt_um_ygdes_hdsiso8_rs` docs explicitly argue *for* hand macros over
synthesis+P&R for dense storage ("the P&R tools choke... one more compelling
reason to use macros and manual place&route!" —
https://github.com/TinyTapeout/tinytapeout-ihp-26a/blob/main/projects/tt_um_ygdes_hdsiso8_rs/docs/info.md).

**[hard] What precheck actually checks** (from
`tt-support-tools/precheck/precheck.py`, the literal list of check steps run
per submission, lines ~481-563):
- DRC: for IHP, one step, "KLayout SG13G2 DRC", which runs the **IHP
  foundry's own rule deck** at
  `$PDK_ROOT/ihp-sg13g2/libs.tech/klayout/tech/drc/ihp-sg13g2.drc`
  (precheck.py:124-129) — i.e. the same signoff deck IHP ships, not a
  TT-specific subset. (sky130 gets Magic DRC + separate KLayout FEOL/BEOL/
  offgrid passes instead; gf180 gets its own unified deck with density/antenna
  split out.)
- **Layer whitelist**: `layer_check()` (precheck.py:275-295) diffs every
  layer/datatype pair actually present in the GDS against
  `valid_layers[tech]` and fails on anything not on the list — this is a hard
  reject, not just DRC. `ThickGateOx.drawing` (IHP layer **44/0**, confirmed
  against IHP's own `.lyp`: https://github.com/IHP-GmbH/IHP-Open-PDK/blob/main/ihp-sg13g2/libs.tech/klayout/tech/sg13g2.lyp,
  fetched 2026-09-25) and `SRAM.drawing`/`.label`/`.boundary` (layer **25/0**,
  **25/1**, **25/4**) are both **explicitly present in the valid-layer list**
  — i.e. **not forbidden**. Only `TopMetal2.*` is forbidden for IHP (see §1).
  So a custom SRAM array using thick-gate devices and the SRAM marker layer is
  not something precheck blocks.
- **Antenna check**: only listed as its own named step for gf180mcuD
  (precheck.py:547-551, "Antenna check" via the gf180 rule deck's antenna
  group). For sky130 and IHP there's no separate antenna step in the check
  list — antenna rules for those PDKs are presumably folded into the
  full FEOL/BEOL/SG13G2 DRC deck run rather than split out. I did not verify
  this against the actual `ihp-sg13g2.drc` deck's rule groups — **[inferred]**.
- **LVS: precheck does *not* run LVS at all.** I grepped `precheck.py` for
  `lvs` (case-insensitive) and got zero hits; the check list has no LVS step
  for any tech. LVS is the *project's own* LibreLane/OpenLane flow's
  responsibility (Magic extraction + netgen, as in the kianv example above,
  where the SRAM macro is blackboxed for that purpose) — TT's own gate never
  re-verifies it at shuttle-integration time.
- Other steps that do run for all techs: "Pin check" (project's I/O pins land
  exactly on the template DEF's pin geometry), "Boundary check" (GDS
  `prBoundary.boundary` fully covers/matches the paid tile area), "Cell name
  check", "Analog pin check" (only if `analog_pins`/`is_analog` set),
  "Verilog syntax check" on the blackbox stub. "Power pin check" (verilog+LEF
  cross-check of PDN pin presence) is scoped to `sky130A`/`gf180mcuD` only —
  **it does not run for ihp-sg13g2** (precheck.py:530-534), so nothing in
  precheck automatically validates the TopMetal1/2.1µm power-pin rule for IHP
  digital submissions; that appears to be left to the pin-placement/DEF-match
  checks and reviewer eyeballing.

**Waiver process**: **[doc, weak]** I found no formal waiver/exception
mechanism described anywhere (FAQ, precheck README, tt-support-tools). The one
relevant mention is a project's own doc explicitly *disclaiming* one:
`tt_um_fabien_pio` on ttihp-26b-staging states "No SRAM waiver, DRC filtering
or nonblocking signoff exception is permitted. Placement/routing, timing...
DRC, LVS and official precheck must all pass before a new revision can be
considered."
(https://github.com/TinyTapeout/tinytapeout-ihp-26b-staging/blob/main/projects/tt_um_fabien_pio/docs/info.md).
The phrasing implies such waiver/filtering mechanisms have existed or been
discussed informally at some point (possibly per-shuttle or per-maintainer
discretion via Discord), but I found no documented, general waiver process.
Precheck itself is a hard pass/fail gate (`exit(1)` on any failed check,
precheck.py:603-609) with no override flag. **Treat "no waiver process" as
[doc, weak] — worth confirming on Discord before relying on it.**

## 3. Analog / mixed-signal tiles on IHP

Source: https://tinytapeout.com/specs/analog/ (fetched 2026-09-25, current
page content).

**[doc]** PDK: analog projects on IHP shuttles use `ihp-sg13g2` (same PDK as
digital). **[doc]** Sizes: **1x2 or 2x2 tiles only** for a single analog
project (larger requires paying for multiple projects' worth of tiles/pins).
**[doc]** Available IHP analog DEF templates
(`tt-support-tools/tech/ihp-sg13g2/def/analog/`): `tt_analog_1x2.def`,
`tt_analog_2x2.def` — **only 1.8V (VDPWR)**, no 3.3V (VAPWR) template exists
for IHP (sky130 has both). **[doc]** Analog pin electrical budget (stated
PDK-agnostically on that page, i.e. presumably applies to IHP too, not
verified separately): path resistance <500Ω, capacitance <5pF, max current
4mA; up to 6 usable analog pins (`ua[0..5]`) even though 8 are wired in the
template.

**[hard]** Analog pin geometry precheck for IHP
(`tech_data.py:111-121`, `analog_pin_rects`): pins sit on **TopMetal1**
(layer 126/0), vias down through **TopVia1** (125/0) — different from
sky130 (met4) and gf180 (Metal4). `uses_vapwr` (3.3V) raises
`NotImplementedError` for `ihp-sg13g2` in that function — i.e. **the 3.3V
analog rail path is not implemented/supported for IHP at all** in current
tooling, consistent with there being no `_3v3` DEF template for IHP.

**[doc]** Pricing: the page has a "Pricing - sky130A" section (140€ min. for
2 tiles, 40€/pin for first 2, 100€/pin beyond) but **no equivalent
"Pricing - ihp-sg13g2" section exists on the page as fetched** — I could not
find a published, PDK-specific price breakdown for IHP analog pins. **Not
verified** — check the shuttle-specific pricing calculator
(https://tinytapeout.com, "calculator" link) or ask on Discord for the current
IHP analog pin price.

**Combining digital + custom analog layout in one project**: this is exactly
what §2's macro mechanism gives you — a LibreLane-hardened digital netlist
with a hand-drawn analog block dropped in as a `MACROS` entry (GDS+LEF+LEF
pins, optionally a `.lib`/spice view for STA/LVS) — same flow, no separate
"mixed-signal template" needed unless you want *dedicated* `ua[]` analog pads
wired straight to hand-drawn analog circuitry, in which case you'd start from
the analog template (`ttihp-analog-template`, not yet checked in detail here)
instead of the Verilog template. **[inferred]** — I did not find a TT doc that
states this combination explicitly for IHP; it follows from the general
LibreLane MACROS mechanism plus the analog pin routing described above, not
from a document that says "yes you can mix them."

## 4. I/O toggle frequency / bandwidth and clocking

**Important caveat: the published tinytapeout.com Clock and GPIO-pins pages
are written for sky130 and are not updated for IHP.** Both pages
(https://tinytapeout.com/specs/clock/, https://tinytapeout.com/specs/gpio/,
fetched 2026-09-25) explicitly key off the `sky130_ef_io_gpiov2_pad` macro:
**max input frequency 66 MHz, max output frequency 33 MHz**, drive strength
4mA, IO supply 1.71–5.5V, ~10ns clk insertion delay, ~20ns worst measured
round-trip latency, <2ns inter-pin skew (TT3.5 silicon, sky130). None of this
is restated anywhere for IHP's `sg13g2_io` pad cells that I could find on the
docs site — **[doc, sky130-only, does not directly answer the IHP part of
the question]**.

**[sketchy but from IHP's own PDK repo, simulated not measured]** IHP's own
`sg13g2_io` library ships a Python-notebook-derived simulation report,
`InputPerformance.html`
(https://github.com/IHP-GmbH/IHP-Open-PDK/blob/main/ihp-sg13g2/libs.ref/sg13g2_io/doc/InputPerformance.html,
fetched 2026-09-25), from the Chips4Makers `c4m-pdk-ihpsg13g2` project. It
runs a SPICE transient on the `IOPadIn` cell at 10/50/100/200 MHz in the
`SLOW_ROOM` corner (Vdd=1.08V, IOVdd=2.97V, 25°C, slow transistor corner) and
concludes **"one can see that 200MHz operation is not a problem for this
corner."** This is simulation, not silicon measurement, and it's the input
receiver only (no equivalent frequency claim found in the companion
`DriveStrengthSim.html`, which is about output drive strength, not toggle
rate). Treat "IHP I/O pads simulate cleanly well past 100–200MHz on input" as
**[doc/simulated, not measured]** — meaningfully higher headroom than sky130's
66MHz rated figure, but not a TT-published spec and not something I could
cross-check against real IHP-shuttle silicon measurements (none found).

**[doc]** TT's general FAQ (top-level, PDK-agnostic) claims "at least 50MHz"
top clock speed as of TT04-TT10 silicon measurements
(https://tinytapeout.com/faq/) — again a sky130-era number, not restated for
IHP.

**Clock port / second clock on an input pin**: **[doc, explicit and directly
answers the question]** TT's FAQ has a worked example, "How can I map an
additional external clock to one of the GPIOs?"
(https://tinytapeout.com/faq/#how-can-i-map-an-additional-external-clock-to-one-of-the-gpios).
It shows exactly this: set `CLOCK_PORT` to e.g. `ui_in[0]`, supply a custom
`.sdc` that declares two `create_clock` trees (the main `clk` and the
auxiliary `ui_in[0]`), and mark them `set_clock_groups -asynchronous` so STA
treats them as independent (no CDC checked between them). The example
explicitly requires the two clocks to be the **same frequency**, unknown/free
phase relative to each other (mesochronous), and to **never interact** inside
the design (no logic reads across both clock domains) — if your design *does*
need a defined phase relationship (e.g. using a genuine quadrature pair where
one signal's edges matter relative to the other, not just as two independent
domains), you'd need your own timing exceptions/constraints beyond this
recipe, and STA won't validate the phase relationship for you. The doc notes
this recipe is written against OpenLane tag 2023.11.23 and that newer
`check_clock_ports.py`-based flows (LibreLane) don't accept the sliced-port
(`ui_in[0]`) syntax the same way — **worth re-testing against current
LibreLane/ttihp-verilog-template before relying on it**, I did not verify this
myself against the current template.

**Demo board microcontroller and PIO**: **[doc]** The board has changed over
time. Current wording from `tinytapeout_www` content
(https://github.com/TinyTapeout/tinytapeout_www/blob/main/content/guides/get-started-demoboard-etr/_index.md,
fetched 2026-09-25): the latest ("ETR") demoboards use an **RP2350B**
("Power, and communications with the management RP2 IC (an RP2350B on the
latest demoboards)..."). The older, still-widely-referenced TT04+ demoboard
page (https://tinytapeout.com/specs/pcb/) describes an **RP2040** clocked at
12MHz with PLL, "well over 150MHz" achievable, using PWM or PIO to generate
the project clock, 1Hz–66.5MHz configurable via the Commander app/MicroPython.
Many current IHP-26a/26b project docs explicitly say "RP2040/RP2350" or just
RP2350 for the demo board MCU — **[example, many hits]**, e.g.
`tt_um_tmr_voter`, `tt_um_riscyv02` ("The TT demoboard's RP2350 (Raspberry Pi
Pico 2)..."), `tt_um_baked_weights` ("RP2350B microcontroller... can only
divide its own 150MHz clock by whole numbers"). **Net: current TT demo
boards ship RP2350(B); RP2040 was the board used through TT04–TT10-era
shuttles and is still supported/referenced in older docs and firmware.**

**Can the demo board's PIO generate two ~90°-offset clocks up to ~60MHz?**
**[inferred, not measured, not found documented]** — I found no TT doc or
community writeup that measures or states this directly. Reasoning from
public RP2040/RP2350 facts: both chips' PIO state machines run from the
(overclockable) system clock via a per-SM clock divider, and two independent
PIO programs on two SMs sharing the same system clock can be started
synchronised and run in lockstep, so a fixed static phase offset (e.g. a
quarter-period delay via instruction padding) between two same-frequency PIO
outputs is achievable in principle. However, the *phase resolution* is one
system-clock tick: at a 150MHz system clock (RP2040 well above spec, RP2350
rated higher), one tick is ~6.7ns, and a 60MHz target period is 16.7ns, so a
90° (quarter-period, ~4.2ns) offset is *finer* than one tick at 150MHz —
meaning you'd need a substantially higher system clock (or accept phase error
of order one full tick, i.e. tens of degrees, not a clean 90°) to hit accurate
quadrature at 60MHz from PIO alone. **This is my own back-of-envelope
reasoning, not a documented or measured TT/RP2040/RP2350 fact — verify by
actually building and scoping it before depending on it.**

## 5. Other rules relevant to custom macros / multi-phase clocking / unusual cells

**[example, many hits, clearly not banned]** Ring oscillators are common and
explicitly present on IHP shuttles: `tt_um_luke_meta`, `tt_um_Xelef2000`
(TRNG, 3 ring oscillators of different lengths), `tt_um_ro_puf_trng` (bank of
8 ring oscillators for a PUF/TRNG), `tt_um_chrbirks_top` ("DCO range ~300-600
MHz, 7-stage ring oscillator") — all on `tinytapeout-ihp-26a`/`25b`. One
practical note: `tt_um_anujic_rng`'s docs mention using
`(* keep = "true" *)` attributes on manually instantiated `sg13g2_inv_1`
standard cells to stop Yosys from optimising away the combinational loop that
makes the ring oscillate — a synthesis-tool workaround, not a TT rule, but
worth knowing if you build one from stdcells rather than a macro.

**[example]** Delay lines and configurable/tap-selectable delay chains are
likewise common and taped out on IHP (`tt_um_luke_meta`'s metastability/DDL
test chip; `tt_um_mzollin_glitch_detector`'s programmable delay-line glitch
detector, explicitly modelled on the RP2350's own glitch-detector peripheral
design). No shuttle notes anywhere restricting these.

**Both clock edges (posedge+negedge, DDR-style)**: **[inferred, not directly
sourced]** I found no TT-specific rule for or against negedge/dual-edge
flip-flops. The IHP `sg13g2_stdcell` library has ordinary negedge-triggered
flip-flop cells like any standard-cell library, and LibreLane/Yosys support
`negedge` in Verilog normally — this is a plain synthesis/STA concern (define
both clock edges properly in your SDC), not something TT precheck or the
shuttle process singles out. Not verified against precheck source (there's no
"clock edge" check in precheck.py).

**Waivers/DRC filtering more broadly**: see §2 — no general waiver mechanism
found; precheck is a hard gate.

## What I could not verify

- Any IHP-specific vertical-stripe geometry rule for power pins beyond the
  2.1µm minimum width (§1).
- Whether the IHP `ihp-sg13g2.drc` deck run by precheck includes antenna
  rules as part of the full deck, or omits them the way the check list omits
  a separate antenna step (§2).
- A published, IHP-specific analog-pin price (§3) — the pricing page only
  publishes a sky130A table.
- Any real silicon measurement (vs. simulation) of IHP `sg13g2_io` pad max
  toggle frequency (§4) — only IHP's own SPICE-notebook simulation to 200MHz
  was found.
- Whether the RP2040/RP2350 PIO can produce a genuinely accurate 90°-phase
  quadrature clock pair at ~60MHz — no TT or community source found; my
  answer in §4 is arithmetic reasoning from public RP2040/RP2350 specs, not a
  measurement.
- Whether the FAQ's dual-clock-tree `config.tcl`/`.sdc` recipe (§4) still
  works unmodified against the current `ttihp-verilog-template` /
  LibreLane-based flow (the FAQ itself flags it was written against an older
  OpenLane tag).
