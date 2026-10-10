# Held-out protocol test

Jane Street will judge mainly on flexibility: whether the chip can be reprogrammed for protocols it was not designed for. To make that claim checkable, a list of 8 real, documented digital protocols or line codes was chosen on 2026-10-10 by an independent agent that was not shown the prototypes or firmware, so the choice cannot have been tuned to what the design already does well. The agent could read only the top-level README and the notes on other designs.

## Procedure

1. The list (with specification document, version, required roles and an operating point for each) was written as plain text. Its first line is a 32-byte random salt read from /dev/urandom, hex-encoded.
2. The file was stored outside this repository and set read-only. Its SHA-256 is committed here.
3. The list stays unopened until a date chosen by the project owner, before the 18 January 2027 deadline.
4. The hardware will be frozen before the list is opened. Implementing the list may change only firmware, configuration and host software; any hardware change disqualifies the test.
5. At opening, the file is published unchanged; anyone can recompute the hash.

## Seal

- Sealing date: 2026-10-10
- Protocols in the list: 8
- SHA-256 of the sealed file: db9c88fcd21ef2a40f25762f6c7bb9781eecbc05a57633ca4c8d12938a9f938b
