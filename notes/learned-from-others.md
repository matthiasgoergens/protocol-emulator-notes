# What we can learn from other people's public work: an adoption plan with credits

Written 2026-10-05 (SGT). Scope: everything our protocol-emulator entry can take from other
public competition entries and from adjacent public projects, with each licence checked. It
supersedes the adoption list in `notes/backlog.md` ("Learn from other public entries'
verification") as the full inventory; the backlog keeps the decisions.

Policy, unchanged from `notes/backlog.md`: ideas may be taken from anyone, with credit. Code only
under a compatible licence, with its notice kept (Apache-2.0 files keep their licence, NOTICE
entries and a record of our changes, with a per-file `SPDX-License-Identifier`; MIT, BSD and ISC
files keep their copyright and licence text). In practice we reimplement in OCaml/Hardcaml, so
almost every row below is "idea". A repository with no licence is ideas only: its code may be run
locally as a reference or oracle, never committed here.

## How to read this note

**Evidence labels** on every claim about someone else's repository:

- **[R]** I read the file myself on 2026-10-05, in a shallow clone at the commit given in
  "Sources" below.
- **[S]** From the 2026-09-25 study, which subagents wrote. I re-checked on 2026-10-05 that the
  file exists at the path given, but did not re-read its content: **unverified** in detail.
- **[L]** From an unpublished landscape summary only (subagent work, 2026-10-05); the file was not
  read: **unverified**.
- Claims in other people's READMEs (pass counts, sign-off results) are **their** claims; none was
  reproduced here.

**Licences** were checked with `gh api repos/<owner>/<repo> --jq .license.spdx_id`; the raw output
is in `notes/learned-from-others-licences.txt`. "none" means GitHub found no licence file.

**Status** is ours: **adopted** (done, with a pointer), **partly**, **not yet**, **superseded**
(we already have something stronger), or **n/a** (comparison or context only).

**Effort**: S under a day, M a few days, L a week or more. **Value**: how much it would strengthen
the entry, judged against what Jane Street says it wants (verification first, novelty, things a
reader can poke at; `notes/asic-puzzle-results-hints.md`).

### Sources (shallow clones, read-only)

Cloned 2026-10-05 into `/var/tmp/learn-from-others/` (HEAD commit and date):
TeslaCoilerOW/ttihp-protocol-emulator cdec435 (2026-09-30); kaikino/core-asic 00e5951
(2026-09-21); kdp1965/ihp-um-janestreet-prism df6d3cb (2026-10-02);
smprather/janestreet-blog-serial-protocol-emulator 58e4903 (2026-10-03);
thomasgilbert481/tt_um_loom fdaa854 (2026-09-29); mohammedbala/chipwheel 737829d (2026-10-04);
gigamonster256/protean 34df2ec (2026-09-21); elementalcollision/retrace baa863b (2026-10-02);
Kanishk234/protocol-emulator-asic 593be7f (2026-10-04); joshvern/pinscript-cmos5l-feasibility
2c7a67c (2026-10-05); WilliamZhang20/protocol-emulator-compiler fe02c61 (2026-10-03);
MarcosAsh/protocol-emulator 3333f0c (2026-10-04); 2AMLogic/sg13cmos5l-protocol-emulator 78b5ddb
(2026-10-05); Lincreased/tt-protoseq 6e6802a (2026-10-04).

Cloned 2026-09-25 into `/var/tmp/competitor-study/`: WilliamZhang20/protocol-emulator b837d90;
umerimran-10xe/protocol-emulator-asic f82fda9; TejasDasa/protocol-emulator-asic 70678ed;
dishishshawn/protocol-emulator-asic facd14f; fjpolo/ProtocolEmulatorr b312d2b;
wsb1994/Gremlin-Board 02e0e16; LeEmperor/hardcaml_protemu 4db452a; Kleven2k/silverfox-tt 5dd5392;
OliverKlug/sophos-protocol-emulator 061c400; mcranny/protocol-emulator-asic 00b048a;
TalentA99/pemu-asic c1a6920; sjrai007/gp_pae 621f432.

## 1. Inventory of adoptable items

Columns: **ID**; **source** (repository, author's GitHub handle, file); **what** it is;
**licence**; **take** (idea or code); **status** (ours); **target** in our repository;
**effort**; **value**.

### 1.1 Verification techniques

| ID | Source | What | Licence | Take | Status | Target | Effort | Value |
|---|---|---|---|---|---|---|---|---|
| V1 | MarcosAsh/protocol-emulator, `formal/*.sby` "teeth" tasks (e.g. `formal/powerup.sby`, `expect fail`) [R]; WilliamZhang20/protocol-emulator `formal/mutation_check.py` [S]; dishishshawn/protocol-emulator-asic `tools/check_formal_mutations.py` [S]; fjpolo/ProtocolEmulatorr `test_rtl/mutation/ProtocolEmulator/test_eq.sby` [S]; 2AMLogic negative fixture [S] | Mutation against formal proofs: a weakened property or planted RTL bug must make the proof fail | Apache-2.0; fjpolo none | idea | **adopted**: planted bugs for every BMC property and 28/28 planted RTL bugs in the RTL-against-spec check (`prototypes/formal/README.md`) | `prototypes/formal/` | done | high |
| V2 | MarcosAsh, `src/analyser.ml` (810 lines: intervals over phase, offset, period, cycles since edge, since data, shift count) and `src/kernel.ml` with the theorem "if the kernel accepts it, it never misses a deadline", proved by `formal/phase_step.sv` and `formal/phase_table.sby` [R] | Programme verifier by abstract interpretation; the assembler refuses firmware that can miss a deadline; a small trusted kernel re-checks the analyser's answer | Apache-2.0 | idea (different ISA) | **not yet**; `prototypes/formal/README.md` says it "has not been read yet" | new `prototypes/verifier/` over `sequencer-v2/isa2.ml` | L | very high |
| V3 | TeslaCoilerOW/ttihp-protocol-emulator, `docs/timing-certificates.md`, `tools/timing/cert/` [R] | Per-image timing certificates: a static analyser predicts the clock edge of every pad change; one generated SymbiYosys proof per segment checks it on the RTL; 132 negative controls from perturbed predictions must fail; a ledger records each image's sha256 and CI fails when an image has no certificate | Apache-2.0 | idea | **partly**: our BMC proves the deadline contracts of the compiled UART/SPI/I2C programmes; no per-image ledger, no link from a verifier's prediction to the RTL | `prototypes/verifier/cert/` (after V2) | M | high |
| V4 | TeslaCoilerOW, `formal_eq/eq_check.py`, `formal_eq/README.md`, `formal_eq/controls/c1..c9`, `docs/equivalence.md` [R]; MarcosAsh `formal/netlist_equiv/` and README ("hardened netlist equals the RTL for all time") [R] | Sequential equivalence of the hardened gate-level netlist against the RTL, in CI: Yosys builds a miter, ABC `dprove` decides it; SRAM macros are cut points whose read data is one free input shared by both sides; a self-test plants two netlist mutants (nand2 to nor2 near an output; two SRAM data pins swapped) and nine recipe controls that must come out "not equivalent"; an undecided result fails | Apache-2.0 | idea (their Python could be copied, but our flow and top differ) | **not yet**: we have RTL-against-spec (Yosys SAT, 23 clocks) and random lockstep on the netlist we extract from our own GDS | `prototypes/postlayout-roundtrip/equiv/` | M | very high |
| V5 | MarcosAsh, `demo/decode.py`, `test/traces/sigrok/*.trace`, `.github/workflows/gds.yaml` lines 113-120 [R] | sigrok's decoders judge pin traces from RTL **and from the gate-level netlist**; each trace names the lines the decoder must print and "teeth" (waveform changes the decoder must refuse); any decoder warning fails; `--rate 24` resamples as a 24 MHz logic analyser would | Apache-2.0 (script); libsigrokdecode GPL-3.0 | idea; sigrok used as an external program only | **partly**: sigrok-cli (in podman) judges S/PDIF with a planted-fault control (`prototypes/spdif/README.md`); no other protocol, no gate level | new `tools/sigrok-judge/`, traces from existing prototypes | M | high |
| V6 | TeslaCoilerOW, `docs/independent-peers.md`, `test_ext/`, `test_ext/vendor/SHA256SUMS` [R] | Tests against unmodified third-party protocol peers at the pads: alexforencich verilog-uart, verilog-i2c, cocotbext-uart, cocotbext-i2c; schang412 cocotbext-spi; nandland SPI; picosoc `spiflash.v`; Hazard3's JTAG-DTM. Vendored at pinned commits with hashes; two drivers disagreeing resolve to X and fail | Apache-2.0 (harness); peers MIT, ISC, Apache-2.0 | idea; peers as code (permissive) | **partly**: independent oracles in places (scapy for Ethernet, pynmea2 for GPS, sigrok for S/PDIF); no third-party HDL peer on the pins | new `tools/peers/`, run against `sequencer-v2` RTL | M | high |
| V7 | umerimran-10xe/protocol-emulator-asic, `formal/protoemu_arb_miter.v` (assume equal owner inputs, assert equal pin outputs; lines 68-80) [R]; thomasgilbert481/tt_um_loom `formal/iso_miter.v` [R, file exists; that it found the open-drain defect in `docs/BUGS.md` #5 is from a summary, L]; MarcosAsh `formal/isolation.sby` [R]; TeslaCoilerOW unbounded two-copy proof per engine [R] | Two-copy non-interference miter between threads | Apache-2.0 | idea | **adopted**: isolation miter, BMC plus relational induction at every depth (`prototypes/formal/` (c)). Open: the shared bank, inboxes and ports have no ownership discipline (our finding 2) | `prototypes/formal/` | S (ownership extension) | high |
| V8 | MarcosAsh, `formal/powerup.sby` (tasks `prove`, `no_reset`, `unreset`, `stale`; teeth in BMC with `expect fail`) and README [R] | Power-up determinism: two copies from any two flop states, the same SRAM words, reset at the first edge and the same pins drive the same pins | Apache-2.0 | idea | **not yet** | `prototypes/formal/` on `sequencer-v2` RTL | S-M | high (determinism is our lead theme) |
| V9 | Kanishk234/protocol-emulator-asic, `docs/design/VERIFICATION.md` "L8-XPROP" (planned in their document) [R] | Gate level: every flop and output is known (not X) within a stated number of clocks after reset, and stays known | Apache-2.0 | idea | **not yet**: our extracted-netlist simulator is two-valued | `prototypes/postlayout-roundtrip/` | S | medium |
| V10 | smprather/janestreet-blog-serial-protocol-emulator, `formal/run_formal.sh`, `formal/results/summary.txt` [R] | Every property reported as PROVED, REACHABLE or VACUOUS at its depth; vacuous is "informational, never a pass" | MIT | idea | **partly**: our BMC runs covers after the last depth; no uniform per-property summary | `prototypes/formal/run_all.sh`, `results/` | S | medium |
| V11 | TalentA99/pemu-asic, `test/formal/README.md` (column "Why it matters in silicon", line 9) [S] | Each property carries the silicon or scope symptom it rules out; "if you cannot name the consequence, the property is probably not worth proving" [S] | MIT | idea | **not yet** | `prototypes/formal/README.md` | S | medium (write-up) |
| V12 | dishishshawn, `tools/check_formal_mutations.py`, `reports/mutation-checks.json` [S] | Mutants named after the safety property they defend; machine-readable evidence per category | Apache-2.0 | idea | **partly**: our planted bugs are named by behaviour, not by property | `prototypes/formal/` | S | low-medium |
| V13 | TejasDasa/protocol-emulator-asic, `docs/formal.md` [S] | Formal properties as a specification audit: five configuration fields without a stated range, found by proof after 100 % random coverage missed them [S] | MIT | idea | **partly**: a cover found the SPI period-8 compiler bug (`prototypes/formal/README.md`, Findings 1); no systematic audit of ISA v2 field ranges | `prototypes/sequencer-v2/` ISA text | S | medium |
| V14 | WilliamZhang20/protocol-emulator, `formal/models/RM_IHPSG13_1P_1024x8_c2_bm_bist_formal.v` (lines 3-27: `anyconst` tracked address, `anyseq` read data elsewhere) [R] | Memory abstraction for formal: track one arbitrary constant address exactly, return free data for the others | Apache-2.0 | idea | **partly**: our RTL-against-spec miter already treats bank read data as free; nothing models a memory's contract (e.g. the gain-cell lifetime contract) in proof | `prototypes/formal/` memory model; gain-cell lifetime contract | M | medium |
| V15 | MarcosAsh, README "`hardcaml_hobby_boards`' `Uart.Tx`, compiled to firmware, drives the core's pin as the circuit drives its line" (`make -C formal fsm_miter`) [R]; janestreet/hardcaml_hobby_boards | Prove that our firmware equals a circuit Jane Street published, by a miter | Apache-2.0; hardcaml_hobby_boards MIT | idea; hobby_boards code may be used (MIT) | **not yet** | `prototypes/formal/` | M | high (Jane Street's own code as the reference) |
| V16 | MarcosAsh, README "Each UNSAT in the SAT proofs is checked by cake_lpr, an LRAT checker verified in HOL4"; Certifaiger witnesses [R] | Proof certificates checked by a verified checker | Apache-2.0 | idea | **not yet**: our BMC uses z3 (SMT, no LRAT); the Yosys SAT runs emit no proof | `prototypes/formal/` | L | medium |
| V17 | MarcosAsh, `test/certify/write_self_check.ml` (README: 1957 candidate invariants mined from 2000 simulated runs, induction drops what it cannot keep) [R README; file exists] | Invariant miner from simulation to make induction close | Apache-2.0 | idea | **not yet**; our README notes `sat -tempinduct` "would probably need strengthening invariants first" | `prototypes/formal/equiv/` | M | medium |
| V18 | Kanishk234, `docs/design/VERIFICATION.md` "L4: metamorphic" (loopback identity, time scaling, lane permutation, idle insertion, tap transparency; planned in their document) [R] | Metamorphic relations: tests that need no expected answer | Apache-2.0 | idea | **not yet** | `prototypes/verif-oracles/` | S-M | high (cheap and oracle-free) |
| V19 | Kanishk234, same file, "L4-IMP" (planned) [R]; wsb1994/Gremlin-Board `tests/test_random_jitter.py` [S] | Impairment sweeps: clock mismatch, jitter, sub-sample glitches, slow open-drain rise; a tolerance envelope per receiver | Apache-2.0 | idea | **partly**: S/PDIF receive margins, multiphase shmoo, video judges; no per-receiver envelope for UART/I2C/CAN | `prototypes/verif-oracles/` | M | medium |
| V20 | MarcosAsh, `test/mutate.py`, `test/mutation_allow.txt` (README: 111 of 114 valid mutants killed, the other 3 equivalent) [R README]; tt_um_loom (823 mutants) [L]; TeslaCoilerOW (93-96 % on held-out mutants) [L] | Mutation score for the whole test suite, with an allow-list of equivalent mutants | Apache-2.0 | idea | **partly**: planted bugs per suite; backlog still lists "Mutation scores for the whole suite" | `tools/mutate/` (new) | M | high |
| V21 | MarcosAsh, `test/heldout.sha256` (SHA-256 of a salted list of eight held-out protocols, committed 2026-10-02; opened in November) [R] | Sealed held-out protocols: commit to a test set before seeing it; then an agent writes each from its public specification and the verifier and a decoder judge it | Apache-2.0 | idea | **not yet** (discussed in `notes/plant-bugs.md`) | new `notes/heldout/` | S | high |
| V22 | MarcosAsh, README "AI-assisted verification" table (what AI does, the gate, the result, what counts against it) [R] | AI use reported with its gates and its failures, counted | Apache-2.0 | idea | **partly**: we run codex and other reviews; they are not counted or tabled | write-up, `docs/` | S | high (Jane Street names AI-assisted verification) |
| V23 | MarcosAsh, `pio/src/timing.mli` (static timing of RP2040 PIO programmes over every path) and README (pico-examples `pio/i2c` start hold 3.125 us against the 4.0 us I2C minimum, filed upstream as pico-examples issue 796) [R] | Run your own timing checker on the incumbent's firmware and find a real bug | Apache-2.0 | idea | **not yet** (needs V2) | `prototypes/verifier/pio/` | M | high (a demo that answers "what would you do differently from PIO") |
| V24 | smprather, `regress/mutate_macro_flow_config.sh` [R] | Mutation testing of the flow configuration's static checks (swapped VPWR/VGND on a macro, missing PDN connects, a lib file shared by two corners) | MIT | idea | **not yet** (no flow configuration yet) | `tt/` (after A) | S | medium |
| V25 | LeEmperor/hardcaml_protemu, `docs/verification.md` [S] | Failure-report contract: test name, seed, sizes, failing trial, revision with local diff, tool versions | none | idea only | **partly**: our results files carry command, commit and tool versions; hwfuzz failure output does not | `prototypes/hwfuzz/` | S | low-medium |
| V26 | wsb1994, `tests/test_verilog_isa_exhaustive.py` [S]; OliverKlug/sophos-protocol-emulator `sim/lockstep.py` [S] | Exhaustive enumeration of the instruction-field cube | Apache-2.0 | idea | **superseded**: our Yosys check covers every instruction stream for 23 clocks | n/a | n/a | n/a |
| V27 | wsb1994, `tests/test_png_sha256.py` [S] | A 152,721-byte file streamed through every TX/RX pair and checksummed | Apache-2.0 | idea | **not yet** | `prototypes/multi-proto/` | S | low-medium |
| V28 | Kleven2k/silverfox-tt `test/test.py` [S]; MarcosAsh `test.py` [S]; TeslaCoilerOW `test/` (`GATES=yes`) [R README] | Two tiers: fast Hardcaml tests below, a cocotb suite on generated RTL and on the hardened netlist above, as Tiny Tapeout's CI expects | Apache-2.0 | idea; TT template code (Apache-2.0) | **not yet** | `tt/test/` | M | very high (submission plumbing) |
| V29 | WilliamZhang20 `test/cocotb_tests/test_fuzz.py` [S]; chipwheel `fuzz.py` [L] | Random model-against-RTL fuzzers with hang watchdogs | Apache-2.0 | idea | **superseded** by hwfuzz (coverage-guided) | n/a | n/a | n/a |
| V30 | elementalcollision/retrace, `tools/l2n/` (KLayout LayoutToNetlist as a second, independent extractor), `tools/retrace/cellcheck.py` (PDK cell fingerprinting), `tools/tempo/faults.py` (six planted layout faults including a supply short and a rail cut off the grid) [R README] | Two independent extractors that must agree; layout faults each check must locate | Apache-2.0 | idea | **partly**: our own extractor with planted cuts and shorts (`prototypes/postlayout-roundtrip/`); no second extractor, no supply faults | `prototypes/postlayout-roundtrip/` | M | medium-high |
| V31 | retrace, `tools/retrace/vcdtb.py` [R README] | Turn a VCD into a self-checking testbench | Apache-2.0 | idea | **not yet** | `tt/test/` | S | low |
| V32 | joshvern/pinscript-cmos5l-feasibility, README [R] | Report typical, slow and fast corners separately ("the PDK's default violation checker selects typical timing; a green workflow alone does not prove slow/fast closure"); retain failed runs; gate tests need the PDK's `sg13cmos5l_udp.v` | Apache-2.0 | idea | **not yet** | `tt/` | S | medium |
| V33 | smprather, `rtl/pe_dru.v` header [R] | The test must reach the claimed rate: their first 10BASE-T receiver passed testbenches driven at half the bit rate and missed real 100 ns bits | MIT | idea (a lesson) | **partly**: our receivers are tested at line rate; no explicit check that each testbench's stimulus rate equals the claim | `prototypes/verif-oracles/` | S | medium |

### 1.2 Architecture ideas

| ID | Source | What | Licence | Take | Status | Target | Effort | Value |
|---|---|---|---|---|---|---|---|---|
| A1 | kaikino/core-asic, `src/proto_delay_chain.sv`, `src/proto_tdc.sv`, `experiments/tdc/README.md` [R] | Sub-clock timing on the real flow: a chain of `sg13cmos5l_dlygate4sd2_1` cells with `(* keep *)`, every net and instance named with one token matched by `RSZ_DONT_TOUCH_RX`, false paths in a custom SDC; measured 150/224/353 ps per stage (fast/typ/slow); 64 of 64 cells survived; self-calibration against the clock period; a ones-count TDC tolerant of bubbles | Apache-2.0 | idea; the flow settings are facts to reuse | **partly**: architecture decision D11 ("two pins, as a placed macro") and the models in `prototypes/multiphase/` and `prototypes/scope/`; no flow probe | new `prototypes/delay-line/` | M | very high (de-risks our most distinctive feature) |
| A2 | kdp1965/ihp-um-janestreet-prism, `chromas/*.v` (31 personalities), `docs/prism_interface.md` [R] | Protocols as state-machine configurations ("chromas") written as Verilog FSMs and compiled into configuration words of one programmable state machine | Apache-2.0 | idea | **n/a**: a different architecture; use as the comparator in the write-up, and its protocol list (HDLC, SpaceWire, 1-Wire, WS2812) as candidates | write-up | S | medium |
| A3 | kdp1965, README and `macros/CFGMEM_IHP16/` (latch-array configuration memory built with DFFRAM) [R] | Latch arrays instead of flops for configuration storage | Apache-2.0 (DFFRAM Apache-2.0) | idea; DFFRAM as a tool | **not yet**: listed as "the first lever" in `notes/architecture-v0.md` | `notes/architecture-v0.md`, `prototypes/unified-pe/` area probe | M | medium |
| A4 | kdp1965, `docs/prism_interface.md` section 4a (halt, single step, breakpoints conditional on a decision tree; the halting cycle gates all datapath actions so the triggering value can still be read) [R] | On-chip debugger for the protocol engine | Apache-2.0 | idea | **not yet** | `notes/architecture-v0.md`, `prototypes/sequencer-v2/` | M | medium-high (Jane Street names hardware debugging) |
| A5 | kaikino, README (32 x 32-bit trace, 16-bit timestamps, trigger and pin-change capture) [R]; kdp1965 section 4m (trace into the SRAMs) [R] | Timestamped trace buffer | Apache-2.0 | idea | **partly**: sparse edge logs into a bank around a trigger are in `notes/architecture-v0.md` (determinism table) | `notes/architecture-v0.md` | M | medium |
| A6 | thomasgilbert481/tt_um_loom, `docs/tt_cmos5l_facts.md` section 11 [R] | A working recipe for `RM_IHPSG13_1P_512x16_c2_bm_bist` through the cmos5l flow, with gds, precheck and gl_test passing (their GitHub Actions run 35377845679, their claim): flattened instance key, lib keys `*_typ_*`/`*_fast_*`/`*_slow_*` (cmos5l corners are all `nom_*`), stripes inside the macro's Metal4 power columns, `MAGIC_EXT_ABSTRACT_CELLS`, Magic DRC off because Magic lacks the SRAM exceptions | Apache-2.0 | idea; configuration facts | **not yet**: decision D4 assumes this macro for the programme store | new `prototypes/sram-macro/` | M | very high (the safety net) |
| A7 | kdp1965, README "Hardening locally" (a LibreLane plugin step `Project.ExtendPowerStripes` that draws tile stripes across each macro's pin columns) [R] | PDN for macros on cmos5l, where the vertical PDN layer is Metal4 | Apache-2.0 | idea or code | **not yet** | `prototypes/sram-macro/` | S | high (with A6) |
| A8 | kaikino, README: "The CMOS5L slim PDK ships no SRAM macro, so program memories are flop arrays" [R] | A contradiction with A6 (tt_um_loom found the cmos5l PDK symlinks the SG13G2 SRAM macros) | Apache-2.0 | n/a | **open question**: settle it by reproducing A6 at our pinned PDK | `prototypes/sram-macro/` | S | high |
| A9 | smprather, `rtl/pe_dru.v` [R] | Both clock edges at 60 MHz give a 12-sample grid on a 100 ns 10BASE-T bit; latch-pair capture because the library's flops are rising-edge only | MIT | idea | **partly**: "both clock edges first (free)" in `notes/architecture-v0.md`; our four-phase stage | `prototypes/multiphase/` | S | medium |
| A10 | kaikino (CRC-32 unit, 128-byte FIFO) [R]; kdp1965 section 4b (`prism_crc.v`, FIFO per shard) [R]; smprather `rtl/pe_crc.v` [R] | Hardware CRC and FIFO beside the engine | Apache-2.0; MIT | idea | **partly**: CRC as a GF(2) PE mode or an assist is still an open decision in `notes/architecture-v0.md` | `notes/architecture-v0.md` | n/a | context |
| A11 | TeslaCoilerOW, README (a host-free mover forwards queue words between engines) [R] | Engine-to-engine forwarding without the host | Apache-2.0 | idea | **partly**: our inter-thread mailbox and bridges | n/a | n/a | context |
| A12 | TeslaCoilerOW, README "Status" (the `diet4` 6x4 variant passes gds, precheck and gl_test in its own workflow) [R]; tile size contested between 6x4 and 8x4 across entries [R in several READMEs] | Keep a smaller fallback build green in CI while 8x4 is unsettled | Apache-2.0 | idea | **not yet** | `tt/` | S | high |
| A13 | kdp1965/tt-support-tools, branch `cmos-8x4` (an 8x4 tile template) [R README of the entry] | 8x4 template for local hardening | Apache-2.0 | idea; tool | **n/a** until the tile size is settled | `tt/` | S | medium |

### 1.3 Tooling

| ID | Source | What | Licence | Take | Status | Target | Effort | Value |
|---|---|---|---|---|---|---|---|---|
| T1 | TinyTapeout/ttihp-verilog-template (cmos5l branch), used by every serious entry | The submission harness: `info.yaml`, `docs/info.md`, the gds, precheck, gl_test and viewer workflows | Apache-2.0 | code (template) | **partly** (2026-10-05, branch adopt-tt-harness): `tt/` has `info.yaml` (6x4), config, RTL cocotb test and one workflow; no gds, precheck or viewer workflow, nothing hardened | new `tt/` | M | very high |
| T2 | TeslaCoilerOW, README ("`make check-generated`: regenerate and fail if the committed core differs", the `regen` workflow) [R] | Generated Verilog checked against the Hardcaml source in CI | Apache-2.0 | idea | **partly**: `tt/scripts/regen.sh --check` works locally; not in CI | `tt/` | S | high |
| T3 | gigamonster256/protean, `flake.nix`, `nix/*.nix` [R] | One Nix flake from Hardcaml to Verilog, cocotb, LibreLane, GDS and gate-level tests, pinning LibreLane 3.0.14, tt-support-tools and the IHP PDK | Apache-2.0 | idea or code | **not yet**: we use opam switches and the LibreLane container | `tt/` (optional) | M | medium |
| T4 | WilliamZhang20/protocol-emulator-compiler [R README] | MLIR dialects for a protocol-engine compiler (scaffolding only) | none | idea only | **n/a**: our compiler is OCaml, which suits Jane Street | n/a | n/a | low |
| T5 | MarcosAsh, `demo/paths.py` [L] | Worst setup paths reported by source line | Apache-2.0 | idea | **not yet** | `tt/` | S | low-medium |
| T6 | smprather, `tools/checks/macro_flow_config.py` [R via V24] | Static check that every macro is placed and powered before the flow runs | MIT | idea | **not yet** | `tt/` | S | medium |

### 1.4 Documentation and evidence practices

| ID | Source | What | Licence | Take | Status | Target | Effort | Value |
|---|---|---|---|---|---|---|---|---|
| D1 | Kanishk234, `docs/CLAIMS.md` (claim, evidence with check id and run, status from a fixed vocabulary: proven unbounded, proven bounded (depth N), tested, simulated only, not yet verified; blind spot) [R]; wsb1994 `docs/EXECUTIVE-SUMMARY.md` (the competition's criteria as rows) [S]; MarcosAsh README "What is proved" and "What is not proved", including the trusted base [R] | A claims-and-evidence table | Apache-2.0 | idea | **not yet** (recommended in `notes/asic-puzzle-results-hints.md` item 7) | new `docs/claims.md` | S | very high |
| D2 | 2AMLogic, `verification/records/core-datapath/records/20260930-195410-ead870a.md` (a `record-meta` JSON block: record id, supersedes, git revision, sha256 of every input) and `verification/check_records.py` [R] | Verification records pinned by content hash, with a checker | Apache-2.0 | idea; the checker could be copied | **partly**: our results files start with command, commit and tool versions; no input hashes, no checker | `tools/evidence/` | S-M | high |
| D3 | TeslaCoilerOW, `tools/evidence/README.md`, `check_consistency.py` [R] | A fail-closed documentation check in CI: statuses the git history contradicts, counts a result file contradicts, missing files or workflows; history markers exempt superseded text | Apache-2.0 | idea; code could be copied | **not yet** | `tools/evidence/` | M | high |
| D4 | TeslaCoilerOW, `docs/bug-ledger.md` (defect, method that found it, evidence, fix commit, status) [R]; tt_um_loom `docs/BUGS.md` [R]; MarcosAsh README "What the checks found" (13 bugs counted by the method that found them) [R] | A bug ledger, counted by finding method | Apache-2.0 | idea | **not yet**: findings are scattered across prototype READMEs | new `docs/bug-ledger.md` | S | high (Jane Street praised comparing implementations and breaking one's own tools) |
| D5 | TeslaCoilerOW `docs/limitations.md` [R tree]; smprather `wiki/STATUS.md` ("green in SIMULATION ... not hardware-verified") [R]; mcranny `docs/validation.md` [S] | Say what each number does not prove, next to the number | Apache-2.0; MIT | idea | **partly**: most prototype READMEs have limits sections | `docs/claims.md` | S | medium |
| D6 | TeslaCoilerOW, README "Status" table with CI run ids [R] | Status table citing runs | Apache-2.0 | idea | **not yet** (no CI) | `tt/README.md` | S | medium |
| D7 | 2AMLogic record (tool traps: `opt` after `flatten` replacing a live cone with free bits; automatic `mem2reg` turning a memory into an all-zero register file) [S] | Record tool-elaboration traps | Apache-2.0 | idea | **not yet** | `prototypes/formal/README.md` | S | medium |
| D8 | tt_um_loom `docs/DECISIONS.md` [R]; 2AMLogic `spec/decision-records/` [S]; Lincreased/tt-protoseq decision log [L] | Numbered decision records | Apache-2.0 | idea | **partly**: decisions live in `notes/architecture-v0.md` and the backlog | n/a | n/a | low |

### 1.5 Demos

| ID | Source | What | Licence | Take | Status | Target | Effort | Value |
|---|---|---|---|---|---|---|---|---|
| M1 | MarcosAsh, `pages/die/` (die viewer linking cells to source lines), the browser playground that runs the kernel on pasted firmware, a results page with each claim's last green CI run [R README, files exist]; TeslaCoilerOW 3D GDS viewer (Tiny Tapeout `viewer` job) [R] | Things a reader can poke at in a browser | Apache-2.0 | idea | **not yet**: we have a browser video gallery (`demos/tv`) | new `demos/web/` | M | high |
| M2 | MarcosAsh, README (on an FPGA, engine 1 timestamps all 52 edges of engine 0's message on the predicted cycles while the host floods the link) [R] | Self-timing demo: the chip checks its own schedule | Apache-2.0 | idea | **not yet**; needs the ULX3S | `prototypes/fpga-ulx3s/` | S-M | high |
| M3 | smprather `wiki/STATUS.md` (WS2812, servo PWM, DHT11, DMX512, MIDI) [R]; MarcosAsh README (DShot600, SENT, CEC) [R] | Protocols where "the waveform is the specification" | MIT; Apache-2.0 | idea | **not yet** | new firmware in `prototypes/sequencer-v2/` | S each | medium |
| M4 | mohammedbala/chipwheel, `incumbents/README.md`, `incumbents/run_all.py` (one RP2040-style PIO state machine from fpga_pio, SERV, QERV, FemtoRV32 on the same flow, clocks per byte and area, gate-level rerun) [R] | Benchmark against incumbents on the same synthesis flow | Apache-2.0 (harness); fpga_pio BSD-2-Clause, SERV ISC, FemtoRV BSD-3-Clause | idea; incumbents as code | **partly**: `measurements/pio-area/` synthesises fpga_pio on sg13g2; no CPU baselines, no clocks-per-byte | `measurements/pio-area/` | S-M | medium-high |
| M5 | TeslaCoilerOW `docs/overview.md` (comparison with RP2040 PIO and other public entries) [R tree only] | Compare against the field in the write-up | Apache-2.0 | idea | **not yet** | write-up | S | medium |

### 1.6 Already adopted from non-competitors (for completeness)

From `notes/prior-art-erdi-kmett.md` and the prototypes' credits: Gergo Erdi's ScottCheck
incremental BMC loop (`prototypes/formal/`, MIT, idea), his TMDS encoder shape
(`prototypes/hdmi-ulx3s/`, MIT, reimplemented), stall injection with golden transcripts and the
hazard case table (`prototypes/verif-oracles/`, MIT, ideas); Edward Kmett's public post "Parallel
and Incremental CRCs" (the CRC monoid oracle in `prototypes/verif-oracles/`, re-derived because
the post's code licence is not stated); lawrie/fpga_pio for the area comparison
(`measurements/pio-area/`, BSD-2-Clause). Not yet adopted from that note: suffix-sharing
compression of programme ROM after `clash-intel8080`'s `Microcode/Compress.hs` (MIT, M).

### 1.7 Licence caveats in one place

- **No licence, ideas only:** WilliamZhang20/protocol-emulator-compiler, fjpolo/ProtocolEmulatorr,
  LeEmperor/hardcaml_protemu, DanielMBouyou/protocol-emulator-asic. Their code may be run locally
  (outside this repository or gitignored) but never committed.
- **libsigrokdecode is GPL-3.0.** Run sigrok-cli as an external program (as `prototypes/spdif`
  does, in podman). Do not vendor or translate its decoders into this Apache-2.0 repository; an
  OCaml decoder must be written from the protocol specification, not from sigrok's Python.
- **MIT** (smprather, TejasDasa, TalentA99, janestreet/hardcaml_hobby_boards, the alexforencich
  peers): code may be copied with the copyright and licence notice.
- **Apache-2.0** (most entries, the TT template, DFFRAM, TinyQV, Hazard3, kaikino, kdp1965): code
  may be copied with the licence, the NOTICE (if any) and a statement of changes; mark files with
  `SPDX-License-Identifier: Apache-2.0`.
- **BSD/ISC** (fpga_pio, FemtoRV, picorv32 spiflash, SERV): copy with the notice.
- The Jane Street puzzle files are Jane Street's; retrace explicitly does not redistribute them,
  and neither do we.

## 2. Adopt next: the 15 most valuable not-yet-adopted items

Grouped so that each group can go to one implementation agent, in its own git worktree, with no
two groups writing the same files. Groups E and F both run LibreLane: run their place and route
one at a time and only when the host is idle (host load below 20). Group C's step 2 reads
`prototypes/formal/` as a library but writes only under `prototypes/verifier/`.

**Group A: Tiny Tapeout harness** (writes `tt/`, `.github/workflows/`)

1. **T1 + T2 + V28 + V32 + A12: the submission harness.** First step: copy the cmos5l branch of
   TinyTapeout/ttihp-verilog-template into `tt/` (Apache-2.0, keep its licence), generate
   `tt/src/` from the sequencer-v2 Hardcaml RTL with a `check-generated` target that fails on any
   difference, and harden it once locally in the LibreLane container at 6x4, recording typical,
   slow and fast setup and hold separately. Then a cocotb gl_test that replays the UART frame of
   `prototypes/sequencer-v2`. Credit: TinyTapeout template; TeslaCoilerOW (regen check, 6x4
   fallback); joshvern (per-corner reporting).

**Group B: netlist against RTL** (writes `prototypes/postlayout-roundtrip/`)

2. **V4: sequential equivalence of the hardened netlist against the RTL.** First step: on the
   retained deadline-sequencer run (`/var/tmp/postlayout-roundtrip/pnr/runs/seq15ns/`), read the
   final netlist with the PDK's liberty cells and the RTL into one Yosys miter, write AIGER, run
   ABC `dprove`; then add the self-test (nand2 to nor2 near an output; two swapped pins) and
   require "not equivalent" for both, and make "undecided" a failure. Credit: TeslaCoilerOW
   `formal_eq/`; MarcosAsh `netlist_equiv`.
3. **V30 + V9: a second extractor and X checks.** First step: run KLayout's LayoutToNetlist on the
   same GDS and compare its net partition with ours; add a supply short and a rail cut to
   `mutate.ml`'s planted faults; add a three-valued reset check (every flop known within N
   clocks). Credit: elementalcollision/retrace; Kanishk234 (L8-XPROP).

**Group C: programme verifier** (writes `prototypes/verifier/`)

4. **V2: abstract-interpretation verifier for ISA v2.** First step: read MarcosAsh's
   `src/analyser.ml` and `src/kernel.ml` in full and write a one-page design note; then an
   interval analysis over `Isa2` that bounds the slot of every pin write and every WAITD outcome,
   with a soundness check that runs `Isa2.Spec` on random programmes and fails if any observed
   time falls outside the computed interval. Credit: MarcosAsh.
5. **V3: per-image certificates.** First step: for the three compiled protocols, turn the
   verifier's predicted edge slots into BMC goals using the existing `prototypes/formal` machine
   (read-only), with perturbed predictions as negative controls, and a ledger of image hashes.
   Credit: TeslaCoilerOW.
6. **V23: run the verifier on the incumbent.** First step: a small RP2040 PIO front end for
   pico-examples' `pio/i2c` and `pio/uart_tx` (BSD-3-Clause), reproducing the start-hold finding
   before looking for new ones. Credit: MarcosAsh (method and the original finding).

**Group D: protocol oracles** (writes `tools/sigrok-judge/`, `tools/peers/`)

7. **V5: sigrok judge for every protocol, with teeth.** First step: generalise the S/PDIF bridge
   into a trace format plus a runner (sigrok-cli in podman, external, GPL-3.0 untouched) for
   UART, SPI and I2C traces from `prototypes/sequencer-v2`, each with one waveform change the
   decoder must refuse; then a `--rate` option that resamples as a 24 MHz analyser would.
   Credit: MarcosAsh `demo/decode.py`; the sigrok project.
8. **V6: third-party HDL peers.** First step: vendor alexforencich/verilog-uart and verilog-i2c
   (MIT) at pinned commits with a SHA256SUMS file, and run them against the sequencer-v2 RTL's
   pins in Icarus with X on contention as failure. Credit: TeslaCoilerOW (method); alexforencich
   (peers).

**Group E: delay line on the real flow** (writes `prototypes/delay-line/`)

9. **A1: reproduce the delay-chain probe.** First step: a 64-stage chain of
   `sg13cmos5l_dlygate4sd2_1` in Hardcaml (instantiated cells), named with one token for
   `RSZ_DONT_TOUCH_RX`, false paths in a custom SDC, hardened standalone; check that every cell
   survives and record the per-corner stage delay against kaikino's 150/224/353 ps; then the
   self-calibration arithmetic (stages per clock period). Credit: kaikino.

**Group F: SRAM macro on cmos5l** (writes `prototypes/sram-macro/`)

10. **A6 + A7 + A8: the programme store's macro through the precheck.** First step: reproduce
    tt_um_loom's section 11 recipe for `RM_IHPSG13_1P_512x16_c2_bm_bist` in a 2x2 tile at our
    pinned PDK, including the per-corner lib keys; record which of A6 and A8 holds. Credit:
    thomasgilbert481 (recipe), kdp1965 (PDN stripes over macro pins), kaikino (the counter-claim).

**Group G: evidence and write-up** (writes `docs/`, `tools/evidence/`, `notes/heldout/`)

11. **D1 + D4 + V22: claims table, bug ledger, AI-use table.** First step: `docs/claims.md` with
    one row per headline claim already in prototype READMEs (claim, evidence file, status from
    Kanishk234's vocabulary, blind spot) and `docs/bug-ledger.md` seeded from the findings
    sections (the SPI period-8 bug, the isolation counterexample, the 28 planted RTL bugs) with
    the method that found each. Credit: Kanishk234, wsb1994, MarcosAsh, TeslaCoilerOW.
12. **D2 + D3: hashed records and a consistency check.** First step: a `record-meta` header
    (git revision, sha256 of every input, command, tool versions, supersedes) written by a small
    OCaml or Python helper for `prototypes/formal/results/`, and a checker that fails when a
    cited count disagrees with its result file. Credit: 2AMLogic; TeslaCoilerOW.
13. **V21: sealed held-out protocols.** First step: choose eight protocols we have not
    implemented, commit only the SHA-256 of the salted list, keep the salt and list out of the
    repository until the reveal date. Credit: MarcosAsh.

**Group H: oracle-free tests** (writes `prototypes/verif-oracles/`)

14. **V18 + V19 + V33: metamorphic relations and tolerance envelopes.** First step: on the
    sequencer-v2 interpreter, time scaling (double every period, the waveform is exactly twice as
    long and decodes the same), thread permutation (same programme on another thread and pin
    gives the same waveform up to the mapping) and idle insertion; then a UART receiver tolerance
    envelope over baud error and glitch width. Credit: Kanishk234; wsb1994; smprather (the
    rate-reach lesson).

**Group K: formal hygiene** (writes `prototypes/formal/`)

15. **V8 + V15 + V10 + V11 + V7 ownership extension.** First step: power-up determinism on the
    sequencer-v2 RTL (two copies, arbitrary initial flops, same programme store, reset at the
    first edge, same pins give same outputs; with a no-reset control that must fail). Then a
    miter of our compiled UART against janestreet/hardcaml_hobby_boards `Uart.Tx` (MIT), a
    PROVED/REACHABLE/VACUOUS summary line per property, a "symptom on a scope" column in the
    README, and ownership of the data bank and inboxes in `props.ml`. Credit: MarcosAsh;
    smprather; TalentA99; umerimran-10xe.

Left for later, in rough order: V20 (whole-suite mutation score), M1 (web viewer and
playground; it consumes Groups B and C's output, so after them), M4 (CPU baselines), A4 (on-chip
debugger), V14 (memory abstraction for the gain-cell contract), V16 and V17 (proof certificates
and an invariant miner), T3 (Nix flake), M3 (more timing protocols).

## 3. Attribution, in the form for the final write-up

Credit by GitHub handle and repository; names only where the author publishes them in the work
itself. Each line says what we took and whether code was copied. Keep only the lines for items
actually adopted at submission time, and update "idea" to "code" wherever a file was copied.

**Competition entries (public repositories)**

- **MarcosAsh**, github.com/MarcosAsh/protocol-emulator (Apache-2.0): weakened properties that must
  fail ("teeth"); the abstract-interpretation programme verifier and its small trusted kernel;
  sigrok decoders judging gate-level traces, with teeth; power-up determinism by a two-copy
  proof; a miter against hardcaml_hobby_boards' `Uart.Tx`; sealed held-out protocols; the table
  of AI-assisted verification; checking incumbent PIO firmware with one's own timing checker.
  Ideas; no code copied.
- **TeslaCoilerOW**, github.com/TeslaCoilerOW/ttihp-protocol-emulator (Apache-2.0): per-image timing
  certificates with negative controls; netlist-to-RTL sequential equivalence with SRAM cut
  points and a self-test; tests against unmodified third-party protocol peers; the generated
  Verilog regeneration check; the documentation consistency checker; the bug ledger; a 6x4
  fallback kept green. Ideas.
- **umerimran-10xe**, github.com/umerimran-10xe/protocol-emulator-asic (Apache-2.0): the two-copy
  arbitration miter (assume equal inputs for the owner, assert equal outputs), the shape of our
  isolation proof. Idea.
- **WilliamZhang20**, github.com/WilliamZhang20/protocol-emulator (Apache-2.0): named RTL mutants
  that bounded proofs must reject; the tracked-address SRAM abstraction. Ideas.
- **fjpolo**, github.com/fjpolo/ProtocolEmulatorr (no licence): mutation checked by an equivalence
  miter. Idea only.
- **dishishshawn**, github.com/dishishshawn/protocol-emulator-asic (Apache-2.0): mutants named after
  the safety property they defend. Idea.
- **TejasDasa**, github.com/TejasDasa/protocol-emulator-asic (MIT): formal properties as an audit of
  the specification's field ranges. Idea.
- **2AMLogic**, github.com/2AMLogic/sg13cmos5l-protocol-emulator (Apache-2.0): content-hashed
  verification records with a "what this is not" section. Idea.
- **Kanishk234**, github.com/Kanishk234/protocol-emulator-asic (Apache-2.0): the claims-and-evidence
  table and its status vocabulary; metamorphic relations; impairment envelopes; gate-level X
  checks. Ideas.
- **wsb1994**, github.com/wsb1994/Gremlin-Board (Apache-2.0): the competition criteria as the rows of
  an executive summary; jitter and baud-error random tests. Ideas.
- **smprather**, github.com/smprather/janestreet-blog-serial-protocol-emulator (MIT): per-property
  PROVED/REACHABLE/VACUOUS reporting; mutation of flow-configuration checks; the lesson that a
  testbench must reach the claimed rate; dual-edge sampling for 10BASE-T at 60 MHz. Ideas.
- **TalentA99**, github.com/TalentA99/pemu-asic (MIT): naming the silicon consequence of every
  property. Idea.
- **kaikino**, github.com/kaikino/core-asic (Apache-2.0): the delay-chain recipe on the CMOS5L flow
  and its measured stage delays; the bubble-tolerant TDC. Idea and flow settings.
- **thomasgilbert481**, github.com/thomasgilbert481/tt_um_loom (Apache-2.0): the recipe for an IHP
  SRAM macro through the cmos5l precheck; a per-thread non-interference miter. Idea and flow
  settings.
- **kdp1965**, github.com/kdp1965/ihp-um-janestreet-prism (Apache-2.0): the PDN-stripe plugin for
  macros on cmos5l; latch-array configuration memory; the conditional-breakpoint debugger; the
  breadth of its protocol list, as our comparator. Ideas.
- **elementalcollision**, github.com/elementalcollision/retrace (Apache-2.0): a second, independent
  layout extractor and planted supply faults. Ideas.
- **joshvern**, github.com/joshvern/pinscript-cmos5l-feasibility (Apache-2.0): reporting each timing
  corner separately. Idea.
- **mohammedbala**, github.com/mohammedbala/chipwheel (Apache-2.0): benchmarking against incumbent
  cores on the same flow. Idea.
- **gigamonster256**, github.com/gigamonster256/protean (Apache-2.0): a Nix flake from Hardcaml to
  GDS. Idea (if adopted).
- **LeEmperor**, github.com/LeEmperor/hardcaml_protemu (no licence): the failure-report contract.
  Idea only.

**Other public work**

- **Gergo Erdi**, github.com/gergoerdi (MIT): ScottCheck's incremental BMC loop; the TMDS encoder
  structure; stall injection with golden transcripts; the typed-microcode hazard table. Ideas,
  reimplemented in OCaml.
- **Edward Kmett**, the blog post "Parallel and Incremental CRCs": the CRC combine identity as an
  oracle. Re-derived.
- **Jane Street**, github.com/janestreet/hardcaml_hobby_boards (MIT): `Uart.Tx` as a reference
  circuit for a miter (if adopted); Hardcaml itself.
- **Tiny Tapeout**, github.com/TinyTapeout/ttihp-verilog-template (Apache-2.0): the project
  template and CI (code, if adopted).
- **Third-party protocol peers** (if adopted, code, unmodified): alexforencich/verilog-uart,
  verilog-i2c (MIT); further peers as TeslaCoilerOW lists them.
- **Incumbent cores** for comparison: lawrie/fpga_pio (BSD-2-Clause); olofk/serv (ISC);
  BrunoLevy's FemtoRV (BSD-3-Clause).
- **sigrok** (libsigrokdecode, GPL-3.0): protocol decoders run as an external oracle; no code
  copied.
- **IHP** (IHP-Open-PDK) and **LibreLane**: the PDK, its SRAM macros and the flow.

## 4. Open questions found on the way

- **SRAM on cmos5l.** tt_um_loom reports a passing precheck with the 512x16 macro; kaikino states
  that the slim PDK ships no SRAM macro. Group F settles it at our pinned PDK.
- **Tile size.** TeslaCoilerOW's README says the organisers confirmed 8x4 on 2026-09-28;
  tt_um_loom's notes say 8x4 did not exist on 2026-09-15 and that organisers advised 6x4. Both
  are their claims. Plan for 6x4 with 8x4 as an upgrade (A12) until we hear from the organisers.
- **Formal back end.** MarcosAsh's LRAT-checked proofs need a SAT back end; our BMC is SMT (z3).
  Whether to bit-blast for certificates (V16) is a cost question, not urgent.
