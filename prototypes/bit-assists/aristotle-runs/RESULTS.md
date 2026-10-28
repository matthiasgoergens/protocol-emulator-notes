# Aristotle on the four bit-assist blocks, 2026-10-28

Each block went up alone, as Verilog emitted by `../emit.exe` (machine-named signals, no comments),
with the English specification in `../aristotle/specs/`. aristotlelib 3.0.0; one run at a time on
this account. Result archives are kept outside the repository (`.gitignore` says why); each run's
`properties.txt` is Aristotle's verdict list. "PROVED" cannot be re-checked here: the archives
hold the property statements and Harmonic's Verilog-to-Lean translation, not the proofs.

| block | run (SGT) | properties | refuted | what the refutation is |
|---|---|---|---|---|
| `stuff_rx` | 11:11-11:32 | 10 proved | 0 | — (see `smoke-stuff_rx-clean/RESULT.md`) |
| `stuff_tx` | 11:32-11:59 | 11 proved | 1 | a contract of the block, unreachable in the chip (below) |
| `line_enc` | 11:59-12:30 | 12 proved | 1 | a gap in our specification (below) |
| `line_dec` | 12:30-12:50 | 9 proved | 1 | our specification too strict (below) |

Among the proved: `keep`/`err`, `need_bit`/`sym`/`line` and `out_valid`/`out_bit`/`err` equal a
reference model of the specification at every cycle, for every input sequence; in USB configuration
no seven 1s on the line, in CAN no six equal bits, and for any run length N no N+1 (from a restart,
configuration held); the Manchester decoder decodes an IEEE 802.3 encoder's output with no error,
and flags equal halves.

**`stuff_tx`: a data bit sent in the restart clock is not counted.** Counterexample: USB
configuration, `restart = 1` with `due = 1` and a data 1, then six more 1s: seven 1s on the line.
The block does what its specification says (restart clears the count; the output rules do not
mention restart). In the chip it cannot happen: `txpath.ml` drives `restart` from `is_idle` and
`due` from `is_data`, two values of the same phase register. It is a contract the block relies on
and nothing states: **never `restart` and `due` in the same clock.**

**`line_enc`: the two Manchester halves differ only while `cfg_invert` is stable across the cell.**
Each half takes its own clock's `cfg_invert`, as our specification says; the consequence we asked
for was stated without that condition. With it, proved. The configuration is static in the chip.

**`line_dec`: `out_bit` is not 0 when `valid = 0`.** Our specification said "all outputs are 0";
the RTL gates `out_valid` and `err` but not `out_bit`. `rxpath.ml` uses `out_bit` only with
`out_valid` (through `Stuff.rx`'s `valid` and `keep`), so it is a don't-care in the chip and the
specification should say so.

Questions Aristotle raised that we have not settled (none left a property unproved): a mode change
in the middle of a Manchester cell keeps the half-finished cell; with `restart` and `tick` in the
same clock the encoder sends the symbol of the state before the restart; either mode with
`cfg_run = 1` sends only stuff bits (already documented in `stuff.ml`). Also noticed while
checking: `rxpath.ml` never restarts its destuffer (`~restart:gnd`) and relies on `in_frame` to
gate dropping; that composition was not part of these runs.
