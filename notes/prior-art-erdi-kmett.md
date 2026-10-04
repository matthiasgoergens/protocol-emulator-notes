# Two people's public work, surveyed for the protocol-emulator chip project

Written 2026-10-04 (SGT). Reading only: `gh api`, `curl`, web fetches; nothing cloned into a git repository, nothing built. Raw downloads (blog text, repo files, API dumps) are under `emulator-notes-drafts/raw/` next to this note.

Labels: **[P]** primary (I read the repository file, post or paper myself), **[P-skim]** primary but only the opening or the relevant part read, **[S]** secondary (a search-engine snippet, a summary fetched through a model, or memory), **[U]** unverified or contradicted.

Contents: 0 method and limits; 1 Gergo Erdi (repositories, blog, book, talks); 2 Edward Kmett (background, repositories, writing and talks, IRC and social media, idea-to-project mapping); 3 ranked list; 4 open questions.

---

## 0. Method and limits

* Repository lists, licences and last-push dates come from `gh api users/<name>/repos` **[P]**. A blank licence means GitHub found no licence file, which in law means "all rights reserved" until the author says otherwise. `NOASSERTION` means a licence file exists but GitHub could not match it to an SPDX template; for Kmett's repositories I opened the files and they are BSD-style text (details in 2.2). `pushed_at` is unreliable for forks (it records the upstream push).
* Gergo's blog is `unsafeperform.io` (the old `gergo.erdi.hu` address redirects). There is no archive page; `/archive/` and `/blog/atom.xml` return 404 or 403. I took the post list from the `/blog/` index page (every post 2005 to 2024-08-12, 225 links; the newest post is "Formatting serial streams in hardware", 2024-08-12) and fetched every post from 2010 onwards as text (`raw/posts/`). The 2005 to 2009 posts are mostly Hungarian personal posts and were skipped. No post later than 2024-08-12 exists on the index as of today.
* Kmett's blog is `comonad.com/reader/` (year archives crawled by title). **IRC**: the only public archive I could reach is `tirclogv.tomsmeding.com` (replacement for ircbrowse), which holds `#haskell` only (Libera, Freenode and old Freenode), has no search function (a `?q=` parameter is ignored), and spans about 19,000 pages for Libera alone. I did not scrape it: that is tens of thousands of requests to a volunteer's server for a speculative return. `##hardware`, `#clash-lang`, `##fpga`, `#ghc` and `#haskell-lens` are not archived there. So **no IRC evidence was found** (absence of access, not evidence of absence). Kmett's own READMEs say he can be reached on `#haskell` on Freenode (older repositories) and `##thc` on Libera (current) **[P]**.
* X/Twitter and the conference sites (confengine) block unauthenticated fetches (403 / JavaScript wall). His Bluesky account `kmett.ai` is public but has two posts only. Hacker News comments by `edwardkmett` were searched through the public Algolia API for: systolic, FPGA, Groq, static scheduling, deterministic, dataflow, Clash, Verilog, Bluespec, TPU, memory bandwidth, SRAM, HBM, propagator, hardware. Only the propagator and dataflow hits are relevant (see 2.5).

---

## 1. Gergo Erdi

### 1.1 Repositories (all `github.com/gergoerdi/<name>`)

Everything here is Clash (Haskell to Verilog/VHDL) unless stated. Licence = SPDX from the API.

| Repository | What it is | Licence | Last push | What we could use |
|---|---|---|---|---|
| `clash-flappysquare` (branches `master`, `ulx3s`, `ulx3s-hdmi`, `clash-1.9`, `lambda-days-2025`) | Flappy Bird as a Clash circuit, many boards incl. ULX3S | MIT | 2025-06-11 | **ULX3S HDMI**: see 1.2 **[P]** |
| `retroclash-lib` | Library behind the book: VGA timing, video helpers, I2C master, PS/2, serial Rx/Tx, memory-map DSL, `DSignal` delay helpers, CPU-as-writer-monad helper | MIT | 2026-06-08 | Timing tables and test oracles for our video, I2C, PS/2 and UART (1.3) **[P]** |
| `clash-intel8080` | 8080 core: pure software model, Mealy-machine "sim", and synthesisable microcoded CPU; test suite | MIT | 2026-06-08 | Test structure and microcode compression (1.4) **[P]** |
| `clash-spaceinvaders`, `clash-pong`, `clash-chip8`, `clash-brainfuck`, `clash-calculator`, `clash-compucolor2`, `clash-tinybasic` | The book's machines. Each has pure "very high-level", logic-board and Verilator simulations | MIT except `clash-chip8`, `clash-brainfuck` (no licence) | 2021 to 2026 | Racing-the-beam video generators (Space Invaders `Video.hs`, Compucolor II), cycle-count accuracy chapter. Idea source only; ask before copying the unlicensed ones |
| `retroclash-sim` | High-level SDL simulators for the book | MIT | 2025-03-16 | Frame-level oracle idea: interpret the VGA signal pins, not the framebuffer (1.2, 1.4) **[P-skim]** |
| `clashilator` (+ `clashilator-example`) | Cabal `Setup.hs` that generates Verilator C++ and Haskell FFI glue from a Clash `.manifest` | MIT | 2025-12-22 | Pattern: generate the co-simulation harness from the top-level port list. In OCaml the equivalent is a Hardcaml interface to Verilator generator **[P]** |
| `clash-bounce-bench` | Benchmark: Clash simulator 12.8 s versus Verilator 0.125 s for 4.19 M cycles (10 frames at 640x480) | none | 2021-07-10 | Evidence for a "Verilator for frame-level runs, cycle simulator for unit tests" split **[P]** |
| `clash-shake` | Shake rules from Clash to bitfile (Vivado, Quartus, SymbiFlow/F4PGA) | MIT | 2026-06-08 | Build-orchestration reference only (we already use the open ECP5 flow) **[P-skim]** |
| `clash-sudoku` (+ `clash-format`) | Sudoku solver circuit over serial; Haskell Symposium 2025 functional pearl. The `test/Sudoku/Pure/Step*.hs` files keep every refinement step from pure software to hardware-shaped code | MIT | 2026-07-08 | Stepwise refinement kept as executable models; stream formatter on `clash-protocols` (1.5) **[P-skim]** |
| `advent-of-clash-2025` | Advent of Code solutions as FPGA designs over a 115200-baud serial link; each has a `-soft` (unbounded software) and `-sim` (circuit) executable | GPL-3.0 | 2026-01-13 | Pattern only (software reference versus circuit, same input). GPL, so no code **[P-skim]** |
| `ULX3S-Blinky` | Fork of DoctorWkt's ULX3S blinky: yosys, trellis, nextpnr-ecp5, `ujprog`, Verilator testbench, 45F constraints | GPL-3.0 | 2025-04-05 (fork) | Tooling checklist for the ULX3S flow; the notes say nextpnr/yosys from December 2018 were needed. No code (GPL) **[P]** |
| `scottcheck` | SBV-based symbolic execution of Scott Adams adventure games | MIT | 2020-10-04 | Incremental bounded model checking pattern (1.5, ranked item 6) **[P]** |
| `clash-utils`, `clash-framebuffer`, `clash-draw-toy` | Older helper code | MIT / none | 2020 | Low value |
| `homelab2utils`, `homelab2-games`, `z80-utils-haskell`, `z80-assembler-haskell` (fork of `dpwright/z80`), `ratkai` | Z80 assembler embedded in Haskell, HomeLab-2 / Videoton TVC utilities and games | GPL-3.0 / none / MIT | 2023 to 2026 | Embedded-assembler-in-host-language idea, same as our compiler front end. GPL items: no code |
| `kansas-lava`, `kansas-lava-cores`, `mos6502-kansas-lava`, `eightbit-kansas-lava`, `chip8-papilio`, `enigma-kansas-lava` | Older Haskell hardware DSL work (Kansas Lava) | mostly `NOASSERTION` / GPL-2.0 | 2015 to 2019 | History only |
| `symbiflow-xc-fasm`, `symbiflow-xc-fasm2bels` (forks) | Bitstream-to-netlist back-conversion | ISC | 2021 | Possible future "bitstream versus netlist" check; not for now |
| `souffle-haskell` (fork), `liquidhaskell`, `liquid-fixpoint` (forks), `circuit-notation` (fork) | Datalog, refinement types, arrow-notation for circuits | MIT / BSD-3 | various | Context only; Liquid Haskell fits the "refinement types" item in the project backlog |

Not Clash or hardware, ignored: Agda/Idris/type-theory repos, Rust-on-AVR forks, Emacs modes, Idris2 tooling, the GHC fork.

### 1.2 Video timing, HDMI/TMDS and ULX3S specifics **[P]**

I downloaded the files from branch `ulx3s-hdmi` into `raw/flappy/`.

* **`Hardware/ULX3S/TMDS.hs`** (MIT, about 65 lines): a complete DVI/HDMI TMDS encoder as a Mealy machine. Per colour channel it takes an 8-bit pixel, the two control bits and a data-enable flag, and gives a 10-bit word. It does the transition-minimising stage (XOR or XNOR chain chosen by popcount, the `popCount > 4 || (== 4 && bit 0 == 0)` rule), then the DC-balancing stage with a signed running-disparity accumulator (`Signed 4`). The four control codes (`0b1101010100` and friends) are tabled. Output is registered. This is exactly the shape of a small Hardcaml port: one `reg_fb` for the accumulator and a handful of `popcount` and `mux` expressions.
* **Provenance warning**: the older `master` branch has `TMDS_encoder.v` copied from fpga4fun.com (`(c) fpga4fun.com & KNJN LLC 2013`, no licence text), wrapped in `llhdmi.v`. The `ulx3s-hdmi` branch replaces it with the Haskell encoder above. Port the Haskell one (MIT, attribution), not the Verilog.
* **`HDMI.hs`**: `vgaToHDMI` takes the VGA signal bundle (`vgaR`, `vgaG`, `vgaB`, `vgaHSync`, `vgaVSync`, `vgaDE`) at the pixel clock and produces four differential pairs. Blue carries `{VSync, HSync}` as its control bits, red and green carry `00`. The serialiser is a 10-bit shift register loaded every ten TMDS-clock cycles (`riseEvery 10`), which is *single-edge* shifting at 10x the pixel clock (250 MHz for 25 MHz), not DDR. A fourth lane carries the pixel clock as a constant `1` bit routed through a black-box (`clockToBit`) so the tools see a clock-derived signal. `differential` makes P and N by complementing.
* **`Top.hs` and `Top.v`**: a Verilog wrapper provides the PLL; `clock.v` instantiates the ECP5 `EHXPLLL` primitive (25 MHz in, 125 MHz feedback, 250 MHz and 25 MHz out), a three-bit power-on reset counter, and the `gpdi_dp[3:0]`/`gpdi_dn[3:0]` pins plus `wifi_gpio0` tied high ("keeps the board from rebooting") for a ULX3S v2.0 pin file `ulx3s_v20_segpdi.lpf`. These are reusable facts for our FPGA bring-up (PLL parameters, the gpio0 tie, pin names) even if we write our own files.
* **Bring-up lesson** (blog 2018-09-02 **[P]**): his VGA output showed nothing until a colleague suggested blinking an LED at 1 Hz from the pixel clock; the PLL was producing 40 MHz instead of 25.175 MHz. The simulator had looked right. Worth copying as a standing check.
* **`RetroClash/VGA.hs`** **[P]**: timing as data (`VGATiming polarity front pulse back` with `SNat` sizes) for 640x480@60, 800x600@60/72 and 1024x768@60, with a state machine `Visible | FrontPorch | SyncPulse | BackPorch` per axis. Porch lengths for 640x480@60: H 16/96/48, V 11/2/31 (matches his 2018 post). He keeps `Maybe (Index w)` for the visible coordinates so blanking is a type, not a comparison. **`Video.hs`** has `center`, `scale`, `maskSides`, `withBorder` for fitting a low-resolution framebuffer to the raster. **`Delayed.hs`** carries pipeline latency in the type (`DSignal dom d a`) and `delayVGA` delays sync signals to match a pixel pipeline, so a latency mismatch between colour and sync becomes a type error. It is the cleanest published treatment of "sync must be delayed as much as the pixel path".
* For PAL/NTSC he has nothing directly. Gergo's 2018 VGA post says outright that TV signals are "more complicated". The HomeLab-2 posts (1.3) are the closest to racing the beam.

### 1.3 Blog posts relevant to the project (`unsafeperform.io/blog/<slug>/`)

Ordered by relevance to us, then date. **[P]** = read the text I fetched; **[P-skim]** = read the opening only.

| Date and title | One-line takeaway | What we could use |
|---|---|---|
| 2018-09-02 CλaSH video: VGA signal generator **[P]** | Whole generator is two counters plus pure functions of the counts; also bundles `startLine` and `startFrame` pulses. The 1 Hz LED-from-pixel-clock trick found a wrong PLL setting | Oracle for our raster counters; the bring-up check |
| 2023-10-18 So... HomeLab-2? What is that? **[P-skim]** | The CPU itself generates video: ZX80-style, the CPU "jumps" into video RAM so the program counter is the fastest raster counter, supporting logic feeds it NOPs (`0x3F`) and a changed byte (`0xFF` = RST 38) marks end-of-line; 80% of the 4 MHz CPU time goes on video. MAME's model of this was a "quick hack" that broke timing and made cassette IO impossible | Prior art to cite for racing the beam in software, and a warning that emulators' timing models are untrustworthy oracles. Also: cassette audio is 10 microsecond pulses timed by the CPU, so video must be switched off while loading (the same resource conflict our sequencer schedules around) |
| 2023-10-21 Getting my HomeLab-2 sea legs, 2023-10-24/27, 2023-10-30 Shocking Finale **[P-skim]** | Z80 assembler embedded in Haskell; a no-frills desktop bytecode interpreter replays an input transcript file to regression-test a game before real hardware; 10-bit maximal LFSR gives a full-screen random wipe over 40x25 cells | Transcript-replay testing; LFSR screen wipe is a cheap demo effect that needs no memory |
| 2020-09-15 A "very typed" container for representing microcode **[P-skim]** | Microcode steps carry a read-address preamble and a write-address postamble; with single-port RAM a write in one step's postamble conflicts with a read in the next step's preamble. He makes this a compile-time error with a type family `Combine` that has *no* clause for `(Just post, Just pre)` | Our compiler/verifier should reject structural hazards (two accesses to one port, a refresh colliding with an access) statically. In OCaml: a checker pass with the same case table, or phantom types |
| 2022-05-02 Cheap and cheerful microcode compression **[P-skim]**; code in `clash-intel8080` `Microcode/Compress.hs` **[P]** | 256 opcodes' microcode sequences share suffixes, so store them as a suffix tree: each micro-op gets an optional "next" link (`[(a, Maybe Int)]`). Reduces ROM while fixed-latency decode stays (one lookup per micro-cycle) | Compress per-thread programme ROM for the sequencer where protocols share tails (e.g. start/stop sequences in I2C/SPI/UART). Algorithm is 58 lines; port with attribution |
| 2020-05-07 Integrating Verilator and Clash via Cabal **[P]** | Clash's own simulator needs 13 s for 10 frames; Verilator 125 ms. Pin-level interface structs generated from the manifest. 20+ FPS end-to-end versus under 1 FPS | Justifies Verilator for frame-level checks of PAL/NTSC and VGA; the generator pattern |
| 2018-09-15 Very high-level simulation of a CλaSH CPU **[P]** | The CPU is just `s -> i -> (s, o)` (a `State` action); run that function directly outside the circuit simulator, wired to SDL and files, with exactly the same code that gets synthesised | Same idea as our executable spec, but note he runs the *synthesised* function, not a separate spec. A cheap third rung between spec and RTL simulation |
| 2018-09-08 PS/2 keyboard interface in CλaSH **[P]** | Sample data on the falling edge of the peripheral-generated clock, 8-cycle debounce, 11-bit frames (start, 8 data, parity, stop); `WriterT (Last Word8) (State PS2State)` becomes a Mealy machine | Reference behaviour and a debouncer length for our PS/2 bit-banging; an independent oracle (it is his decode, we generate the waveform) |
| 2018-09-23 and 2018-09-30 CPU modelling in CλaSH; composable CPU descriptions **[P]** | A CPU written as a monolithic state function turns to spaghetti; he moves to a `State` monad with lenses and a "Last-writer-wins" output record (the `mealyCPU`/`.:=` helpers now in `retroclash-lib` `CPU.hs`) | Compare with how our sequencer's per-slot outputs are assembled; the default-output-plus-edits idiom avoids forgotten defaults (latches) |
| 2020-08-01 Solving text adventure games via symbolic execution **[P]** | Same interpreter run concretely and symbolically with SBV; `loopState` pushes one symbolic input per step, adds the new constraint, calls `checkSat`, pops on `Unsat`, so depth grows until a winning state is found; reported two SBV bugs (invalid SMT-LIB output, symbolic arrays) | See ranked item 6 |
| 2024-08-12 Formatting serial streams in hardware **[P]** | Stream transformers over `clash-protocols` `Circuit (Df a) (Df b)`; the `expander` helper lets you write a plain `s -> i -> (s, o, Bool)` function and get backpressure handling for free; state is built from `Either`, `Index`, tuples so counter widths stay minimal | Handshake-correct streaming without hand-written ready/valid logic; relevant to our UART/serial test harness output |
| 2020-11-17 A tiny computer for Tiny BASIC **[P-skim]** | An 8080 + ROM + RAM + ACIA in about ten lines using a memory-map DSL (`mask 0x0800 $ ram0 ...`) | Concise memory-map style, for our demo wrappers |
| 2022-07-02 Small benchmark for functional languages targeting web browsers; 2021-09-18 Rust on the MOS 6502; 2017-05-12 Rust on AVR **[P-skim]** | Compiler-targeting experiments on 6502/AVR; code size and speed measurement habits | Low; useful only for the habit of publishing the benchmark with the post |
| 2015-03-02 Initial version of my Commodore PET; 2013-01-19 A Brainfuck CPU in FPGA; 2010-09 From register machines to Brainfuck **[P-skim]** | Early retro CPU builds in Kansas Lava and Clash | History |
| 2012-12-01 Static analysis with Applicatives **[P-skim]** | A computation built from an applicative can be inspected (which market data does it need?) before it runs; the dependency set is known without executing | Same shape as "which memory cells expire when" being known before simulation; a reading for the compiler's dependence analysis |
| 2010-02 The B Method for Programmers (parts 1 and 2); 2010-10 The case for compositional type checking **[P-skim]** | Proof-carrying imperative programmes (Atelier B); compositional versus linear type inference | Background for the "refine, then prove" story; not actionable |

Remaining posts on the index (2005 to 2024) are Hungarian-language personal posts, travel, Agda/Idris type theory and Haskell-library notes; none is relevant to the chip.

### 1.4 Testing and verification approaches (what he actually does) **[P]**

From `clash-intel8080/test/*.hs`, `Sim.hs`, `README.md`:

1. Three implementations of one CPU: a pure software `Model.hs` (`runSoftCPU`), the Mealy-machine `Sim.hs` that wraps the *synthesised* `cpu` function, and the synthesised circuit.
2. Both software layers run the classic 8080 exerciser images (`TST8080.COM`, `8080PRE.COM`; `CPUTEST.COM` and `8080EXM.COM` are present but commented out, likely for run time) under `tasty-golden`, comparing the printed output with a stored `.out` file. There is no cycle-by-cycle lockstep against another emulator; the oracle is the images' own self-checking output.
3. `test-sim.hs` perturbs the environment: it draws a random "memory ready" access pattern with QuickCheck (`arbitrary `suchThat` or`) and cycles it through a `Supply`, so memory reads and IO stall at random times while the CPU must still produce the identical golden output. That is a latency-insensitivity test.
4. The `world` function models memory, IO ports and the interrupt controller as a monad stack around the CPU, with `MaybeT` for "device not ready".
5. Book chapters on "Memory contention", "Access contention" and "Cycle-count accuracy" (Compucolor II) exist; the book is paid (Leanpub/Lulu), so cite only.

The only lockstep-like idea we lack is (3): stall injection on our sequencer's memory/pin inputs.

### 1.5 Papers, talks, book

* *Retrocomputing with Clash* (book; table of contents read from `unsafeperform.io/retroclash/toc.html` **[P]**). Chapters worth citing: video output using VGA, generative graphics, asynchronous serial, memory maps and access contention, microcoded 8080, Space Invaders video, Compucolor II cycle-count accuracy. Book text is not open; the code repositories are MIT.
* *A Clash Course in Solving Sudoku* (functional pearl, Haskell Symposium 2025, DOI 10.1145/3759164.3759345; paper licensed CC BY-NC-SA 4.0 **[P-skim]**: abstract, introduction and section headings). Shows a Haskell-first flow: pure software solver, then adapting it step by step to finite hardware. Useful as a citation for the refine-by-executable-steps methodology we already use.
* *ScottCheck: An Adventure in Symbolic Execution* (extended abstract, IFL 2020; talk video **[S]**).
* *Executable, Synthesizable, Human Readable: Pick Three* (Haskell Love 2021), *Clash: Haskell for FPGA Design: it's easy as 1-2-3...419,200* (Lambda Days 2025, Flappy Square). Listed on `unsafeperform.io/talks/` **[P]**; I did not watch the videos.

---

## 2. Edward Kmett

### 2.1 Background that matters to us

* He was Head of Software Engineering at **Groq** (a statically scheduled, deterministic inference chip) and is now Founder and Chief Scientist of **Positron AI** (founded 2023). [S: Serokell interview header 2022-08-23; moderncto podcast; EE News Europe 2025-02-12 gives "Chief Scientific Officer" and the first server using eight Altera Agilex 7 FPGAs with HBM2e, 93% memory-bandwidth utilisation claimed, a second-generation multicore ASIC planned for 2026.] His own Bluesky (`kmett.ai`, 2025-07-28 **[P]**) says: "inference needs better memory capacity, memory bandwidth utilization, more power efficiency, and an architecture built bottom up with transformers in mind", and announces Positron's USD 51.6M Series A. The Haskell Foundation podcast #87 (dated 2026-10-02 **[S]**) describes his current work as "Haskell, C++, and FPGAs". I could not obtain the transcript, so I do not know what he says there about systolic arrays or static scheduling; the audio is the lead to follow (https://haskell.foundation/podcast/87/).
* **Groq statements, moderncto.io podcast #404 (2021-11-08), via a model summary of the page [S]**, near-verbatim: "Every operation is deterministic. It takes exactly the same amount of time every time you run it."; all on-chip memory is SRAM; "We can do things like predict exactly how much power your model will take"; "One gigantic SIMD unit. You have the matrix multiply units on either side of the chip."; "Being able to control that variance, because we can lock it down to zero, is pretty key."; "They're reasonably heavily invested in Haskell as a technology stack, and I guess I'm the Haskell guy."; and that Jonathan Ross "designed the initial version of [TPUs] in his 20% time at Google, in a dialect of Haskell, no less, in Lava." **[U]** on the last claim: other search results say the first TPU was written in Bluespec; I could not resolve which. Verify before quoting. In the same interview he is reported as saying Groq's chips beat FPGAs in many spaces but not dedicated ASICs.
* The Groq compiler papers are not by him but are the right citation for "compiler-scheduled determinism": "The Virtuous Cycles of Determinism: Programming Groq's Tensor Streaming Processor" (ACM, DOI 10.1145/3490422.3510453) **[S]**, which is described as using static scheduling so the cycle count is known at compile time regardless of data.
* The user told us Kmett is where the systolic-array idea came from. I found **no public statement by him about systolic arrays**: not in his blog, repositories, HN comments, Bluesky, or any interview text I could fetch. If a talk or stream says it, it is in material I could not read (video, X). **[U]**

### 2.2 Repositories (`github.com/ekmett/<name>`)

Licence column: `NOASSERTION` entries are single-file BSD-style licences (3-clause unless noted); I opened each licence file **[P]**.

| Repository | What | Licence | Last push | Relevance |
|---|---|---|---|---|
| `propagators` | "The Art of the Propagator": monotone propagators over join-semilattice cells; observable sharing to convert direct style into propagator style | BSD-style | 2024-04-01 | Scheduling by constraint propagation (2.4) |
| `guanxi` | Relational programming in Haskell, "mostly developed on twitch"; talk "Guanxi, Logic Programming a la Carte" (YOW Lambda Jam 2019); Datalog, SAT, FRP and CSP as propagation | Apache-2.0 **or** BSD-2-Clause | 2026-01-20 | Design reference for a scheduler or verifier built on propagation |
| `ersatz` | Monad for generating CNF/QBF problems with *observable sharing*: write a circuit as an ordinary function (`full_adder a b cin = ...`), get CNF out, send to an external SAT solver, read the answer back into Haskell types | BSD-style | 2025-06-17 | Bit-level combinational equivalence and bounded checks of generated schedules; contrast with the older `satchmo` monadic style in his README **[P]** |
| `ad` | Forward/reverse-mode automatic differentiation (continuing Pearlmutter and Siskind's work) | BSD-style | 2026-09-20 | Calibration and parameter search (2.4) |
| `intervals`, `approximate`, `compensated`, `rounded` | Interval arithmetic, approximate numbers, compensated floating point, MPFR bindings | BSD-2 / BSD-3 | 2024 to 2026 | Interval bounds for gain-cell retention |
| `machines` | Networks of composable stream transducers | BSD-style | 2025-03-03 | Model of the systolic dataflow in an executable spec |
| `structs`, `unpacked-containers`, `unboxed`, `transients`, `succinct`, `discrimination`, `lca` (online LCA), `hyperloglog`, `intern` (hash consing) | Low-level data-structure work: strict mutable structs (`SEGFAULT` if misused), succinct rank/select, linear-time discrimination sorting, hash consing | BSD-style | 2015 to 2026 | Compiler internals (hash-consed IR nodes; discrimination for grouping operations by key) |
| `bound` | Locally nameless / generalised de Bruijn terms, monads as substitution | BSD-style | 2026-01-23 | A binder-safe IR for the compiler, if it ever grows binders |
| `linear-logic` | Intuitionistic linear logic over Linear Haskell, tracking for each type its proofs and its refutations, GHC type-family plugin | BSD-style | 2026-09-24 | Resource tracking (2.4) |
| `rules` (2014, "possibly playing with equality saturation"), `speculation`, `tasks`, `concurrent`, `models` | Experiments | BSD-2 / BSD-style | 2014 to 2018 | Equality-saturation peephole rewriting predates `egg` (2021) |
| `thc` ("Turbo Haskell Compiler", Truffle/Graal), `cadenza`, `coda`, `hide`, `jitplusplus` | Language and tooling experiments; `thc` licence Apache-2.0 plus UPL; blog says "Writing and code (c) Edward Kmett" | mixed | 2026-10 | Not hardware; `thc` takes GHC Core and gives Graal something to specialise: staging by partial evaluation |
| `rts` ("spmd-on-simd stuff") | Placeholder README; code experiment, 2017 | BSD-2 | 2017-08-05 | Possible SIMD-lane scheduling ideas; I did not read the code **[U]** |
| `lens`, `free`, `kan-extensions`, `comonad`, `profunctors`, `semigroupoids`, others | The ecosystem libraries | BSD-style | live | Category-theoretic vocabulary only |

### 2.3 Writing and talks

Blog `comonad.com/reader/` (read titles for 2012 to 2023; fetched the posts below):

* **Parallel and Incremental CRCs (2013)** **[P-skim]**: CRC-32 is long division in GF(2^32), so it is a monoid once you work out how to *combine* two partial CRCs: `crc(r, ab) = crc(crc(r, a), b)` gives the left fold, and the parallel version multiplies the first half's remainder by `x^(8*len b)` (computed by peasant exponentiation in GF(2^32)) and adds (xors) the second half's. He says he has "never seen this algorithm before applied to CRCs" in the post. Cites Ross Williams's *A Painless Guide to CRC Error Detection Algorithms* and *Reversing CRC, Theory and Practice*. **Directly relevant to our CRC-in-GF(2) systolic mode.** (This is the same identity as zlib's `crc32_combine`, so we can cross-check against that too.)
* **Cellular Automata, parts I to III (2013 to 2015)** **[P-skim]**: comonads (Store, zippers) for stencil evaluation; the shape is that of a systolic wavefront.
* **Revisiting Matrix Multiplication parts I to VI (2013 to 2014)** **[P-skim]**: bit shuffling with lenses and isomorphisms, Z-order (Morton) layouts, most-significant-difference comparison of interleaved keys without interleaving; cache-oblivious layout. Relevant to tiling matrices over a systolic array and to address generation.
* **Cache-Oblivious Data Structures, part I: deamortised ST (2013)**, **Fast Circular Substitution (2014)**, **Fibonacci / Leonardo random-access lists (2015)**, **On-line Lowest Common Ancestor (2015)**, **Unlifted Structures (2015)**: data-structure and compiler-performance notes **[P-skim only for the first two; the rest are titles]**.
* **Turbo Haskell (2026-09-30)** **[P-skim]**: THC, with SIMD via GHC primops and the JVM Vector API; no hardware content.

Talks (YouTube, titles and years confirmed through search listings **[S]**; I did not watch them):

* **Propagators**: Lambda Jam 2016 (https://www.youtube.com/watch?v=acZkF6Q2XKs), YOW West 2016 parts 1 and 2 (https://www.youtube.com/watch?v=tETbivwzXBM, https://www.youtube.com/watch?v=0igYOKcIWUs), and the "hard mode" Boston Haskell version (https://www.youtube.com/watch?v=DyPzPeOPgUE). A community resource list (gist `gwils/edb26e4b975c2438189f6414cdeb33b0`, 2017-06-20 **[P]**) says these are the most current statement of his ideas and, importantly, **that Datalog rules are propagators and tables are cells, and that the scheduling algorithm to steal is semi-naive Datalog evaluation over a maintained topological order, with stratified negation allowing non-monotone writes that do not sit on cycles.**
* Guanxi, Logic Programming a la Carte (YOW Lambda Jam 2019; Functional Conf 2019 video https://www.youtube.com/watch?v=35xgRnWsUsg; slides announced on X, `x.com/kmett/status/1146764473689989120`) **[S]**.
* Discrimination is Wrong (Lambda Jam 2015), Fast Purely Functional Cache-Oblivious Maps (Lambda Jam 2014), Combinators Revisited (Lambda Jam 2018), opening keynote Lambda World 2018, Transients (Lambda Jam 2017) **[S]**.
* No talk by him on systolic arrays, FPGAs or Groq turned up in any listing I found. **[U]**

### 2.4 Ideas that could inspire us

| Idea | Source and date | How it could apply |
|---|---|---|
| Deterministic, statically scheduled execution as the selling point: zero variance, exact cycle and power prediction, all-SRAM | moderncto #404, 2021-11-08 [S]; Groq ACM paper [S] | Our write-up can frame the four-thread compiler-scheduled sequencer and expiring gain-cell memory as the same philosophy at protocol scale; cite both. Also supports "the schedule is the specification" |
| Propagators as monotone functions on join-semilattices; scheduling like semi-naive Datalog | propagators README (2015 onwards) [P], gist 2017 [P], talks 2016 [S] | Compiler pass that places programmes on threads and array segments could be a propagation network: cells hold lattice values (earliest/latest slot, retention deadline), propagators tighten them to a fixpoint. Finite-height lattices (slot numbers, bounded time) guarantee termination |
| Determinism needs *monotone* propagators; termination needs a complete or finite-height lattice (his example: Heron steps on a rational interval for the square root of 2 climb the lattice forever) | HN comment 2015-10-16, https://news.ycombinator.com/item?id=10397134 [P] | Gives us a written checklist: our lattices must be finite so the scheduler is total and deterministic; also states the CALM-style reason fixpoints do not depend on evaluation order |
| Assumption tracking as SAT enumeration (time blowup instead of the ATMS's 2^n space blowup) | HN comment 2015-10-15, https://news.ycombinator.com/item?id=10390477 [P] | Backtracking search when scheduling decisions are not forced |
| Circuits as ordinary functions turned into CNF by observable sharing | `ersatz` README [P] | Our Hardcaml circuits are already ordinary OCaml values; a combinational-equivalence check (generated versus reference) via a SAT backend is the same idea. Hardcaml has a verification library for this (`hardcaml_verify`, from memory **[S]**; check) |
| Parallel/incremental CRC via the monoid structure of GF(2) division | `comonad.com/reader/2013/parallel-crc/` [P-skim] | Split a message across PEs, compute partial CRCs, combine with a multiplication by `x^n`; and use the combine identity (and zlib `crc32_combine`) as an *independent oracle* for the CRC PE |
| Z-order/Morton layouts and bit shuffling as isomorphisms | Revisiting Matrix Multiplication 2013 [P-skim] | Address generation for tiled sprites, tiles and matrices on the array |
| Stencil/cellular-automaton evaluation by comonads | Cellular Automata 2013 to 2015 [P-skim] | Executable-spec style for video sprite/tile PEs; a wavefront of local rules is what a systolic array runs |
| Linear logic over Linear Haskell with proofs and refutations | `linear-logic`, 2026-09 [P-skim] | A "must be consumed exactly once before expiry" discipline for gain-cell refresh obligations in the schedule verifier (OCaml has no linear types, so as a checker pass) |
| Interval arithmetic and compensated sums | `intervals`, `compensated` [P-skim] | Retention-time bounds as intervals; evaluate sums without rounding surprises in the DSP and GPS correlation oracles |
| Automatic differentiation | `ad` [P-skim] | Calibration: fit gain-cell decay parameters or PE coefficients by gradient from measurements; low priority for a competition entry |
| Hash consing and discrimination sorting | `intern`, `discrimination`, Lambda Jam 2015 [S] | Compiler IR: share identical sub-programmes; group slot requests by key in linear time |
| Equality saturation for rewrite-based optimisation | `rules` 2014 [P-skim] | Peephole schedule optimisation; modern analogue is `egg` |
| Strict mutable structs with half-price pointers | `structs` [P-skim] | Not for OCaml; skip |
| FFI/performance tricks: zero-copy `Text` to `TruffleString` | HN comment 2026-10-02, https://news.ycombinator.com/item?id=49937018 [P] | Not relevant to the chip |

### 2.5 IRC, social media and mirrors: what I actually found

* **IRC** (see section 0): nothing found; the reachable archive is `#haskell` only and unsearchable. Concrete way forward if wanted: ask Tom Smeding (his page says he is on Libera `#haskell`) for a full-text index, or run a targeted crawl of `https://tirclogv.tomsmeding.com/cal/haskell` for a date window. I did not do either.
* **Hacker News** (searched `author_edwardkmett`): 2015-10-15/16 propagator comments (relevant, above), and 2026-10-02/04 Turbo Haskell thread. No hardware hits for systolic, FPGA, Groq, Bluespec, Verilog or static scheduling. Raw hits in `raw/kmett/hn-*.json`.
* **Bluesky `kmett.ai`**: two posts (2024-11-15, 2025-07-28). Only the Positron fundraising post matters.
* **X/Twitter**: not fetchable. Known URLs that search turned up: `x.com/kmett/status/1867130425828573558` ("So what do we do here at Positron AI? Glad you asked!", linking something, December 2024 **[S]**; content not read), `x.com/kmett/status/1146764473689989120` (guanxi slides, 2019), `x.com/kmett/status/957359973473964033` (listed beside the propagator talks, content not read). Reading those needs a logged-in browser.
* **Not searched**: Reddit threads (API blocked), Twitch stream archives for guanxi, the Haskell Foundation podcast audio, Functional Futures podcast audio.

---

## 3. Ranked "what to take" (top 8)

Ordered by value to us per unit of effort. Effort: S under a day, M a few days.

1. **Port Gergo's TMDS encoder and serialiser structure to Hardcaml for the ULX3S (MIT, attribution to Gergo Erdi).** Files: `Hardware/ULX3S/TMDS.hs`, `HDMI.hs`, the `EHXPLLL` settings in `clock.v` (branch `ulx3s-hdmi` of `clash-flappysquare`). Next step: write `tmds_encode` in Hardcaml (about 40 lines), then property-test it against an *independent* decoder built from the DVI 1.0 spec: decode(encode(x)) = x for all 256 values, running-disparity magnitude bounded, control codes exact. Do not copy the fpga4fun Verilog (no licence). Effort S. [P]
2. **CRC combine as a verification oracle and a PE mode (Kmett, 2013 post).** Next step: re-derive (do not copy; the post's code licence is not stated) `crc(a ++ b) = shift(crc(a), len b) xor crc(b)` in GF(2); property-test our CRC PE by splitting random messages at random points and checking the combine identity, plus against `zlib` `crc32_combine`. If it holds, it also gives a legitimate way to spread one CRC across array segments. Cite the post in the write-up. Effort S. [P-skim]
3. **Cite the Groq/Kmett determinism line as prior art and positioning.** Next step: read the ACM paper ("Virtuous Cycles of Determinism", DOI 10.1145/3490422.3510453) and listen to Haskell Interlude #87 (2026-10-02) and moderncto #404; confirm the quotes before using them; add one paragraph contrasting deterministic compiler-scheduled streaming at inference scale with ours at protocol scale. Also settle the TPU/Lava/Bluespec contradiction before mentioning it. Effort S. [S]
4. **Static rejection of structural hazards in the schedule verifier (Gergo's typed microcode).** Next step: enumerate our port-conflict cases (read and write to one memory port, refresh versus access, two threads driving a pin) and write them as an exhaustive case table like his `Combine` family, with the *absence* of a clause meaning "rejected"; make the verifier fail loudly on a missing clause (his trick: no clause, no type). Optionally phantom types in the OCaml compiler. Effort M. [P-skim]
5. **Suffix-sharing compression of thread programme ROM (Gergo's microcode compression).** Next step: measure how many micro-ops our protocol programmes share as suffixes (I2C start/stop, UART frames, SPI byte loops); port `Compress.hs` (58 lines, MIT) to OCaml if the saving is real; check decode stays one lookup per cycle (his design does this via a next-link per entry). Effort M. [P]
6. **Incremental bounded model checking with push/pop (ScottCheck).** Next step: make the sequencer's executable spec a functor over a value module so the same code runs on concrete values and on SMT terms; copy `loopState` (depth 1, 2, 3, ... with `push`, `constrain`, `checkSat`, `pop`) to search for a schedule-violating input trace. Needs an SMT binding or SMT-LIB over a pipe; the project's planned formal/model-checking item. MIT licence. Effort M to L. [P]
7. **Stall injection plus golden transcripts in our test suite (clash-intel8080 `test-sim.hs`).** Next step: perturb the pin-sample and memory-ready inputs with a random pattern and require the identical transcript; keep golden outputs for the standard protocol traces. Cheap if the lockstep harness already exists. Effort S. [P]
8. **Propagator-style scheduler, only if the current scheduling pass shows strain.** Read Kmett's propagator talk and the Datalog-scheduling note in the gist; adopt the constraints (monotone propagators, finite-height lattices, stratified non-monotone writes) as a design checklist. Compare with the existing compiler before building anything; keep `guanxi` (Apache-2.0 or BSD-2) and `ersatz` as code references only. Effort L; do not start before items 1 to 7. [S]

Also cheap and worth doing alongside item 1: the bring-up check from Gergo's 2018 post (blink an LED at 1 Hz from the pixel clock to catch a wrong PLL setting) and citing the HomeLab-2 posts as prior art for CPU-generated video.

---

## 4. Open questions and things I could not establish

* Whether Kmett has said anything public on systolic arrays or Groq-style scheduling: not found. Leads: Haskell Interlude #87 audio, Twitch/YouTube guanxi streams, X threads (need a browser), Positron blog.
* IRC: needs either a search-capable archive or a targeted crawl; both skipped on purpose.
* The TPU "Lava versus Bluespec" claim is unresolved.
* I did not read the code of `rts`, `models`, `concurrent`, or the guanxi and propagators sources beyond READMEs, so "design reference" is a judgement from READMEs and talk descriptions, not from the code.
* The licence of code snippets inside Kmett's blog posts is not stated (blog footer on the 2026 post says "Writing and code (c) Edward Kmett"); treat as all rights reserved and re-derive.
* Gergo's `clash-chip8`, `clash-brainfuck`, `clash-bounce-bench`, `clash-framebuffer`, `z80-utils-haskell` have no licence file; ask him before copying.
