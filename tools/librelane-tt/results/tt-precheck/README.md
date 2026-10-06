# Tiny Tapeout precheck of tt/ (2026-10-06)

Input: `tt_submission/` of the hardened stage `/var/tmp/librelane-tt/tt-harden-1` (harden record in
`../tt-harden/`), made by `tt_tool.py --create-tt-submission --ihp` at tt-support-tools d66cf17.
sha256: `tt_um_seqv2.gds` 7edf0ad8cbde83286c53e22d71d26119b523b38a51a430bec0a44ac6bb8e6410,
`.lef` 23f198a9a113fd0a932976b54ef196c749c65da2937a68e504b58043391fb7ea, `.v`
bf3b72f167878adacda70ac70bd415ebdaf3c20bc169142a0b92ea1b2148df37. Command:
`tt/scripts/precheck.sh /var/tmp/librelane-tt/tt-harden-1 /var/tmp/librelane-tt/precheck-1`; KLayout 0.30.9
from the pinned image (the action's Nix environment has 0.30.4), PDK IHP-Open-PDK 2bbec755.

- `real/`: `results.md`, `results.xml`, `precheck.log`. Nine checks, all pass; the SG13CMOS5L KLayout DRC
  took 1,122 s (the other eight under 3 s together).
- `controls-quick/`: five planted errors (LEF pin renamed, shape outside prBoundary, TopMetal1 drawing,
  renamed top cell, unlisted layer), each rejected by the intended check. The ~19 min KLayout DRC deck was
  switched off in the scratch copy of `precheck.py` for these, so they say nothing about the deck.
- `controls-full/drc-sliver/`: the unmodified precheck on a copy with a 0.05 um Metal1 sliver; the deck
  rejects it (9 violations). So the deck can fail on this GDS, and the clean run is not vacuous.
- `gl-test/`: gate-level cocotb test (`make GATES=yes`) on `tt_um_seqv2.v`, 2 of 2 pass.

What this does not show: the wrapper `tt_um_seqv2` is a placeholder, so a pass is about the shuttle's
geometry and pin rules, not about the design.
