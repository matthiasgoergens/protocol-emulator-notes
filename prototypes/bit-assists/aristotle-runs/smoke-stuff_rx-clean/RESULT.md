# Aristotle on `stuff_rx` (the design, no planted fault)

Submitted 2026-10-28 11:11 SGT, finished 11:32 SGT (21 min). Project
6a1ab0c1-6326-4389-861d-9474a160befd, aristotlelib 3.0.0. Input: `upload/stuff_rx.v` as emitted by
`../../emit.exe` at bea3cdb, and `prompt.txt` (`../../aristotle/specs/common.txt` +
`stuff_rx.txt`). The result archive is kept outside the repository, at
`/var/tmp/aristotle-results/stuff_rx-clean/` (see `../.gitignore` for why).

**Verdict: 10 properties, all PROVED, none refuted** (`properties.txt`). Five were stated from
our prompt ("you"), five proposed by Aristotle:

- `keep` and `err` equal the specification's values at every cycle, computed from a reference
  model of the specified state (run count, previous bit) driven by the same inputs: full
  functional agreement, for every input sequence, at every depth;
- `cfg_run = 0` keeps every valid bit with no error; no output without `valid`; a violation
  is never kept;
- protocol scenarios from a frame start: ones mode (USB, HDLC) stuffs after a full run, restarts
  the run after another bit, and restarts after a violation; either mode (CAN) stuffs after a
  full run and a stuff bit starts a run of one.

**What I checked myself.** Its reference model (`Spec/Setup.lean` in the archive) encodes our
specification rule for rule: the full test, "continues the run" in both modes, the restart
values, saturation at 15, restart over a valid bit, `valid = 0` holding the state, `clear`
first. Every property assumes `clear = 1` in cycles 0 to k-1 for some k >= 1 and then holds at
every later cycle with all inputs free, `clear` included. No power-on value is assumed.

**Trust boundary.** The archive holds the property statements and the translation of the RTL
into Lean, but no proofs: "PROVED" is Harmonic's word, not something we can re-check. The
translation is Harmonic's own (`v2l`, no warnings for this module). Compare
`../../results/blocks.txt`: 4 seeds x 1,000,000 clocks of RTL against the OCaml model, the
independent evidence for the same block.
