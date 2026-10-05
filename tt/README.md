# tt/: Tiny Tapeout submission harness

Group A of `notes/learned-from-others.md` (items T1, T2, V28, V32, A12), first step. Nothing here has
been through LibreLane, precheck or any place-and-route; the timing script has only been run on a
metrics file from another project.

## Contents

| path | what |
|---|---|
| `info.yaml`, `src/config.json`, `docs/info.md` | project description, flow configuration and datasheet text; layout and `config.json` from the template |
| `src/project.v` | hand-written wrapper `tt_um_seqv2` (placeholder: 64-word register programme store loaded serially) |
| `src/deadline_sequencer_v2.v` | generated from `prototypes/sequencer-v2/emit2.ml`; never edit |
| `scripts/regen.sh` | `regen.sh` rewrites the generated file; `regen.sh --check` fails if the committed file differs from what Hardcaml generates today |
| `test/` | cocotb test (`make` for RTL, `make GATES=yes` for a gate-level netlist once one exists) |
| `scripts/corner-report.py` | setup and hold slack per corner from a LibreLane run directory |
| `../.github/workflows/tt-harness.yaml` | runs the RTL test; no secrets, read-only token |

Top level: `deadline_sequencer_v2` is the sequencer-v2 core, which group A of `notes/learned-from-others.md` names (sequencer-v2) as the
chip core to harden. No note names a Tiny Tapeout top level yet (there is no
integrated top, see `notes/codex-brainstorm-2026-09-25.md`), so the wrapper is mine and minimal.

## Commands

    tt/scripts/regen.sh --check                 # needs opam switch 5.3.0 with hardcaml
    cd tt/test && uv run --no-project --python 3.12 --with-requirements requirements.txt make
    tt/scripts/corner-report.py <librelane-run-dir>

cocotb 2.0.1 does not build on Python 3.14, hence the pinned interpreter.

## Credits

Ideas and code taken from other public work, by GitHub repository:

- **TinyTapeout/ttihp-verilog-template** (Apache-2.0), branch `cmos5l`, commit b86a2a7: the project
  layout, `info.yaml` schema, `src/config.json` (copied unchanged), and the structure of
  `test/Makefile`, `test/tb.v`, `test/test.py` and `test/requirements.txt`. Files adapted from
  it keep their SPDX identifier and say where they come from. Code copied: `config.json`,
  `requirements.txt`, adapted `Makefile` and `tb.v`.
- **TeslaCoilerOW/ttihp-protocol-emulator** (Apache-2.0): the idea of a check that fails when
  committed generated Verilog differs from its generator (their `make check-generated`), and of
  a 6x4 variant as the fallback size. Idea only; `regen.sh` is our own.
- **joshvern/pinscript-cmos5l-feasibility** (Apache-2.0): the practice of reporting each timing
  corner separately. Idea only; `corner-report.py` is our own. The metric names it reads are
  LibreLane's.

The repository is Apache-2.0 (see `../LICENSE`).
