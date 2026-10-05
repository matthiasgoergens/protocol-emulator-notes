# Hints for our protocol-emulator entry, from Jane Street's ASIC puzzle results

Sources (fetched 2026-10-04; raw copies in `src/` and `src/w/` beside this file):

- Results post: <https://blog.janestreet.com/asic-puzzle-results/> (cited as RESULTS)
- Competition post: <https://blog.janestreet.com/protocol-emulator-asic-competition/> (cited as COMP)
- Writeups read (skimmed, not studied end to end): Soto Franco <https://www.sotofranco.dev/pdfs/asic-reverse-engineering.pdf>; Aaron Shi <https://pakkachan.github.io/asic/>; van Driel and Post <https://kjartanvandriel.github.io/asic/>; Garner (SPICE) <https://github.com/davidg351/Jane-Street-Puzzle-August-2026/blob/main/JaneStreetPuzzleWriteup_DavidGarner_FINAL.pdf>. Fetched but only sampled: Shapovalov, Ravishankar, Aravapalli, Taboada, Vargas, Wójcik, Smallwood.

Corrections (2026-10-05): `learned-from-puzzle-solvers.md` section 5 corrects six points here. Notably, our post-layout round trip covers sg13g2, not the shuttle's sg13cmos5l. The puzzle post also asked solvers not to use AI to generate their write-ups. And the sentence about Soto Franco's section 7 is his own, not Jane Street's.

Confidence note: everything under "Quotes" is verbatim from the pages above. Section 5 is my interpretation and is not Jane Street's.

## 1. What the puzzle chip was, and its style

- A hardware checker for an 11x11 Star Battle ("Two Not Touch") puzzle: 121 serial input cycles, then parallel checks ANDed into a success signal. RESULTS: "A 2-bit counter for each row and every column", "A 121-bit ROM mapping squares to regions, and a 2-bit counter for each region", "A delay line for tracking nearby squares", "A counter for the total number of stars, used to produce certain Easter egg outputs".
- Style: tiny, serial, counter-and-ROM based, no CPU; a string-output generator in ROM, scrambled by an LFSR keyed on the board checksum ("To prevent the solution from showing up as plaintext").
- Flow: "designed using the SKY130 open-source standard cell library, using the LibreLane toolchain"; each floorplan "island" is one RTL module (they left that as a hint). Cell names were deliberately left in the GDS.
- The competition flow is different: IHP 130nm CMOS5L via Tiny Tapeout, 6x4 tiles (about 24 tiles, "about 1K logic cells per tile", about 0.7 mm2), possibly 8x4; March 2027 shuttle; deadline 18 January 2027.
- Taste signals: small and legible design; deliberate puzzle structure; strings in ROM; a design whose function can be read out of the hardware.

## 2. What they featured and praised

Quotes:

- Verification habit (the loudest message): "Some of the best debugging stories came from solvers deliberately trying to break their own tools. Models that reproduced our sample waveform perfectly still contained mistakes. Comparing separate implementations and constructing inputs that should fail exposed errors that replaying the examples hadn't caught. That's a useful habit well beyond puzzles, especially when AI makes it easier to build tools faster than you can check them."
- Curiosity over answer-getting: "Several solvers kept investigating after they had already found the answer... That curiosity led to some of our favorite writeups: accounts that explained how the circuit worked, rather than stopping when it printed the right string."
- Reproducibility of the writeup: "especially to those who wrote up their process in enough detail for the next person to follow along."
- Independent oracle: Soto Franco's Python model "reproduced the supplied trace despite getting every tie-high cell wrong"; "Alejandro caught the problem by comparing the Python model against a separate Icarus Verilog simulation on additional inputs."
- Interactive visualisation: "Possibly our favorite visualization: Kjartan van Driel designed a beautiful interactive animated walkthrough". Also a side-by-side netlist and layout viewer (Stapleton), annotated layout islands (Ravishankar), a playable web version of the puzzle (Gulawani).
- Creative cross-domain demos: FPGA synthesis of the netlist with switches and LEDs (Smallwood); Minecraft command blocks (Kaniyeri); analog SPICE (Garner); Groth16 zero-knowledge proof (Wójcik).
- Different methods credited by name: own netlist extractor in C++ (Shapovalov), impulse-response diffing of flops (Shi), SAT then understanding (Aravapalli), reverse-engineering the LFSR (Taboada).
- Writeups that state their standard of evidence (Soto Franco, section 1): "Every claim below was tested against the circuit, and the two simulators built along the way are required to agree on every verdict" and "established by exhausting the solver rather than by finding one answer and stopping". Shi's note on AI use up front: "the reverse engineering, analysis and decisions are mine. I used AI to write/ check code". Garner's writeup is candid about tool choice (Cadence vs open source).
- Tooling used by entrants: KLayout, Yosys, Z3, Icarus, cocotb, Surfer-style waveform viewers; Python, Rust, C++, OCaml, Haskell, Odin.
- Scale: about 400 submissions from more than 30 countries.

## 3. Easter eggs (what they find fun)

1. The two failed attempts in `example_inputs.vcd`, as 7-bit ASCII: "THE NIGHT SKY AWAITS".
2. VCD header dated "Sat Dec 31 23:59:60 2016" (a real leap second), and a `$version` string nudging you to open a waveform viewer.
3. Morse code on an unused layer: "PER ARENAM AD ASTRA".
4. Failure messages: all zeros give "EMPTY SKY", all ones "BIG BANG", adjacent stars the "TWO NOT TOUCH" hint, else "TRY AGAIN".
5. About 1,400 isolated met2 squares forming a 57x57 pixel Jane Street logo.
6. The eleven region shapes spell "JSC".
7. A genuine layout bug (floating `a31oi` input, giving `TWO"NOT TOUCH`), caught in LVS and kept on purpose "to see who would catch it".
- Pattern: puns and Latin, themed text (stars, sky), data hidden in file metadata and unused layers, a joke that rewards close inspection, and a bug owned and turned into a game. Two of 400 found all six intended eggs.

## 4. Statements about the competition

COMP quotes:

- "We're particularly interested in projects with unique functionality, as well as those that demonstrate novel approaches to design and verification methodologies!"
- "We are excited to see the languages and verification techniques you use, including formal methods, random constrained tests, AI-assisted verification, and more."
- "As AI-assisted chip design becomes more common, we believe verification will be an extremely important aspect of the ASIC design flow going forwards."
- "Show us anything else your architecture makes possible that we haven't thought of."
- "Your chip should be reprogrammable enough to support new protocols after fabrication" and "The goal isn't to put a UART block, an SPI block, and an I2C block on one die and call it done."
- Baseline: "Start with UART, SPI, and I2C. Stretch goals include low-speed USB and 10Mbit Ethernet." Others: "JTAG, SWD, PS/2, CAN bus". Inspiration: "the PIO state machines on the RP2040 or the PRU cores on TI's Sitara parts, and consider what you'd do differently."
- Practicalities: "If you have access to an FPGA, consider using it to test your RTL before the ASIC flow." "Run synthesis early, check the mapped cell area, and leave room for clock-tree buffers and routing... A design that looks small enough after synthesis can still be difficult to route or too slow." "For instruction memory, SRAM can be more area-efficient than flip-flops." "Start by getting a UART transmitter out of a pin. Then make it programmable." "build in public"; teams recommended; "We'll pay to tape out the most novel designs".
- Description of the device: "a tiny CPU with an instruction set designed for reading pins, writing pins, counting cycles, and hitting timing precisely"; useful for "hardware debugging and reverse engineering".
- Hardcaml: "we use Hardcaml to generate the RTL for our FPGA and ASIC designs."
- RESULTS repeats the pitch: "We'll pay to fabricate our favorite designs... build an open-source, programmable chip that can handle protocols like UART, SPI and I2C, with enough flexibility to support new protocols after fabrication."
- Nothing published about judging criteria beyond "most novel" and the verification emphasis. No weights, no rubric. Do not assume one.

## 5. Recommendations for our entry (each tied to a quote)

1. Lead the write-up with the independent-oracle story. Quote: "Comparing separate implementations and constructing inputs that should fail exposed errors that replaying the examples hadn't caught." We already have executable specs, lockstep and independent oracles; show one concrete case where an oracle caught a bug that a passing example-replay missed (a mutation or seeded fault, with numbers and the raw run saved). Negative tests ("inputs that should fail") deserve their own section.
2. Say how AI was used, and how its output was checked. Quote: "especially when AI makes it easier to build tools faster than you can check them" and COMP's "AI-assisted verification". Be candid, as Shi was; tie each AI-built artefact to the check that constrains it.
3. Answer "what does the architecture make possible that nobody thought of" explicitly. Quote: "Show us anything else your architecture makes possible that we haven't thought of." A deterministic, compiler-scheduled sequencer is our difference from PIO and PRU ("consider what you'd do differently"): state the trade-off against RP2040 PIO and PRU directly, including where we lose (flexibility, interrupts, data-dependent timing).
4. Do not look like three blocks on a die. Quote: "The goal isn't to put a UART block, an SPI block, and an I2C block on one die and call it done." Demonstrate a protocol that was not designed for, loaded after the fact: pick one, ideally a stretch goal (low-speed USB or 10Mbit Ethernet; the Ethernet-to-TV demo already points that way) or JTAG/SWD (the debugging use they name).
5. Make the demos explain themselves, interactively. Quote: "Possibly our favorite visualization: Kjartan van Driel designed a beautiful interactive animated walkthrough". A browser page that steps the sequencer cycle by cycle (racing the beam, the shmoo stage) would match what they rewarded; the playable puzzle and netlist/layout viewers show they like things they can poke at.
6. Keep investigating past "it works". Quote: "accounts that explained how the circuit worked, rather than stopping when it printed the right string." Include a "why this and not the obvious alternative" account for each architectural choice, and the hypotheses we refuted (Soto Franco's section 7 records three refuted hypotheses and was called out as characterising the design).
7. State the standard of evidence up front, as Soto Franco did ("Every claim below was tested against the circuit"). A short table: claim, check, who/what independent from the implementation, whether run on RTL, gate-level netlist or silicon-flow output. "Planned formal checks" should be labelled planned; do not let them read as done. Prefer finishing at least a small formal proof (for example sequencer timing invariants) before the deadline, since COMP names formal methods first.
8. Verify the gate-level netlist, not only the RTL. The puzzle story was that a model matching the sample trace still mishandled tie-high cells. After the IHP/LibreLane flow, rerun our lockstep and fuzz suites on the post-layout netlist (cell models, tie cells, scan or reset quirks). Cheap and on-theme.
9. Respect the area warning. Quote: "A design that looks small enough after synthesis can still be difficult to route or too slow at your chosen clock frequency." Report mapped cell area, utilisation, timing slack on the real 6x4 flow early, and consider SRAM for the program store ("SRAM can be more area-efficient than flip-flops"). A systolic array is the likeliest area risk: give a measured cell count.
10. Test on an FPGA first and show it. Quote: "If you have access to an FPGA, consider using it to test your RTL". Smallwood's FPGA-with-switches-and-LEDs was featured. Our UART-out-of-a-pin-then-programmable path follows their literal advice ("Start by getting a UART transmitter out of a pin. Then make it programmable.").
11. Hardcaml is their house language. Quote: "we use Hardcaml to generate the RTL". Use Hardcaml idioms (Hardcaml waveforms, cyclesim, generated Verilog), and write a short section on what we found awkward; they will read that with interest.
12. Add Easter eggs, in their register. Ideas, mine, not from them: a Latin or space-themed message in the demo ROM, an unused-layer mark or logo in the GDS (check Tiny Tapeout rules on custom layer content first), a timestamp or metadata joke in the waveform dumps, an honestly documented bug left in as a find-the-flaw puzzle. Their own best egg was a real bug owned openly. Keep it light; it must not touch the functional design.
13. Publish in public and pace the release. They say "feel free to build in public"; the repo `matthiasgoergens/protocol-emulator-notes` already does. A visible, dated verification log gives the "followable process" they thanked solvers for.
14. Make the write-up reproducible by a stranger: exact commands, tool versions, seeds, saved logs. Quote: "in enough detail for the next person to follow along."

## 6. Gaps and cautions

- No judging rubric was published; "most novel" and verification are the only signals. Ask `asic-competition@janestreet.com` if a question matters (for example custom-layer marks, the 8x4 tile decision).
- I did not read the Shapovalov, Ravishankar, Aravapalli, Taboada, Vargas or Wójcik writeups in depth, only the summaries in RESULTS. The Google Drive links (Ebert, Kaniyeri) were not fetched.
- Their hidden-bug anecdote ("This one was originally a bug in our layout") shows they will notice real flaws; expect any reviewer to run the flow, so make sure `info.yaml`, the 6x4 setting and the template build pass cleanly before submission.
