# Issues and PRs of other entries, swept 2026-10-28

Read-only `gh` sweep of 26 repos from `learned-from-others.md` "Sources". Raw JSON listings are in `/var/tmp/sweep-ip/` (`<owner>__<repo>.{i,p}.json`, `summary.txt`). Reading depth: counts for all repos; bodies and comments read for the items listed below; 2AMLogic's 167 issues were scanned by title and about 10 read in detail. Discussions were not queried. No contact from Jane Street staff appears in any thread read.

## Counts (issues / PRs, all states)

| Repo | Issues | PRs | Note |
|---|---|---|---|
| 2AMLogic/sg13cmos5l-protocol-emulator | 167 | 192 | AI-agent fleet ("Loom"); almost all bot or operator authored |
| mcranny/protocol-emulator-asic | 0 | 19 | author's own PRs, Codex bot review |
| umerimran-10xe/protocol-emulator-asic | 0 | 15 | author's own stacked PRs |
| WilliamZhang20/protocol-emulator | 1 | 7 | two outside PRs |
| WilliamZhang20/protocol-emulator-compiler | 0 | 4 | outside PRs |
| LeEmperor/hardcaml_protemu | 0 | 2 | two scaffolding PRs |
| MarcosAsh/protocol-emulator | 0 | 1 | ruff workflow, outside contributor |
| joshvern/pinscript-cmos5l-feasibility | n/a | n/a | repo no longer resolves (deleted, renamed or private) |
| the other 18 repos | 0 | 0 | TeslaCoilerOW, kaikino, kdp1965, smprather, thomasgilbert481, mohammedbala, gigamonster256, elementalcollision, Kanishk234, Lincreased, TejasDasa, dishishshawn, fjpolo, wsb1994, Kleven2k, OliverKlug, TalentA99, sjrai007 |

## 2AMLogic/sg13cmos5l-protocol-emulator

The tracker is an AI-fleet work queue: issues are filed by `rjwalters` (operator) and `loom-fleet-dispatch[bot]` (curator, champion, lease comments). The only non-fleet human is `turian` (Joseph Turian, #41, a one-line README chart embed). It is a process record and a very large catalogue of self-found verification gaps. Base URL `https://github.com/2AMLogic/sg13cmos5l-protocol-emulator`.

- **#244** (2026-10-11, rjwalters): open-drain uio pins drove HIGH for about 100 ps on release under routed delay, because the top file forwarded the core's data bit and relied on `uio_oe` dropping first. Found by the routed-SDF protocol waveform sweep (#217, 46 comments). Fix: tie pad data to 0 on open-drain pins and let `uio_oe` carry the bit. Acceptance required a negative control with the old wiring and an assertion that `oe & out & od` is never 1. Lesson for us: gate-level zero-delay and RTL benches cannot see a glitch that only exists with real delays; if we have any open-drain or tri-state pin, run the SDF-annotated check on it and keep a negative control.
- **#211** (2026-10, DR 0013 F8): the UART loader's count byte is outside the CRC. Flipping bit 0 of the count (`a5 01 f0 00 13 c1` becomes `a5 00 ...`) makes the chip commit one word, take the CRC as the trailer, ACK and RUN a truncated image. Found in review of the loader PR, reproduced on the RTL. Operator ruling: add a complement byte (`A5, N-1, ~(N-1), payload, CRC`). Lesson: a CRC that does not cover the length field is a classic hole; our loader (if any) should be checked with a deliberately constructed alias, not random corruption (random hits it at about 2^-16).
- **#168**: the all-zero image verifies because the CRC of zeros from a zero seed is zero, so a warm start runs 256 NOPs from power-up SRAM. Lesson: pick a nonzero CRC seed or add a magic word; "never run unverified memory" claims fail for the trivial image.
- **#131** (cites the Jane Street organisers' email of 2026-10-09, "Protocol emulator ASIC competition: update and FAQ", asic-competition@janestreet.com): flops do not start at 0, the design must reach a known state from `rst_n`, and a deselected design is powered down and loses state, so the program must be reloaded after reselect. The fleet turned this into target-spec row 14 and verification-plan section 8: random-initial-state or X gate-level run, reset-coverage listing, uninitialised program memory, reselect cycle. Lesson: check we have a power-up-garbage gate-level run and a reselect scenario; the email is the only citable source until the blog post is updated.
- **#97**: the UART reference model's drift check measures only the last transition, so payload 0xFF with a bit period 3% short passes. Lesson: an oracle that depends on the payload's edge pattern gives false assurance; add a frame-end or stop-bit timing bound and a mistimed negative control per payload class.
- **#309, #272, #258, #262**: SPI modes 1/3 sample MISO one core cycle early; the benches pass because the bench peripheral drives MISO 1 ns after the edge and does not model clock-to-output delay. I2C Fast-mode t_LOW had zero margin; ACK was sampled while SCL was low and the stimulus never exercised a late-responding peripheral. Lesson: bench peripherals that are too well behaved hide timing-protocol bugs; model t_V, pull-up rise time (#304) and late ACK.
- **#10**: the CI `gl_test` failed because the gate-level Makefile omitted the PDK UDP file (`sg13cmos5l_udp.v`); the `gds` workflow reported failure at `gl_test` and `viewer` after the build itself succeeded. Same pattern in umerimran #12 below. Lesson: Tiny Tapeout `gds` action failures are often harness gaps (missing sources, flattened and renamed registers), not design errors. Check ours passes `gl_test` with `GATES=yes`.
- **#201, #173, #60, #246**: LibreLane/OpenROAD problems with the SRAM macro: max-slew on macro input pins (A_DIN, A_WEN, A_REN) after ROM changes, max-cap on A_DOUT avoided "by placement, not by construction", PDN unable to reach the Metal4-only power pins of the macro, slow-corner setup margin falling to +1.9 ns. Lesson: any SRAM-macro design should expect slew and PDN fixes; WilliamZhang20/protocol-emulator PR #1 (kdp1965, "Update SRAM PDN stripes + macro location") is the same issue.
- **#273** (open, blocked): asks the organisers whether `info.yaml` must set tiles to 6x4 (the post's "Process" paragraph says so) or whether 2x2 is accepted; the template lists valid sizes without 6x4 and the 2026-10-09 email says "Design to 6x4 until the 8x4 template is out". No answer recorded. Lesson: check our `info.yaml` tile setting against the post wording; ambiguity in the rules is acknowledged by competitors.
- **#44, #45, #242**: a two-key ratification gate (separate bot identities, an "EE key" and a "market key") reviewing the spec. The EE key's first review (2026-10-11) requested changes because DR 0001's central statement "every instruction retires in exactly 1 cycle" and three more claims contradicted the frozen RTL; fixed and approved the same day. Lesson: documented claims drifting from the RTL is the commonest defect they find; they gate on it mechanically.
- Process-hygiene issues worth borrowing: #49/#215/#216 (CI red for a fingerprint reason; reject contradictory or empty JUnit results; gate `gl_test` on repo-owned XML validation); #50 (`! grep -q failure results.xml` always matches `failures="0"`, so `npm run test` always exits 1); #51 (dead `workflow_dispatch` trigger); #53 (hand-enumerated file list skipped 2 of 18 scripts); #231 (pin `tt-gds-action` to a SHA); #257 (in-flow DRC off, so is precheck a sufficient gate); #295 (ten mutant scripts with duplicated runners); #293 (unbounded proof for no-data-dependent latency still open); #152 (independent ISA reference simulator in lockstep); #131; #86 (committed LVS records contained an absolute home path). Lesson: a test that cannot fail (#50) or a CI step that silently skips files (#53) are exactly the "silent no-op" class.

## mcranny/protocol-emulator-asic

19 PRs, all by the owner; reviews are by `chatgpt-codex-connector` (Codex GitHub review bot). PR #19 (V3: 48 MHz time-cursor architecture with SRAM program memory, 2026-10-20) drew P1 findings that matter: host READ replies are stale by one address because the SRAM read data is registered after the reply is captured; the synthesis config defines neither `V3_SRAM_BLACKBOX` nor `FUNCTIONAL`, so the normal Tiny Tapeout build silently synthesises 16 Kbit of flops instead of the macro; the local flow was not migrated to the 48 MHz inputs. PRs #5/#8/#9 gate release on physical and gate-level evidence and electrical signoff (slew); #7 restores routed-netlist simulation with CMOS5L primitive models; #13 adds "independent protocol observers". PR #11 was closed and superseded by a stack of four, with the evidence archived as a release. Lesson: an off-the-shelf PR-time Codex review caught a one-cycle readback skew and a build-config switch that selects the wrong implementation; a macro-vs-fallback `ifdef` is a silent-wrong-design risk, and we should confirm our flow takes the intended branch (count cells or macros in the final netlist).

## umerimran-10xe/protocol-emulator-asic

PR #12 (2026-09-17): the `gds` workflow had been failing at `gl_test` since an earlier PR; the post-layout netlist is flattened and registers are renamed, so a test reaching into `tb.user_project.u_top` raised AttributeError. Fix: that one test skips under `GATES=yes`, all pin-only tests still run on the netlist. PRs #4, #5, #7, #15: reference model with constrained-random checking, timing checks, machine count settled by measurement, and a proof of the edge-capture block at four cursors. PR #2: stop hardening on every push, lint locally. Lesson: tests that peek at internals cannot run on the gate netlist; keep a pins-only subset so gate-level coverage is real, and watch for the workflow being red for weeks unnoticed.

## WilliamZhang20/protocol-emulator and -compiler

Protocol-emulator PR #5 (2026-10-13, owner): fixes three RTL bugs previously documented as known issues: MAP during a running region was dropped (the sequencer moved on while `action_busy` suppressed it), group-E action ops E5/E8/E9/EB/EC wrongly decoded as timer loads and could overwrite a running `START_TIMER` or raise a spurious `EV_TIMER_DONE`, and the compare target was not latched. PR #3: host command B returned the previous SRAM access (off-by-one readback), FIFO port collisions, SRAM readback; slow-corner WNS -0.46 ns from SRAM output into the RX FIFO. Lesson: partial opcode decode (matching only the first nibble) and read-after-read staleness are the recurring RTL bugs across entries (same as mcranny #19). Outside contributions: `jespiron` ("deLEETcode", PRs #7/#8, compiler PRs #3/#4: spatial compiler), `llhtimlam` (#6 spatial architecture proposal), `danielb123456` (compiler #2 assembler encoder, owner invoked `@claude review` and the bot errored), kdp1965 (#1, SRAM PDN stripes). No review threads of substance.

## Others

LeEmperor/hardcaml_protemu #1: owner notes "ASIC verif is so much more involved than FPGA verif; I see why entire teams are dedicated to this stuff"; the project is Hardcaml/OxCaml. MarcosAsh/protocol-emulator #1: outside contributor switched a workflow to ruff (CI pattern only). Dependabot appears in umerimran #1 (pytest bump).

## Top 5 verification lessons

1. Zero-delay RTL and gate-level benches hide real-delay bugs (2AMLogic #244 open-drain glitch, #309 MISO sample timing); run SDF-annotated checks and keep a negative control that reproduces the defect.
2. Oracles with blind spots certify bugs: payload-dependent drift check (#97), bench peripheral with zero clock-to-output delay, a test that always exits 1 or never runs (#50, #53, #315). Add mutation or negative controls per oracle.
3. "Never run unverified memory" style claims fail on the trivial image (all-zero CRC, #168) and on length aliasing (#211); construct the aliasing input, do not rely on random corruption.
4. Power-up and reselect: the organisers' 2026-10-09 email says flops start random and a deselected design loses its state; competitors added random-init/X gate-level runs and a reselect scenario (#131).
5. Registered-read staleness and partial decode are the most frequent RTL bugs (mcranny #19, WilliamZhang20 #3/#5); and `gl_test` in the Tiny Tapeout `gds` workflow fails for harness reasons (missing PDK UDP file, flattened names), so run it ourselves early.

## Outside-contributor and judge interactions

No Jane Street staff comment in any thread. Jane Street appears only as the 2026-10-09 organiser email (quoted in 2AMLogic #129/#131/#273: reset and power, "Design to 6x4 until the 8x4 template is out", 6x4 guaranteed and 8x4 expected mid-October) and the unanswered tile-size question (#273). Outside humans: `turian` (2AM #41), `jespiron`, `llhtimlam`, `danielb123456`, `kdp1965` (WilliamZhang20 repos), `Chanclon` (MarcosAsh). Automated reviewers seen: chatgpt-codex-connector (mcranny), `@claude` action (WilliamZhang20 compiler, errored), 2am-ee-key and 2am-market-key bots (2AM #242).

## Notes

- New repos noticed: none directly. 2AMLogic's fleet references `2AMLogic/2am` (fleet manifest, workspace) and a `klayout-tools` ("klt") tool repo used for DRC/LVS/STA evidence tiers T1; neither is a competitor entry, not chased.
- Unverified: what 2AMLogic's other ~150 issues say beyond titles; some titles are listed above as lessons from titles alone (#315, #295, #293, #152, #231, #257, #86).
