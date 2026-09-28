# NEXT: verified state and next actions

## Goal

Entry to Jane Street's protocol-emulator ASIC competition: IHP 130 nm, 6×4
Tiny Tapeout tiles, deadline 2027-01-18. Direction remains one programmable
chip whose protocols and demos are configurations of generic blocks.

## Current state

- Local `master` contains the `platformer` and `radio-video` merges; commits
  are not pushed.
- `platformer` is merged at `554203d`; `radio-video` is merged at `c1e08db`.
- The platformer branch added the generic-block game study, area comparison,
  RTL/model checks, and local-only still/GIF workflow. Its 285-field game run
  is still executing and no result is claimed yet.
- The radio-video branch adds FM/RDS, advert detection and CAN models. The
  evidence claims were tightened after an independent audit.

## Verified evidence

- Gain-cell storage: `15 passed`; weak row `55/6000` corrupt and flagged;
  promotion performs `248` operations with zero corruption.
- Exact synthesis areas are `1837.987200`, `3082.665600` and `8417.001600
  um^2`; code-inclusive densities are `18.333025`, `9.99458125` and
  `5.57711953125 um^2/payload bit`.
- FPGA focused-control tests pass `5/5` under pytest and unittest. The plain,
  four-phase and planted-fault runs are `22/22 as expected`, with no skips or
  infrastructure errors; quarter VCD timestamps are `11,667,600 ps` and
  `2,200,176 ps`.
- Platformer model/RTL evidence: `0` differing pixels in 20,000 random model
  lines and 240 directed edge lines; RTL checks report zero differences for
  random and directed cases, while three planted faults are caught.
- Platformer timing and palette checks are recorded in `results/timing.txt`
  and `results/palette-compare.txt`; the 143 palette colours differ by at
  most `0.007` full scale.
- Radio advert smoke data is one training and one test seed with an
  eight-minute target; retained timelines are `724-725 s` because the
  generator completes the final programme segment. Video-only accuracy is
  `0.996`; combined `r128_mild` is `0.950`; audio-only is `0.208`.
- Radio CAN replay is `2000/2000` clean frames, `1998` rejected sampled bit
  faults, two harmless delimiter flips and zero wrong accepted frames. The
  sweep excludes the final ten wire bits and does not exercise ACK, EOF or
  missing-stuff-bit faults.
- Radio PE lockstep is `0/20000` normally and `8006/20000` with the planted
  EMA fault, now checking complete transcript lengths.

## Skeptic findings

| Claim | Outcome | Evidence |
| --- | --- | --- |
| Original code-inclusive density figures | Refuted | Rounded synthesis areas were used; `73944f2` replaces them with exact Yosys areas. |
| Weak-bit `0.25` factor | Confirmed | It is physical once; the second profile factor only changes scheduling. |
| Thin tt/85 stored-zero deadline | Confirmed | `106.9 us` versus an `8 us` aggregate deadline. |
| Quarter-control swap behaviour | Qualified | Controls select `SETP q=1` eligibility first; swap feasibility is later, and an unswappable first candidate is an infrastructure error. |
| Radio advert and lockstep wording | Corrected | Eight-minute target, audio-cue, CAN-scope and transcript-length caveats are now explicit. |

## Open items

- Finish or explicitly abandon the 285-field platformer game run; until then
  keep its result unclaimed.
- FPGA quarter replay still has the swap limitation above.
- FM rows retain settings but not code hashes, dependency versions or raw
  samples; the expensive full sweep was not rerun.
- Architecture gaps remain G4, G6, G7, G13, G14 and G15. G13 is whole-chip
  place and route and should run only when the host is idle.
- `.codex/config.toml` has unrelated uncommitted home-configuration changes.
  The requested emulator worktree write profile is already committed in
  `~/git-tracked` as `83e47ad`; do not stage the unrelated remainder.

## Next actions

1. Resolve the platformer 285-field run and record either its checked result
   or a reproducible failure boundary.
2. Re-run the focused FPGA checks after any quarter-control changes, keeping
   the swap limitation visible.
3. Tackle one architecture gap at a time, starting with G4 or G14, and keep
   total host load below 20. That number is a conservative concurrency policy
   from prior restart instability, not a hardware limit.

Local commits are safe; do not push without an immediate explicit
confirmation.
