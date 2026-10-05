# Jane Street's hardware taste, and what it means for our entry

Research note, 2026-09-25. Sources: the Jane Street tech blog (fetched directly and via
subagent survey, cross-checked against the RSS feed and `/archive/`, so the hardware-relevant
list below is believed complete); the *Signals & Threads* podcast (full transcripts, embedded
as JSON on the site); the `janestreet` GitHub org (Hardcaml and its satellite libraries, plus
the newly-public `hardcaml_agents_docs`); and public records for the competition's two authors,
Benjamin Devlin and Anish Singhani (GitHub, Semantic Scholar, CiNii/NDL, CMU's own news site).
Confidence is marked per claim: **High** (primary-source quote or verified artefact), **Medium**
(reported by a subagent from a primary source I did not re-verify myself), **Low/Speculative**
(inference). Raw fetches live under `/var/tmp/js-taste/` for spot-checking.

## (a) What they find cool

The clearest single line is from the post that immediately preceded the competition, "Can you
reverse engineer an ASIC?" (Aug 2026, by Devlin and Singhani): *"staring at a sea of gates,
timing reports, or waveforms and slowly teasing out what's really going on. These problems are
hard in a way that's deeply satisfying to solve, and honestly, it's a big part of why we like
working here."* **(High.)** That is the house style: difficulty-as-pleasure, not
difficulty-as-obstacle. It shows up again in how the puzzle itself is built — hand the reader
only the GDS mask, no labels, and make the reverse-engineering the whole game. The same taste
runs through their "Can you reverse engineer our neural network?" puzzle and the annual "Advent
of FPGA"/"Advent of Hardcaml" contests: they like puzzles where the tool you build to solve the
problem is as interesting as the solution **(Medium)**.

The second theme is Hardcaml's own origin story, told by its creator Andy Ray on the *Signals &
Threads* podcast ("Programmable Hardware," episode 1, Sept 2020): *"It was frustration with the
tools that we were using to build hardware, in particular, testing stuff... Verilog does not
have a software core... over half your job is testing."* **(High, verified transcript.)** And
what he says he actually loves about the result: *"I really love it because I can write my test
benches in OCaml... I think I'm massively more productive in writing and testing hardware using
OCaml than I was in Verilog."* Later in the same episode he's dismissive of paying for
commercial EDA verification features — *"code coverage and checkerboards for simulation
coverage and automated tools for generating constrained random inputs... It's all very, very
expensive. And I still don't think it's as good as just having a decent software language in
the first place."* **(High.)** That is a strong, specific taste signal: they do not admire
verification-by-expensive-tool, they admire verification-by-good-language-design, and they have
gone and built the free equivalent (Hardcaml's built-in mux/case/register-toggle/FSM-transition
coverage, `docs/coverage.md` — see §b) rather than buy it.

A third theme, recurring across three separate podcast episodes (Programmable Hardware, "Multicast
and the Markets" with Brian Nigito, "Clock Synchronization" with Chris Perl): determinism, not
raw speed, is the actual point of custom hardware. Nigito on "mechanical sympathy": *"if any
piece of the system is so complicated that you can't rewrite it correctly and perfectly in a
weekend, it's wrong."* Perl on why he distrusts a misbehaving GPS appliance: *"The primary
currency of the sysadmin is inspectability... a proponent of things you can inspect and
debug."* **(Medium, from subagent transcript extraction.)** Distrust of black boxes and love of
inspectable, text-based artefacts is the connective tissue between "why we like Hardcaml" and
"why we designed the puzzle the way we did."

Competitions themselves are clearly part of the culture, not a one-off marketing exercise: the
2022 ZPrize cryptography competition (Jane Street won 1st in the MSM track, 2nd in NTT, with
Hardcaml, and wrote it up saying *"we believe by using Hardcaml we were able to more efficiently
and robustly come up with designs in the short competition period"*, **High**), the VDF-alliance
low-latency-multiplier competition (an internal engineer won it independently, also written up
on the blog, **High**), and the annual Advent of FPGA/Hardcaml contests all show the same
appetite for competitive, deadline-boxed hardware design as a genuinely enjoyed activity, not
just a hiring funnel.

Finally, both named competition authors have an independent, pre-Jane-Street history in
**cryptographic hardware acceleration** specifically, not hardware in general. Ben Devlin's
University of Tokyo PhD (2013, Ikeda/Asada lab) was on self-synchronous circuits, including a
completion-detection **1024-bit RSA crypt-engine with side-channel-attack analysis**
**(Medium, via CiNii/NDL/Semantic Scholar records)**; he later built an FPGA SNARK prover and
won the VDF alliance's low-latency competition, before co-authoring Jane Street's Hardcaml MSM
ZPrize paper. Anish Singhani taped out an **AES128/AES256/SHA256 crypto-accelerator ASIC** on
SkyWater 130nm as a CMU undergraduate, then founded and taught CMU's "Introduction to
Open-Source FPGA and ASIC Chip Design" course (27 students, all taped out a chip) before joining
Jane Street as an FPGA engineer **(Medium, via CMU's own news article and his GitHub, both
independently corroborating each other)**. This is a real, verifiable shared thread — not
just "hardware people" but specifically "people who like building crypto/security hardware and
teaching others to do it." If our entry has anything cryptographic, timing-side-channel, or
PUF-flavoured to show (our gain-cell memory's PUF/self-erasing behaviour, notably), it is
speaking directly to something both judges have personally built before.

## (b) How they test and verify hardware — idioms to adopt

**Expect tests, generalised to hardware.** Jane Street's blog post "Using ASCII waveforms to
test hardware designs" (Andy Ray, 2020) is their canonical hardware-testing reference: circuit
and testbench both written in Hardcaml/OCaml, simulated with the cycle-accurate `Cyclesim`, and
the output — including a full ASCII/Unicode waveform rendered by `Hardcaml_waveterm`'s
`Waveform.print` — captured verbatim inside a `[%expect]` block, so a later change that alters
timing shows up as an ordinary source diff. **(High.)** The 2023 post "The joy of expect tests"
names Hardcaml's waveform tests explicitly as an example of the pattern taken to its logical
extreme: *"many of the tests feature square plain-text waveforms."* **(High.)** The idea
generalises past waveforms too: a 2026 post on `Bonsai_term` TUI apps gives "screenshot" expect
tests for terminal output the same treatment, explicitly because *"these tests are trivial for a
coding agent to run and the output is legible for the agent too."* **(High.)**

**Step testbenches, migrating to effect-based concurrency.** `hardcaml_step_testbench` is a
monad for running several logical "threads" against one `Cyclesim`, synchronised every clock
edge — directly comparable to cocotb's coroutine testbenches, but in-process and statically
typed against the actual port record rather than crossing a VPI/FFI boundary into an external
simulator **(Medium, from ecosystem-survey agent, cross-checked against the library's own
README)**. Jane Street's own internal guidance (now public in `hardcaml_agents_docs`, see
below) says new code should default to the OCaml-5-effects successor, `hardcaml_lws`, and treats
`step_testbench` as legacy. A 2026 blog post, "Fun with Algebraic Effects," explains why:
monadic concurrency is awkward for testbenches with multiple independent synchronised threads,
and effects are natural for it, motivated explicitly by wanting *fast feedback* because *"
compiling these digital circuits into FPGAs can take on the order of hours (or closer to months
for ASICs)."* **(High.)**

**Formal verification via `hardcaml_verify`.** SAT-based combinational equivalence checking
(`Sec`, useful for "did my refactor change behaviour") and NuSMV-backed sequential model
checking against LTL/CTL properties, with counterexample traces decoded back to `Bits.t`
**(Medium, verified against the library's `.mli` files by a subagent)**. This is the one place
the September 2026 "Formal methods and the future of programming" post says formal methods
already earned their keep before Jane Street's general pivot: *"outside of some special cases
(notably, hardware synthesis), our sense has been that formal methods were just not worth the
costs for us."* **(High.)** Notably, `hardcaml_verify`'s own README is seven lines with no
worked formal-property example — a real, citable gap (see §e).

**Built-in structural coverage, for free.** Cyclesim has native mux-selector, case-arm, register
bit-toggle (both edges), and Always-DSL state-transition coverage, with a waiver mechanism for
accepted gaps, toggled via `HARDCAML_CYCLESIM_COVERAGE=1` or an expect-test helper
**(Medium, verified against `docs/coverage.md` and the coverage source files by a subagent)**.
This reads as Jane Street's homegrown answer to exactly the paid EDA feature Andy Ray dismisses
on the podcast (above) — built into the reference simulator, not bolted on.

**Multiple simulation backends behind one typed API.** `Cyclesim` (OCaml, slow, fully
introspectable) → `hardcaml_c` (compiles to a C shared library) → `hardcaml_verilator`
(fastest, loses internal-signal visibility) all expose the same port-based interface, so
testbenches are backend-agnostic **(Medium)**. Advent of FPGA's judging explicitly rewarded
entries that pushed on "unexpected implementation backends," and one 2025 winner (Frans
Skarman) used bounded model checking as the actual solving mechanism, reading the puzzle answer
off the counterexample depth **(Medium, from blog-survey agent)** — verification tooling used
offensively, not just defensively, is clearly admired.

**Publishing the AI-coding prompts, not just the library.** `hardcaml_agents_docs` is a small,
newly-public repo of Jane Street's own internal guidance for getting LLMs to write correct
Hardcaml — design-style rules, a simulation-idiom guide, and a variant-interfaces guide — and
the Hardcaml manual's own "Using AI with Hardcaml" chapter says outright: *"At Jane Street we
have found that AI models are able to parse Hardcaml, as well as being able to write testbenches
quite well when given a few hand-crafted prompts."* **(Medium, verified by a subagent reading
the files directly.)** Given the competition explicitly asks about "AI-assisted verification,"
this is close to a direct hint about what kind of methodology write-up will land well.

**Layered testing culture, generally.** Outside hardware, "Getting from tested to
battle-tested" (Dec 2025) describes Jane Street's testing stack for a low-latency message bus —
unit tests, Quickcheck, AFL-based fuzzing, and finally Antithesis (deterministic-hypervisor
whole-system fault injection) to catch what the earlier layers missed — and is candid that *"our
quickcheck and fuzz tests are limited to the confines of the artificial environments we
construct for them."* **(High.)** The candour matters as much as the stack: Jane Street's
hardware post is equally upfront about waveform-expect-test drawbacks ("we have yet to teach our
diff tools about waveforms"). Owning your tools' limits in public is itself part of the taste.

## (c) Themes to emphasise, and themes to avoid

**Emphasise:** genuine reprogrammability over fixed blocks — the competition post is blunt that
"the goal isn't to put a UART block, an SPI block, and an I2C block on one die," so our
sequencer-plus-compiler story is a direct fit **(High, primary source)**; verification as a
headline, argued in the same terms Jane Street uses for its own culture (plain-text, diffable,
honest about limits, layered); real silicon over simulation-only claims — the ZPrize and VDF
write-ups, the Advent of FPGA judging, and the competition's own prize ("test their design in
real silicon") all reward finishing the loop to hardware **(High/Medium)**; teaching-oriented
framing — given Singhani's CMU course history, a design that is approachable to newcomers (a
worked warm-up, a step-by-step README) plausibly resonates personally, not just strategically
**(Low/Speculative — inference from his biography, not a stated preference)**; and anything
cryptographic or security-adjacent in our entry (the gain cell's PUF/self-erasing behaviour is
the obvious candidate) is speaking to both authors' own research history **(Medium, per above)**.

**Avoid:** presenting verification as an expensive, tool-bought checkbox — Ray's dismissal of
"checkerboards for simulation coverage" is specific and pointed **(High)**; anything that reads
as "obviously AI-generated" without an explainable design — Advent of FPGA's rules explicitly
exclude this and demand *"you should be able to explain your design"* **(High)**; opaque
black-box components we can't verify ourselves — the Clock Synchronization episode's "crazy
pants" GPS-appliance story is a specific instance of a general distrust **(Medium)**; and
over-claiming robustness for parts that are actually unverified — our own alignment note already
flags the gain-cell memory as "our biggest verification debt," and the culture of candour above
suggests saying so plainly is the right move, not a weakness to hide.

## (d) Recommendations for the repository

1. **Add ASCII waveform expect tests for every compiled protocol programme** (UART, SPI, I2C,
   and later CAN/JTAG/SWD/PS2/Ethernet/USB), rendered the way `hardcaml_waveterm` renders them,
   so a protocol's timing is checked into the repo as a diffable artefact, not just asserted in
   prose. *Source: "Using ASCII waveforms to test hardware designs"; "The joy of expect tests."*
2. **Put ASCII waveforms of each protocol directly in the README**, the way `hardcaml`'s own
   README shows its 8-bit counter example inline. *Source: same, plus the Hardcaml README
   itself.*
3. **Migrate the sequencer's four-thread lockstep testbenches to an effects-based, `Lws`-style
   concurrent harness** rather than a hand-rolled scheduler, since this is now Jane Street's own
   stated default and matches our four-barrel-thread structure closely. *Source:
   `hardcaml_agents_docs/hardcaml_simulation_guideline.md`; "Fun with Algebraic Effects."*
4. **Write LTL/CTL formal properties for protocol framing and deadline guarantees** using
   `hardcaml_verify`'s existing NuSMV path — no new library code needed — and publish it as a
   short worked example, since `hardcaml_verify`'s own README currently has none. This directly
   answers the competition's "formal methods" ask and is a genuinely useful gap-fill for the
   Hardcaml community. *Source: `hardcaml_verify` source; tools-to-port survey.*
5. **Turn on and report Hardcaml's built-in structural coverage** (mux/case/register-toggle/FSM
   transition) for the sequencer and PE, with waivers recorded and justified rather than hidden.
   *Source: `docs/coverage.md`.*
6. **Bridge to sigrok/libsigrokdecode as an independent protocol-decoder oracle**: Hardcaml's
   `Vcd.wrap` already emits standard VCD, and libsigrok already has a native VCD input driver, so
   the pipeline (Cyclesim → VCD → `sigrok-cli -P uart,spi,...`) needs only glue, not new decoder
   code, and gives us a decoder built and maintained by a community with no connection to our own
   assumptions. *Source: tools-to-port survey (`hardcaml/src/vcd.mli`,
   `sigrokproject/libsigrok/src/input/vcd.c`).*
7. **Cross-check the Ethernet protocol assist against LiteEth** (a mature, silicon-proven,
   independently-written Migen Ethernet core) via a Verilator co-simulation harness, as a second,
   genuinely independent implementation to diff frame encode/decode against — directly
   strengthens the Ethernet stretch goal's verification story. *Source: tools-to-port survey.*
8. **Feed hwfuzz from Hardcaml's built-in coverage metric and add a differential oracle.**
   RFUZZ's whole contribution is automatically-extracted mux-toggle coverage from FIRRTL, which
   Cyclesim already computes for free; DifuzzRTL's contribution is cross-checking fuzzed traffic
   against a golden reference (their ISA simulator; ours could be sigrok or LiteEth from #6/#7).
   Verify first whether hwfuzz already reads Hardcaml's coverage before claiming the gap.
   *Source: RFUZZ (`ProfilingTransform.scala`), DifuzzRTL comparison, tools-to-port survey.*
9. **Publish our own Hardcaml AI-agent guidance**, mirroring `hardcaml_agents_docs` and the
   manual's "Using AI with Hardcaml" chapter, describing the prompts/conventions we used to get
   agents to write correct sequencer programmes and PE microcode — this answers the
   "AI-assisted verification" criterion with an artefact, not just a claim. *Source:
   `hardcaml_agents_docs`; `docs/using_ai.md`.*
10. **Build a small functional/cross-coverage library on top of Hardcaml's existing structural
    coverage** — a `Coverpoint`/`cross` combinator recording which semantic scenarios (opcode ×
    error-code × backpressure-state, etc.) were actually exercised. This is a real, named gap
    versus UVM-style coverage-driven verification, is a pure library addition (no AST changes),
    and composes naturally with hwfuzz as a stopping criterion. *Source: tools-to-port survey,
    gap analysis §8.*
11. **Export VCD from every top-level testbench**, even though we already have ASCII expect
    tests, so a reviewer can open real waveforms in Surfer or GTKWave — Hardcaml's own docs name
    both explicitly as intended VCD consumers, and it costs nothing beyond wiring `Vcd.wrap` in.
    *Source: `docs/waveforms.md`; tools-to-port survey.*
12. **Write the verification section of our submission in the register the blog itself uses**:
    plain, candid about what's still weak (we already do this for the gain cell in
    `notes/jane-street-alignment.md`), organised around "verification as a headline," and citing
    where our approach goes further along some dimension (real silicon, a novel fuzzer feedback
    signal, formal properties, an independent decoder oracle) — the exact axis Advent of FPGA's
    judges said they rewarded. *Source: "Results from the Advent of FPGA Challenge"; "The joy of
    expect tests."*

## (e) Gaps in the Hardcaml ecosystem, and what's worth porting

A parallel survey looked at what the wider open-source hardware-verification world has that
Hardcaml doesn't, both for our own entry and as a possible contribution back. Top five, ranked
by (payoff to our entry × payoff to the Hardcaml community) / effort:

1. **sigrok/libsigrokdecode via VCD** (recommendation 6 above) — both endpoints already exist
   and are documented as compatible; a few hours of glue work.
2. **A functional/cross-coverage library** on top of Hardcaml's existing structural coverage
   (recommendation 10) — pure-library addition, fills a real and named gap.
3. **A worked formal-property suite against `hardcaml_verify`'s NuSMV path** (recommendation 4)
   — no new code needed, just properties and a short write-up; the library's own README
   currently has no example at all.
4. **LiteEth as an independent cross-check reference** (recommendation 7) — a previously
   silicon-proven Ethernet core, usable via a Verilator co-simulation harness.
5. **Feeding hwfuzz from Hardcaml's already-computed coverage, plus a differential oracle**
   (recommendation 8) — likely the cheapest of the five, since the coverage metric RFUZZ had to
   build a custom FIRRTL pass for, Hardcaml already computes natively.

Named but explicitly **not** attempted before the deadline: Amaranth's embedded `Assert`/
`Assume`/`Cover` statements, which lower directly to Yosys `$assert`/`$assume`/`$cover` cells and
let the same property be checked at simulation time and formal-verification time with no
translation step. Hardcaml has nothing structurally equivalent — formal work is entirely
external, via `hardcaml_verify`'s separate NuSMV codegen. Closing this gap would be a
backend/AST-level change to Hardcaml itself, not a contest-week task, but it is worth naming in
our submission as the honest answer to "what would you build next" **(Medium, tools-to-port
survey, verified against Amaranth's `_ast.py` source)**.

All confidence labels above reflect what was actually verified: quotes marked **High** were
fetched and read directly (by me or cross-checked against a subagent's raw fetch); **Medium**
claims came from a subagent's report of a primary source I did not personally re-open; **Low/
Speculative** items are explicitly inference, not sourced fact.
