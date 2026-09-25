# NEXT: where things stand (handoff 2026-09-25 19:30 +08)

**Goal.** An entry to Jane Street's protocol-emulator ASIC competition: IHP 130 nm, 6×4 Tiny
Tapeout tiles, deadline 2027-01-18. Direction (`PLAN.md`, "Direction"): ONE programmable chip.
Every protocol and demo is a programme or configuration of a few generic blocks. Framing: "software-defined
hardware" (Groq's term), led by determinism and compilers (`notes/backlog.md`). Repo:
github.com/matthiasgoergens/protocol-emulator-notes (public, Apache-2.0 since d3de5ae; standing
permission to push master fast-forward).

## Read first
- `notes/architecture-v0.md`: the unified chip, ISA v2 encoding table, area budget, the gaps
  G1–G15 and decisions D1–D15 (merged f89ee80).
- `notes/backlog.md`: everything agreed, including framing, policies and tools to port.
- `notes/jane-street-alignment.md`: their asks, quoted.

## Done (on master, pushed unless noted; latest c3c1602)
- **Protocols in simulation:** UART, SPI, I2C; JTAG and SWD (`prototypes/proto-jtag-swd`);
  PS/2 and CAN (`prototypes/sequencer-ps2-can`); low-speed USB as firmware and as a block
  (`prototypes/usb-ls`); 10BASE-T node with ARP and ping (`prototypes/eth10-node`); bridges and
  Ethernet- or CAN-to-TV (`prototypes/multi-proto`).
- **Blocks:** four-phase pin stage (`prototypes/multiphase`); the unified PE, with an OCaml model,
  Hardcaml RTL and lockstep, 41/41 planted bugs caught, 17/17 cells, 14,359 µm²
  (`prototypes/unified-pe/verify`, e2f7073, G1 closed).
- **Studies:** GPS (`prototypes/gps-hotcold`); FPGA ULX3S bring-up, 18/18 in simulation
  (`prototypes/fpga-ulx3s`); gain cells and tricks (`prototypes/gain-cell`); SRAM corner-cutting;
  rule breaks (`prototypes/rule-breaks`: TT's precheck runs only IHP's main DRC table, so run the
  maximal deck ourselves).
- **Notes:** Jane Street taste; hard-to-program history; systolic prior art (Groq, TPU, Eyeriss).
- **Fix:** 10BASE-T receiver shift-register clear (74562bf); its regenerated Verilog is bad8787.

## In flight: agent worktrees (each on its own branch; merge when a report lands)
All agents were killed by the restart at about 15:05, or later by the usage limit. Status per
worktree (commits ahead of master / uncommitted files):
- `emulator-wt-isa-v2` (9/0): **G2**, ISA v2 interpreter, RTL and firmware ports. It was
  resumed at 19:17 and may still be running; otherwise resume it.
- `emulator-wt-scope` (12/0): beyond-Nyquist scope, compressive inference, K-hypothesis tests.
  Resumed at 19:17.
- `emulator-wt-array-uses` (9/0): problems for the systolic array (Viterbi, Reed–Solomon,
  raycaster, …). Status unknown.
- **Killed, not resumed:**
  - `emulator-wt-mc-thick` (22/0): Monte Carlo of the thick cells;
  - `emulator-wt-periphery` (4/0): gain-cell periphery and pump safety;
  - `emulator-wt-fast-eth` (4/3): IHP pad speed, 100BASE-FX and 100BASE-TX;
  - `emulator-wt-radio-video` (6/1): FM receive to TV, advert detection;
  - `emulator-wt-platformer` (6/0): tile platformer on generic blocks;
  - `emulator-wt-fpga-subslot` (0/9): quarter-clock replay tooling.

  For each: read its README and results, finish or merge.
- `emulator-snap-brainstorm2`: a finished codex brainstorm snapshot; remove it.
- Untracked leftovers of merged worktrees are archived in `/var/tmp/worktree-leftovers/`.

## Open items (evidence in brackets)
1. **Berger code is unsound as specified.** It assumes only 1→0 decay, but stored 0s rise in
   the thin level-shifted cell (the 0 fails first in some Monte Carlo samples:
   `prototypes/gain-cell/tricks-thin/results/mc-*`) and in the all-thick cell (0.5–0.9 V
   within 1 s: `prototypes/gain-cell/tricks-thick/README.md`). A mixed-direction control
   already escapes it (`prototypes/systolic-storage/README.md`). Fix the design, for example
   with a two-sided check or refresh bounds, before presenting it.
2. **Untriaged:** the codex brainstorm's answer, `notes/codex-brainstorm-2026-09-25.md`
   (committed with this handoff, but not yet triaged). Headline: "silicon laboratory" (learn an unknown peripheral, perturb it,
   emulate it). It recommends an SRAM programme store and an agents-programming-the-chip
   experiment with eight unseen tasks.
3. **Gaps from architecture-v0 still open:**
   - G4, NCO colour at 60 MHz through the software TV;
   - G13, whole-chip place and route (heavy; run only when the host is idle);
   - G14, tile reload;
   - G6, G7, G15.
4. **PE definition changes from G1** to fold into architecture-v0: a "follow" bit and
   broadcast chaining (`prototypes/unified-pe/verify/README.md`).
5. **Unanswered questions:** whether to add Ed Kmett (a private contact, Groq) to the private
   outreach notes. Parts ordering: `~/prog/janestreet/fpga-notes/shopping-list.md` (items marked
   "verify" are from memory).

## Rules learnt this session (also in memory or CLAUDE.md)
- **Load:** keep the total load below 32 and aim under 20. At most 3–4 compute agents, each
  with 1–3 jobs; check `uptime` before every launch. 15 parallel agents forced a restart
  (memory `limit-host-load.md`). Much of the current load (~40) is Matthias's other work.
- **Tools and style:**
  - codex via `codex-luna` only (cheap model);
  - DeepSeek off-peak (`deepseek-peak-guard`), with MiMo Flash as a stand-in;
  - prefer OCaml;
  - verify every agent's numbers against its files before relaying them.
- Private material (the people to contact, outreach) lives in
  `~/prog/janestreet/competitor-notes/`, never in the public repo.

## Next actions, in priority order
1. **Collect finished agents and merge:** isa-v2, scope, array-uses. Check their numbers at
   source first.
2. **Triage the codex brainstorm** with a cheap reader, commit it, and fix the Berger-code
   design (open item 1).
3. **Resume the killed studies one at a time** when the load is below 20: first
   fpga-subslot and platformer (light), then radio-video, then the SPICE ones (mc-thick,
   periphery, fast-eth).

## Unverified beliefs
- That array-uses is still running: no notification since 19:17.
- That the fast-eth and radio-video uncommitted files are useful work in progress, not
  scratch.
