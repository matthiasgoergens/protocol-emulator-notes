# Sequencer ISA v2: interpreter, RTL, lockstep, the landed firmware on it, area

`notes/architecture-v0.md` section 2.1 specifies ISA v2 of the deadline sequencer: one encoding
that reconciles the seven proposals made by six workstreams. Until now it existed on paper only
(gap G2). This directory implements it and checks it:

- `isa2.ml`, the executable specification: assembler, interpreter, disassembler;
- `sequencer2.ml`, the Hardcaml RTL, with 28 bugs that can be planted on request;
- `lockstep2.ml`, random programmes on interpreter and RTL in lockstep, comparing every clock;
- `ports/`, the landed suites of seven prototypes run on v2;
- `synth/`, one Yosys synthesis of the core.

The base prototype (`../deadline-sequencer`) and every other prototype are untouched. The ports
use their files through symlinks.

Build: `opam exec --switch=5.3.0 -- dune build` (Hardcaml v0.17). `./run_all.sh` regenerates
every result file one simulation at a time, niced, waiting while the machine's load is above 20.
`synth/synth.sh` runs the synthesis.

## What v2 is, as implemented

The encoding is the architecture note's table. Where the table leaves a gap, the choice made
here is listed under Decisions and marked D1 to D10 in `isa2.ml`. In summary:

| op | fields | as implemented |
|---|---|---|
| 1 SETP | mask[11:4] val[3] oe[2] q[1:0] | unchanged |
| 2 LDC, 3 LDD, 4 LDA, 6 WAITD, 12 IN | | unchanged; LDA ignores bits 11..8 |
| 5 WAITP | pin[11:9] val[8] fail[7:0] | unchanged, 8-bit fail |
| 7 SHO | pin[11:9] msb[8] od[7] pair[6] psel[5] cap[4] q[1:0] | pair drives pin+1 with the complement (psel 0) or the next accumulator bit (psel 1, shift by two); cap samples pin XOR 1 into the vacated bit; od and q apply to every pin written (D7) |
| 8 SHI | pin[11:9] msb[8] quad[7] | unchanged |
| 9 JMP, A JNZ | addr[7:0] | 8-bit addresses within the thread's page |
| B OUT | src[11] tag[10:8] imm[7:0] | host_out ← (tag, src ? imm : acc) |
| D MBX | dir[11] ch[10:8] fail[7:0] | SEND/RECV on inbox 0–3 (depth 1) or port 4–7; blocks in its own slot; at dl = 0 jumps to fail. HALT is `JMP self` |
| E WAITC | cond[11:8] fail[7:0] | proceed if the condition holds, else at dl = 0 jump, else stay; conditions as the table |
| F EXT | sub[11:8] imm[7:0] | 0 SKNE, 1 SKEQ, 2 FINE, 3 CNTA, 4 LDB, 5 STB, 6 BANK, 7 CFG; 8–15 no operation |

Per thread the state is pc 8, page 2, acc 8, cnt 12, dl 12, bank pointer 10, fine 8 with an
armed bit, cfg 8 and lsend 3. Shared are the pins, four one-byte inboxes with full bits, and the
round latch. The core fetches `{page, pc}` from one external store (the 512 × 16 macro is pages
0 and 1). It reads and writes the data bank through a synchronous port.

## Decisions: gaps in the table, and the fix proposed for it

- **D1 How the host sets page and pc.** The table says "page set by the host". But threads
  that share a page need different start addresses, so a page alone is not enough. Here the
  core loads each thread's `(page, pc)` from host configuration (`boot_page`, `boot_pc`) at
  reset. A write port (`ctl_*`) sets one thread's page and pc at run time. The write wins over
  the thread's own pc update in the same clock, and it is bypassed into the fetch address, so the
  thread's next instruction already comes from there. *Fix:* the programme-store paragraph should
  say "the host writes each thread's page and start pc (at reset, or at run time to restart a
  thread)".
- **D2 BANK, a deliberate deviation from the table's wording.** The table's "set the bank
  pointer's high byte" (keeping the low byte) leaves no way to set the low byte.
  The two 4-kbit gain-cell banks hold 1,024 bytes, so the pointer is 10 bits. Here BANK loads
  `bp ← {imm[1:0], acc}`: any address in two words (LDA, BANK). imm[7:2] are reserved, for a bank
  select if there are more banks. LDB and STB post-increment, wrapping at 1,024. *Fix:* "6 BANK
  imm: bp ← {imm[1:0], acc}".
- **D3 WAITC 11 needs state.** "The last SEND target has space" requires remembering that
  target. Each thread gets a 3-bit `lsend`, set by every SEND whether or not it succeeds, so a
  SEND that gave up at dl = 0 can be followed by a WAITC 11 that waits for space in the same
  target. Channel 0–3 means the inbox is empty; channel 4–7 means the out-port is ready. `lsend`
  resets to 0, so a WAITC 11 before any SEND tests inbox 0. Counting failed SENDs is a choice,
  not something the table forces. *Fix:* name the register, its reset value and "every SEND,
  completed or not" in the table.
- **D4 FINE.** A per-thread offset and armed bit. The thread's next SETP or SHO carries the
  offset out (`fine_out`, `fine_valid`, registered with the pins) and disarms it.
- **D5 CFG.** Bit 7 is the round-latch mode, the only bit the core itself uses. Bits 6..0 are
  exported per thread (`cfg_out`) for the chip's flag-input selects. Four selects of the table's
  six sources need 12 bits, so 7 bits cannot select all of them independently. Either the flag
  selects are host configuration, like the pin map, or CFG's immediate is split. *Fix:* choose
  one; this core does not decide it.
- **D6 Round latch.** With cfg bit 7 set, WAITP, SHI (not quad) and SHO's capture see pin_in
  as it was on the clock where thread 0 executes, for all four clocks of that round. Without the
  bit, a thread sees its own clock's pin_in.
- **D7 SHO's modes together.** od and q apply to both pins of a pair. cap reads the partner pin
  even when pair drives pin+1 (it reads the input pad). With psel 1 the capture enters the
  vacated bit next to the new data (msb: bit 0; lsb: bit 7), and the other vacated bit is 0.
  cnt counts one per SHO in every mode.
- **D8 Flag inputs.** 16 wires into the core, four per thread (bits 4t..4t+3). The selection
  of sources is outside.
- **D9 LDB timing.** The bank is a synchronous SRAM. LDB presents the address in its own clock,
  and the byte enters the accumulator on the next clock. The thread's next slot is three clocks
  later, so it cannot tell. The lockstep shows the in-flight byte as the accumulator during that
  one clock.
- **D10 MBX.** The inboxes hold one byte, the choice in the area estimate. RECV may read any
  inbox, as in multi-proto, not only the thread's own.

**Two costs of the table, measured by the ports.** WAITC has no polarity bit. A branch taken
when a condition *holds* is therefore two words (`WAITC c → skip; JMP l`): one slot when not
taken, two when taken. This affects multi-proto's `br_set` and CAN's JC. WAITC also branches
only at dl = 0: JC ignored the deadline, so every rewritten JC had to be checked for dl = 0.
Both were foreseen in the note; here they were paid, not estimated.

## Verification

**Lockstep** (`lockstep2.ml`, `results/lockstep.txt`). Interpreter and RTL run on random
programmes, filling all four pages, with random boot pages and pcs, random pins, quarter-clock
samples, host input, ports, flags and bank contents, and host control writes at random.
Every clock compares:
- the clock's effects: host byte and tag, host ready, port push and pop, bank write, FINE
  output, cfg output;
- **all** architectural state: pc, page, acc, cnt, dl, bp, fine, armed, cfg and lsend of every
  thread, inbox bytes and full bits, pins, output enables, the quarter-clock view, the round
  latch and the thread counter; and the bank contents.

Results:
- 1,000 programmes × 5,000 clocks from each of two generators, 10 M clocks, **0 mismatches**.
  The *biased* generator favours MBX, WAITC, EXT and SHO's modes, mostly dl = 0 (so waits
  branch) and small immediates (so SKNE and SKEQ match). The *uniform* generator draws random
  16-bit words, as the base prototype's did.
- The coverage table in the same file counts, for 20 programmes, each MBX outcome (done,
  fail-branch, stay, for inbox and port, send and receive), each WAITC condition in each outcome,
  each EXT operation and each SHO mode combination. Every listed case occurs; the totals range
  from 5 (`WAITC 04 stay`) to 1,674 (`MBX recv inbox fail-branch`).
- **28 planted bugs**, one or more per new instruction and mode: 8-bit pc, page, host-control
  bypass, pair and psel, cap, OUT tag and src, SEND, RECV, ports, lsend, WAITC 8, 9, 11 and the
  flag group, SKNE, SKEQ, FINE, CNTA, LDB (three), STB, BANK, round latch (two). The biased
  generator catches every one. The uniform generator catches some far less often: WAITC 8 in 2
  of 30 programmes, SKEQ in 0, STB in 15, the round latch in 3. That is why the generator is
  biased. SKEQ is the weakest catch even when biased (6 of 30), because it needs acc equal to a
  random immediate.

What the lockstep cannot show: that interpreter and RTL both follow the table. Both were written
from one reading of it, so a shared misreading passes. An independent review (codex, Luna model)
of isa2.ml against the table found no field or semantic deviation beyond D2, which is deliberate,
and two readings the table leaves open (D3). It also pointed out that LDB's read address was not
compared directly; it now is (`bank_read`). The ported suites are independent evidence, but only
for the instructions their firmware uses (below).

The controls found two mistakes of mine. Three different planted bugs first failed at the same
clock of the same programme, which pointed to a real mismatch rather than to the bugs. It was
the harness: it set the bank's read data between clock edges, which Cyclesim does not
propagate. The harness now shows the in-flight byte itself (D9). And the STB bug counted as
"caught" only because of that mismatch: it had been declared but never wired into the RTL. A
check that every declared bug is used found it.

## The landed firmware on v2 (`ports/`, `results/ports/`)

Each port runs the prototype's own firmware and its own checks, with the prototype's files
linked in, not copied. Only the ISA and RTL modules are replaced. `ports/shim/isa.ml` keeps the
variant's own assembler (cut from its file by a dune rule) and swaps the interpreter for v2's.
`ports/shim/harness.ml` swaps the RTL. Each word is translated as it is fetched (`compat.ml`),
so firmware that patches its own words at run time still works (usb-ls's controller makes 88
patches in the directed run). The translation, per variant:
- base: HALT becomes `JMP self`; opcodes E and F (NOP in the base) become NOP; operand bits the
  base ignores are cleared, because v2 gives some of them a meaning;
- usb-ls: in addition, SKNE becomes EXT SKNE or SKEQ, the pair bit becomes pair + psel, and
  the event OUT becomes OUT src 1 tag 1.

It is exact except that a base programme falling off its 64th word would continue at 64 instead
of 0; none does. For usb-ls, whose system RTL feeds raw words to the core, the same translation
is also built in hardware (`ports/usb-ls/sequencer_ls.ml`), and the lockstep checks it against
the OCaml one.

| suite | what runs | on v2 | evidence |
|---|---|---|---|
| UART, SPI, I2C (`deadline-sequencer` compiler and demo) | 3 protocols on 3 threads, I2C slave, decoders, edge timing, fault injection, baud sweep | DEMO PASS, output **identical** to the original's | `results/ports/deadline-sequencer-demo.txt` |
| 10BASE-T TX (`sequencer-ethernet`) | all 4 threads, pin against the Ethernet model's encoder, 3 controls, RTL | PASS, **identical** | `results/ports/sequencer-ethernet.txt` |
| JTAG and SWD (`proto-jtag-swd/wide`) | directed and 60 + 40 random sessions, controls, TCK/SWCLK characterisation, the variant's own random lockstep | ALL PASS, **identical** to `proto-jtag-swd/results/wide-all.txt` | `results/ports/jtag-swd.txt` |
| low-speed USB (`usb-ls`) | T0 on the base ISA (13 clock offsets), the whole device T0–T2 with CRC assist and controller: enumeration, 8 random sessions, 4 controls; random-programme lockstep of the variant | FIRMWARE LS DEVICE PASS, **identical** to `usb-ls/run-fw-8seeds.log` | `results/ports/usb-ls.txt` |
| PS/2 device and host (`sequencer-ps2-can`) | 3 scenarios, 6 controls, 16 random runs (18.6 M clocks in lockstep) | ALL PASS, **identical** to `logs/2026-09-25/ps2.txt` | `results/ports/ps2.txt` |
| UART ↔ I2C bridge (`multi-proto`, bridge A) | re-assembled for v2 (below): main run with RTL, 12 random seeds, isolation, controls, budget edges, backpressure | BRIDGES PASS | `results/ports/multi-proto-bridge_a.txt` |
| CAN (`sequencer-ps2-can`) | TX thread re-assembled; RX thread not ported (below) | see below | `results/ports/can-tx.txt` |

"Identical" means the whole output matches the recorded one, line for line: every count, every
cycle number, every turnaround time. `run_all.sh` puts the diff under each result.

**multi-proto, bridge A.** The bridge uses the mailbox variant, whose WAITC has a polarity bit
and whose SHX captures any pin. It was re-assembled with a v2 version of its assembler
(`ports/multi-proto/asm.ml`) behind the same interface, so `bridge_lib.ml` itself is unchanged.
- `br_set` becomes two words.
- "Wait while inbox i is full" becomes WAITC 11. That is valid only when the thread's last SEND
  went to inbox i. The shim checks this at every execution: 56,483 executions, 0 violations.
- The bench is `bridges.ml` cut down to bridge A (`results/ports/multi-proto-bridge_a.diff`).
  Bridge B's SPI master captures MISO on pin 4 while driving MOSI on pin 3, and v2 captures only
  from the partner pin. B therefore needs re-pinning, which is a change to the bridge, not a port.
- Inbox depth is 1 throughout, so the ordering controls (newest first, swapped pair) cannot be
  expressed.
- One control became vacuous. "Receiver over budget by 6 slots" passes at depth 1, because RTS
  holds the host off while the inbox is full. The *original* code at depth 1 passes it too
  (`results/ports/multi-proto-depth1-control.txt`), so this is a property of depth 1, not of v2.
  The budget-edge controls (+4 slots fails) still bite.

**CAN.**
- The TX thread takes a stream that the host has already stuffed and given its CRC, so it needed
  none of the rejected engines. It was re-assembled (`ports/can/can_fw.ml`): CFG 3 became CNTA,
  and each JC was rewritten as a WAITC with its paths swapped, keeping every path's slot count.
- `can_tx.exe` runs our TX-only nodes against the reference CAN nodes, which are the receivers
  (`results/ports/can-tx.txt`).
- The RX thread is **not ported**. It is built on the per-thread CRC engine and stuff tracker
  that v2 rejected. Their v2 replacements are the bit-path assists (architecture-v0 sections 2.3
  and 3): the edge-tracking sampler in NRZ mode with SJW and hard sync (gap G6, not built), the
  stuff tracker (an unverified area probe) and the CRC unit on a flag input. None exists as a
  verified model, so there is nothing to port the RX thread onto yet. Missing: a model and RTL of
  the NRZ + SJW sampler, a destuffer with a violation flag, the CRC unit wired to a flag input,
  and a field-parsing RX thread.

## Area (`synth/`)

Yosys 0.62 in the LibreLane 3.0.14 container, IHP SG13G2 typical liberty, area-mode abc,
flattened. This is the script of `../multi-proto/synth.sh`, whose re-synthesis of the base core
with the same Yosys is the like-for-like baseline. Debug ports removed; programme store and bank
outside.

`synth/synth.sh` has two machine-specific inputs: the IHP SG13G2 checkout under
`/home/matthias/.ciel`, and Docker configuration at `/var/tmp/claude-notes/dockercfg`. Another
machine must point `LIB` and `DOCKER_CONFIG` at its own installations. The IHP toolchain contract
is unchanged: LibreLane 3.0.14, Yosys 0.62 and the SG13G2 typical-corner liberty.

| | µm² | flip-flops | source |
|---|---|---|---|
| base core | 17,263 | 179 | `../multi-proto/results/synth-summary.txt` |
| architecture-v0's v2 estimate | about 30,600 | – | note, section 2.1 |
| **v2 core, measured** | **41,349** | **396** (19,400 µm²) | `synth/reports/deadline_sequencer_v2.stat.txt` |

The v2 core is **35 % over the estimate** and 2.4 × the base core. Most of the gap is state the
estimate did not count. Its "+3,000 for WAITC, the other EXT operations, cap and the ports" has
no room for:
- the per-thread registers that EXT and WAITC need: bank pointer 40 flip-flops, FINE offset and
  armed bit 36, cfg 32, lsend 12;
- the pages (8) and the pending-load register (3).

Those 131 flip-flops are about 6,400 µm² before their write muxes. The core does *not* include
things the estimate's last +2,500 counted: the pin map and the flag-source muxes. Its cfg
registers are part of that item. Ways to shrink it, **not measured**:
- move cfg[6:0] to host configuration outside the core (28 flip-flops);
- give each thread one mode register instead of separate cfg and fine;
- share one bank pointer among threads that do not use the bank at once.

A like-for-like budget line for section 6 of the note is **41.3k, not 30.6k**.

## Open issues

- CAN RX needs the bit-path assists modelled first (above). The v2 CAN therefore has no
  end-to-end receive test.
- Bridge B needs its SPI pins reassigned so that MISO is MOSI's partner.
- Inboxes have depth 1. Ordering faults are untestable, and one budget control became vacuous.
- The table fixes proposed under D1, D2, D3 and D5 should go into `notes/architecture-v0.md`.
- SKEQ's planted bug is caught in only 6 of 30 random programmes. A generator that loads the
  compared value just before would raise that.
- Several new instructions have no evidence beyond the lockstep, i.e. beyond my reading of the
  table: FINE, LDB, STB, BANK, CFG and the round latch, the ports (MBX 4–7), SHO's complement
  pair (psel 0) and its capture. No ported firmware uses them. The first independent use should
  be eth10-node's transmitter with the complementary pair, and a bank-streaming demo.
- No place and route or timing yet; the base core closed 66 MHz with 7 ns to spare.
