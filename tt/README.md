# tt/: Tiny Tapeout submission harness

Group A of `notes/learned-from-others.md` (items T1, T2, V28, V32, A12), first step. `scripts/harden.sh`
has hardened it once, as Tiny Tapeout's ihp-cmos5l action would (2026-10-05, LibreLane 3.1.0.dev3,
6x4 tiles, 20 ns): 9,621 cells, 0 routing DRC, 0 Magic DRC, 0 LVS errors, worst setup slack
+10.39 ns, hold +0.12 ns, in 29 minutes (17 of them Magic DRC). Record in
`../tools/librelane-tt/results/tt-harden/`. That output has been through Tiny Tapeout's precheck
(`scripts/precheck.sh`, all 9 checks pass, 2026-10-06; record in `../tools/librelane-tt/results/tt-precheck/`)
and the gate-level test. The precheck passing says nothing about the design: it checks the
shuttle's geometry and pin rules, and the wrapper is still a placeholder. The timing
script has only been run on a metrics file from another project.

**Since 2026-10-06 the project is the combined chip** (`../prototypes/chip-top`): top
`tt_um_chip_top` in `src/chip_project.v` around the generated `chip_tt` (sequencer, PE array,
pin stage on both clock edges, streamer, sampler, edge sampler, CRC unit, matcher, pin NCO, host
link) with IHP's 512x16 and 1024x8 SRAM macros. `src/config.json` is the template plus the macro
recipe of `../prototypes/chip-top/sram-macro` with the 1024x8 at the right end of the core
(routing congestion otherwise). Hardened at 4 PEs (`CHIP_SIZES=1,1,1,1`, the default): routing
DRC 0, LVS 0, precheck 9 of 9 (`../prototypes/chip-top/results/harden-pe4/`). `make` in `test/`
runs the chip's test (needs `PDK_ROOT` for the macro models). **The earlier sequencer-only
harness stays available**: `variants/seqv2/` (its `info.yaml`, `config.json`, `info.md`; wrapper
`src/project.v`), hardened with `TT_VARIANT=seqv2 scripts/harden.sh STAGE` and tested with
`make CHIP=no`, which is what `tt-harness.yaml` runs in CI. The history below is that harness's.

## Contents

| path | what |
|---|---|
| `info.yaml`, `src/config.json`, `docs/info.md` | the combined chip's project description, flow configuration (template plus the SRAM macros) and datasheet text |
| `src/chip_project.v`, `src/chip_tt.v` | wrapper `tt_um_chip_top`; `chip_tt.v` is build output from `scripts/regen_chip.sh` |
| `src/pdn_cfg.tcl`, `src/RM_IHPSG13_1P_*.v` | the macros' power-grid script (tt_um_loom's) and port-only blackboxes |
| `variants/seqv2/` | the earlier sequencer harness's `info.yaml`, `config.json` and `info.md` |
| `src/project.v` | hand-written wrapper `tt_um_seqv2` (placeholder: 64-word register programme store loaded serially) |
| `src/deadline_sequencer_v2.v` | build output, not committed: generated from `prototypes/sequencer-v2/emit2.ml` by `scripts/regen.sh`, which `test/Makefile` runs on every `make` |
| `scripts/regen.sh` | generates the core's Verilog; rewrites it only when its contents change |
| `test/` | cocotb test (`make` for RTL, `make GATES=yes` for a gate-level netlist once one exists) |
| `scripts/corner-report.py` | setup and hold slack per corner from a LibreLane run directory |
| `scripts/harden.sh` | hardens the project as Tiny Tapeout's ihp-cmos5l GDS action does (tt-support-tools d66cf17, LibreLane 3.1.0.dev3), in a scratch directory, with the pinned image from `../tools/librelane-tt` |
| `scripts/precheck.sh`, `scripts/precheck-controls.sh` | Tiny Tapeout's precheck on a hardened stage, with its KLayout from the pinned image; and copies of the submission with one planted error each, which the precheck must reject |
| `scripts/stage-for-action.sh` | lays tt/ out at a workspace root, as the GDS action needs (see below) |
| `../.github/workflows/tt-gds.yaml` | Tiny Tapeout's own gds, precheck and gl_test actions on tt/, by hand only; read-only token, no secrets; never run on GitHub yet |
| `../.github/workflows/tt-harness.yaml` | generates the Verilog and runs the RTL test; no secrets, read-only token |

Top level: `deadline_sequencer_v2` is the sequencer-v2 core, which group A of `notes/learned-from-others.md` names (sequencer-v2) as the
chip core to harden. No note names a Tiny Tapeout top level yet (there is no
integrated top, see `notes/codex-brainstorm-2026-09-25.md`), so the wrapper is mine and minimal.

## Commands

    cd tt/test && uv run --no-project --python 3.12 --with-requirements requirements.txt make
    tt/scripts/harden.sh /var/tmp/tt-harden/NEW-DIR        # needs tools/librelane-tt/build.sh once
    tt/scripts/precheck.sh /var/tmp/tt-harden/NEW-DIR /var/tmp/tt-precheck/NEW-REPORT   # after harden.sh; about 20 minutes
    tt/scripts/precheck-controls.sh /var/tmp/tt-harden/NEW-DIR /var/tmp/tt-precheck/CONTROLS quick
    tt/scripts/corner-report.py <librelane-run-dir>

The gate-level test is `make GATES=yes` in `test/` with `PDK_ROOT` set and the stage's
`tt_submission/<top>.v` copied to `test/gate_level_netlist.v`.

`make` generates `src/deadline_sequencer_v2.v` first, which needs Hardcaml v0.17 (opam switch 5.3.0
on this machine; `OPAM_SWITCH=` uses the current environment). cocotb 2.0.1 does not build on
Python 3.14, hence the pinned interpreter.

The generated Verilog is not committed, so it can never drift from its source. The Tiny Tapeout
GDS action reads Verilog from `src/` and does not run OCaml, so a GDS workflow has to generate it in
a step before the action, as `tt-harness.yaml` does before the test.

## Does the GDS action need its own repository?

No, but it cannot be pointed at `tt/` either; the project has to be laid out at the workspace root
first, which `scripts/stage-for-action.sh` does and `../.github/workflows/tt-gds.yaml` uses. Read from
TinyTapeout/tt-gds-action, branch ihp-cmos5l, commit 3412659, and tt-support-tools d66cf17:

- The action has no input for a project directory: its inputs are `tools-repo`, `tools-ref`, `pdk` and
  `librelane-version` (`action.yml` lines 8-31). Every step runs in the workspace root and
  names root-relative paths: `./tt/tt_tool.py --create-user-config` (line 90), `--harden` (103),
  `--create-tt-submission` (179), and the uploads `src/*` and `info.yaml` (174, 186, 189).
- `tt_tool.py` itself could be pointed elsewhere: `--project-dir` exists (`tt_tool.py` line 12,
  default `.`), and `Project` reads `<dir>/info.yaml` and `<dir>/src` from it (`project.py` 74-87). But
  the action never passes it; its `TT_ARGS` is only `--ihp` (`action.yml` lines 42-55).
- `tt_tool.py` also needs the project directory to be a git repository with a remote: `get_git_remote`
  and `get_git_commit_hash` call `Repo(local_dir).remotes[0]` and `.commit()` (`project.py` 293-296)
  and `harden` calls both before it starts. A subdirectory of a clone is not that (`Repo` does not
  search parent directories by default).
- The action checks tt-support-tools out at `path: tt` (`action.yml` line 76), which is this repository's
  own `tt/`. Run at the root of a checkout of this repository, that checkout step would put a second
  repository on top of the project.
- The precheck action downloads the `tt_submission` artifact into the workspace root and finds
  `info.yaml` by walking up from the GDS (`precheck.py`, "while not os.path.exists(f"{yaml_dir}/info.yaml")"),
  and the gl_test action reads `test/requirements.txt` and copies the netlist to `test/` of the
  workspace root (`gl_test/action.yml` lines 57, 62, 76).

So the workflow checks this repository out into `repo/`, and `stage-for-action.sh` copies `tt/info.yaml`,
`src/`, `docs/` and `test/` to the root, generates the core's Verilog into `src/`, and makes the root a
throwaway git repository whose remote is this repository's URL (as `harden.sh` does). Checked locally:
in a stage made that way, `tt_tool.py --create-user-config --ihp` at d66cf17 writes the same
`user_config.json` as the stage `harden.sh` hardened. Not checked: the workflow on GitHub. One
consequence of the throwaway root: `commit_id.json` names the stage's commit, not a commit of the real
repository (the stage's commit message gives that one).

## Credits

Ideas and code taken from other public work, by GitHub repository:

- **TinyTapeout/ttihp-verilog-template** (Apache-2.0), branch `cmos5l`, commit b86a2a7: the project
  layout, `info.yaml` schema, `src/config.json` (copied unchanged), and the structure of
  `test/Makefile`, `test/tb.v`, `test/test.py` and `test/requirements.txt`. Files adapted from
  it keep their SPDX identifier and say where they come from. Code copied: `config.json`,
  `requirements.txt`, adapted `Makefile` and `tb.v`.
- **TeslaCoilerOW/ttihp-protocol-emulator** (Apache-2.0): the idea of a 6x4 variant as the
  fallback size. Their `make check-generated` (fail when committed generated Verilog differs from
  its generator) prompted ours; we went further and stopped committing the generated file.
- **joshvern/pinscript-cmos5l-feasibility** (Apache-2.0): the practice of reporting each timing
  corner separately. Idea only; `corner-report.py` is our own. The metric names it reads are
  LibreLane's.

The repository is Apache-2.0 (see `../LICENSE`).
