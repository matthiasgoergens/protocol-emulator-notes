# verif-oracles: stall injection, a CRC combine oracle, a hazard case table

Three cheap verification additions, each an idea taken from someone's public work. Credits first:

- **Stall injection with golden transcripts** follows Gergo Erdi's `clash-intel8080`
  (`test/test-sim.hs`). That test draws a random "memory ready" pattern and requires the CPU to
  print the same golden output however its memory and IO stall (`notes/prior-art-erdi-kmett.md`
  §1.4 and item 7).
- **The CRC monoid oracle** follows Edward Kmett's post "Parallel and Incremental CRCs"
  (comonad.com, 2013): a CRC paired with its length is a monoid. The derivation and the code here
  are our own, since the post's code has no stated licence (item 2).
- **The hazard case table** follows Gergo Erdi's typed microcode. There, a type family has one
  clause for each pair of micro-operations that may share a cycle, so a pair with no clause does
  not compile (item 4).

Nothing outside this directory was changed. Other prototypes' files are used through
symlinks, as `sequencer-v2/ports` does, and everything runs on ISA v2 (`../sequencer-v2`).

Build with `opam exec --switch=5.3.0 -- dune build --root .` (Hardcaml v0.17; nothing was
installed). `./run_all.sh` regenerates every file in `results/`. It runs one job at a time,
niced, and waits while the load is above 20. The zlib check uses `uv run --no-project python`
(standard library `zlib`, and libz through `ctypes`).

## 1. Stall injection (`stall/`, `stall-wide/`)

The method is the same throughout. Run once unperturbed to get the golden protocol transcript:
the bytes decoded from the bus, or the line itself for timing-exact protocols. Then perturb every
input that may legitimately be late, at random, and compare the transcript with the golden one.
Interpreter and RTL run in lockstep in every case.

| programme | perturbed input | result | evidence |
|---|---|---|---|
| JTAG host (driver and sampler threads) | host byte valid, bursts of 0 to 39 clocks started with p = 0.02, 0.2, 0.6 or 0.95 per clock (up to 1.4 M stalled clocks) | **latency-insensitive**: 80 sessions; the TDO transcript equals the golden one, and the IEEE 1149.1 TAP models are satisfied. At p = 0.95, 19 of 20 runs hit the bench's own cycle budget, each with a correct prefix | `results/stall-jtag-swd.txt` |
| SWD host | the same host stalls, plus target WAIT with p up to 0.5 (566 retries) | **latency-insensitive**: every packet's ACK, data and parity equal the golden run's. At p = 0.95, 13 of 15 runs ran out of budget with a correct prefix | same |
| UART TX and SPI master (deadline-sequencer demo) | none exists: the bytes are compiled in, and no pin is read | insensitive by construction; the transcripts stay identical under I2C stretching | `results/stall-i2c-stretch.txt` |
| I2C master write (deadline-sequencer demo) | slave clock stretching | **assumes exact timing.** The compiled master never reads SCL. Stretches of 1 to 4 clocks are absorbed (0 of 30 runs differ); at 1 to 16 clocks 1 of 30 runs differs, and from 1 to 64 clocks all 30 do (wrong bytes, a lost STOP, wrong acks to the host). **Documented, not fixed:** the demo's closed-form timing checks depend on this programme. Bridge A's `i2c_master` honours stretching, with a 4095-slot bound | same |
| 10BASE-T TX (sequencer-ethernet) | host byte valid per thread FIFO; the next byte arrives d clocks after the last was taken | **timing-exact, with a 95-clock slack.** Every byte up to 95 clocks late: exact. From 96 clocks the original firmware puts **wrong levels on the line with no indication** (49 of 50 runs with one byte 97 to 200 clocks late; 43 of 50 under random bursts). **Fixed** (below) | `results/stall-ethernet.txt` |
| bridge A (UART ↔ I2C, mailboxes) | already perturbed by its own bench: host gaps, ±1.6 % baud, CTS, slave stretching up to 1,500 clocks | already latency-tolerant by test (12 seeds); not rerun here | `../sequencer-v2/results/ports/multi-proto-bridge_a.txt` |

**The Ethernet fix** (`stall/eth_fixed.ml`). A timing-exact transmitter cannot produce an
identical transcript under every stall, so the specification checked is weaker but explicit:

> The line carries the golden frame, or a golden prefix followed by release (high impedance)
> for the rest of the frame window together with an underrun report to the host. A wrong level
> on the line is a violation.

The original loop has two spare slots per bit. The fix spends one of them on `WAITC 9`
(host byte valid) at dl = 0, two slots before IN. On a miss it branches to a handler that:

- still emits the byte's last bit on time;
- uses `cnt`, loaded with the thread's bit count in the prologue, to tell the end of the
  stream from an underrun;
- on an underrun releases pin 0 and sends `OUT tag 7`.

The fixed firmware is 34 to 36 words per thread, against 28 to 30. Under four stall patterns × 50
seeds it has **0 violations** and the RTL agrees on every clock. The original fails all four
patterns.

The cost is slack: 83 clocks instead of 95. The first check comes 21 slots after the prologue's
IN, not 24; that prediction was made before the measurement.

Controls, all flagged:

- the original firmware;
- the fix without the line release;
- the fix without the report;
- a golden transcript with one half-bit flipped.

**Not run, read only.** A survey of the code found three more programmes whose IN sits inside a
timed bit loop with no valid check. Each would need the same treatment.

- **CAN TX** (`sequencer-v2/ports/can/can_fw.ml:79`): the mid-frame refill `WAITC c_byte; IN`.
  A late byte lengthens a bit.
- **Low-speed USB** (`usb-ls/firmware.ml:197`, `dloop`): IN inside the data-packet loop.
  `usb-ls/controller.ml:14` states the assumption: the reply FIFO must not run dry mid-packet.
  The bench sweeps latency but never `refill` above 160 clocks or depth 1.
- **PS/2** (`sequencer-ps2-can/ps2_fw.ml:77`): the device's IN comes after its "data high"
  check, so a late byte makes that check stale. At line 121 the host-to-device IN runs while
  the device is already clocking.

**Mailbox readiness.** The ports' ready/valid inputs (MBX 4 to 7) are used by no ported
firmware. Inbox readiness is internal: it depends on the neighbouring threads, which bridge A's
bench varies.

## 2. CRC combine oracle (`crc/`)

The identity, from `crc_combine.ml`. R is the direct (non-augmented) register, so
R(s, m) = s·xⁿ + M·xʷ mod P, and R(s, a‖b) = R(s, a)·x^|b| + R(0, b). The catalogue's
`out` map (reflect if refout, then xor xorout) is invertible, which gives

    crc(a ‖ b) = out( (in(crc a) ⊕ init) · x^(8|b|)  ⊕  in(crc b) )   mod P

x^(8|b|) mod P is computed by square-and-multiply, so the combine costs O(log |b|) w-bit
carry-less multiplies.

Results:

- **The identity against the direct CRC** (`refs.ml`'s two textbook loops; all 7 catalogue
  check values reproduced): 3,000 random splits per CRC, 0 failures. The monoid laws (identity
  `(crc "", 0)` and associativity, lengths up to 100,000) hold, and square-and-multiply agrees
  with bit-at-a-time for n ≤ 3,000 and with x^(a+b) = x^a·x^b for a, b < 2⁴⁰.
  `results/crc-maths.txt`.
- **Against zlib 1.3.2**, an independent implementation:
  - 2,000 splits: `zlib.crc32` of the whole message and libz `crc32_combine` both equal ours;
  - 2,000 random pairs with len₂ up to 2⁵⁷, which only the two combines can reach: 0 mismatches;
  - planting two wrong values makes the checker report both.

  `results/crc-zlib.txt`, `results/crc-zlib-control.txt`.
- **Planted faults in the combine.** Each catalogue CRC that the fault affects catches it:
  - shifting by bits instead of bytes: 7 of 7;
  - dropping the init term: 5 of 7;
  - ignoring reflection: 3 of 3 reflected;
  - zlib's formula (shift the first CRC as it stands, xor the second) applied to every CRC:
    exactly IBM-3740 and MPEG-2, the two whose init differs from their xorout. That was
    predicted before the run.

  No catalogue CRC here has refin ≠ refout, so that case is derived but untested.
- **The unified PE, model and RTL in lockstep** (`cells.ml`'s configurations; `results/crc-pe.txt`).
  50 random messages per configuration, each split at a random point. The PE computes both parts
  and the whole, and combine(PE(a), PE(b)) = PE(a‖b), using no direct CRC. 0 failures and 0
  lockstep mismatches in all 10 configurations: CRC-16 on one PE ×4, and CRC-32 on a pair, every
  clock or with gaps and follow, ×3 each.
- **Faults planted in model and RTL together** (`results/crc-shared-faults.txt`).
  `sin_s15_uses_own` fails the identity in the same 6 of 10 configurations as the direct CRC,
  20 of 20 messages each. Lockstep sees nothing. The other five shared faults do not touch the
  CRC path; no configuration fails.
- **The identity's blind spot**, shown rather than assumed (`results/crc-blind-spot.txt`). A PE
  fed each byte's bits in the wrong order computes a genuine CRC of another message of the same
  length. The identity holds in 20 of 20 runs; only the direct CRC catches it, in 20 of 20.
  **The oracle complements the direct reference; it does not replace it.**
- **One CRC split across two array segments**, computed concurrently in one array run
  (`results/crc-split.txt`; 15 splits per CRC, 0 wrong, 0 lockstep mismatches):
  - CRC-16: part a on segment 0 (PE 0, from init), part b on segment 1 (PE 2, from 0),
    bits through the two feed registers in alternate clocks;
  - CRC-32: a on segment 1's pair, b on the first pair of segment 2, bits through the fixed
    ports with independent random gaps;
  - then crc = out(R_a·x^(8|b|) ⊕ R_b) mod P on the host. Starting b from 0 removes the init
    term.

  The multiply by the constant x^(8|b|) mod P was not mapped onto a PE.

Limit: the every-clock CRC-32 pair cannot run an empty message. Its run bit is cleared on the
last bit's clock, so with no bits it never stops. The oracle therefore splits only into
non-empty parts.

## 3. Hazard case table and static checker (`hazard/`, plus drivers in `stall/`, `stall-wide/`, `hazard-mp/`)

No programme verifier existed. `architecture-v0` §8.4 names one. multi-proto §5 states pin
ownership as a condition the compiler must check, but nothing checked it. This is a minimal
static checker over v2 words.

**Discipline**, in two layers:

1. **Compile time.** The decoder and the classifier (instruction → resource uses) are matches
   over closed variants with no wildcard. `hazard.ml` is compiled with warnings 4 (fragile
   match), 8 and 9 as errors. Two checks, both reverted (`results/hazard-compile-controls.txt`):
   a wildcard match fails to compile, and adding a use kind fails in five matches until it is
   classified.
2. **Run time.** Three allow-lists: SOLO (kind, wait class, declared?), PAIR (kind, kind, can
   share a clock?, declared shared?) and COUNTERPART.
   - **A key with no entry is REJECTED**, and the rejection names the key.
   - A reachable reserved EXT operation raises `Unhandled`.
   - Malformed or duplicate table entries raise at start-up.
   - `results/hazard-table.txt` prints every key with its verdict: 64 allowed, 72 REJECTED.

**What is enumerated.**

- Each thread's reachable code, from its boot address, following every branch both ways.
- The bank of each LDB/STB and the target of WAITC 11, from a data-flow fixpoint: BANK's imm[1]
  sets the bank and SEND sets `lsend`, starting from the reset values.
- Clock coincidence: thread t's clocks are t mod 4. Refresh `(bank, period, offset)` and array
  streams (every clock) are declared, and coincidence is decided by gcd.
- Wait classes: a SEND, RECV or WAITC is unbounded when its failure target returns to itself
  through jumps and NOPs. A failure path that ends in a HALT elsewhere has given up, so it counts
  as bounded.

The hazards and how each is caught:

| hazard | how | planted, caught |
|---|---|---|
| two threads driving one pin | PAIR (drive, drive, not shared) missing | yes; also inside real JTAG firmware |
| pin ownership violation | SOLO (drive, undeclared) missing; includes SHO pair wrapping to pin 0 | yes ×3, including behind a JNZ; dead code is correctly ignored |
| read and write on one bank port in one clock | PAIR (bank kinds, same clock) missing | array stream versus STB: yes; other bank: accepted |
| refresh versus access | PAIR (access, refresh, same clock) missing | yes at offset 5 and with period 6 on T2; accepted at offset 2 and with period 6 on T1 (odd clocks never coincide) |
| mailbox SEND to a full inbox with no deadline | SOLO (send or space-wait, unbounded) missing | yes ×3: fail = self, a jump straight back, WAITC 11 spinning; a SEND with a give-up path is accepted |
| two consumers, undeclared producers, a send nobody receives | PAIR and COUNTERPART | yes ×4 |

27 controls, 27 as expected (`results/hazard-controls.txt`). The controls include accepted
twins, so a checker that rejects everything fails too.

**Applied to the existing programmes.** Declarations are written from each prototype's own pin
assignments, not from what the checker infers.

- **deadline-sequencer demo:** accepted.
- **10BASE-T TX, original and fixed:** accepted once pin 0 is declared a four-thread
  time-division group, the one PAIR entry for shared pins.
  - Removing that entry, or the declaration, rejects all 6 thread pairs, so the entry is
    load-bearing.
  - Moving SPI's CS to T0 gives 5 rejections.

  `results/hazard-base.txt`.
- **JTAG and SWD hosts:** accepted (`results/hazard-wide.txt`).
- **Bridge A on v2:** **4 rejections, a real finding** (`results/hazard-bridge.txt`).
  - The I2C master (T1) answers into inbox 2 with `SEND ch2 fail=self` at pc 78, 96, 100 and 103.
    These waits never time out, and at pc 78 SCL is held low while it waits.
  - It is safe today only because T2 (the UART TX) always drains inbox 2. The checker confirms
    that T2 has no unbounded wait other than that RECV. That its JNZ loops end is argued, not
    checked.
  - The run is repeated with an explicit **waiver** carrying that argument. It is printed as
    WAIVED with its reason, never silently.
  - **Fix (not applied; bridge_lib.ml belongs to multi-proto):** `LDD n; SEND ch2 → error` with a
    deadline of one UART byte, the pattern its `scl_rise` already uses.

**Not checked:**

- the host rewriting a thread's pc at run time (D1);
- the bank pointer carrying from bank 0 into bank 1 by post-increment;
- self-patching code (usb-ls);
- deadlines met;
- address disjointness between bank users.

## Review

One adversarial review by another model family (`codex-luna`, read-only), output in
`results/codex-review.txt`. Each point was checked against the code.

- **Right, fixed:** `wait_class` gave up after 8 steps, so a failure path through nine NOPs
  back to the wait counted as bounded. The step limit is gone, and two controls were added: the
  nine-NOP loop is rejected, and a give-up into HALT is accepted.
- **Right, stated:** no refin ≠ refout CRC was tested. The planted "zlib formula" is our
  generalisation of zlib's expression, which agrees with the direct CRC only where init equals
  xorout. `WAITC 9` is not a hazard kind.
- **Checked and rejected:**
  - *"The end-of-stream path can report."* The body's check branches to `under`, whose JNZ on
    `cnt` halts at the end of the stream. Only the prologue's check (the first byte missing at
    start) branches straight to the report, which is intended. Every golden run ends exact with
    no report, and the judge rejects "exact but reported".
  - *"valid/ready only holds while one thread stalls."* Validity is per thread FIFO,
    `next.(t)` and `avail.(t)`, and it changes only on that thread's `host_in_ready`, whichever
    thread runs in between.
  - *"The judge accepts a wrong level followed by release."* `released_after` starts at the
    first mismatching sample itself, so that sample must be released.
