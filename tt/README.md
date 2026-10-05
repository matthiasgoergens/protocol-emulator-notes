# tt/: Tiny Tapeout submission harness

Group A of `notes/learned-from-others.md` (items T1, T2, V28, V32, A12), first step. Nothing here has
been through LibreLane, precheck or any place-and-route; the timing script has only been run on a
metrics file from another project.

## Contents

| path | what |
|---|---|
| `info.yaml`, `src/config.json`, `docs/info.md` | project description, flow configuration and datasheet text; layout and `config.json` from the template |
| `src/project.v` | hand-written wrapper `tt_um_seqv2` (placeholder: 64-word register programme store loaded serially) |
| `src/deadline_sequencer_v2.v` | build output, not committed: generated from `prototypes/sequencer-v2/emit2.ml` by `scripts/regen.sh`, which `test/Makefile` runs on every `make` |
| `scripts/regen.sh` | generates the core's Verilog; rewrites it only when its contents change |
| `test/` | cocotb test (`make` for RTL, `make GATES=yes` for a gate-level netlist once one exists) |
| `scripts/corner-report.py` | setup and hold slack per corner from a LibreLane run directory |
| `scripts/harden.sh` | hardens the project as Tiny Tapeout's ihp-cmos5l GDS action does (tt-support-tools d66cf17, LibreLane 3.1.0.dev3), in a scratch directory, with the pinned image from `../tools/librelane-tt` |
| `../.github/workflows/tt-harness.yaml` | generates the Verilog and runs the RTL test; no secrets, read-only token |

Top level: `deadline_sequencer_v2` is the sequencer-v2 core, which group A of `notes/learned-from-others.md` names (sequencer-v2) as the
chip core to harden. No note names a Tiny Tapeout top level yet (there is no
integrated top, see `notes/codex-brainstorm-2026-09-25.md`), so the wrapper is mine and minimal.

## Commands

    cd tt/test && uv run --no-project --python 3.12 --with-requirements requirements.txt make
    tt/scripts/harden.sh /var/tmp/tt-harden/NEW-DIR        # needs tools/librelane-tt/build.sh once
    tt/scripts/corner-report.py <librelane-run-dir>

`make` generates `src/deadline_sequencer_v2.v` first, which needs Hardcaml v0.17 (opam switch 5.3.0
on this machine; `OPAM_SWITCH=` uses the current environment). cocotb 2.0.1 does not build on
Python 3.14, hence the pinned interpreter.

The generated Verilog is not committed, so it can never drift from its source. The Tiny Tapeout
GDS action reads Verilog from `src/` and does not run OCaml, so a GDS workflow has to generate it in
a step before the action, as `tt-harness.yaml` does before the test.

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
