# Prior art: racing-the-beam techniques for our PAL chip

Our chip: PAL composite, no frame buffer, 256x240, an RP2040 streaming a
~50-70 byte packet per scanline (palette, scroll, background parameters and
all 16 sprites can change every line), a 16-cell systolic sprite pipeline
(8-bit bitmaps, 16px wide, later cell wins), a background of two 16-bit
phase accumulators XORed together, and a wave engine summing up to ten
plane waves. Composite colour bandwidth is ~1.3MHz. A host precomputes
offline; the chip only streams small per-line state.

This surveys how racing-the-beam machines (Atari VCS, C64, NES) and the
demoscene (Amiga and PC-era software effects) solved "no frame buffer, tiny
budget per scanline," and translates each idea to our hardware.

## Atari 2600

Montfort and Bogost's *Racing the Beam* (MIT Press, 2009;
mitpress.mit.edu/9780262539760/racing-the-beam/, companion site
nickm.com/vcs/, Wikipedia en.wikipedia.org/wiki/Racing_the_Beam) is the
canonical account: the 2600 has no frame buffer, so the CPU writes TIA
registers in step with the beam with a budget of ~76 cycles per scanline.
Our packet imposes the same discipline one notch less extreme: the 2600's
register write *is* the picture; ours only configures generators that then
run autonomously for the line.

- **Flicker multiplexing.** Only two movable sprites exist per scanline, so
  games (e.g. Pac-Man's ghosts) draw a different object subset each frame,
  trading visible ~30Hz flicker for object count (case study in Montfort &
  Bogost; summary at luckybookshelf.com/racing-the-beam-by-nick-montfort-and-ian-bogost/).
  We already have 16 real cells per line, so the transfer is temporal, not
  spatial: alternate which *set* of 16 sprites is resident frame to frame
  when we want more than 16 independent movers, treating flicker as style.
  A luminance-domain 50Hz flicker composites fine — it isn't a chroma trick.

- **Playfield mirroring and HMOVE.** The 20-bit playfield register can
  mirror per screen-half or be rewritten mid-line (bumbershootsoft.wordpress.com,
  "Atari 2600: Playfields and Scoring"; problemkaputt.de/2k6specs.htm).
  HMOVE shifts objects up to 8px right at line start; writing it on every
  line produces the "HMOVE comb," which some studios kept as a deliberate
  black bar rather than hiding (bigmessowires.com/2023/01/11). Our two
  XORed accumulators already generalise mirroring — a power-of-two period
  *is* repetition — and we get clean per-line fine positioning without
  inheriting the comb. The transferable habit is the general one: an edge
  case in our own accumulator wraparound or sprite-priority rule may be
  worth keeping as a signature look rather than engineering away.

## Commodore 64 / VIC-II

Raster interrupts let software reconfigure video registers at a chosen
scanline without polling (en.wikipedia.org/wiki/Raster_interrupt,
en.wikipedia.org/wiki/MOS_Technology_VIC-II) — the mechanism behind nearly
every C64 demo effect. Our RP2040 is an interrupt handler that never
misses a line, because it streams precomputed state instead of racing
cycles live.

- **Sprite multiplexing.** 8 hardware sprites, reused mid-frame by
  rewriting Y once a sprite's 8 lines are drawn, giving 100+ apparent
  sprites per frame (codebase.c64.org/doku.php?id=base:sprite_multiplexing;
  lemmings.info/rasters-sprites-and-multiplexing/). Irrelevant to us
  directly — we already get per-line reconfiguration for free with 16 real
  cells. The useful transfer runs the other way: vary which of our 16
  cells "belongs" to a logical object as the line counter advances, to
  build objects needing more than 16 concurrent slots (not more than 16
  lines tall, which we already get free).

- **FLI/FLD.** FLI reprograms colour/bitmap registers every raster line
  for finer effective colour resolution; FLD moves bitmap rows by
  arbitrary raster distances (en.wikipedia.org/wiki/Commodore_64_demos).
  Per-line palette and background changes are already native to our
  packet, so FLI-grade *between-line* control is free. FLI's fine
  *within-line* colour detail is not: at ~1.3MHz, palette swaps must land
  at line start (bandwidth-free there) but stay at modest hue counts.

- **VSP/AGSP and sprite stretching.** VSP plus linecrunch gives
  pixel-fine scrolling on a character grid (kodiak64.co.uk/blog/future-of-VSP-scrolling)
  — moot for us since our 16-bit accumulators already scroll at pixel
  resolution natively. Sprite stretching toggles the Y-expand bit between
  lines to repeat a sprite row instead of advancing, stretching one row
  to fill the screen for one redraw (codebase64.org/doku.php?id=base:stretching_sprites;
  extreme variant at linusakesson.net/scene/lunatico/misc.php). This *is*
  directly reusable: hold a cell's bitmap-row pointer constant across
  many lines while varying only X, for cheap wobbling banners or "rubber"
  logos.

- **Open borders.** Toggling the 24/25-row register at the right instant
  suppresses the border to paint into blank retrace area, and a
  line-by-line variant does the same horizontally (lemon64.com/forum/viewtopic.php?t=71739,
  t=28410; aartbik.blogspot.com/2019/09). We have no equivalent "border" —
  256 columns is just our generator's run length — so no direct analogue;
  noted only as a category (any fixed blank timing region is a candidate
  to exploit later, no evidence yet that ours has slack).

## Amiga: the Copper

The Copper is a small coprocessor executing wait-for-position/write-register
instructions in lockstep with the beam, independent of the CPU
(en.wikipedia.org/wiki/Raster_bar; thebedroomcoder.co.uk/posts/copper-lists-explained-without-the-headache;
ginnov.github.io/littlethings/tutorials/copper_tutorial.html) — the closest
prior-art analogue to our per-line packet, except its list is data the
Amiga streams to itself rather than a host streaming in.

- **Copper bars / per-line palette.** A copper list writing a new colour
  every scanline makes smooth shaded bars at zero CPU cost once built;
  groups like Phenomena, Sanity, Spaceballs pushed this hard
  (c64portal.pl/2024/01/05/amiga-gfx-with-copper-bars/). This is nearly our
  packet model already — a moving gradient bar (position plus a few
  colours per line) is essentially free, and since our colours land at
  line boundaries rather than mid-line, there's no subcarrier-settling
  issue at all.

- **Parallax via per-line scroll.** Rewriting a bitplane's scroll register
  every line fakes depth from one bitplane by giving scanline bands
  different scroll speeds (same sources; en.wikipedia.org/wiki/Demo_effect).
  Directly cheap for us: band the screen into a few strips with different
  host-set scroll rates on one background layer. Pure horizontal
  displacement at line start — no bandwidth concern.

## NES: mid-frame splits without a coprocessor

No Copper, so games poll **sprite zero hit**: a status flag set the first
time sprite slot 0's opaque pixel overlaps an opaque background pixel,
letting the CPU catch an exact scanline to rewrite scroll registers
(forums.nesdev.org/viewtopic.php?t=15890, t=3599; tutorial at
nesdoug.com/2018/09/05/18-sprite-zero/). It only cleanly changes X scroll;
better games used a mapper scanline IRQ (MMC3/MMC5, Konami VRC) instead.
This whole category is solved architecturally for us: every line already
gets a fresh packet, so a scroll split is just a differing background
parameter between two lines, with no polling and no 8-pixel restriction.
The real lesson is the mirror image of the C64 open-borders one: the NES
fought its hardware for a synchronous per-line event that we get by
construction, so the design effort should go into making sure the RP2040
side never jitters that guarantee.

## Demoscene effects and their precompute

Effects are documented informally across wikis: Pouet's "A list of
oldschool demoeffects..." (pouet.net/topic.php?page=3&which=7523),
sizecoding.org/wiki/Design_Tips_and_Demoscene_effects_with_pseudo_code,
seancode.com/demofx/, and en.wikipedia.org/wiki/Demo_effect. Academically,
Markku Reunanen's licentiate thesis "Computer Demos — What Makes Them
Tick?" (Aalto, 2010; archive.org/details/reunanen-licthesis) and PhD
thesis "Times of Change in the Demoscene" (Turku, 2017;
utupub.fi/bitstream/handle/10024/130915/AnnalesB428Reunanen.pdf) are the
substantial long-form treatments. Daniel Botz's German dissertation *Kunst,
Code und Maschine: Die Ästhetik der Computer-Demoszene* (transcript Verlag;
danielbotz.de) is the deepest aesthetic treatment, using Kittler's
media-materiality to argue demoscene aesthetics are inseparable from
exposing the hardware — relevant since our project sits in that lineage.
**Unverified:** I could not read Botz's book directly (German,
print/limited digital); the summary above rests on secondary sources
(ResearchGate, gamescenes.org/2011/10/interview.html).

Unifying principle: a host (originally an offline assembler/table
generator, sometimes literally pen-and-paper) builds sine/distance/angle/
perspective tables once; the runtime only indexes and adds, no trig or
division live. This is exactly our "host precomputes, RP2040 streams"
model; our added constraint is that runtime state must fit the per-line
packet, not a CPU instruction stream.

- **Plasma.** Sine waves summed per point (often via distance-from-moving-
  centre), passed through a rotating colour table for cycling bands. This
  *is* our wave engine's job: the host precomputes wave parameters per
  frame, palette rotation is a packet field. Survives 1.3MHz as long as
  colour bands stay wide — the same constraint plasma always had on real
  subcarrier TVs.

- **Rotozoomer.** An affine screen-to-texture map is linear, so classic
  code increments `u,v` per pixel and resets per line from one sine/cosine
  lookup. Our accumulators already are "increment per pixel, reset per
  line" engines — the host just computes the per-line reset value. Unsure
  how much real per-pixel texture detail the XOR-of-two-accumulators
  pattern can carry versus a true bitmap lookup; likely stays in
  "stripes/interference" territory rather than arbitrary textures.

- **Tunnel.** Precomputed distance and angle tables per screen point,
  animated by scrolling their phase, no per-pixel runtime math. Our
  accumulator can approximate the angle table if the host precomputes a
  per-line rate profile — a good fit specifically because it's a per-line
  rate change, our packet's strength.

- **Twister.** A column of short bars, each angle/length from one sine
  lookup per bar, not per pixel. Cheap: a handful of (angle, length,
  colour) triples per frame, implementable as thin sprites at computed
  per-line X/width.

- **Sine scroller.** Vertical offset per column from a precomputed sine
  table indexed by scroll position. Fits either sprite-built text (per-
  cell Y offset) or a background accumulator driven by a precomputed
  low-frequency wobble. Spatial displacement only — no bandwidth concern.

- **Vector balls.** One shaded-ball bitmap stamped at positions from a
  precomputed 3D path (Lissajous/orbit), projected once per frame. A
  strong direct fit: one 16px bitmap, up to 16 positions per line from a
  host path table, "later cell wins" giving correct overdraw for free.
  Arguably our closest one-to-one match to a documented effect.

- **Kefrens bars.** Horizontal strips individually offset from a
  precomputed sine table (originally exploiting the Amiga blitter),
  faking volume from flat bars. Same mechanism as our parallax scroll,
  applied to a colour bar instead of a background layer — cheap.

- **Unlimited bobs / shadebobs.** "Unlimited bobs" amortises blit cost via
  clever background restore — not transferable, we have no frame buffer
  to damage or restore. Shadebobs draw a soft additive blob along a path
  with no erase step — this part transfers: a precomputed radial-falloff
  sprite bitmap moving along a precomputed path. Unsure whether our
  "later cell wins" rule can be reconfigured to add rather than override
  for true additive brightening on overlap; if not, dense overlapping
  soft blobs are a reasonable substitute.

- **Fire.** A palette-index array decayed by averaging neighbours and
  subtracting a constant, coloured through a black-to-white-hot ramp —
  unusually, a genuine live simulation rather than a table lookup. The
  simulation itself doesn't map onto our per-line generators (needs a
  persistent 2D buffer), but the *output* does: run it entirely on the
  host and stream the result as precomputed per-line patterns through the
  background layer — playback, not live computation.

## Ranked list: eight effects most worth building first

1. **Vector balls via the sprite pipeline.** Host precomputes an orbit/
   Lissajous path per frame, streams up to 16 ball positions per line,
   reuses one shaded-ball bitmap. Cheapest, closest match to existing demo
   art, and gives an immediate player control (steer the orbit's centre).

2. **Copper-bar palette gradient, player-tunable.** Per-line palette
   writes are nearly free; let a control shift the bar's position or
   width live, proving that packet-per-line composes with player input.

3. **Kefrens-bar / parallax scroll layers.** Band the screen into strips
   with independent scroll rates; drive relative strip speed from player
   movement for a cheap, convincing depth cue in a side-scroller.

4. **Sine-scrolling text/HUD.** Nearly free, and useful as a real HUD
   (score, wave number) rather than pure decoration; validates the
   per-line Y-wobble plumbing other effects will need.

5. **Tunnel via accumulator angle-rate profile.** Higher risk (unsure if
   our accumulators fake angle convincingly) but a strong "wow" effect and
   a natural tunnel-flying/dodge game with player-controlled rotation or
   speed — worth an early spike to resolve the open question.

6. **Plasma via the wave engine, player-modulated.** Matches the wave
   engine's purpose directly; let player input perturb a wave's frequency
   or phase (e.g. a "charge" mechanic) so the effect doubles as feedback.

7. **Rotozoomer floor.** Good fit for the background accumulators and a
   natural racing/perspective floor; sequence after the tunnel spike since
   it shares the open question about texture detail from the accumulator
   XOR.

8. **Fire, precomputed and played back.** Lowest hardware risk (pure host
   simulation, per-line playback) but lowest interactivity unless a player
   action seeds where the fire originates each frame, requiring the host
   to step the simulation per input rather than pre-baking a fixed loop.
