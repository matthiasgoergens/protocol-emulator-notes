# S/PDIF (IEC 60958 consumer) on the generic blocks

S/PDIF transmit and receive, built only from blocks in `notes/architecture-v0.md`: ISA v2 firmware
on the sequencer, the pin NCO, the edge-tracking sampler, the packer, the data bank and (for the
demo) the PE array. The work is in simulation; no protocol-specific hardware was added. One block
gets a new mode, the pin NCO's "pace" mode, described below.

Build: `opam exec --switch=5.3.0 -- dune build` (Hardcaml v0.17). `./run_all.sh` regenerates every
file in `results/`, one simulation at a time, niced, and waits while the load is above 20.
`./run_all.sh tx controls` runs the named suites only. The sigrok oracle needs podman, and builds
its image on first use.

Reused through symlinks, unchanged:
- `isa2.ml` comes from `../sequencer-v2`: the ISA v2 interpreter, lockstepped there against its RTL.
- `edge_sampler.ml` comes from `../eth10-node`: the sampler's model and its verified RTL.
- `upe.ml`, `row.ml` and `synth.ml` come from `../array-uses`: the upe_v0 PE model and the chiptune.

## The answer

| | result | evidence |
|---|---|---|
| Transmit, 44.1 and 48 kHz, 16-bit, at 60.000 and 60.852 MHz | The chip's pin output matches the reference encoder for all 57,472 UIs in each of the 4 cases, with 0 FIFO underruns. The pacer RTL equals its model on every clock. | `results/tx.txt` |
| Same output, independent decoders | Our OCaml oracle matches 898/898 subframes with 2 channel-status blocks equal. sigrok's spdif decoder matches 897/897 subframes (preamble, 24-bit audio, V, U, C, P) in all 4 cases. | `results/tx.txt`, `results/sigrok.txt` |
| Transmit jitter on the quarter grid | 4.1 ns p-p, which is 0.023–0.025 UI. After AES3's 700 Hz filter, at the transmitted edges, the peak is 0.012–0.013 UI. The limit is 0.025 UI (AES3), and the consumer figure is 0.05 UI. | `results/jitter.txt` |
| Receive: 40 random runs | 40 of 40 clean. Each run had 420 frames of 24-bit random audio, source ±1000 ppm, random jitter up to the AES3 template, at 44.1/48 kHz and an RX clock of 60/60.852 MHz. | `results/rx-random.txt` |
| Receiver jitter tolerance | ≥ 1 UI p-p at 10 and 100 kHz; 0.60–0.90 UI at 400 kHz; 0.35–0.40 UI at 1 MHz. AES3 asks for 0.25 UI p-p above 8 kHz. Each point is one run, not a statistic. | `results/tolerance.txt` |
| Round trips: chip TX → chip RX | 7 of 7 pass, ±1000 ppm, including RX at 60.852 MHz. | `results/roundtrip.txt` |
| Planted faults | Every one of 6 line faults is caught by the chip and by the oracle. 4 chip faults are caught, and so is 1 sigrok control. | `results/controls.txt`, `results/sigrok.txt` |
| Demo | The PE-array synthesiser feeds the chip TX, then the line (+150 ppm, 1 ns rms), then both the oracle and the chip RX. Both outputs equal the synthesiser's tap word, frame for frame. There is a WAV and an analyser panel. | `results/demo.txt`, `results/demo/` |

## Transmit

Pin chain: thread T0 → out-port 0 → byte FIFO → shift register (MSB first) → NRZI coder → pin NCO in
pace mode → four-phase output stage. The firmware is in `tx_fw.ml`; the hardware is `pacer.ml`
(model and RTL).

**The domain is transitions, not levels.** T0 writes one bit per UI, 1 meaning "the level changes at
the start of this UI". Each biphase-mark symbol is then `1 b`, and each preamble is a constant byte:
B 0x9C, M 0x93, W 0x96. AES3's two polarity sets give the same transitions. So a subframe is 8 bytes:
- preamble;
- 0xAA twice, for the zero aux and four LSB bits;
- four expanded nibbles of the 16-bit sample;
- the V U C P byte, `0xAA | C<<2 | P`.

The NRZI coder turns transitions into levels, so the firmware never tracks polarity.

**No ALU.** ISA v2 has no XOR or add, and cannot shift by a variable amount. Everything bit-level is
a table in the 1,024-byte bank, read by `BANK page` (bp ← {page, acc}) and `LDB`:
- page 0: low-nibble expansion;
- page 1: high-nibble expansion;
- page 2: parity;
- page 3: 192 channel-status code bytes.

That fills 960 of 1,024 bytes. The running parity of a subframe is held in the programme counter
(the code is duplicated per parity state). A byte needed twice is parked in the thread's own inbox
with SEND and RECV, because LDB overwrites the accumulator.

T1 walks the channel-status table (8 words) and hands T0 one code byte per frame through inbox 0:
- bit 0: C of the left subframe;
- bit 1: C of the right subframe;
- bit 7: frame 0, i.e. preamble B.

T0 is 138 words. The thread is paced by the FIFO: a SEND waits while the FIFO is full.

**The pin NCO's pace mode (new).** The pin NCO already computes its phase at the four quarter
points of each clock (`../multiphase/nco.ml`). In pace mode, a carry between two quarter points is a
bit boundary: it pops the next bit into the NRZI coder, and the new level starts at that quarter.
Edges are the ideal edges delayed to the next quarter-clock grid point, the same quantisation as the
NCO's square-wave mode.

The RTL is in `pacer.ml`. Lockstep against the model: 200 random configurations, 600,200 clocks,
0 mismatches (`results/pacer.txt`). In the transmit runs the RTL and the model also agree on every
clock. Area was **not synthesised**. My estimate is a 3-bit quarter decoder, an 8-bit shift register,
a 4-byte FIFO and a few muxes beside the existing 24-bit NCO, about 2,000 µm² (est).

Increment: `inc = round(2^32 · 128 fs / fclk)`, for example 0x1815a07b for 44.1 kHz at 60 MHz.
The pacer needs inc < 2^30, at most one boundary per clock. That holds up to a UI rate of
fclk/4: 15 MBd, or 117 kHz frames at 60 MHz.

**Channel status sent** (`iec60958.ml`): consumer, linear PCM, Cp = 1 (copy permitted), no
pre-emphasis, mode 0, category CD 0x01 with L = 0 (original), source 0, channel 1 (left) and 2 (right),
fs 44.1 kHz (0000) or 48 kHz (0100), clock accuracy level II, word length 16 bits of 20.

Sources:
- The bit layout is from the public preview of IEC 60958-3:2006, §5.2 (byte 0 and Table 2).
- The frame, preambles and coding are from AES3-1992 (r1997) §§2.2–2.4.
- Copies are under `/var/tmp/spdif/refs` (iteh.ai sample PDF; cim.mcgill.ca AES3 PDF).
- The CD category value 0x01 is the ALSA header's `IEC958_AES1_CON_IEC908_CD`.

**The L bit** (generation status, bit 15) is from IS/IEC 60958-3:2003 §5.3, the Indian adoption,
which is public at law.resource.org (`/var/tmp/spdif/refs/is-iec60958-3-2003.txt`, lines 589–614).
Generally L = 1 means "commercially released pre-recorded software". "For historical reasons, the
reverse situation is valid" for laser-optical products ("100 XXXXL") and broadcast reception, where
L = 0 means commercially released. A CD player playing an original disc therefore sends L = 0.

My first version sent L = 1, with this sense backwards from memory. The codex review flagged it
and the text settled it. The analyser applies the reversal when it prints the L bit.

### Transmit jitter (`results/jitter.txt`)

Method:
- Take the time-interval error of every UI boundary over 50 ms, against a least-squares line.
- Take p-p, and the peak after the intrinsic-jitter filter.
- The filter is AES3-1992 §6.2.5.1: "a minimum-phase high-pass filter with 3 dB attenuation at
  700 Hz, first order roll-off to 70 Hz". It is modelled as one pole.

| grid at 60.000 MHz | 44.1 kHz p-p | 44.1 kHz filtered peak | 48 kHz p-p | 48 kHz filtered peak |
|---|---|---|---|---|
| quarter (four phases) | 4.14 ns = 0.023 UI | 0.0117 UI | 3.91 ns = 0.024 UI | 0.0120 UI |
| quarter, phases off by ±1 ns | 0.035 UI | 0.0179 UI | 0.036 UI | 0.0189 UI |
| half (both clock edges) | 0.047 UI | 0.0234 UI | 0.050 UI | 0.0248 UI |
| clock grid | 0.094 UI | 0.0469 UI | 0.101 UI | 0.0504 UI |

At 60.852 MHz the figures are within 0.001 UI of these.

The table measures every UI boundary. Intrinsic jitter is defined at the transitions, which are an
irregular subset of the boundaries; the codex review pointed this out. So the measurement was
repeated at the transmitted edges only. It used the pacer model driven by the TX firmware: 20 ms of
random audio, about 71,000–78,000 edges, with the filter stepped by each edge's own interval. The
filtered peak is **0.0117–0.0129 UI** across the four rate and clock cases (last block of
`results/jitter.txt`, with a check that it stays below 0.025 UI).

Limits, with the UI defined as 1/128 of a frame (AES3 §2.1.13; 177.2 ns at 44.1 kHz):
- AES3 intrinsic jitter: < 0.025 UI peak, filtered. The quarter grid passes with half the margin
  to spare. The half grid sits at the limit. The clock grid fails.
- IEC 60958-3 consumer: 0.05 UI. This figure is from a Wolfson/Cirrus white paper
  (`/var/tmp/spdif/refs/cirrus-jitter.txt`); I have not seen the standard's own text. The same paper
  says "at 48kHz, one UI is equivalent to 163ns", which agrees with AES3's UI.
- Receiver tolerance, AES3 §6.3.6 figure 11: 0.25 UI p-p above 8 kHz, rising to 10 UI p-p below
  200 Hz. The paper adds 0.2 UI above 400 kHz for IEC 60958-3 (unverified).

So the quarter grid is good for S/PDIF with margin. The quantisation is deterministic. Its
period is 147 UIs at 44.1 kHz and 60 MHz (240 MHz / 5.6448 MHz = 3125/147). Its spectrum therefore
sits at about 38 kHz and its harmonics, above the 700 Hz filter.

Not modelled:
- the pad's rise and fall asymmetry;
- the delay-line phases' real skew (the ±1 ns row is a sensitivity, not a measurement);
- the TOSLINK module.

The module dominates. The PLT237 datasheet gives pulse-width distortion of ±20 ns and up to 20 ns
of jitter (hardware notes below). The chip's 4 ns is small beside that.

## Receive

Chain: pins at four samples per clock → **edge-tracking sampler in biphase-mark mode**, unchanged
RTL → **packer** → thread R0 (parser) and thread R1 (channel-status collector). The firmware and
packer are in `rx.ml`.

The packer is the pin sampler's packing: LSB first into 16-bit words with a count, 0 meaning full.
It flushes a partial word at the sampler's burst end, and has a 4-word FIFO. R0 reads it on
in-port 0 as three bytes per word: count, low, high.

**Preambles without new hardware.**
- Biphase mark has edges 1 or 2 UI apart; only preambles have a 3-UI run.
- Set holdoff between 1 and 2 UI and timeout between 2 and 3 UI. The sampler's burst then ends
  inside every preamble, and the next edge starts a new burst.
- The timeout counts from the last anchoring (cell-boundary) edge, not the last edge.

Traced on the model, the segments between burst ends are:

| preamble | packer words | segment parity | C bit |
|---|---|---|---|
| B (Z) | a count-1 word holding 1, then 16 + 12 bits (d4..d31) | 0 | bit 2 of the last byte |
| M (X) | (an empty segment), then 16 + 13 bits ("1", d4..d31) | 1 | bit 3 |
| W (Y) | a count-1 word holding 0, then 16 + 12 bits | 0 | bit 2 |

My first hand trace got W wrong. I had expected "0 1 d4..": I had restarted the timeout at every
edge. The model showed a separate "0" segment, and the firmware follows the model.

**One configuration covers 44.1 and 48 kHz** at 60.000 and 60.852 MHz: holdoff 61 and timeout 101
sub-samples (4.17 ns each at 60 MHz). Margins in UI, as the distance from a threshold to the
nominal interval:

| | 1 UI vs holdoff | 2 UI vs holdoff | 2 UI vs timeout | 3 UI vs timeout |
|---|---|---|---|---|
| 44.1 kHz, 60 MHz | 0.43 | 0.56 | 0.38 | 0.63 |
| 48 kHz, 60 MHz | 0.56 | 0.44 | 0.59 | 0.41 |
| 44.1 kHz, 60.852 MHz | 0.41 | 0.59 | 0.34 | 0.66 |

The smallest margin, 0.34 UI, matches the measured high-frequency tolerance. At 1 MHz, adjacent
edges move in opposite directions, so an interval changes by the full p-p, and the receiver fails
at 0.40–0.45 UI. 32 kHz needs its own configuration: its 2 UI equal 48 kHz's 3 UI, so no single
timeout separates them.

**R0** is 238 of the page's 256 words, so it is nearly full. Per word it reads the count and
branches on it with SKNE. Each data byte goes to the host (`OUT tag 1`) and through the parity table,
with the running parity held in the pc. On the last high byte it:
- tests the C bit with WAITC on the accumulator bit, which is a branch;
- sends `(B flag, C)` to R1;
- checks the segment parity;
- closes the record with `OUT tag 2` (kind, and parity bad).

A count the preamble table does not allow gives `OUT tag 3`; a bad prefix value gives tag 5. Both
resynchronise at the next word.

The host reassembles d4..d31 from the four data bytes, shifted by the kind's prefix. That shift is
the one bit-alignment step the ALU-less sequencer leaves to the host.

**R1** stores each subframe's code byte with STB into one of two 384-byte buffers in the bank:
left and right interleaved, double-buffered, so the host has a whole block time to read the
finished one. On a B code it switches buffers and reports `OUT tag 4`. The RX bank holds the parity
table (256 bytes) plus 2 × 384 bytes: **1,024 of 1,024**. TX and RX can therefore not share one
chip's bank as built (960 + 1,024 bytes). Shrinking R1 to one buffer, or packing C bits eight to a
byte, would be the fix. Neither was done.

Error accounting in the tests. A run is clean only if all of these hold:
- At most one error comes before the first complete subframe (the receiver locking on
  mid-subframe).
- At most one framing error comes after the last edge of the capture (the stream stopping
  mid-subframe).
- No other error occurs.
- At most two of the sent subframes are missing, the first and the last.

The codex review found the first version of these criteria too loose: it allowed four missing
subframes and any number of errors at the edges. They were tightened, and every suite was re-run.

## Verification

**Oracles**
- The reference encoder `iec60958.ml` defines what should be sent.
- `oracle.ml` is an independent decoder written from the AES3 rules. It shares no code with the
  encoder or the chip path, and works differently: it classifies edge-to-edge intervals as 1, 2 or
  3 UI against a tracked UI estimate, then parses preambles (3-3-1-1, 3-2-1-2, 3-1-1-3), symbols,
  parity, frames and blocks.
- sigrok's own `spdif` decoder (sigrok-cli 0.7.2, libsigrokdecode 0.5.3, Debian trixie, in podman)
  runs on the chip's pin captures (`sigrok_check.sh`). It checks no parity and reports bogus
  "Signal Bitrate" text, so it is compared on (preamble, audio, V, U, C, P).
- A capture must start near the first edge. sigrok learns the pulse widths from the first
  intervals; a long idle lead-in made it decode nothing. That was found and fixed here.

How independent the oracle is: it is a different algorithm, but it encodes the same reading of
AES3 as the encoder (preamble interval patterns, slot order). A misreading shared by both would pass
it. sigrok's decoder, written by others, is the check against that, though it does not check parity.

**What is compared.** Decoded subframes are compared with sent ones in order. The comparison
resynchronises after a mismatch, and reports resyncs and skipped subframes. Complete
channel-status blocks are compared bit for bit, left and right.

**Planted faults** (`results/controls.txt`), all on a 44.1 kHz stream with +500 ppm and jitter. Each
must make the run fail, and the clean baseline must pass.

| fault | chip RX | oracle |
|---|---|---|
| an M sent as W | caught (1 subframe differs) | caught (frame-order errors) |
| the block's B sent as M | caught (subframe differs, no complete CS block) | caught |
| parity bit flipped | caught (parity flag) | caught |
| one channel-status bit flipped, parity kept | caught (CS block differs, parity clean) | caught |
| missing cell-boundary edge | caught (framing error, 1 subframe lost, resync) | caught |
| one UI removed | caught (framing errors, resync) | caught |
| chip: sampler holdoff 35 (< 1 UI) | caught | – |
| chip: sampler timeout 130 (> 3 UI) | caught | – |
| chip: TX parity-table entry 0x5a wrong | 6 UIs differ from the reference; the oracle finds exactly the 6 parity errors expected | |
| chip: TX expansion entry 0x33 wrong | 5 UIs differ; 5 subframes differ at the oracle; sigrok's comparison fails | |

**Random receive** (`results/rx-random.txt`, `main.exe rx 40 2026`). Each of the 40 runs draws:
- 44.1 or 48 kHz;
- an RX clock of 60 or 60.852 MHz;
- a source offset uniform in ±1000 ppm;
- 0–2 ns rms Gaussian jitter;
- sinusoidal jitter up to the AES3 template at a random frequency of 200 Hz–400 kHz;
- 24-bit random audio, random V and U, and a start at a random frame of the block.

The sampler runs as RTL throughout. The RTL-against-model comparison (`impl = Both`) was run in the
smoke test: 0 mismatches once bits outside "valid" are ignored.

## Demo (`results/demo.txt`, `results/demo/`)

The tune is `../array-uses/synth.ml`'s chiptune: 4 square voices and a noise voice on 16 upe_v0
PEs. Here the segment steps once per audio frame, triggered by T0's feed word, instead of once per
clock. PEs 14 and 15 pass the signed sum to the segment tap, and T0 reads the tap on in-port 0.

The run covers 1.0 s (60 M clocks). The path is chip TX, then the line (+150 ppm, 1 ns rms), then
both the oracle and the chip RX, each writing a WAV:
- `oracle.wav`: the oracle's decode;
- `chip-rx.wav`: the chip RX's decode;
- `synth-direct.wav`: the tap words themselves.

All three are identical frame for frame. The analyser panel (`analyser.txt`, 40 columns, for the
console's text layer later) shows:
- the sample rate measured from B-preamble spacing against the receiver clock: 44,106.6 Hz for
  +150 ppm;
- frame and block counts, and parity, framing and validity errors;
- L/R peak meters in dBFS;
- the decoded channel status.

Shortcuts in the demo:
- The synthesiser's configuration is reloaded "direct", the idealised double-buffered load, every
  176 frames.
- The voices sound as naive square waves sampled at 44.1 kHz (aliasing, as chiptunes do).
- Stepping once per feed word is the architecture's stream stepping, imposed through the model.

## Assumptions about the generic blocks (to settle before RTL)

1. **The pin NCO's pace mode**, described above. This is the one new mode. It is a few gates, but
   it is not in the architecture note yet.
2. **Out-port 0 → the streamer FIFO, in-port 0 ← the packer.** ISA v2 defines ports 4–7 as segment
   feed and tap. The note says the packer goes to "segment feed or thread", and P34 says "the
   streamer's FIFO, started by a thread". The port mapping here is my choice.
3. **The packer delivers count, low and high bytes** per word to a thread. The pin sampler hands
   16-bit words with a count to the host.
4. **Segment stepping once per feed word**, the architecture's stream mode.

## Hardware notes

Part status was checked on 2026-10-05 by a research agent reading the cited pages. "Checked by me"
marks the claims I re-read myself.

**TOSLINK transmitter (logic-level input, 3.3 V): Everlight PLT237/T10WH.**
- DigiKey shows it **Active**, 2.7–5 V, 25 Mbps, 793 in stock (checked by me:
  https://www.digikey.com/en/products/detail/everlight-electronics-co-ltd/PLT237-T10WH/14641724).
- Datasheet (agent):
  https://media.digikey.com/pdf/Data%20Sheets/Everlight%20PDFs/PLT237-T10WH_Rev1_3-22-21.pdf
  - VIH 2.0 V min, VIL 0.8 V max, so a 3.3 V pad drives it directly.
  - Pulse-width distortion ±20 ns and jitter up to 20 ns max, at 5 V and 25 Mbps NRZ.
  - Vin and Vcc should be removed together.
- Rejected:
  - Toshiba TOTX147 (3.3 V, 15 Mb/s NRZ) is listed obsolete.
  - TOTX1350 and TOTX1950 are 5 V parts.
  - Everlight PLT133/T10W is active but out of stock, and DigiKey points to the PLT237.
  - TOTX177, Cliff FC684205T: unverified.

**TOSLINK receiver: Everlight PLR237/T10BK (likely; supply range unverified).**
- DigiKey names it the replacement for the obsolete PLR135/T10.
- Search snippets (unverified) give 25 Mbps, PWD ±25 ns, and jitter 1–15 ns at −14 dBm.
- Its 3.3 V operation must be read from the datasheet before ordering:
  https://www.mouser.com/datasheet/2/143/Everlight_09052023_PLR237_T10BK_Rev1_3_30_21-3313190.pdf
- Fallbacks:
  - Toshiba TORX147, 2.7–3.6 V with CMOS output, which the agent read from the datasheet, but it
    is listed obsolete.
  - Cliff FCR684208R, 3–5 V and 16 Mbps per snippets: unverified.
- Its output goes straight to an input pin. The receiver's tolerance measured above (≥ 0.35 UI p-p,
  58–62 ns) is about twice the module's PWD.

**Coax output, 0.5 V p-p into 75 Ω, 75 Ω source.**
- The level, and the source impedance of 75 Ω ±20 %, are from the Cirrus CS8406 datasheet
  appendix, per the agent. Not re-read by me.
- My derivation for a 3.3 V pad, shown to agree with the CS8406 3.3 V values the agent reported
  (243 Ω and 107 Ω):
  - Thevenin requirements: R_s ∥ R_p = 75 Ω, and 3.3 V · R_p / (R_s + R_p) = 1.0 V open circuit,
    which gives 0.5 V into 75 Ω.
  - Solving: R_s = 2.3 R_p, then R_p = 75 · 3.3 / 2.3 = 107.6 Ω and R_s = 247.5 Ω.
  - R_s includes the pad's output resistance. With about 30 Ω of pad, use **215 Ω series + 107 Ω
    to ground** (E96: 215, 107).
  - Then add 0.1 µF in series to the RCA jack as a DC block. The divider has no DC path to the
    jack's ground otherwise, so this makes the output AC-coupled as consumer inputs expect.
  - A 1:1 pulse transformer is optional, for ground isolation.
- Measure the pad's real resistance and VOH and VOL under load; they move the level by tens of
  percent.

**Coax input.**
- 0.5 V p-p is not a logic level. Terminate in 75 Ω, AC-couple with 10–100 nF, and square it up
  before a pin. Options:
  - a comparator with hysteresis biased at mid-supply (TLV3501, LMV7219: not checked);
  - an unbuffered inverter biased as an amplifier (74HCU04 with 10 kΩ feedback: a hobby circuit,
    unverified).
- Simpler for the demo board: use only TOSLINK for input.

## Review

There was one adversarial review, `codex-luna exec`; its findings are in
`results/codex-review.txt`. Each finding, and what was done about it:
1. The L bit had the wrong sense: correct. It was fixed against the standard's text (above).
2. Jitter should be measured at the transitions only: correct. The measurement was added (above),
   and the result barely moves.
3. The pass criteria were too loose: correct. They were tightened (above), and all suites were
   re-run.
4. The oracle shares the encoder's reading of AES3: true, and noted above.

The review found the following correct: the framing, the preamble bytes, the slot placement, the
channel-status positions and rate codes, the receive signatures, C-bit positions and parities, and
the ISA v2 usage.

## Open issues

- Area of the pace mode was not synthesised (estimate above).
- No slot-budget measurement was made: how much of T0's and R0's time is spent waiting. Zero
  underruns and zero overflows at 48 kHz show that they keep up, not by how much.
- R0 at 238 of 256 words leaves no room for 24-bit reassembly on chip.
- TX and RX cannot run at once in one bank as built (above).
- 32 kHz is not tested; it needs its own sampler configuration.
- The analyser's sample rate is measured; the host also has the CS code. An auto-ranging receiver
  would choose the sampler configuration from the measured preamble spacing.
- Jitter tolerance points are single runs. A statistic would need many seeds per point.
- The architecture note (§3 mapping table) still needs an S/PDIF row. It is not edited here, to
  avoid colliding with work in sibling worktrees.
