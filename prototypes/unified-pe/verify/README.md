# upe_v1: the unified PE and its array, specified, built in Hardcaml and verified (2026-09-25)

This closes gap G1 of `notes/architecture-v0.md`: the unified processing element was an area
probe (`../rtl/upe.v`) with no model and no test. Here it has an executable specification, a
Hardcaml implementation of the PE and of the 16-PE array cut into segments 2|2|4|8, a lockstep
test with biased generators and planted-bug controls, a synthesis check against the probe, and a
configuration library in which every cell the architecture requires is run through both model
and RTL and judged by an independent reference. Every number below points to a file in
`results/` (or `../reports/`, `../results/`).

## Files and commands

| file | what it is |
|---|---|
| `spec.ml` | the op-word encoding, the array's ports and control registers, the state record. Written from section 2.4-2.5 of the architecture note, not from `upe.v` |
| `model.ml` | the executable specification: integer arithmetic, a left-to-right evaluation of the chain each clock |
| `upe_rtl.ml` | the Hardcaml PE and array; `bug` plants one named fault (41 of them) |
| `rtlsim.ml` | the array under Cyclesim behind the model's interface |
| `lockstep.ml` | stimulus generators (uniform and 11 biased ones), lockstep runner, coverage |
| `refs.ml` | independent references: catalogue CRCs (two textbook loops), the C/A code from the ICD's G1/G2 definition, convolution |
| `cells.ml` | the configuration library and its directed tests |
| `../rtl/upe_v1.v`, `../rtl/upe_v1_array.v` | Verilog written by Hardcaml (`main.exe verilog-pe`, `verilog-array`) |

Build with the opam switch that has Hardcaml (nothing was installed):
`opam exec --switch=5.3.0 -- dune build ./main.exe`, then `main.exe lockstep 200 400`,
`controls 20 300`, `coverage 20 300`, `cells`, `shared-bugs`. Synthesis:
`../synth.sh upe_v1 upe_v1.v upe_v1` (the probe's flow: Yosys 0.62 in LibreLane 3.0.14, IHP
sg13g2 typical, area-mode abc).

## Results

**Synthesis (one run).** The Hardcaml PE synthesises to **14,359 µm², 1,050 cells, 99 flops**
(`../reports/upe_v1.stat.txt`, row `upe_v1` in `../results/areas.txt`). The probe `upe_v0` is
14,312 µm², 985 cells, 100 flops: **+47 µm² (+0.3 %)**, inside the ±300 µm² that abc's mapping
moves between runs of near-identical RTL (`../README.md`). The feature sets differ in detail
(below), so this confirms the probe's figure rather than reproducing its netlist. The array was
not synthesised (one run was allowed); `../rtl/upe_v1_array.v` is there for the next one.

**Lockstep.** 1,353,600 clocks, 12 generators × 200 trials × 564 clocks (164 of set-up through
the configuration and init chains, 400 of running traffic), every state bit of every PE (S, P,
its valid, F, the lane register, 64 configuration flops), the feed and control registers and
the four taps compared every clock: **0 mismatches** (`results/lockstep.txt`).

**Planted bugs in the RTL: 41 of 41 caught** (`results/controls.txt`), at least one per mode:
saturation, wrap, carry, carry-in, max/min, the loser, each logic op, gating, both negations,
bit test, each g source, the window (range and bit order), merge, g_in, both shifts' serial
inputs, conditional writeback, the zero flag, each lane output, broadcast, stream stepping,
deletion, follow, join, loop, feed valid, fixed ports, both chains, the tap, valid hold. Uniform
random configurations alone caught all 41 too, because every PE runs every clock, but slowly
where a mode needs a coincidence: a window accepting d = 16 took 5,226 clocks uniform and 372
biased; g_in cut at the segment 2/3 boundary 3,349 against 93; a wrong loop-back source 906
against 58. The coverage table (`results/coverage.txt`) shows why: a window merge happened 13
times in 20 uniform trials and 1,155 times under the window generator.

**Shared-specification faults: 6 of 6 caught by the references, 0 by lockstep**
(`results/shared_faults.txt`). Lockstep against one's own specification cannot see what the
specification shares with the RTL, so six faults were planted in model and RTL together (window
bit order, carry from bit 15, negation without +1, s15_in from own S, merge colour from K's high
byte, unsigned max). Lockstep reported 0 mismatches for each; the cells failed: sprites (339 and
415 wrong pixels), the NCOs (2,984 wrong phases), FIR, CIC, mixer, GPS and sync (negation), all
three CRC-32s (s15_in), sorting (unsigned max: 90 of 90 wrong).

## Configuration library (`results/cells.txt`: 17 of 17 pass)

Each test runs model and RTL in lockstep (0 mismatches in every one) and judges the outputs
against `refs.ml`.

| cell | configuration | test and reference | result |
|---|---|---|---|
| sprite | segments 2+3 joined: a pixel counter (S ← S + 0x0100 wrapping, P ← result) then 11 sprite PEs: g = window, P ← merge, S held, stream stepping | 6 lines, S and K reloaded per line through the init and configuration chains, random gaps between pixels, one line of 11 overlapping solid sprites; a direct painter's-algorithm renderer | **works as specified**, 1,536 of 1,536 pixels |
| tile, mid-line reload | renderer PE 2 in segment 1 (PE 3 passes and does not use S): g = S[15] (S[15] ^ a broadcast 0), S ← S << 1, P ← merge with the tile colour; the next tile row's two bytes are written into the init chain every 16 pixels, in the gaps between pixels | 16 tiles, one pixel every 3 clocks; reference from the tile bitmaps | **a one-colour tile layer with mid-line bitmap reload works**, 256 of 256; the note's tile cell (S *and* K reloaded per tile, so a colour per tile) does not. Constraints that follow from the spec rather than from this schedule: an init write shifts the S of every PE in its segment, so the renderer's segment-mates must not use S (a 2-PE segment wastes least), and an init write on a clock where the renderer steps replaces that step's shift, so the writes need gaps between pixels. Reloading K mid-line means 8 configuration bytes per PE through a chain whose op is garbled while it shifts; it was not attempted. The note said tiles were not expressible (G14); a bitmap tile layer is, a per-tile colour is not |
| FIR on 1-bit samples | transposed, segment 3: P ← A + (g ? −K : K), g = the broadcast sample, coefficients reversed | 8 taps, 400 samples; direct convolution | **works**, 400 of 400. Saturation of the partial sums was not reached (coefficients ±1,000) |
| CIC | segment 3: integrator ×2 (S ← S + A wrapping), phase counter (K = 0xC000, lane out = carry, which is 0 once in 4 steps), decimator (deletes when the lane is 1), comb ×2 (P ← A − S, S ← A) | order 2, R = 4, 400 inputs to ±10,000 so the integrators wrap, random gaps; direct convolution with boxcar4² at n = 4j, mod 2¹⁶ | **works**, 100 of 100. Decimation needs the counter and decimator PEs: 6 PEs, not 4 |
| NCO 16 and 32 bit | S ← S + K wrapping; 32 bit: low PE lane out = carry, high PE carry-in = lane | 3,000 steps; t·K mod 2¹⁶ and 2³² | **works**, 5,980 of 5,980. The high word runs one step ahead by K_hi (its carry arrives a step late); starting it at −K_hi makes {high(t+1), low(t)} = t·K exactly |
| mixer | P ← 0 + (g ? −A : A), g = the 32-bit NCO's MSB on the lane (join from segment 1) | 2,991 samples; x·sign of the phase | **works**, 2,991 of 2,991; sample c meets phase (c + 2)·K |
| GPS C/A correlator | segments 2+3 joined, 12 PEs: S ← S + (g ? −A : A), g = broadcast chip, P ← A | PRN 1-4 with delays 0, 11, 5, 7 chips, ±3 plus noise, 1,023 chips each; code from the ICD's G1/G2 registers, itself checked against the ICD's first-10-chip octal values for PRN 1-4; direct correlation | **works with a change**: 52 of 52, peaks 3,037-3,103 at the right offset each time. v0 gives each segment its own broadcast bit, each written by its own mailbox write, and the mailbox takes one write per clock, so two segments' bits can never change on the same clock: at every chip change one segment's correlators would integrate at least one sample against the old chip. Added: control bit 5, "take the previous segment's broadcast". Within one segment (at most 8 correlators) v0 suffices |
| sync word | (a) exact: PE 0 deserialises the broadcast bit (S ← S << 1 \| lane), PE 1 XORs with the word, F ← zero. (b) soft ±1 score: 8 PEs in transposed form, template bit in S[15], g = S[15] ^ bit, P ← A + (g ? −1 : 1) | 600 bits, 0x1ACF inserted 3 times, 0x7E twice (one with a flipped bit); direct comparison and direct score | **works**: 1,177 of 1,177. The note said not a PE configuration (matcher assist); exact match costs 2 PEs, a soft N-bit score N PEs, and the threshold is left to a thread or another PE |
| min-plus | per edge two PEs: P ← A + w (saturating), then S ← min(S, A), P ← S | 10 instances of a 4-edge path, 30 candidate distances each with gaps; half with weights to 20,000 (3 instances reach infinity, 0x7FFF), half also streaming 0x7FFF and values just below it; direct fold | **works as specified** (2 PEs per relaxation); 40 of 40 |
| sorting | systolic insertion: S ← max(S, A), P ← loser; S starts at −32,768 | 10 instances of 20 values through 8 PEs, half of them with duplicates and the extremes −32,768 and 32,767; `List.sort` | **works**: the top 8 in order and the other 12 plus 8 sentinels out of the tap, 90 of 90. Only the insertion (priority-queue) step was tried, not a compare-exchange network |
| CRC-16 | one PE: S ← (S << 1 with sin = g) XOR (g ? K : 0), g = S[15] ^ A[0], K = poly without x⁰; F ← (S' = 0) | XMODEM, IBM-3740, KERMIT, USB: catalogue check values, 20 random messages each, bits through the mailbox feed (a bit every other clock); reflected CRCs by feeding LSB first and reflecting the result; residue: message ‖ CRC leaves S = 0 and F = 1 | **works as specified**, 92 of 92. The bit-order construction is anchored by the catalogue: "123456789" through the PE equals the catalogue check value for every CRC |
| CRC-32 | a pair as in the note: low g = cb_in ^ A[0], sin = g; high g = g_in, sin = s15_in | ISO-HDLC, BZIP2, MPEG-2: catalogue checks, 21 messages each, twice | **works as the note designs it only when both PEs step on the same clocks**: with a bit every clock and the segment run for exactly the message, 63 of 63. The only v0 mechanism for bits with gaps is stream stepping, and in stream mode the high PE's A (the low PE's P) becomes valid one clock after the low PE's, so it steps a clock late and g_in belongs to the wrong step: 21 of 21 messages wrong with gaps and 21 of 21 without. (A thread could instead pulse the segment's run bit once per bit, but not for bits arriving from the fixed port.) Added: a **follow** bit (step exactly when the left PE steps); with it the pair takes bits with gaps, 63 of 63 |

## Proposed changes to the PE definition

1. **follow** (op bit 32): step when the left neighbour steps. Needed by the CRC-32 pair (and
   any pair) fed at less than a bit per clock. One mux on the step signal, the configuration
   bit already exists among the 48; it is inside the 14,359 µm² above. Estimate from the
   LEF areas (`../../systolic-storage/results/lef_areas.txt`): one mux2, 18 µm² per PE.
2. **Broadcast chaining** (segment control bit 5): a segment's broadcast bit may be the
   previous segment's, so joined segments share one broadcast. Array level: three flops and
   three mux2 for segments 1-3, about 200 µm² (est). Needed for correlator banks longer than one
   segment. Not done, and worth considering with it: a broadcast taken from the previous
   segment's end lane, so that a code generator on the array can drive the correlators (today
   the chip can come only from a thread, one mailbox write per chip).
3. Not proposed: a fused add-then-min (min-plus works on two PEs); a tile reload path (tiles
   work within the limits above).

## Where upe_v1 differs from the probe (`../rtl/upe.v`, read after the model was written)

The probe and the note leave semantics open that a model has to fix. Choices made here:
- **Registered lane output for g and carry.** The probe's lane output g is combinational, so
  a PE downstream sees g for the pixel one position behind its A; the rotozoomer's v → merge
  hand-off would be off by one. Here the lane register takes lane_in, S'[15], carry or g at the
  step, aligned with P.
- **Carry-in replaces the negation's +1** (probe: ORs them). With this, a chain of PEs with the
  lane carry-in does multi-word subtraction as well as addition.
- **Max and min compare X with the modified Y**; the probe subtracts and ignores the Y
  modifier. No cell uses a negated max.
- **F has a hold option**; the probe always writes F (g or zero) on a step.
- **Valid out updates every clock the segment runs** (A's valid, less deletion), in both
  stepping modes; the probe sets it to 1 outside stream mode.
- **Serial input choices**: g, lane, s15_in, A[0] (probe: lane, s15_in, parity, g).
- The array's feed, control, fixed ports, chains and taps are specified in `spec.ml`; the probe
  had none of them.

## Review

One adversarial review by another model family (codex-luna), output in
`results/codex-review.txt`. It found no wrong result but four claims stated more broadly than
the tests showed, and three thin tests. Changed in response: the tile row now says the note's
per-tile colour is not achieved and states which constraints follow from the spec; the CRC-32
row says stream mode fails with and without gaps, and why; the GPS row states the structural
reason (one mailbox write per clock) instead of a threshold; GPS now runs four PRNs and delays
(was one), min-plus ten instances including infinity (was one without), sorting ten instances
with duplicates and extremes (was one). Not changed: its point that the 41 RTL controls show
sensitivity of the model-RTL comparison and not that the model matches the note. That is what
the shared-fault controls and the independent references are for, and the README says so.

## Open issues

- The array was not synthesised; its area is still the probe's estimate (11,090 + 3,500 µm²).
- GPS with the code generated on the array (a GF(2) PE pair driving the broadcast) is not
  expressible without the lane-to-broadcast option above, and was not tried.
- FIR saturation, negated max/min and 16-bit NCO audio (sigma-delta) were not given directed
  tests; lockstep covers them against the model only.
- The window wraps mod 256: a sprite at x > 240 reappears at the left edge. The test keeps
  x ≤ 240; the console reference should decide whether that is wanted.
- The console's own 720-line reference (`../../retro-console`) was not rerun on the UPE; the
  sprite test uses an independent renderer written here.
