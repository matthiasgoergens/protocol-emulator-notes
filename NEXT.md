# NEXT: browser video exports and quarter-grid evidence

## Goal

One programmable chip for the protocol-emulator competition: protocols and
demos are configurations of generic blocks. Architecture and brainstorm
decisions remain in `notes/architecture-v0.md` and
`notes/codex-brainstorm-triage.md`.

## Current state, 2026-09-30

- Current branch is `tv-demo-videos`, based on `fd16953`. Its new work is
  `demos/tv/export.py`, the gallery template and README. Five checked MP4s
  and a 17.37 MB portable gallery ZIP are local in `demos/tv/out/`, ignored
  by Git. The manifest records 120/540/540/48/300 fields and all hashes.
  Existing-output refusal was tested (exit 2); full exports and ZIP checks
  passed (exit 0). No browser was connected for playback UI testing.
- The platformer's rendered fields are absent; its retained result remains
  below. Do not present a host preview as a new RTL capture.
- `g4-video-judgement` was pushed to origin at `fd16953`, verified by
  `git rev-parse origin/g4-video-judgement`. The user explicitly authorised
  commits and pushes this session. No video-host upload or deployment occurred.
- G4 work was on `g4-video-judgement`, based on `cf0f3f1`.
  `34a39ef` preserves the exploratory run; `e6b7316` records the corrected
  experiment, observations, decoder option and architecture updates.
  `master` remains at `cf0f3f1` (`git rev-parse master`).
- Both full corrected experiments finished. `analyse.py` exits 0 and
  verifies every individual observation and carrier RTL sample against a
  fresh-process confirmation. See `prototypes/video-nco/results/summary.md`.
- No experiment or review from this session remains in flight.

## Measured evidence and limits

- Carrier-only RTL: 10,000 clocks per standard, zero wrong nibbles or phase
  bytes. Swapped quarters differ in 370 PAL and 285 NTSC clocks. Samples
  and counts: `prototypes/video-nco/results/*-rtl.txt` and `rtl.json`.
- Quarter-grid NTSC: 46.64–47.02 dB picture PSNR, maximum bar-centre hue
  error 1.339–1.492°, four of four phases meet the declared 35 dB/2° target.
- Quarter-grid PAL: 45.65–45.71 dB, hue error 2.137–2.223°, zero of four
  phases meet the 2° target. G4 remains open. Individual measurements,
  dependency versions and source hashes: `results/observations.json`.
- The hue-offset and amplitude paths, DAC/filter and phase-stage connection
  are behavioural. The existing NCO has no hue-offset input. The reference
  is sinusoidal, so error includes square-wave harmonics and gating as well
  as temporal quantisation (`prototypes/video-nco/README.md`).
- Ideal-carrier phase calibration also has picture sensitivity: at 3/8
  cycle, PAL is 32.96 dB and NTSC 30.49 dB against phase zero. Each NCO is
  paired with its own same-phase reference, not with phase zero.
- G14 is narrower than the old note claimed: bitmap-only S reload renders
  256/256 pixels, with pixel gaps and segment-mates that do not use S.
  Per-tile K/colour reload remains open (`unified-pe/verify/README.md`).

All paths in the video evidence bullets are under `prototypes/video-nco/`
unless a different prototype is named.

## Refutations and review

- Initial PAL collapse was partly a decoder artefact: absolute burst phase
  was confused with alternating V sign. Optional burst-pair tracking passes
  512 synthetic sign/rotation cases; the old rule misses 256. Existing
  callers keep the old default. Nominal phase-zero PNGs match the first run.
- Exact-integer detected sync crossings were an invalid judge criterion.
  The revised margin is a paired 1-clock difference, introduced after the
  exploratory run; quarter-grid maxima are 0.0064 PAL and 0.237 NTSC clocks.
  This supports relative timing, not absolute TV lock or compliance.
- Two cheap subagents reviewed the carrier recurrence, judge, decoder
  correction, final data and prose. Concerns remain in
  `prototypes/video-nco/review.txt`, including noisy bursts, decoder phase
  sensitivity and the missing hardware path. No headless cross-model review
  was run; the codex skill requires explicit per-run permission.
- Berger safety claims in the old architecture are historical. The storage
  prototype has mixed-direction modelling and shortened extended-Hamming
  checks (`prototypes/systolic-storage/README.md`); the compiler note still
  needs reconciliation. The backlog now marks its running tags as historical.

## Earlier evidence and open items

- Platformer retained run: 285 fields, 68,400 lines, zero different pixels
  in 2,452 s (`prototypes/platformer/results/game.txt`); not rerun here.
- FPGA retained evidence: five unit tests, focused replay 6/6, full runs
  22/22 expected (`prototypes/fpga-ulx3s/evidence/2026-09-28-control-fix/README.txt`).
  Quarter-swap eligibility/feasibility limitation remains; not changed here.
- FM provenance and CAN fault-scope limitations remain documented in
  `prototypes/radio-video/README.md`; no full sweep rerun this session.
- G6, G7, G13 and G15 remain architectural integration work. G13 whole-chip
  place and route should run only when the host is idle. Keep host load below
  20, a conservative concurrency policy rather than a hardware limit.
- Preserve the fast-eth, mc-thick and periphery worktrees and unrelated
  generated artefacts. Do not stage unrelated home-configuration changes.

## Next three actions

1. Use a finer-grid square reference to separate PAL's remaining carrier,
   gating and burst-estimation error from temporal quantisation.
2. Implement the hue-offset/amplitude path and check it through the actual
   pin stage, keeping the analogue/pad questions explicit.
3. Design a safe per-tile K/colour reload for G14; state-only reload does
   not resolve the configuration-chain hazard.

Local commits are safe. Never push without immediate explicit confirmation.
