# Gate audit, 2026-10-28: can a check report PASS when its tool is absent, crashed or silent?

Idea and method from mrnathanhumphrey-droid/protocol-emulator-asic (Apache-2.0; `docs/redteam/RT1_BUILT.md`
and `model/price_gates.sh`): their red team found gates that scored "tool produced no result" as "mutant
rejected". We borrowed the question, not code (nothing from that clone was executed). Our version of the
method: make the tool absent (PATH stub that exits 0 and prints nothing, `/bin/false`, a stub executable,
or a missing result file), run the check, record whether it goes red.

Inventory: 142 shell scripts, Makefiles and workflow files (excluding `vendor/`, `_build/`, `info.yaml`)
plus the Python judges (`tools/sigrok-judge/judge.py`, `prototypes/formal/sby_report.py`, `tools/asm/test/judge_examples.py`,
`prototypes/*/judge*.py`) and three workflows. About 40 of the shell scripts contain `|| true` or an
equivalent; most of those are regenerators whose result file is read later, which is by design, and are
listed as "not a verdict" below. 12 checks that issue a verdict were measured; 10 of those could report
PASS (or exit 0) with the tool missing and were fixed.

## Measured

Stub dir `/var/tmp/gate-audit-2026-10-28/stub-empty/` holds `opam podman docker yosys sby z3` that exit 0
silently. Logs: `/var/tmp/gate-audit-2026-10-28/logs/`. "Before" is the HEAD~6 script (master).
Result files the scripts overwrite were restored with `git checkout` after each run.

| Check | Tool(s) | Tool absent, before | After | Bash-specific failure mode? | Commit |
|---|---|---|---|---|---|
| `tt/scripts/precheck-controls.sh` | podman, precheck venv | exit 0, "control pin-name: precheck exit 2 (rejected, as it should be)" with no report at all | exit 1, "NOT RUN: no failed check in a report" | yes: `\|\| status=$?` then non-zero read as "rejected" | bf23c7d |
| `prototypes/multiphase/isa_controls.sh` | opam/dune | exit 0, blank lines for all four runs | exit 1 | yes: `grep \| ... \|\| true` swallowing the tool and the grep | 296c1b4 |
| `chip-top/formal/arith_equiv/run.sh` | podman, yosys | exit 0 (exe stubbed) | exit 1 | yes: `\| grep ... \|\| true` | baa9bb0 |
| `chip-top/formal/edge_step_equiv/run.sh` | podman, yosys | exit 0 | exit 1 | yes: same | baa9bb0 |
| `tools/asm/run_all.sh` | opam/dune, exes | exit 0, empty summary lines, "exit 127" only inside the result file | exit 1 | yes: `{ ...; echo "exit $?"; } > f \|\| true` | 13cae15 |
| `prototypes/spdif/run_all.sh` | opam/dune | printed "checks failed" but exit 0 | exit 1 | yes: same pattern, message without status | 13cae15 |
| `prototypes/verif-oracles/run_all.sh` | opam/dune | exit 127, but only because one unguarded line (`zlib-vectors`) fails; five suites had "wrote ...: " (empty) and recorded exit 127 | still exits (127 from that line) and now also exit 1 from the per-suite check | yes: same pattern | 13cae15 |
| `prototypes/formal/run_all.sh kind2` | kind2 | exit 0, results/kind2.txt holding only a header | exit 1, "NOT RUN: no Kind 2 verdict" | yes: `\| grep ... \|\| true` | 1eb4a94 |
| `prototypes/formal/report.sh` | (reads result files) | one result file present, three missing: exit 0, summary of the one file | exit 1, "NOT COMPLETE" | partly (a missing file printed as "(no result file)" and ignored) | 1eb4a94 |
| `tools/sigrok-judge/judge.py --only X` | podman, sigrok | typo in `--only`: "ALL CHECKS PASS", exit 0, zero cases run | exit 1, "NO CASES RUN (NOT PASS)" | no (Python) | 2c1430c |
| `prototypes/chip-top/suite.sh quick` (CI) | lockstep.exe, edge_phase.exe | stub exes that exit 0 and print nothing (apart from the coverage line): exit 0 | exit 1 on the first silent step | yes: `grep ... \|\| true` after the tool | 2c1430c |
| `tools/sigrok-judge/judge.py` (normal) | podman, sigrok-cli | missing trace: FAIL (measured, exit 1); sigrok-cli failure raises | unchanged | no | none needed |

Not measured for the normal case (needs the opam build, PDK or minutes of CPU): the after-state of the
passing path is read from the diffs and the committed result files (`exit 0` and a non-comment line present
in every committed result file of asm, spdif and verif-oracles; `report.sh` on the real results exits 0 with
61 PROVED, as before).

## Read only, not run, not changed

| Check | Tool-absent behaviour (read) | Bash-specific? |
|---|---|---|
| `formal/equiv/run_equiv.sh` | docker/yosys missing gives status ERROR (not PROVED) and exit 0, because of `\|\| true` | yes |
| `formal/powerup`, `formal/uart-miter`, `chip-top/formal/run_array_powerup.sh`, `verifier/rtl/run_rtl.sh` | `sby \|\| true`, verdict from `sby_report.py` (UNDECIDED, never PROVED, when the log is empty) but exit 0 | yes |
| `formal/sby_report.py` | prints UNDECIDED/ERROR, exits 0 unless an assertion lacks an antecedent cover; labelled, not a false pass | no |
| `verifier/run_all.sh`, `verifier/kernel_z3.sh` | `run()` propagates failure; `kernel_z3.sh` counts `COUNTEREXAMPLE` lines with `grep --count \|\| true`, so zero lines from a crashed solver reads as zero counterexamples (needs a look) | yes |
| `sequencer-v2/run_all.sh` | same `\|\| true` + "exit $?" in file pattern as the fixed run_all scripts; measured red only incidentally (exit 1 with stubs) | yes |
| `rule-breaks/drc/run.sh`, `gain-cell-macro/{drc,lvs,magic_drc}.sh` | `\|\| true` then grep for a verdict; empty verdict prints nothing, no PASS word, but also no failure | yes |
| `eth10-node/run_demo.sh` | controls: `host check ... \|\| true`, then `grep verdict` (fails under `set -e` if absent) | yes |
| `chip-top/synth/collect_harden.sh`, `pe-synth/pnr/run_pnr.sh`, other pnr scripts | collectors and flows, not verdicts | - |
| `.github/workflows/tt-harness.yaml` | `test -s results.xml && ! grep failure`: a cocotb run that collected zero tests would pass | no |
| `.github/workflows/tt-gds.yaml` | delegates to TinyTapeout actions | no |
| `.github/workflows/chip-top.yaml` | runs `suite.sh quick` (fixed above) | - |
| `tt/test/Makefile` | cocotb; same zero-test caveat as tt-harness | no |
| `tt/scripts/precheck-controls.sh` | untested with the real tool: a control that makes precheck.py raise (no results.md) now counts as NOT RUN; run `full`/`quick` once to see that all five controls still produce a ❌ row | - |

## Commands

```
S=/var/tmp/gate-audit-2026-10-28; export PATH=$S/stub-empty:$PATH      # stubs: exit 0, no output
bash prototypes/multiphase/isa_controls.sh; bash tools/asm/run_all.sh; bash prototypes/spdif/run_all.sh ...
# before-versions: git show HEAD~6:<path> > scratch copy; fake stage for precheck-controls:
#   $S/fakestage/{info.yaml,tt/,precheck-venv/bin/python (exit 0)}
# kind2: scratch copy of formal/ with a stub main.exe, KIND2=/bin/false, ./run_all.sh kind2
# report.sh: scratch git repo with only results/bmc.txt
# suite.sh: scratch copy, stub lockstep.exe/edge_phase.exe printing only the coverage lines
# judge: tools/sigrok-judge/judge.py --only nonesuch
```

## Where a structured runner (one Python/uv runner) would remove the most

Ranked by how much of the failure surface it removes: explicit PASS / FAIL / NOT RUN per check, required tools
and output files declared, a freshness check (result newer than the inputs and the tool).

1. The `run_all.sh` family (asm, verif-oracles, spdif, sequencer-v2, verifier, formal): all re-implement
   header + `{ cmd; echo "exit $?"; } > file || true` + a `grep` summary. A runner replaces them wholesale and
   makes exit status the recorded verdict.
2. The sby/yosys wrappers (`equiv`, `powerup`, `uart-miter`, `run_array_powerup`, `run_rtl`, the two chip-top
   equivalence runs): `tool || true` then parse. A runner declares "needs podman image X, produces log Y,
   verdict = parsed line Z" and turns a missing log into NOT RUN.
3. `precheck-controls.sh` and `isa_controls.sh` and other mutant/control checks: "tool failed" and "tool
   rejected the mutant" must be different outcomes; a runner types them differently.
4. `report.sh` and `kind2` glue: freshness (stale results/*.txt from an earlier run reads as current) is
   unaddressed even after these fixes and needs the runner.
5. `suite.sh`: already structured, but its markers are free-text greps; a runner would declare them.
6. The DRC/LVS scripts under gain-cell-macro and rule-breaks.
7. Python judges and CI workflows gain least; they are already explicit.

Not addressed anywhere in the repository: stale result files (nothing compares a result's date or commit with
the tool or inputs that should have produced it).
