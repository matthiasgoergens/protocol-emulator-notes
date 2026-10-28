# GitHub sweep: other entrants since 2026-10-05, verification techniques

Written 2026-10-28 (SGT). Scope: public GitHub repositories for Jane Street's Protocol Emulator
ASIC competition (IHP sg13cmos5l via Tiny Tapeout, deadline 2027-01-18), pushed after 2026-10-05,
with emphasis on verification. Complements `notes/learned-from-others.md` (inventory of 26 repos at
2026-10-05, IDs V1..V33); nothing already listed there is repeated unless it changed.

Evidence labels: **[R]** I read the file myself in a shallow clone; **[N]** I saw the file named
(path listing, commit message or someone else's README) but did not read its content. Every pass
count or "killed N of M" below is **the repository owner's claim**; none was reproduced. Nothing
from any clone was executed (no scripts, builds, interpreters inside the clones). Clones are in
`/var/tmp/learn-from-others-2026-10-28/<owner>__<repo>/` (depth 30 to 50, no tags).

## 1. Method

- `gh api search/repositories` with 18 query phrasings (protocol emulator asic, sg13cmos5l, ttihp,
  jane street asic, hardcaml protocol emulator, ...) each with `pushed:>2026-10-05`, 3 pages of
  100; the GitHub rate limit for search (30/min) was hit once part-way, so some pages of some
  queries are missing (see section 6). Plus 4 `search/code` queries.
- From ~260 hits I kept the ~110 that looked like competition entries or adjacent verification
  work, cloned them shallowly, and ranked by verification-related file count and commit activity.
  15 repos were read in depth, 25 skimmed, the rest checked by file listing only (most are the Tiny
  Tapeout template plus a README; 22 files with ~4 "verification" files is the template itself).
- All 26 known repos were re-checked with `git log --since=2026-10-05` on their clones.
- Licences from `gh api repos/<o>/<r> --jq .license.spdx_id`; table in section 5.

## 2. Headline

About 80 of the repos I cloned are not in the 2026-10-05 inventory, but most are template-sized or early
RTL. Six new or substantially updated repos carry verification ideas we do not have in
`notes/learned-from-others.md`: **parthDOOM/escapement** (the strongest new entry on
verification), **Srujan0006/spex**, **theotacconi/openPIO**, **mrnathanhumphrey-droid/protocol-emulator-asic**,
**JessicaTemplet/td-ut-protocol-emulator** (Hardcaml, like us), and the non-entry
**kristofferkoch/vibe-pio** (formally verifiable RP2350 PIO model with SMT program synthesis;
found through Abagel-coder's research note). MarcosAsh/protocol-emulator added 92 commits, several
of them verification refinements.

## 3. NEW techniques

Columns: **Source** (repo, path, commit); **What**; **Licence**; **Read?**; **Difference from ours**;
**Value** for our entry (H/M/L, my estimate).

### 3.1 Formal and equivalence

| # | Source | What | Licence | Read? | Difference from ours | Value |
|---|---|---|---|---|---|---|
| N1 | parthDOOM/escapement `docs/04-VERIFICATION.md` (Formal section), `formal/esc_ctx.sby`, `formal/esc_core.sby`, `formal/split_core.py` @ eb77584 | **Compositional assume-guarantee proof** of an unbounded "never late" property: a per-context k-induction proof assuming only admitted pushes, plus a core proof that every push is admitted; the split is drawn so neither side assumes what the other proves. Stated as one clause the property "had not converged after seven hours of PDR"; split it proves in under a minute. | Apache-2.0 | R (doc), N (sby, split_core.py) | We prove isolation and determinism with BMC plus relational induction; no property we hold was split by assume-guarantee to make PDR converge. | H if we have any property that does not converge; otherwise M |
| N2 | same, `formal/split_core.py` and doc "Run time" | **One SymbiYosys task per assertion source line**, run `JOBS` at a time, with `lemma-group` tags so assertions that need each other as lemmas are proved together (alone, P5 did not finish in two hours; grouped with H3/H4 it proves in two minutes). Total 58 min wall for 27 tasks. | Apache-2.0 | R (doc), N (script) | Our `run_all.sh` runs whole-design proofs; no per-assertion split or lemma grouping. | M (cheap, makes PDR practical) |
| N3 | same, doc "Latch banks (v1.4)" and `formal/esc_lreg.sby`, `esc_greg.sby` | **Clock-gate and latch-bank equivalence with an unconstrained clock**: G1..G5 prove a gated or latch register bank equals an enable flip-flop at every instant (k-induction), with teeth (a naive `clk & en` gate fails G3 at the first step; latch fed straight from write data fails G4). The logic proofs then see only the flip-flop model. | Apache-2.0 | R (doc) | We have not used latches or clock gating in the logic proofs; relevant if we gate clocks to save area or power. | M (only if we use clock gating or latch memory) |
| N4 | same, `formal/equiv.sh` @ eb77584 | **RTL vs hardened-netlist miter with SRAM macros cut out**: macro outputs become shared free inputs, macro inputs become compared outputs; ABC `dprove` (bounded search, then signal correspondence and induction); 245 s for the v1.4 netlist; teeth: NAND->NOR near `uio_oe[0]` fails at step 1, a shift-register bit rewired fails at step 21. Same family as V4 (TeslaCoilerOW, MarcosAsh) | Apache-2.0 | R (script head), R (doc) | Same technique as V4 which we have marked "not yet"; a third independent implementation to compare against, with a **separate mode: the second design may be a mutated RTL tree** (see N5). | H as a V4 reference |
| N5 | same, doc "Mutation testing" + `equiv.sh` header; MarcosAsh `test/mutate.py` commit 3edd72e | **Adjudicating surviving mutants**: a mutant that all test suites miss is proved formally equivalent or not against the original RTL (escapement: `equiv.sh` pointed at a mutated source tree; 710 mutants, 658 generated). MarcosAsh does the cheap version: hash the Verilog each mutant elaborates to; if it equals the original's, the mutant changes no gate and is dropped from the score and listed. | Apache-2.0 both | R (escapement doc, equiv.sh header; MarcosAsh diff) | V20 (mutation score with allow-list of equivalent mutants) only lists a hand-kept allow-list; both of these *decide* equivalence mechanically. | H (small, turns a mutation score into a defensible number) |
| N6 | escapement doc "Mutation testing" | **Deterministic mutant sampling**: a site is chosen when a hash of (file, operator, line text) falls under a fixed rate, so editing one line changes only that line's mutants; every suite a mutant needs must pass on the unmutated RTL first, otherwise "cannot run" reads as "killed". Hung suite counts as kill. | Apache-2.0 | R | Our planted bugs are hand-chosen; no generated population and no baseline-must-pass guard. | M |
| N7 | B44ken/protoemu `reports/generated-core-equivalence.txt` @ e97bf3a, `tools/formal-hls.sh` (named) | **Per-output-bit teeth for a miter**: the Yosys miter compares all 87 output bits; then 87 separate single-output-bit mutations are each required to fail the proof. Also pins the generator inputs and tool versions by SHA-256 in the report. | Apache-2.0 | R (report), N (script) | Cheap proof that every compared bit is actually wired into the comparison; our RTL-vs-spec check has 28 planted bugs but no "flip each compared bit" sweep that I know of. | M-H (minutes to add to our miter) |
| N8 | Kanishk234/protocol-emulator-asic `scripts/ci/verify_cached_port_select.py` and siblings @ e78b862 | **Equivalence of a timing-motivated rewrite against a hash-pinned verified base**: base and trial RTL named by SHA-256 constants in the script; a "named reference" transformation exposes the golden combinational decode so the sequential proof can match the new cached state; the transformation itself proved for every legal N. | Apache-2.0 | R (head of one script) | Our proofs are against the spec, not against "last verified RTL"; this is the process for safe late edits after freeze. | M (matters when timing closure forces a rewrite) |
| N9 | Cyan-28/ProtoEmul `flow/equiv_check.sh` @ d75983b | EQY driver run without `make`; compares the **generic** (pre-`dfflibmap`) netlist; states that a mapped comparison hit a base-case failure when flip-flops were modelled from liberty attributes and was **deliberately not attempted**. A caution for V4: map-level equivalence needs real cell models. | none | R (header) | Warns of a pitfall in V4 (escapement and TeslaCoilerOW get past it by building cell functions from the liberty). | L-M |

### 3.2 Test-suite and oracle integrity

| # | Source | What | Licence | Read? | Difference from ours | Value |
|---|---|---|---|---|---|---|
| N10 | mrnathanhumphrey-droid/protocol-emulator-asic `model/price_gates.sh`, README "How it is verified" @ c27fc5a | **Pricing each independent tool**: remove each external tool (pyRTA, TChecker, IMITATOR, sigrok) in turn and require its gate to go red (13 of 13, their claim), so no verdict silently falls back to the author's own arithmetic. | Apache-2.0 | R (README), N (script) | Exactly our "a check that can silently degrade to a no-op" rule, applied mechanically to tool dependence; our sigrok judges have a planted-fault control but we do not delete the tool and see whether the gate still passes. | H |
| N11 | same, `docs/redteam/RT1_BUILT.md` | **Written red-team pass on the gates themselves**, 17 numbered findings with CONFIRMED / SUSPECTED, `file:line`, plus a list of "attacks that failed - the claim held". Concrete gate defects it found: a gate that scores "tool produced no result" as "mutant rejected" (passes with the tool absent); a script that never checks the generator's exit status and reads stale files; `field_exercised` returning True on a crash; a coverage gate where a crash counts as coverage. | Apache-2.0 | R | Our adversarial reviews target claims; this targets the *gates* with a failure-class taxonomy (absent tool = pass, stale artefact = pass, crash = pass). A useful checklist for our own `run_all.sh`. | H |
| N12 | same, `README` ("confirmed by the failure *message*, not just the exit code"), `model/gate_mutant_kills.py` | Every injected defect is tied to a **named check** and the kill is confirmed by that check's failure message; 6 of 56 mutants are declared survivors, each with the reason no check should see it. | Apache-2.0 | R (README claim), N (script) | Our planted bugs record "killed" but not "by which check, with which message". | M |
| N13 | same, `test/gl_harness_check.py`, KG-khangelani `docs/verification.md` ("GL-shaped harness") | **Does the testbench survive gate level?** A seconds-long check that the harness elaborates the way `gl_test` will (no parameters on the flat netlist, no Python reach-in to signals synthesis drops). Origin: `gl_test` died after 3h50 + 2h11 of hardening on `tb.v: parameter SPL not found`. KG compiles the RTL with `GL_TEST` so direct-engine handles are absent. | Apache-2.0 both | R (mrnathanhumphrey), R (KG doc) | Two independent repos hit the same trap. Our TT submission plumbing (V28, not yet) should include this. | H (cheap, saves a day of CI) |
| N14 | same, `model/gate_reset_audit.py`, README table | **Reset audit**: 2,145 of 3,449 flops unreset, in 5 groups each allowlisted with a reason; `F2`: every output bit is flop-driven or constant. Also mcranny/protocol-emulator-asic (commits 111e147, b7f00aa) rejects incomplete initialisation evidence with seven negative cases. | Apache-2.0 | R (README), N (scripts) | Complements our power-up determinism proof (V8): theirs is a structural audit of *which* flops lack reset, ours is a behavioural proof. | M |
| N15 | same, README | **Two simulators must produce byte-identical per-cycle traces** (Icarus and Verilator) of every port; found two testbench races neither simulator showed alone and a seed sweep that had silently tested nothing. | Apache-2.0 | R (README) | We run one simulator for the lockstep comparisons (as far as I know). | M |
| N16 | same, `test/clean_room.py` | **Clean-room check**: move every generated, gitignored artefact into a quarantine directory, regenerate with the recorded recipes, require byte-identical content (not just presence) and a passing suite. Origin: a hand-made gitignored hex file nothing could regenerate. | Apache-2.0 | R (head) | We keep commands beside results; no regenerate-and-compare gate. | M |
| N17 | Srujan0006/spex `docs/CLAIMS.md`, `tests/oracles/README.md` @ 5b5ac02 | Same claims-table idea as D1 (credits Kanishk234), plus: **a strict "blind spot" column per claim**, **corrected claims kept visible** ("C1 corrected 2026-10-20": the earlier 0.158 mm2 figure struck through, replaced by 0.337 mm2 measured), and an explicit note that *the oracles, spec and model are all written by the same AI*, so independence is not claimed. Independence is tested: `tests/oracles/test_independence.py` (N). Oracle rule: "write from standards only, never import spec/ or spex/", each oracle ships a planted-fault test. | Apache-2.0 | R (CLAIMS, README) | Our D1 is "not yet"; this is the most honest worked example. | M-H (write-up) |
| N18 | same, `scripts/mutate_model.py`; CLAIMS C2/C3 correction | **Mutation counts caught as vacuous**: "45/45" and "52/52" were later found vacuous (BUGS 16) and re-run; the correction is in the claims table. A lesson matching our `Save the run` rule. | Apache-2.0 | R | We already know this failure; they show a public correction format. | L-M |
| N19 | same, `docs/CLAIMS.md` C7/C10 and `scripts/export_tchecker.py`, `scripts/build_tchecker.sh` | **Model-check the spec itself as a timed automaton** (TChecker 0.8, dense time): "never starts a frame inside another", "ends a frame 9T +- d after start", SPI byte boundaries after exactly 8 samples, I2C bus-free time >= tBUF (226 / 63 cycles at 48 MHz); planted spec bugs make the error reachable, and each property has a non-vacuity reachability query (28/28 verdicts as expected, their claim). mrnathanhumphrey independently uses TChecker and IMITATOR (parametric) the same way. | Apache-2.0 both | R (CLAIMS), N (scripts) | We check the RTL against a spec; nothing checks the *spec's timing properties* with a timed-automata tool. Two independent entrants chose TChecker. | M-H as a differentiator, M effort (needs an export from our spec) |
| N20 | same, `tests/model/test_decoder.py`, CLAIMS C9 | **Translation validation of the compiler**: an independent decoder (written from the semantics doc, importing nothing from the compiler) decodes every compiled image back to an edge graph that must equal the compiler's; 6 corrupted-image controls and 3 planted encoding bugs detected. | Apache-2.0 | R (CLAIMS) | Our assembler/compiler is checked end to end but not by an independent decoder of its output. | M |
| N21 | theotacconi/openPIO `test/lockstep/netlist.py`, `fuzz.py` @ 63f4d11 | **Gate-level lockstep in pure Python**: Yosys synthesises RTL to $_AND_/$_OR_/... cells, the netlist is compiled to straight-line Python and stepped per clock against the Python model; `--xval 0|1` sets don't-care (`x`) constants, so running the same fuzz at both values is a cheap X-sensitivity check; `OPENPIO_SRC` points at a mutated copy to check harness sensitivity. | Apache-2.0 | R (heads) | Our post-layout round trip extracts a netlist from our own GDS and runs random lockstep; the xval trick is a free addition to V9 (gate-level X). | M |
| N22 | JessicaTemplet/td-ut-protocol-emulator `scripts/run_tx_mutation_test.sh`, `test/gen_formal_fifo.ml` @ 8e82c43 | Hardcaml-source-level mutation (35 faults as find/replace on `lib/*.ml`, built with `--profile release` so unused variables do not fail), **an explicitly documented unkillable mutant** (rounding direction of the clock-recovery shifts differs by 0.02 cycle over 3000 bits: "would only ever survive"), and the point that a **loopback-symmetric mutant** (wrong CRC polynomial in both directions) is invisible to loopback and only an independent reference encoder catches it. Also: bounded-exhaustive 4^10 push/pop sequences on the real RTL, then an unbounded PDR proof of the same FIFO properties on the Hardcaml-generated RTL, formal generator written in OCaml. | Apache-2.0 | R (script head, README rows) | The closest to our toolchain (Hardcaml). The symmetric-mutant point is a design rule for our own loopback tests. | M |
| N23 | soundgod10-droid/protocol-emulator-asic `formal/core_fv.v` @ e806789 | Core proved with **every instruction/data word, event slot, input history and FIFO state free**, properties embedded in RTL under `ifdef FORMAL` (B1..B4 barrel order, E1..E8 pin events, W1..W3 memory write), and a counter shortened to 16 bits with an argument that its low 16 bits are the same as the chip's 32. | Apache-2.0 | R (head) | Same shape as ours; the **shortened-counter justification** is a pattern we may need for long timers. | L |

### 3.3 Selection, specification and process

| # | Source | What | Licence | Read? | Difference from ours | Value |
|---|---|---|---|---|---|---|
| N24 | MarcosAsh/protocol-emulator `demo/corpus_draw.py`, `demo/corpus_draw_33346612.json`, README "Protocols drawn at random" @ 49df2ef | **Randomly drawn test corpus with a public beacon**: a drand round fixed in advance picks 6 protocols from a pinned snapshot of sigrok's decoder list (`rank by sha256(randomness || id)`), minus the owner's sealed exclusion list whose hash was committed before the round; an agent writes each blind from the pinned spec. Results shown including failures: 3 certified, 2 hollow because the spec gives no bounds, 1 failed (no timing limits to check against). Extends V21 (sealed held-out) from "I picked them in secret" to "nobody picked them". | Apache-2.0 | R (script head, README) | V21 is "sealed list"; this removes the selection-bias objection and adds the "hollow spec" verdict. | H (cheap, striking, shows the generality Jane Street asks about) |
| N25 | same, `demo/extract.py`, `demo/intake.sh`, commits f046f3b, 49df2ef | **Double extraction of a datasheet's timing limits**: two headless agents read the spec blind in separate copies, tables are compared field by field, any disagreement stops with "limit disputed, DOC p.N" and a human rules; a spec whose limit rows bound nothing (typical values only) is called *hollow* rather than silently passing. | Apache-2.0 | R (diffs) | Our "third-party peers" use ready oracles; nobody on our side checks the limit tables that firmware is certified against. | M |
| N26 | same, README "Trying to break it", `test/delay_variants.ml` (partly R) | **Planted delays against a static certifier**: 1-3 `nop` cycles at every deadline wait of 7 swept firmwares plus counts from one short of the slack to three past: 283 planted, certifier accepted 181 and none ran late on the model; refused 102, of which 92 did run late (their claim); also "every deadline wait given one more cycle than its slack: all 567 refused". Lists the 10 refusals that are late only on paths the test input never takes. Also attributes 13 bugs to the technique that found each (model tests 3, soundness check 3, AI review 3, proofs 2, ...). | Apache-2.0 | R (README), partly R (delay_variants.ml) | Soundness *and* tightness of a static timing verifier, measured against a model run; applies if we have the timing verifier V2 equivalent. Bug-attribution table is a reusable write-up device. | M-H |
| N27 | kristofferkoch/vibe-pio `tools/trace_audit.py`, `docs/pio-spec.md`, `docs/cycle-contract.md` @ 747afa5 | **Traceability audit**: every spec fact `[SPEC-x.y-n]` and contract clause `CC-n` is classified *verified* (cited by an `assert`), *referenced* (comment, assume, cover) or *uncited*; the script parses a citation grammar with ranges and slash lists and flags section-wide citations as weaker. | none | R (docstring) | Generalises V11 (each property names the consequence it rules out): this asks the converse, which spec facts have **no** property. | H (a few hours; excellent coverage statement for the write-up) |
| N28 | same, `tools/hypersynth.py`, `formal/pio_synth_fv.sv` | **Program synthesis by SMT**: the 32 instruction words become free `anyconst`, a cover goal on `gpio_out[0]` states the waveform, the solver finds a program; witness is canonicalised (unvisited words to `nop`; a visited reserved word aborts), disassembled, reassembled bit-exact, then re-verified three ways (Python model replay, generated Icarus testbench, bounded formal with the program fixed). | none (ideas only) | R (docstring) | The same free-instruction machinery as our RTL-vs-spec check, pointed the other way: "the solver wrote UART". A demo as much as a verification technique. | H as a demo, M effort |
| N29 | same, `tools/hyperequiv.py` | **Equivalence oracle for two programs** on the same hardware: Python-model lockstep prefilter on random stimulus (a divergence is a definite FAIL), then an sby miter at horizon N, then a CEX decoded back into the first differing pin and disassembled PCs and replayed through both models. | none | R (docstring) | Lets us prove "this hand-written firmware equals that generated one" at the pins; V15 does it for one pair. | M |
| N30 | dishishshawn/protocol-emulator-asic `test/receivers.py`, `tools/fingerprint.py`, `test/test_fingerprint.py`, commit 094e2bc | **Receiver fingerprinting**: the chip's own firmware sends exact-length frames and glitches (179 probes) to a *third-party receiver* and identifies which of five UART receiver algorithms it implements from the verdicts alone; greedy decision tree, 1,061 engine runs, 9/9 correct after one rebuild and five negative controls (their claim); a model left out of the map is misidentified (recorded as a limit). CI requires `reports/fingerprint.json` byte-identical. | Apache-2.0 | R (commit message, handoff doc, test header) | Turns the emulator into a measuring instrument for other people's peers (e.g. fingerprint the Alexforencich or sigrok receivers we test against). | M-H as a demo/write-up idea |
| N31 | KG-khangelani/protocol-emulator-asic `.github/workflows/upstream-canary.yaml`, `tools/check_upstream_drift.py`, `evidence/E00NN-*` | Weekly **read-only upstream canary**: compares the live Tiny Tapeout tools ref with the qualified commit and uploads the drift as an artefact, never changing the flow; numbered immutable evidence records with SHA-256s and "negative evidence preserved". 2AMLogic uses the same append-only record convention (`verification/README.md`), plus **two harnesses on one RTL** (the TT template's `test/` and their own) so a disagreement is itself a finding. | Apache-2.0 both | R (workflow, doc, README) | We pin the tools but do not monitor drift; with a January deadline and a changing sg13cmos5l template, drift is a real risk (thomasgilbert481 notes the 8x4 template is still unpublished). | M |
| N32 | thomasgilbert481/tt_um_loom `docs/VERIFICATION.md` L5, commit a8b7749 | **Timing-annotated gate-level firmware simulation in Icarus**: 14 firmware scenarios (thirteen protocol programs plus the four-at-once demo) on the 8x4 netlist with typical-corner SDF delays, 25 ms simulated in 58 min over four parallel builds, about 0.4 s per simulated microsecond; delays verified applied by comparing times (158 s with SDF vs 16 s without for one UART scenario). Cell delays only; timing checks ignored, so STA remains the setup/hold evidence. | Apache-2.0 | R (commit message) | Gives a measured cost for an SDF run and the "check the delays were applied" trick; we have not run SDF-annotated firmware. | M |
| N33 | thomasgilbert481/tt_um_loom (D-035 commits 927cc34..d38284c) | **Firmware for protocols the design was not built for**: NEC IR, 1-Wire (DS18B20 model), LIN master with auto-baud slave, SPI slave modes 1/2, I2C to UM10204 table 10. Their own (non-blind) version of V21. | Apache-2.0 | N (commit titles) | Direction of travel only. | L |
| N34 | PankajNair/protocol-emulator-tt `formal/AGENT_CONTRACT.md`, `.claude/agents/assertion-formal.md`, `scripts/assert_superset.py` (N), nightly `signoff.py` | **Agent-written formal properties behind a mechanical gate**: contract with write scope, protected paths, gate command and threshold; accepted only if (1) every `cover` is reached (vacuity), (2) BMC pass and k-induction PROVEN, (3) `assert_superset` finds no existing `assert`/`assume` removed or edited and no new `assume`; deep covers must carry a `deep-evidence:` tag naming an existing cocotb test; the contract tells the agent to inject a bug into a scratch copy and confirm the property fails. | Apache-2.0 | R (contract, agent file, nightly workflow), N (assert_superset.py) | Mechanical rules for AI-written proofs ("never strengthen by weakening"); feeds V22 (AI use with gates). | M-H (write-up; the superset gate is easy to copy) |

## 4. Known repos: material changes since their listed commit

- **MarcosAsh/protocol-emulator** (listed 3333f0c; now 49df2ef, 92 commits, Apache-2.0): N5, N24, N25, N26 above; also sigrok decoder snapshots fetched and checked by SHA-256 (commit f98a8f8), ir_rc6/microwire/xy2_100/caliper/lfast firmware added to the library, README rewritten to put the result first (49df2ef). Read: diffs for 3edd72e, e2813fa, 49df2ef, README sections.
- **Kanishk234/protocol-emulator-asic** (listed 593be7f; now e78b862, 50+ commits): almost all commits are physical-flow screening of the stock Tiny Tapeout flow (hold, antenna and slew repair; "stock official baseline screen" CI), plus N8. The only commit since 10-05 that touches `docs/design/VERIFICATION.md`, `formal/equiv.sh` or `formal/l0_asrt.sby` is f0c4482 (I did not diff it). Planned L4 items (V18, V19) have not visibly moved.
- **thomasgilbert481/tt_um_loom** (listed fdaa854; now 0807004, 18 commits): N32, N33; BUGS 11 fixed and re-hardened; moved to the 8x4 block (D-034), "slow corner ~43 MHz"; quotes an organisers' update of 2026-10-09 (demo board v3 is the prize "ETR" board; local hardening as the fallback for the six-hour job limit).
- **smprather/janestreet-blog-serial-protocol-emulator** (listed 58e4903; now fa2bfaf, 8 commits): host IMEM read bug fixed (55ab86f), a mutation suite for one testbench (994224c), deadline corrected to 2027-01-18. No new technique.
- **dishishshawn/protocol-emulator-asic** (listed facd14f; now 47683dd): N30.
- **mcranny/protocol-emulator-asic** (listed 00b048a; now 856a1ea, 39 commits): V2 release candidate; "Require every gate-level suite to execute" (ba50456, a guard against a gate-level suite that silently runs zero tests), reset and initialisation audit (111e147, b7f00aa), annotated GitHub timeouts recognised (c1c9be5). Overlaps N13 and N14. Read: commit messages and stat only.
- **2AMLogic/sg13cmos5l-protocol-emulator** (listed 78b5ddb; now 18198b7, 192 commits): mostly klayout-tools (klt) 0.8.0 evidence re-minting, an ERC supply spec on the LibreLane GDS (commit 6d58a5c), pre-silicon characterisation report; N31 conventions. Read: commit list, `verification/README.md`.
- **kdp1965/ihp-um-janestreet-prism** (05a68dc): documentation updates only (counters, bit-stuffing, FIFO replay).
- **Lincreased/tt-protoseq** (c381eec): decision log entries (D-012, D-016), `verified_facts.md`; no new technique seen.
- **TejasDasa** (81137ac): an I2C target firmware; **LeEmperor** (ca7c593): repo clean-up; **WilliamZhang20/protocol-emulator-compiler** (58c13be): a Claude Code workflow only. Unchanged: TeslaCoilerOW, kaikino, chipwheel, protean, retrace, WilliamZhang20/protocol-emulator, umerimran-10xe, fjpolo, wsb1994, Kleven2k, sjrai007, TalentA99, OliverKlug, DanielMBouyou, antojoseph.

## 5. Other things not about verification (brief)

- escapement: **timing certificates for firmware** (`sw/escert`: a certifier proves firmware never triggers an admission fault), an on-chip execution digest and telemetry, the "protocols as data" and "reject-not-late" semantics (`docs/11-SEMANTICS.md`, `docs/18-PROTOCOLS-AS-DATA.md`), and a results web page generated from CI (`site/`). [N] for most; README claims are theirs.
- relwire (Apache-2.0): **one protocol program, every role**: a role mask makes the same binary a controller, target or sniffer; arbitration loss turns a controller into an observer at run time; randomised "projection consistency" fuzz (`test/fuzz.ml`, OCaml) requires all roles plus a passive observer to agree on every bound bit (read header only).
- openPIO: 14 per-protocol "domain agents" write firmware against a golden model and file RFCs about ISA gaps until all pass; a hardware protocol assist (NRZI, bit-stuffing, Manchester) beside a PIO-style core.
- mrnathanhumphrey: pre-registered documents (`docs/ARCH_PREREG_01.md`, "written before any RTL"), a Lean model of the scheduler tied to RTL by trace replay, a non-preemptive EDF scheduler over five lanes, FPGA runs with real parts.
- Spex: sealed held-out protocol list + a fresh-session "can an agent write a new spec from the guide only" experiment (`docs/HELDOUT.md`, credit to MarcosAsh); area accounting with a published correction (C1).
- Abagel-coder `docs/research/verification-novelty.md` (R): a literature scan recommending MCY (mutation with formal filtering), EQY, microcotb (the same cocotb tests on silicon), cocotb-coverage, riscv-formal-style harnesses, and warning that bare "AI helped verify" claims will be discounted. **I did not check the papers it cites**; I did check that `YosysHQ/mcy` (ISC, pushed 2026-10-13) and `YosysHQ/eqy` exist, and that `psychogenic/microcotb` is LGPL-2.1 and last pushed 2025-02-25.
- Alternative-arch note: B44ken/protoemu generates its core from C with PipelineC and proves C-to-RTL equivalence (N7).

## 6. Repos examined

All clones: shallow, in `/var/tmp/learn-from-others-2026-10-28/`. "Depth" says how much I read.

| Repo | HEAD | Date | Licence (GitHub) | Depth |
|---|---|---|---|---|
| 2AMLogic/sg13cmos5l-protocol-emulator | 18198b7 | 2026-10-27 | Apache-2.0 | skimmed (file list, commit log, some files) |
| aaarus/protocol-emulator-v1 | ae29ee6 | 2026-10-12 | none | cloned; file list / commit log only (mostly template-sized, no verification files) |
| aaarus/protocol-emulator-v2 | c51219a | 2026-10-28 | none | cloned; file list / commit log only (mostly template-sized, no verification files) |
| Abagel-coder/protocol-emulator | f904d1f | 2026-10-17 | Apache-2.0 | read files |
| abhictrl/protocol-emulator-asic | 56ee128 | 2026-10-27 | Apache-2.0 | cloned; file list / commit log only (mostly template-sized, no verification files) |
| adichan20/protocol-emulator | 38ea0fb | 2026-10-25 | none | cloned; file list / commit log only (mostly template-sized, no verification files) |
| AHILAN123/ChipDesign | c5edd89 | 2026-10-23 | none | cloned; file list / commit log only (mostly template-sized, no verification files) |
| alexmotea2005/protocol-emulator-asic | 959c04b | 2026-10-21 | Apache-2.0 | cloned; file list / commit log only (mostly template-sized, no verification files) |
| All-SeeingEye/Protocol-Emulator-ASIC | a32b151 | 2026-10-23 | MIT | cloned; file list / commit log only (mostly template-sized, no verification files) |
| antojoseph/protocol-emulator-verifier | cf8a592 | 2026-09-29 | Apache-2.0 | cloned; file list / commit log only (mostly template-sized, no verification files) |
| Arcaderydoo/protoemu | 09e054a | 2026-10-13 | Apache-2.0 | cloned; file list / commit log only (mostly template-sized, no verification files) |
| ArkaKhorchidian/tt-protocol-emulator | f73aeb9 | 2026-10-21 | Apache-2.0 | skimmed (file list, commit log, some files) |
| Austin-MgKaung/inwa-protocol-emulator | ff12edd | 2026-10-21 | Apache-2.0 | cloned; file list / commit log only (mostly template-sized, no verification files) |
| b3elz3bub/ProtoEmu | 814d507 | 2026-10-12 | none | cloned; file list / commit log only (mostly template-sized, no verification files) |
| B44ken/protoemu | e97bf3a | 2026-10-05 | Apache-2.0 | read files |
| bhavsar-dhruv/Jane-street-protocol-emulator | 205b859 | 2026-10-04 | Apache-2.0 | cloned; file list / commit log only (mostly template-sized, no verification files) |
| bvsrvaibhav/protocol-emulator | 6d2b6fb | 2026-10-16 | Apache-2.0 | cloned; file list / commit log only (mostly template-sized, no verification files) |
| Cocomilk22/js-emulator | 298b51e | 2026-10-11 | Apache-2.0 | cloned; file list / commit log only (mostly template-sized, no verification files) |
| Cyan-28/ProtoEmul | d75983b | 2026-10-04 | none | read files |
| DailingW/js_protocol_emulator_asic | d7aadd2 | 2026-10-08 | Apache-2.0 | cloned; file list / commit log only (mostly template-sized, no verification files) |
| danhle0711/protocol-emulator-asic | 593f12b | 2026-10-02 | Apache-2.0 | cloned; file list / commit log only (mostly template-sized, no verification files) |
| DanielMBouyou/protocol-emulator-asic | ffabc43 | 2026-09-18 | none | cloned; file list / commit log only (mostly template-sized, no verification files) |
| danieltyukov/jane-street-asic-puzzle | 034ed83 | 2026-10-08 | MIT | cloned; file list / commit log only (mostly template-sized, no verification files) |
| deepsn458/elec422_protocol_emulator | 64ac313 | 2026-10-25 | Apache-2.0 | skimmed (file list, commit log, some files) |
| deetya326/protocol-emulator | 4a40080 | 2026-10-06 | Apache-2.0 | cloned; file list / commit log only (mostly template-sized, no verification files) |
| devanandanj/protocol-emulator-asic | 3f6f9d5 | 2026-09-19 | Apache-2.0 | cloned; file list / commit log only (mostly template-sized, no verification files) |
| dishishshawn/protocol-emulator-asic | 47683dd | 2026-10-10 | Apache-2.0 | read files |
| Doubleimpala/Jane-Street-Janitors | 8977605 | 2026-10-10 | Apache-2.0 | cloned; file list / commit log only (mostly template-sized, no verification files) |
| dpsdagain/tt-protocol-emulator | 9c35f6f | 2026-10-14 | Apache-2.0 | cloned; file list / commit log only (mostly template-sized, no verification files) |
| elcruzo/protocol-emulator | a6afcd0 | 2026-10-11 | Apache-2.0 | cloned; file list / commit log only (mostly template-sized, no verification files) |
| elementalcollision/retrace | baa863b | 2026-10-02 | Apache-2.0 | cloned; file list / commit log only (mostly template-sized, no verification files) |
| Elrond-Xie/HardwareProtocolEmulation | 9878877 | 2026-10-20 | NOASSERTION | cloned; file list / commit log only (mostly template-sized, no verification files) |
| EnochWong521/protocol-emulator-asic | c808ace | 2026-10-27 | none | cloned; file list / commit log only (mostly template-sized, no verification files) |
| erizeli/js_protocol_emulator | 8bd586e | 2026-10-11 | none | cloned; file list / commit log only (mostly template-sized, no verification files) |
| evan-youan-yu/protocol-emulator-asic | 1e79ace | 2026-10-20 | Apache-2.0 | skimmed (file list, commit log, some files) |
| f4t4nt/jane-street-asic-puzzle-2026 | a90db22 | 2026-10-22 | none | cloned; file list / commit log only (mostly template-sized, no verification files) |
| fjpolo/ProtocolEmulatorr | 1b1f8aa | 2026-10-02 | none | cloned; file list / commit log only (mostly template-sized, no verification files) |
| Geethu37-TOP/programmable-protocol-emulator | b513e31 | 2026-10-20 | Apache-2.0 | cloned; file list / commit log only (mostly template-sized, no verification files) |
| Geethu37-TOP/protocol-emulator-cmos5l | de0badf | 2026-10-20 | Apache-2.0 | cloned; file list / commit log only (mostly template-sized, no verification files) |
| Geethu37-TOP/protocol-emulator | d945276 | 2026-10-20 | Apache-2.0 | cloned; file list / commit log only (mostly template-sized, no verification files) |
| gigamonster256/protean | 34df2ec | 2026-09-21 | Apache-2.0 | cloned; file list / commit log only (mostly template-sized, no verification files) |
| GiorgosAdam06/protocol-emulator-asic | d04cf74 | 2026-10-04 | Apache-2.0 | cloned; file list / commit log only (mostly template-sized, no verification files) |
| goutamyadav/Chip-jane-street | cda59dc | 2026-09-20 | Apache-2.0 | cloned; file list / commit log only (mostly template-sized, no verification files) |
| Highfive1/Jane-Street-ASIC-Puzzle-2026-Solution | (empty repo) | - | none | cloned; file list / commit log only (mostly template-sized, no verification files) |
| ic-icarus/jane-street-protocol-emulator | 50923dd | 2026-10-22 | Apache-2.0 | cloned; file list / commit log only (mostly template-sized, no verification files) |
| IGNYTION-IO/crucible-asic-starter | 6aed39b | 2026-10-22 | Apache-2.0 | skimmed (file list, commit log, some files) |
| Jahnavi-Koppala/Jane-Street-ASIC-Challenge-2026 | b67b692 | 2026-10-27 | none | cloned; file list / commit log only (mostly template-sized, no verification files) |
| JAsic2000/protocol-emulator | 677c8f0 | 2026-10-10 | Apache-2.0 | cloned; file list / commit log only (mostly template-sized, no verification files) |
| jasonzh0/de1-soc-protocol-engine | ecceb39 | 2026-09-18 | Apache-2.0 | cloned; file list / commit log only (mostly template-sized, no verification files) |
| jeddfadhley/protocol-emulator-asic | 7cbcfe3 | 2026-10-12 | Apache-2.0 | skimmed (file list, commit log, some files) |
| Jerrycpp/jane-street-asic-challenge | 49a1a5d | 2026-10-27 | none | cloned; file list / commit log only (mostly template-sized, no verification files) |
| JessicaTemplet/td-ut-protocol-emulator | 8e82c43 | 2026-10-25 | Apache-2.0 | read files |
| jhwang04/c_model | 1e7b945 | 2026-10-24 | none | cloned; file list / commit log only (mostly template-sized, no verification files) |
| JLee-Sin/COMS-EMU-JS-TT | 19ae210 | 2026-10-13 | Apache-2.0 | cloned; file list / commit log only (mostly template-sized, no verification files) |
| JoshuaShunk/protocol-emulator-asic | 925c248 | 2026-10-02 | Apache-2.0 | cloned; file list / commit log only (mostly template-sized, no verification files) |
| kaikino/core-asic | 00e5951 | 2026-09-21 | Apache-2.0 | cloned; file list / commit log only (mostly template-sized, no verification files) |
| Kanishk234/protocol-emulator-asic | e78b862 | 2026-10-27 | Apache-2.0 | read files |
| kdp1965/ihp-um-janestreet-prism | 05a68dc | 2026-10-15 | Apache-2.0 | skimmed (file list, commit log, some files) |
| KelvinTichana-creator/protocol-emulator | d1e9577 | 2026-10-13 | none | cloned; file list / commit log only (mostly template-sized, no verification files) |
| kevinroshann/protocol_emulator | (empty repo) | - | none | cloned; file list / commit log only (mostly template-sized, no verification files) |
| KG-khangelani/protocol-emulator-asic | ae13f6b | 2026-10-14 | Apache-2.0 | read files |
| Kleven2k/silverfox-tt | 5dd5392 | 2026-09-23 | Apache-2.0 | cloned; file list / commit log only (mostly template-sized, no verification files) |
| konradkriehmig/generalized-specialized-ic | a795cac | 2026-10-26 | Apache-2.0 | cloned; file list / commit log only (mostly template-sized, no verification files) |
| kristofferkoch/vibe-pio | 747afa5 | 2026-09-11 | none | read files |
| Kshitij-Vaidya/protocol-emulator | df8681a | 2026-10-25 | Apache-2.0 | cloned; file list / commit log only (mostly template-sized, no verification files) |
| lblommesteyn/relwire | d1b5d80 | 2026-10-09 | Apache-2.0 | skimmed (file list, commit log, some files) |
| LeEmperor/hardcaml_protemu | ca7c593 | 2026-10-11 | none | skimmed (file list, commit log, some files) |
| Lincreased/tt-protoseq | c381eec | 2026-10-09 | Apache-2.0 | skimmed (file list, commit log, some files) |
| LOVE4KIMCHAEWON/jane-street-asic-2026-reproduction | 606f4ae | 2026-10-13 | NOASSERTION | cloned; file list / commit log only (mostly template-sized, no verification files) |
| LOVE4KIMCHAEWON/pinscript-asic | 5bd19b9 | 2026-10-13 | Apache-2.0 | cloned; file list / commit log only (mostly template-sized, no verification files) |
| Mahek-H-Varasada/Project-TickTape | 1dc4798 | 2026-10-12 | none | cloned; file list / commit log only (mostly template-sized, no verification files) |
| MarcosAsh/protocol-emulator-bench | 1e73cc7 | 2026-10-15 | CERN-OHL-P-2.0 | cloned; file list / commit log only (mostly template-sized, no verification files) |
| MarcosAsh/protocol-emulator | 49df2ef | 2026-10-27 | Apache-2.0 | read files |
| mcranny/protocol-emulator-asic | 856a1ea | 2026-10-18 | Apache-2.0 | skimmed (file list, commit log, some files) |
| Megha06-byte/sounika_protemul | 8709f0a | 2026-10-13 | Apache-2.0 | cloned; file list / commit log only (mostly template-sized, no verification files) |
| misa-hw/janestreet_protocol_emulator_asic | 8cb3aad | 2026-10-03 | none | cloned; file list / commit log only (mostly template-sized, no verification files) |
| mohammedbala/chipwheel | 737829d | 2026-10-04 | Apache-2.0 | cloned; file list / commit log only (mostly template-sized, no verification files) |
| mrnathanhumphrey-droid/protocol-emulator-asic | c27fc5a | 2026-10-26 | Apache-2.0 | read files |
| mtanneer/janestreet.asic.protocol-emulator | 46dace3 | 2026-09-15 | Apache-2.0 | cloned; file list / commit log only (mostly template-sized, no verification files) |
| OliverKlug/sophos-protocol-emulator | aabafcb | 2026-10-01 | Apache-2.0 | cloned; file list / commit log only (mostly template-sized, no verification files) |
| ostrium-labs/ferite | acb2a23 | 2026-10-25 | Apache-2.0 | skimmed (file list, commit log, some files) |
| PankajNair/protocol-emulator-tt | 6d65008 | 2026-10-23 | Apache-2.0 | read files |
| parthDOOM/escapement | eb77584 | 2026-10-27 | Apache-2.0 | read files |
| Parthiv191/JS-ASIC | e2c9ad9 | 2026-10-26 | Apache-2.0 | cloned; file list / commit log only (mostly template-sized, no verification files) |
| pivotvlsi/jane_street_asic_protocol_emulator | 7efc2f7 | 2026-10-11 | none | cloned; file list / commit log only (mostly template-sized, no verification files) |
| Poorvi-007/protocol-emulator-asic | a1d069e | 2026-10-13 | Apache-2.0 | cloned; file list / commit log only (mostly template-sized, no verification files) |
| Raghuveer22/jane-street-protocol-emulator | 005798d | 2026-10-10 | NOASSERTION | cloned; file list / commit log only (mostly template-sized, no verification files) |
| raphaelroshan/jane-street-asic-lab | 3d63d41 | 2026-09-17 | Apache-2.0 | cloned; file list / commit log only (mostly template-sized, no verification files) |
| rimuadmin/ProtoFlex | 79215b6 | 2026-10-10 | none | cloned; file list / commit log only (mostly template-sized, no verification files) |
| Ritikjindal/Protocol_Emulator | 7e2b1b3 | 2026-10-18 | Apache-2.0 | cloned; file list / commit log only (mostly template-sized, no verification files) |
| Rudra-1528/jane-street-asic-emulator | 0f415af | 2026-10-22 | none | cloned; file list / commit log only (mostly template-sized, no verification files) |
| ryanalumkal/protocol-emulator-asic | 717fc7e | 2026-10-20 | Apache-2.0 | skimmed (file list, commit log, some files) |
| rylanmalarchick/protocol-emulator-asic | 233f35b | 2026-10-26 | Apache-2.0 | cloned; file list / commit log only (mostly template-sized, no verification files) |
| Sameerakhatoon/Jane-Street-Protocol-Emulator-ASIC-Competition | (empty repo) | - | none | cloned; file list / commit log only (mostly template-sized, no verification files) |
| sankalpswarup/jane_street_asic_challenge | e02b736 | 2026-10-02 | none | cloned; file list / commit log only (mostly template-sized, no verification files) |
| saper6569/tt06-protocol-emulator-ASIC | ede6f08 | 2026-10-20 | Apache-2.0 | skimmed (file list, commit log, some files) |
| Sashwath-s/ttihp-pinwheel | 90967d1 | 2026-10-27 | Apache-2.0 | skimmed (file list, commit log, some files) |
| satyaammu93/jane-street-asic-2026 | 65e0a74 | 2026-09-19 | Apache-2.0 | skimmed (file list, commit log, some files) |
| semismash/MDA | 41f6db5 | 2026-10-17 | CC0-1.0 | cloned; file list / commit log only (mostly template-sized, no verification files) |
| Seva-Alipov/protocol-emulator-jane-street | 8d0e537 | 2026-10-24 | none | cloned; file list / commit log only (mostly template-sized, no verification files) |
| shaikhmubin02/protocol-emulator-asic | a2454f1 | 2026-10-06 | Apache-2.0 | cloned; file list / commit log only (mostly template-sized, no verification files) |
| shanebri/JaneStreet-protocol-emulator-ASIC-competition | 85506c6 | 2026-10-21 | MIT | skimmed (file list, commit log, some files) |
| sjrai007/gp_pae | 621f432 | 2026-09-15 | Apache-2.0 | cloned; file list / commit log only (mostly template-sized, no verification files) |
| smprather/janestreet-blog-serial-protocol-emulator | fa2bfaf | 2026-10-27 | MIT | skimmed (file list, commit log, some files) |
| soundgod10-droid/protocol-emulator-asic | e806789 | 2026-10-27 | Apache-2.0 | skimmed (file list, commit log, some files) |
| Sp1me/protocol-emulator | 949c59e | 2026-09-17 | Apache-2.0 | cloned; file list / commit log only (mostly template-sized, no verification files) |
| Srujan0006/spex | 5b5ac02 | 2026-10-24 | Apache-2.0 | read files |
| TalentA99/pemu-asic | c1a6920 | 2026-09-18 | MIT | cloned; file list / commit log only (mostly template-sized, no verification files) |
| talsania/protocol-emulator | 6051504 | 2026-10-12 | Apache-2.0 | cloned; file list / commit log only (mostly template-sized, no verification files) |
| TejasDasa/protocol-emulator-asic | 81137ac | 2026-10-06 | MIT | skimmed (file list, commit log, some files) |
| TeslaCoilerOW/ttihp-protocol-emulator | cdec435 | 2026-09-30 | Apache-2.0 | cloned; file list / commit log only (mostly template-sized, no verification files) |
| Tfloow/JaneStreetChip | 18e261f | 2026-09-18 | Apache-2.0 | cloned; file list / commit log only (mostly template-sized, no verification files) |
| theotacconi/openPIO | 63f4d11 | 2026-10-27 | none | read files |
| theworldofobi/pinscribe | 981b47a | 2026-10-23 | Apache-2.0 | cloned; file list / commit log only (mostly template-sized, no verification files) |
| ThomasCliffe27/ASIC_Protocol_Emulator | c454c06 | 2026-10-28 | none | skimmed (file list, commit log, some files) |
| thomasgilbert481/tt_um_loom | 0807004 | 2026-10-25 | Apache-2.0 | read files |
| tusharsingh09/JaneStreetASIC | 9d1a9d1 | 2026-10-22 | Apache-2.0 | cloned; file list / commit log only (mostly template-sized, no verification files) |
| umerimran-10xe/protocol-emulator-asic | f82fda9 | 2026-09-18 | Apache-2.0 | cloned; file list / commit log only (mostly template-sized, no verification files) |
| uoftasic/protocol-emulator | b976406 | 2026-10-24 | Apache-2.0 | cloned; file list / commit log only (mostly template-sized, no verification files) |
| UW-ASIC/TinyTracer | f4631ad | 2026-10-21 | Apache-2.0 | cloned; file list / commit log only (mostly template-sized, no verification files) |
| varun-r-mallya/janestreet-asic-design-contest | 01c3794 | 2026-09-16 | Apache-2.0 | skimmed (file list, commit log, some files) |
| vladov3000/protocol-emulator | d734a1d | 2026-10-19 | Apache-2.0 | cloned; file list / commit log only (mostly template-sized, no verification files) |
| vrindapandeyyy/jane-street-can-you-design-a-chip | a387951 | 2026-10-21 | none | cloned; file list / commit log only (mostly template-sized, no verification files) |
| vuongminh1711/ProtocolEmulatorASIC | 8e70308 | 2026-10-23 | none | cloned; file list / commit log only (mostly template-sized, no verification files) |
| WayneHsieh9/Jane-Street-Protocol-Emulator | 2656ba1 | 2026-10-05 | Apache-2.0 | cloned; file list / commit log only (mostly template-sized, no verification files) |
| wellitsabhinav/MOTIF-Protocol-Motif-Machine | 9e4c500 | 2026-10-14 | Apache-2.0 | skimmed (file list, commit log, some files) |
| WhisperingRock/js_asic_pemu | 9bdc277 | 2026-10-23 | none | cloned; file list / commit log only (mostly template-sized, no verification files) |
| WilliamZhang20/protocol-emulator-compiler | 58c13be | 2026-10-16 | none | skimmed (file list, commit log, some files) |
| WilliamZhang20/protocol-emulator | b837d90 | 2026-09-23 | Apache-2.0 | skimmed (file list, commit log, some files) |
| wsb1994/Gremlin-Board | 16e9128 | 2026-09-30 | Apache-2.0 | cloned; file list / commit log only (mostly template-sized, no verification files) |
| yibeizzZZ/FoRG-protocol-emulator | b027c8f | 2026-10-10 | Apache-2.0 | cloned; file list / commit log only (mostly template-sized, no verification files) |

## 7. Not checked / could not access

- **Coverage of the search is incomplete.** GitHub search caps at 1000 results per query and 30 requests per minute; I hit the limit during the third query batch, and the error text landed in the output of some pages, so some result pages of some queries are missing. Repos that use unusual wording (no "protocol", "emulator", "janestreet", "sg13cmos5l", "ttihp" in name, description or README) are not found. A repo with a name like `chip-project` and no description would be missed.
- ~25 cloned repos were not looked at beyond file listing and commit log because they have only the Tiny Tapeout template files plus RTL under 30 files (their `verif=4` count is the template). Some may have verification hidden inside `test/test.py` that I did not open.
- **Not read in depth** although listed as "skimmed": jeddfadhley (verification doc head and `mutate.py` head only: lockstep, 45 planted bugs, pads compared in both clock halves, which is a detail rather than a technique), ArkaKhorchidian (lockstep head), evan-youan-yu (verification plan table only), soundgod10 (`core_fv.v` head only), shanebri (doc head), wellitsabhinav/MOTIF (verification.md head: preregistered unseen workload with its failing case kept), ostrium-labs/ferite (a Rust hardware toolkit, not an entry), mcranny and 2AMLogic (commit lists only).
- I did not open: `escapement/formal/split_core.py`, `esc_*.sby`, `sw/escert`, `test/mutation/*.py`; `spex/scripts/export_tchecker.py` and `tests/oracles/test_independence.py`; `openPIO/test/formal/*.sby`; `mrnathanhumphrey/model/price_gates.sh`, `gate_mutant_kills.py`, `gate_reset_audit.py`; `PankajNair/scripts/assert_superset.py`, `scripts/signoff.py`. Their descriptions above come from READMEs, docstrings and commit messages ([N]); read them before copying anything.
- Pass counts and "killed N of M" figures in every section are the owners' claims. None was reproduced; none of the scripts was run (instructed read-only).
- Four repos were empty or unreachable: `Highfive1/Jane-Street-ASIC-Puzzle-2026-Solution` (size 0), `kevinroshann/protocol_emulator` (empty), `Sameerakhatoon/...Competition` (empty), `joshvern/pinscript-cmos5l-feasibility` (now 404; it was listed at 2c7a67c on 2026-10-05, so it has been deleted or made private). `misa-hw/janestreet_protocol_emulator_asic` has two files.
- Not GitHub: GitLab, Codeberg, personal sites, Hugging Face, Discord, blog posts, and the competition's own page comments. Private and unlisted repos cannot be seen. GitHub issues, PRs and discussions were left to the parallel `issues-prs.md` sweep.
- Licences are what GitHub's detector reports; a repo showing "none" has no detected licence file (ideas only). `Raghuveer22/jane-street-protocol-emulator` reports NOASSERTION and `pivotvlsi` an empty value.
- Not examined: licence compatibility of embedding (we reimplement in OCaml; every item above is an idea, not a code import). Escapement's `equiv.sh` and openPIO's `netlist.py` are Apache-2.0 and could be used as references with notices kept.
