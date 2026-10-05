The strongest entry is a reprogrammable “silicon laboratory”: it learns an unknown peripheral, perturbs it with sub-clock precision, minimises failures, and then emulates it. Keep the gain-cell memory as a self-characterising experiment, but use SRAM for the machine’s programme store.

A critical finding from the adversarial pass: the Berger-code argument is currently unsound for the latest cells. [gain-cell-compiler.md](</home/matthias/prog/janestreet/emulator-snap-brainstorm2/notes/gain-cell-compiler.md>) assumes exclusively 1→0 decay, but the later thin/level-shifted simulations observe stored zeroes rising into ones, and [systolic-storage/README.md](</home/matthias/prog/janestreet/emulator-snap-brainstorm2/prototypes/systolic-storage/README.md>) explicitly says a mixed-direction control escapes Berger detection. Fix that before presenting Berger as the safety net.

## Priorities

1. **Freeze a “boringly alive” emulator baseline**

   **Exactly:** sequencer, one 256×16 SRAM programme store, host load/readback, synchronised clock-grid GPIO, streamer/sampler, and the existing matcher. UART, SPI and I²C must work with all custom analogue blocks disabled.

   **Why:** this directly satisfies Jane Street’s primary request. The component-area sum is roughly 80,000 µm² before top-level routing: plausible in 24 tiles, though only integrated P&R will establish that.

   **Cost/risk:** low conceptual risk; ordinary SRAM-macro integration remains unfinished.

   **First step:** freeze the top-level memory map and interfaces, then synthesise and place-and-route the whole baseline with the exact SRAM macro.

2. **“Learn, break, emulate” an undocumented peripheral**

   **Exactly:** interrogate a deliberately undocumented FPGA “sensor”; use the four-phase output to issue legal commands and timed glitches, the TDC to capture response timing, the systolic matcher to recognise motifs, and `hwfuzz` to explore and shrink queries. A host agent infers a timed state machine and compiles it onto the sequencer. Finish by replacing the target with the ASIC emulator and showing that its original controller cannot distinguish them.

   **Why:** this is a single, legible demonstration of protocol emulation, hardware debugging, reverse engineering, fuzzing and AI-assisted design.

   **Prior art:** Angluin L*/LearnLib active automata learning and ChipWhisperer-style glitching. I am unsure of precedent for the complete learn–glitch–minimise–emulate loop in a small programmable ASIC.

   **Cost/risk:** moderate host software; state explosion and incorrect electrical models can produce false conclusions.

   **First step:** implement the mystery target with an unlock sequence and a narrow timing vulnerability, then demonstrate inference and substitution on FPGA.

3. **Differential timing fuzzer producing a minimal shmoo witness**

   **Exactly:** sweep edge phase, pulse width and jitter against a golden and suspect target. Use TDC timing differences and matcher states as context-gated coverage. Return both an eye/shmoo boundary and the smallest waveform causing divergence.

   **Why:** this turns the existing Ethernet differential-fuzzing result into a physical debugging instrument. “Here is the exact 700 ps-wide, phase-specific pulse that breaks your receiver” is likely more compelling to hardware engineers than another supported protocol.

   **Prior art:** ATE shmoo plots, BERT eye scans, differential fuzzing and ChipWhisperer. The integrated coverage-guided minimiser is the distinctive part.

   **Cost/risk:** metastability, pad behaviour and oracle assumptions. The existing Ethernet work already demonstrates that the transducer model can itself be wrong.

   **First step:** plant a setup/hold defect in an FPGA target and require repeatable discovery and minimisation across fresh campaigns.

4. **Make gain memory characterise and verify itself**

   **Exactly:** a small isolated array containing thin, thick and perhaps pumped/all-thick rows; programmable wait and sense times; checkerboard/walking-bit/high-neighbour-activity patterns; row lifetime profiling; raw failure maps; and compiler schedules generated from the measured table. Demonstrate one schedule just inside and one just outside the certified contract.

   **Why:** “silicon measures its physical contract, the compiler consumes it, and an independent checker certifies the binary” is a much stronger novelty story than merely claiming denser memory.

   **Prior art:** RAIDR, AVATAR, Flikker, SoftMC/DRAM Bender, plus drum scheduling and SOAP. The combination of deliberately heterogeneous gain cells, compiler-derived lifetimes and proof-carrying schedules appears much less precedented.

   **Cost/risk:** high: periphery, sensing and the error model are unfinished. Keep it off the functional critical path.

   **First step:** replace the one-directional decay abstraction with an adversarial model containing every observed 0→1 and 1→0 failure mode; then select a code with a quantified residual-undetected-error probability.

5. **Self-tuning receiver and eye monitor**

   **Exactly:** sweep the four phases/fine taps, score Manchester/preamble/CRC hypotheses in the matcher, and select the best sampling phase. The crisp target is to make the existing PAL-clock 10BASE-T receiver pass ±4–5 ns jitter, where it currently fails.

   **Why:** it converts a recorded weakness into a silicon-only capability and connects TDC calibration to a useful receiver.

   **Cost/risk:** moderate; CDC, bubbles and metastability must be modelled honestly.

   **First step:** add phase search to the existing continuous-time Ethernet jitter harness and preregister the success boundary.

6. **Speculative: an age-selective forensic recorder**

   **Exactly:** write events into rows with different calibrated lifetimes. After a rare matcher trigger, surviving bands provide a coarse “how long ago” indication while the TDC provides fine edge intervals.

   **Why:** it makes expiry an observable debugging primitive rather than an inconvenience.

   **Cost/risk:** high and possibly not worthwhile: stochastic retention may provide little timing information.

   **First step:** Monte Carlo the elapsed-time classification error. Cut it unless it clearly beats counters or an SRAM ring buffer.

## Verification that would convince a sceptical judge

| Piece | Strong methodology and required evidence |
|---|---|
| Expiring memory/compiler | An independent final-binary checker re-derives liveness and proves every read/refresh precedes its calibrated lower-bound deadline on every branch, with port conflicts and temperature transitions included. Exhaustively compare small cases with brute force; mutation-test lifetime off-by-ones, stale bins and refresh of expired data. Show raw silicon row distributions and inside/outside-contract runs. |
| Hand-drawn cells | Foundry DRC, full extracted LVS and PEX—not Tiny Tapeout precheck, which performs no LVS—for every orientation, abutment and edge case. Post-layout PVT, mismatch, neighbour-pattern and duty-cycle sweeps. Tape A/B process monitors. The SRAM marker being accepted by precheck is **not** evidence that arbitrary relaxed-rule cells are foundry-qualified; obtain explicit approval or keep them as isolated coupons. |
| Charge pump/level shifters | Automatic terminal-stress checking through start-up, brownout, stalled clocks, unloaded output, row switching and shorts; PEX Monte Carlo under realistic load. Resolve the currently open thin-oxide flying-capacitor reliability question with IHP. Provide pump-ready interlocks, disable/bypass, a monitor comparator and raw test access. |
| Four-phase output/TDC | Formal phase ownership and lane-conflict properties; generated-clock STA, min-pulse checks, SDF and transistor/PEX analysis of XOR reconvergence runt pulses. Internal output-to-TDC loopback plus external pad loopback; publish monotonicity, DNL/INL, jitter and PVT shmoos. Retain a plain-clock mode. |
| Agent programmes | Agents only propose; an independent checker, cycle-exact simulator, decoder and physical-device test decide. Preserve all failed attempts and counterexamples. |
| `hwfuzz` | Judge it by mutation score and restored historical bugs, separated by defect class, rather than raw coverage. Run multi-seed campaigns, report discovery-time distributions, investigate survivors, and replay minimised cases on FPGA/silicon. RFUZZ is prior art for mux coverage; context-gated comparison coverage may be novel, but the current three-seed trends are not yet persuasive evidence. |

## What to cut, and the SRAM answer

The weakest point is convergence: there is no integrated top-level, attached programme memory or FPGA system, while gain-cell periphery, pump, TDC and general PE are all first-time integrations.

Use the SRAM safety net. A 256×16 macro exactly holds four 64-word sequencer programmes and is about 28,000 µm² from the repository’s macro figure. At this bank size the gain-cell advantage is only about 1.4× after periphery and check bits; that is not worth risking the whole chip. Use SRAM for code, calibration and recovery, and offer an experimental “no-SRAM mode” for the gain-cell demonstration.

Keep one custom flagship—the calibrated output/TDC debugger. Demote the pump, distributed thin-row storage, SRAM rule-breaking and general PE to test structures unless they clear early gates. Treat PAL-over-Ethernet, 480-Mbit USB and FM as optional demonstrations, not tapeout acceptance criteria.

## Testing the agents-plus-simulators thesis

The broad thesis breaks at incomplete oracles, analogue PVT/metastability, undocumented pads, sparse search rewards and examples leaked into model context. A cycle-exact simulator proves behaviour of its model, not silicon. Historical demoscenes accumulated undocumented knowledge over years; agents do not conjure observations they have never been given.

Test the narrower, defensible claim: **agents make expert scheduling repeatable when hazards are enumerable and an independent executable judge exists.**

Freeze the ISA, simulator and verifier, then use eight unseen tasks such as JTAG, SWD, PS/2, 1-Wire, CAN arbitration/bit stuffing, difficult I²C, a timed glitch search and a matcher-triggered response. Run the same fixed agent/model under two randomised arms: simulator+verifier versus compiler errors only, five fresh sessions per task and arm. Predeclare the primary endpoint as independently accepted output without human code edits, with a practically meaningful target such as a 30-percentage-point improvement. Record success rate, time, attempts, human interventions, code length and worst timing/expiry margin; judge with hidden decoders and replay on FPGA.

That result—not one curated miracle programme—would make the demoscene claim credible.
