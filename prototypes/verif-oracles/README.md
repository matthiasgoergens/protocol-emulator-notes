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

Nothing outside this directory was changed when the oracles were written. Other prototypes'
files are used through symlinks, as `sequencer-v2/ports` does, and everything runs on ISA v2
(`../sequencer-v2`). The findings were fixed afterwards (branch fix-findings, 2026-10-05) in their
own prototypes; each entry below says where.

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
| I2C master write (deadline-sequencer demo) | slave clock stretching | **assumed exact timing; fixed 2026-10-05.** The compiled master never read SCL: stretches of 1 to 4 clocks were absorbed, at 1 to 16 clocks 1 of 30 runs differed, and from 1 to 64 clocks all 30 did (wrong bytes, a lost STOP, wrong acks to the host). The compiler now follows every SCL release with a 4095-slot `WAITP` on SCL (below the table). Before and after under the same five patterns: 91 of 150 runs differ before, **0 of 150 after**, up to 2,000-clock stretches | same |
| 10BASE-T TX (sequencer-ethernet) | host byte valid per thread FIFO; the next byte arrives d clocks after the last was taken | **timing-exact, with a 95-clock slack.** Every byte up to 95 clocks late: exact. From 96 clocks the original firmware puts **wrong levels on the line with no indication** (49 of 50 runs with one byte 97 to 200 clocks late; 43 of 50 under random bursts). **Fixed** (below) | `results/stall-ethernet.txt` |
| bridge A (UART ↔ I2C, mailboxes) | already perturbed by its own bench: host gaps, ±1.6 % baud, CTS, slave stretching up to 1,500 clocks | already latency-tolerant by test (12 seeds); not rerun here | `../sequencer-v2/results/ports/multi-proto-bridge_a.txt` |

**The I2C fix** (`../deadline-sequencer/compiler.ml`, `i2c_write`). After each release of SCL the
thread waits for SCL to read high (`LDD 4095; SETP; WAITP scl=1 -> fin`) and times the high phase
from there; at the deadline it releases both lines and halts, so the host gets fewer ack bytes.
The stretch-blind layout with these waits would need 76 words, more than the base ISA's 64, so
the bit loop now puts SDA's change two slots after SCL falls instead of a quarter period. Without
stretching, SCL's period and high time, the ack's sample point and the STOP are unchanged; two
low phases change (after START 28 to 36 clocks, between the bytes 44 to 40), which the oracle
prints. Under stretching the high time measured from the rise is at least 29 clocks (32
nominal), because the rise is seen up to a slot late. Holds of 16,180 clocks are absorbed; holds
of 16,780 end cleanly (lines released, thread halted, acks so far only). The demo, its v2 port
(identical output), multi-proto's bridges (identical) and fpga-ulx3s's I2C tests checked against
their predictions all pass; the board and its Verilator model were not rerun.

**The Ethernet fix** (`stall/eth_fixed.ml`, since 2026-10-05 a symlink to
`../sequencer-v2/ports/sequencer-ethernet/eth_fixed.ml`, where `main_fixed.exe` tests it). A timing-exact transmitter cannot produce an
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

**Merged into the real firmware?** Only where the ISA allows it. `../sequencer-ethernet` and
`../eth10-node` are base-ISA firmware, and the base ISA cannot see whether a host byte is waiting
(IN blocks, and there is no host-valid condition), so the fix needs v2's `WAITC 9`. It now lives
with the v2 port of sequencer-ethernet, whose `main_fixed.exe` runs `main.ml`'s checks on it
(the model, the RTL, the controls) plus a stream cut short that must end released and reported.

**The three other programmes with an IN inside a timed loop** (found by reading; run 2026-10-05):

- **CAN TX** (`sequencer-v2/ports/can/can_fw.ml`, `more`): **confirmed and fixed.**
  `ports/can/can_stall.exe` judges txd clock by clock against the unstalled run, as here. Before:
  byte 5 more than 959 clocks late breaks the frame (20 of 20), random bursts break 17 of 20, and
  a byte that never comes leaves the thread hung with no report. After: `WAITC 9` one slot before
  the IN, and an underrun handler that releases txd and reports `OUT tag_tx 5`. 0 violations;
  the slack drops from 960 to 956 clocks (one slot), as predicted.
- **Low-speed USB** (`usb-ls/firmware.ml`, `dloop`): **confirmed and fixed in the FIFO contract.**
  `usb-ls/stall_fw.exe` slows or bursts the controller's refills, judged by the bench's host.
  Before (RDY = FIFO not empty, depth 4): every session breaks at a 200-clock refill and with
  bursts (undecodable data packets), none at 160. The variant ISA cannot check validity inside
  the loop (dl is the symbol timer, so `WAITP` there waits instead of branching), so RDY now rises
  only when the whole reply is in the FIFO (depth 32; the longest reply is 29 bytes). After:
  0 errors under every pattern, at the cost of NAKs while a reply is buffered.
- **PS/2** (`sequencer-ps2-can/ps2_fw.ml`, `txgo` and `hgot`): **refuted under the doorbell
  contract.** Both INs follow the doorbell pin, which the benches raise only when the byte is
  valid. `sequencer-ps2-can/ps2_stall.exe` delays the byte by up to 2 ms: with that contract
  every run passes in both roles. With the doorbell 500 us ahead of its byte both roles fail: the
  host role sends late bits to a device that is already clocking (wrong bytes, parity errors), and
  the device role loses the host's commands. The device's wait comes before it starts clocking,
  so PS/2 itself tolerates that gap; what fails is consistent with its inhibit and
  request-to-send checks going stale during the wait. 100 us early is absorbed. The firmware is unchanged and the contract is written down
  at `ps2_fw.ml`'s pins type.

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
- The bank addresses of each LDB/STB and the target of WAITC 11, from a data-flow fixpoint
  starting from the reset values: BANK sets the pointer from its immediate and the accumulator
  (tracked as far as LDA's immediate; otherwise all 256 low bytes), LDB and STB step it (with the
  carry into bank 1), and SEND sets `lsend`. A pointer stepped in a loop grows to every address
  the loop could reach, since the loop count is not tracked.
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
| bank address, inbox or port outside the thread's ownership declaration (below) | SOLO (kind, undeclared) missing | yes ×7, plus 4 planted in bridge A and 1 in the bank-reading UART |
| two threads declared to write one bank address, or to use one port in the same direction | OWNERSHIP | yes ×2 |
| a declaration that breaks the inbox rules: a receiver other than the owner, two senders not declared shared, a sender with no receiver | OWNERSHIP | yes ×3, and the declared-shared twin accepted |

46 controls, 46 as expected (`results/hazard-controls.txt`). The controls include accepted
twins, so a checker that rejects everything fails too.

**Ownership of the bank, the inboxes and the ports** (added 2026-10-05, after the isolation
finding of `../formal`). Pins had an ownership discipline; nothing protected the rest. The
declaration, `../sequencer-v2/ownership.ml`, says per thread:
- which bank addresses it may read (LDB) and write (STB), as ranges;
- which inboxes it may send to (SEND, WAITC 11) and receive from (RECV, WAITC 10);
- which ports it may send to and receive from (MBX channels 4 to 7).

Anything not declared is forbidden, and "use" means naming the resource, whether or not the
instruction succeeds. Pins stay in `grants`; a grant of anything else is refused at start-up.
A use outside the declaration is undeclared, which the SOLO table has no entry for, so it is
REJECTED, with the offending addresses named. Two threads declared to write one address, or on
one port in one direction, are rejected before any code is read. A bank address written by one
thread and read by another is listed as a channel, not rejected. The same declaration is
checked by bounded model checking in `../formal` (scenarios e, e-bank) and is the assumption that
makes the UART isolated even when it reads the bank (`../formal/README.md`).

**Rules on the declaration itself** (added 2026-10-05, `Ownership.conflicts` in
`../sequencer-v2/ownership.ml`; the OWNERSHIP rule here and the bounded model checker in `../formal`
apply the same function):
- no bank address may be written by two threads; one thread per port and direction;
- inbox i belongs to thread i, and only thread i may receive from it: WAITC 10 polls the
  executing thread's own inbox, so another receiver could not wait for it;
- an inbox has at most one declared sender unless it is declared shared (a `shared` group on
  `Inbox i`);
- an inbox some thread sends to must be received by its owner.

PAIR already rejects two consumers or two producers that the *code* has; these rules catch the
same faults in a declaration whose code does not (yet) show them, which is what the model checker
assumes of havoc threads. Four controls where only the declaration is wrong (46 in all, all as
expected): T2 declared to receive from T1's inbox; two declared senders of inbox 1 (rejected),
and the same declared shared (accepted); a declared sender of inbox 2 with no declared receiver.
Five earlier controls whose declarations were sloppy in the same ways now also report OWNERSHIP
besides the rule they test. Every real programme's declaration (the demo, 10BASE-T, JTAG and SWD,
bridges A and B) keeps the rules.

The 15 controls added with ownership: LDB inside and outside a declared range, an endless LDB loop, BANK from an
unknown byte, the carry from 511 to 512, overlapping and disjoint write ranges, ports used with
and without a declaration, a port declared to two threads, and WAITC 10 on an inbox not owned.

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
- **Ownership of the bank, inboxes and ports**, declared from each prototype's own description:
  the demo, 10BASE-T, JTAG and SWD own none of them and use none (accepted); bridge A's inboxes
  are T0 → inbox 1 → T1 → inbox 2 → T2, which the code keeps to (accepted). Four violations
  planted in bridge A's real firmware are all rejected: T3 receiving from inbox 2, T3 sending into
  inbox 1, T3 reading the bank, T2 sending to a port. The UART that reads its two bytes from the
  bank is accepted when declared to read 0..1 and rejected at 0 only. Bridge B could not be
  checked: its SPI master's capture (SHX) uses pins 3 and 4, and v2's capture pin for pin 3 is 2,
  which is why only bridge A was ported to v2. **No finding** in the existing programmes.
- **Bridge A on v2:** found 4 rejections, **fixed 2026-10-05** (`results/hazard-bridge.txt`).
  - The I2C master (T1) answered into inbox 2 with `SEND ch2 fail=self` at four places. These
    waits never timed out, and at one of them SCL was held low while it waited. It was safe
    only because T2 (the UART TX) always drains inbox 2, which was accepted under a waiver.
  - `multi-proto/bridge_lib.ml` now answers with `LDD 4095; SEND ch2 -> replylost; LDD 0`: on
    expiry the answer is dropped and 0xFB goes to the host. The `LDD 0` matters: without it the
    byte-code dispatch (`br_set`, a one-slot branch only at dl = 0) waited out the leftover
    deadline, and the first attempt ran ten times slower until the bench caught it.
  - The checker accepts bridge A with no waiver. As a control, the driver rebuilds the old code
    (every SEND to inbox 2 pointed back at itself) and the checker rejects 4 of 4.
  - Bridge tests (v1 and v2) pass and gain "answer deadline A": with T2 stopped, every answer
    beyond the inbox depth is reported and the I2C traffic still matches the reference.
  - **Bridge B fixed 2026-10-05** (`small-fixes`): the SPI master (`spi_master` in
    `multi-proto/bridge_lib.ml`) answers the same way, at its two SENDs (the transfer's reply and
    the protocol error), with `replylost` reporting 0xFB. The checker accepts it with no waiver;
    the control (both SENDs back to fail = self) is rejected 2 of 2. v2's SHX wants the capture
    pin one below the output pin, so the checked copy has SCLK 4, MOSI 3, MISO 2 instead of
    bridges.ml's 2, 3, 4; the code is otherwise the same. `multi-proto/bridges.ml` gains "answer
    deadline B". B has no RTS, so the receiver overflows while the master waits out a deadline;
    the test only requires that T1 goes on and reports lost answers.

**Not checked:**

- the host rewriting a thread's pc at run time (D1);
- self-patching code (usb-ls);
- deadlines met;
- loop counts in the bank pointer analysis (a pointer stepped in a loop covers every address).

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
