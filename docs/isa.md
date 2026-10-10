# ISA v2 reference: the deadline sequencer

The sequencer is the chip's processor: four hardware threads that share one programme store and
the pins. This page defines every instruction: its encoding, its fields, what it does, how many
slots it takes, and its edge cases. The definitive text is the executable specification,
`prototypes/sequencer-v2/isa2.ml`. Everything here is checked against it by
`tools/asm/test/docs_drift.ml`: the encoding tables below are parsed and compared bit for bit
with isa2.ml's encoder and interpreter, and every code block that has `; expect:` lines is
assembled and run on the interpreter, with the expectations checked.

The assembly syntax used in the examples is described in [assembly.md](assembly.md).

## Threads, slots and time

Four threads issue round-robin, one instruction per clock in total: thread *t* executes on every
clock congruent to *t* mod 4. A **slot** is one instruction of one thread, so it lasts 4 clocks
(66.7 ns at 60 MHz). **Every instruction takes exactly one slot.** An instruction that waits does
not stall anything: it simply executes again in the thread's next slot, and the other threads are
not affected. So a thread's timing depends only on its own programme and its inputs, and the time
of every pin edge is a count of instructions, which is what makes the static timing verifier
possible ([architecture.md](architecture.md)).

In this page, "slot *s*" of a thread is its *s*-th instruction issue, counted from 0 at the
thread's start. Thread *t*'s slot *s* is clock 4*s* + *t*.

## State

Per thread:

| register | bits | meaning |
|---|---|---|
| pc | 8 | address within the thread's page |
| page | 2 | the page: the fetch address is {page, pc} in one shared store of 1,024 words |
| acc | 8 | accumulator: shift register for SHO and SHI, data for OUT, IN, MBX, LDB, STB |
| cnt | 12 | loop counter: loaded by LDC and CNTA, decremented by SHO and SHI, tested by JNZ |
| dl | 12 | deadline register: loaded by LDD, counts down once per slot to 0 |
| bp | 10 | bank pointer into the 1,024-byte data bank |
| fine, armed | 8, 1 | FINE offset for the thread's next pin write |
| cfg | 8 | bit 7: round-latched inputs; bits 6..0 are exported to the chip, not used by the core |
| lsend | 3 | the channel of the thread's last SEND, for WAITC condition 11 |

Shared: the 8 logical pins' output levels and output enables; the four one-byte inboxes, each
with a full bit; the round latch. Everything is 0 after reset, except each thread's page and pc,
which the host sets ([host-link.md](host-link.md)).

## Encoding

Every instruction is one 16-bit word with the opcode in bits 15..12. Fields are written
`name[hi:lo]` or `name[bit]`; `name[hi:lo]=v` is a field with a fixed value in that form of the
instruction. The last column lists the bits the instruction ignores: a word with any of them set
behaves exactly like the word with them clear (the disassembler prints such a word as `.word`).

<!-- encoding table: parsed by tools/asm/test/docs_drift.ml -->
| opcode | form | fields | ignored |
|---|---|---|---|
| 0 | NOP | | [11:0] |
| 1 | SETP | mask[11:4] val[3] oe[2] q[1:0] | |
| 2 | LDC | imm[11:0] | |
| 3 | LDD | imm[11:0] | |
| 4 | LDA | imm[7:0] | [11:8] |
| 5 | WAITP | pin[11:9] val[8] fail[7:0] | |
| 6 | WAITD | | [11:0] |
| 7 | SHO | pin[11:9] msb[8] od[7] pair[6] psel[5] cap[4] q[1:0] | [3:2] |
| 8 | SHI | pin[11:9] msb[8] quad[7] | [6:0] |
| 9 | JMP | addr[7:0] | [11:8] |
| A | JNZ | addr[7:0] | [11:8] |
| B | OUT | src[11]=0 tag[10:8] | [7:0] |
| B | OUTI | src[11]=1 tag[10:8] imm[7:0] | |
| C | IN | | [11:0] |
| D | SEND | dir[11]=0 ch[10:8] fail[7:0] | |
| D | RECV | dir[11]=1 ch[10:8] fail[7:0] | |
| E | WAITC | cond[11:8] fail[7:0] | |
| F | SKNE | sub[11:8]=0 imm[7:0] | |
| F | SKEQ | sub[11:8]=1 imm[7:0] | |
| F | FINE | sub[11:8]=2 imm[7:0] | |
| F | CNTA | sub[11:8]=3 | [7:0] |
| F | LDB | sub[11:8]=4 | [7:0] |
| F | STB | sub[11:8]=5 | [7:0] |
| F | BANK | sub[11:8]=6 imm[1:0] | [7:2] |
| F | CFG | sub[11:8]=7 imm[7:0] | |
| F | EXT | sub[11:8]=8..15 | [7:0] |
<!-- end encoding table -->

HALT is not an instruction: it is `JMP` to its own address (the assembler's `halt`). BANK's
bits 7..2 are reserved for a bank select if a chip has more banks. EXT sub-operations 8 to 15
are reserved and do nothing.

WAITC's conditions:

<!-- waitc table: parsed by tools/asm/test/docs_drift.ml -->
| cond | name | holds when |
|---|---|---|
| 0..7 | acc0..acc7 | bit *cond* of acc is 1 |
| 8 | byte | cnt[2:0] = 0 (a byte boundary in a bit loop counted by cnt) |
| 9 | host | a byte is waiting from the host (IN would proceed) |
| 10 | inbox | the thread's own inbox (inbox *t* for thread *t*) is full |
| 11 | space | the target of the thread's last SEND has room: inbox lsend empty, or port lsend - 4 ready |
| 12..15 | flag0..flag3 | the thread's flag input *cond* - 12 is 1 (flag inputs 4*t* .. 4*t* + 3 of the chip) |
<!-- end waitc table -->

MBX channels:

<!-- channel table: parsed by tools/asm/test/docs_drift.ml -->
| ch | name | is |
|---|---|---|
| 0..3 | inbox0..inbox3 | the one-byte inbox *ch*, shared by all threads |
| 4..7 | port0..port3 | the array port *ch* - 4: SEND writes segment *ch* - 4's feed register, RECV reads its tap |
<!-- end channel table -->

## Instructions

Each entry gives the assembler form, the effect, and the slots it takes. "Next" means pc + 1;
pcs wrap at 256 within the page.

### NOP — `nop`

Does nothing. 1 slot. (The deadline register still counts down, as in every slot.)

### SETP — `setp MASK, VAL, OE [, q=Q]`

Every pin in MASK gets output level VAL and output enable OE. With OE = 1 the pin is driven at
VAL; with OE = 0 it is released (open drain: an external pull-up or the other side sets the
level). The new level starts at quarter Q of the clock (0..3), on the four-phase pin stage
([architecture.md](architecture.md)); the level the core reports for the clock (its last
quarter) is the new one whatever Q. 1 slot.

```asm
; check: SETP's level, and that each pin write is an edge in its slot
start:
    setp 0x01, 1, 1          ; slot 0: pin 0 high
    nop                      ; slot 1
    setp 0x03, 0, 1          ; slot 2: pins 0 and 1 low
    halt
; expect: pin0 edges at slots 0, 2
; expect: pin1 edges at slots
```

### LDC — `ldc N`, LDD — `ldd N`, LDA — `lda N`

Load cnt (N = 0..4095), dl (N = 0..4095) or acc (N = 0..255). 1 slot each.

LDD sets dl in its own slot; from the next slot on, dl counts down by 1 per slot of the thread
until it reaches 0, whatever the thread executes. This is the deadline: the waits below compare
against it.

### WAITD — `waitd`

Stays (executes again in the next slot) while dl ≠ 0; proceeds when dl = 0. So `ldd N` followed
directly by `waitd` lasts N + 2 slots in all: one for LDD and N + 1 for WAITD.

```asm
; check: ldd N; waitd lasts N + 2 slots
start:
    setp 0x01, 1, 1          ; slot 0
    ldd 5                    ; slot 1
    waitd                    ; slots 2..7
    setp 0x01, 0, 1          ; slot 8 = 0 + 1 + (5 + 2)
    halt
; expect: pin0 edges at slots 0, 8
```

A WAITD with dl already 0 proceeds at once (1 slot). LDD 0 then WAITD lasts 2 slots.

### WAITP — `waitp PIN, VAL [, FAIL]`

Proceeds when logical pin PIN reads VAL. Otherwise, if dl = 0 it jumps to FAIL; else it stays.
With dl = *d* when the WAITP first issues, it proceeds in any slot 0..*d* of the wait in which the
pin reads VAL, or, if the pin never does, jumps to FAIL in slot *d* (its last), so FAIL executes
*d* + 1 slots after the WAITP first issued. FAIL is an address in the thread's page; the
assembler's default is the WAITP itself, so that with dl = 0 it waits for ever.

The pin read is the input as sampled for the thread's clock, or the round latch (see CFG).

```asm
; check: a WAITP that times out: dl = 4 when it first issues, the pin never reads 0
; input: pin1=1
start:
    ldd 4                    ; slot 0: dl <- 4
    waitp 1, 0, late         ; slots 1..5 with dl 4, 3, 2, 1, 0; jumps in slot 5
    setp 0x01, 1, 1          ; (not reached)
    halt
late:
    setp 0x02, 1, 1          ; slot 6 = 1 + 4 + 1
    halt
; expect: pin1 edges at slots 6
; expect: pin0 edges at slots
```

```asm
; check: a WAITP that proceeds at once
; input: pin1=0
start:
    ldd 4                    ; slot 0
    waitp 1, 0, late         ; slot 1: pin 1 reads 0, proceeds
    setp 0x01, 1, 1          ; slot 2
    halt
late:
    halt
; expect: pin0 edges at slots 2
```

A branch after a wait that ended early still sees the remaining deadline: a WAITP or WAITC that
should branch at once needs dl = 0, so put `ldd 0` before it if a deadline may be pending.

### SHO — `sho PIN, msb|lsb [, od] [, pair] [, psel] [, cap] [, q=Q]`

Shift a bit of acc out to a pin. The bit is acc[7] (msb) or acc[0] (lsb); PIN is set to it; acc
shifts by one (left for msb, right for lsb); cnt decrements by 1 (wrapping at 4096). 1 slot.

- `od`, open drain: a 0 is driven low, a 1 releases the pin (instead of driving it).
- `pair`: pin PIN + 1 (mod 8) is written in the same slot, with the complement of the bit (no
  `psel`: a differential pair, 10BASE-T TD±, USB D±), or with `psel` with the next acc bit
  (acc[6] or acc[1]: two bits a slot), and acc then shifts by two.
- `cap`, capture: the partner pin (PIN XOR 1) is sampled in the same slot and its level enters
  the bit the shift vacates next to the new data (msb: bit 0; lsb: bit 7), so one SHO is a full
  duplex SPI bit. With `pair` and `psel` the other vacated bit is 0.
- `q`: the quarter of the clock where the new level starts, as for SETP; ignored with `od`.

`od` and `q` apply to both pins of a pair.

```asm
; check: SHO shifts acc and counts cnt down; JNZ loops while cnt is not 0
start:
    lda 0xA5
    ldc 8
loop:
    sho 0, msb               ; 8 times: pin 0 <- 1 0 1 0 0 1 0 1
    jnz loop
    halt
; expect: at slot 18: acc=0x00 cnt=0
; expect: pin0 edges at slots 2, 4, 6, 8, 12, 14, 16
```

(The first SHO, in slot 2, drives pin 0 from 0 to 1; a SHO that writes the level the pin
already has is not an edge.)

### SHI — `shi PIN, msb|lsb [, quad]`

Shift a pin into acc: msb: acc ← acc << 1 | pin; lsb: acc ← acc >> 1 | pin << 7. cnt decrements
by 1. With `quad` the pin's four quarter-clock samples of the last clock shift in at once, in
time order: msb: acc ← acc << 4 | s0 s1 s2 s3 (s0, the earliest, at bit 3); lsb: acc ← acc >> 4
| s3 s2 s1 s0 << 4 (s0 at bit 4). The non-quad read uses the round latch if CFG enables it; the
quad read does not. 1 slot.

```asm
; check: eight lsb-first SHIs leave the first bit in bit 0
; input: pin2=1
start:
    ldc 8
loop:
    shi 2, lsb
    jnz loop
    halt
; expect: at slot 17: acc=0xff cnt=0
```

### JMP — `jmp ADDR`, JNZ — `jnz ADDR`, `halt`

JMP: pc ← ADDR (an address in the thread's page). JNZ: pc ← ADDR if cnt ≠ 0, else next; cnt is
not changed (SHO and SHI count it down). 1 slot. `halt` is `jmp` to itself: the thread stays
there, one slot at a time, for ever.

```asm
; check: pc wraps at 256 within the page
.org 254
start:
    nop                      ; slot 0 at 254
    nop                      ; slot 1 at 255
.org 0
    setp 0x01, 1, 1          ; slot 2 at 0: the pc wrapped
    halt
; expect: pin0 edges at slots 2
```

### OUT — `out [tag=T]`, OUTI — `outi V [, tag=T]`

Send a byte to the host with a 3-bit tag: acc (OUT) or the immediate V (OUTI). The chip puts
(tag, byte) into its 8-entry HOSTOUT FIFO; the host reads it over the host link. 1 slot; OUT
never waits (a full FIFO drops the byte and sets a sticky status bit, see
[host-link.md](host-link.md)).

```asm
; check: OUT and OUTI
start:
    lda 0x42
    out                      ; slot 1: 0x42, tag 0
    outi 0x07, tag=5         ; slot 2: 0x07, tag 5
    halt
; expect: out 0x42/0 at slot 1, 0x07/5 at slot 2
```

### IN — `in`

If the host has a byte waiting (HOSTIN not empty): acc ← it, it is removed, next. Otherwise
stay. IN has no deadline: to wait for the host with a limit, use `waitc host, FAIL` first.
1 slot per issue.

### SEND — `send CH [, FAIL]`, RECV — `recv CH [, FAIL]`

SEND: if channel CH has room (inbox CH empty, or port CH - 4 ready) it takes acc and the thread
goes on; otherwise, at dl = 0 jump to FAIL, else stay. RECV: if channel CH has a byte (inbox CH
full, or port CH - 4 valid) acc ← the byte, the inbox empties (the port advances), and the
thread goes on; otherwise as SEND. FAIL defaults to the instruction itself, so with dl = 0 a
SEND or RECV waits for ever. Every SEND sets lsend ← CH, whether or not it succeeds. Any thread
may SEND to or RECV from any inbox. 1 slot per issue.

On the chip the ports are always ready for a SEND; a RECV gets a segment's tap word low byte
first, then high byte ([configuration.md](configuration.md)).

```asm
; check: a byte through an inbox: SEND then RECV
start:
    lda 0x5A
    send inbox2              ; slot 1: inbox 2 was empty, takes 0x5A
    lda 0x00
    recv inbox2              ; slot 3: inbox 2 is full: acc <- 0x5A
    halt
; expect: at slot 4: acc=0x5a pc=4
```

```asm
; check: a RECV from an empty inbox at dl = 0 jumps to its fail address
start:
    recv inbox3, empty       ; slot 0: empty, dl = 0: jump
    halt
empty:
    setp 0x01, 1, 1          ; slot 1
    halt
; expect: pin0 edges at slots 1
```

### WAITC — `waitc COND [, FAIL]`

Proceeds when condition COND holds (table above); otherwise at dl = 0 jumps to FAIL, else stays.
With dl = 0 it is a one-slot conditional branch, taken when the condition does *not* hold: there
is no polarity bit. A branch taken when the condition holds is two words, `waitc COND, skip;
jmp TARGET; skip:` (the `bif` macro of `std.inc`).

```asm
; check: WAITC on an accumulator bit as a branch
start:
    lda 0x04
    waitc acc2, other        ; slot 1: bit 2 is 1: proceeds
    setp 0x01, 1, 1          ; slot 2
    waitc acc0, other        ; slot 3: bit 0 is 0, dl = 0: jumps
    halt
other:
    setp 0x02, 1, 1          ; slot 4
    halt
; expect: pin0 edges at slots 2
; expect: pin1 edges at slots 4
```

### SKNE — `skne V`, SKEQ — `skeq V`

Skip the next instruction if acc ≠ V (SKNE) or acc = V (SKEQ): pc ← pc + 2. 1 slot either way;
the skipped instruction takes no slot.

```asm
; check: a skip takes one slot
start:
    lda 3
    skne 4                   ; slot 1: acc is not 4: skip
    setp 0x01, 1, 1          ; skipped
    setp 0x02, 1, 1          ; slot 2
    halt
; expect: pin1 edges at slots 2
; expect: pin0 edges at slots
```

### FINE — `fine V`

Sets the thread's fine offset to V (in 1/256 of a clock) and arms it; the thread's next pin
write (SETP or SHO) carries the offset to the chip's fine-delay output and disarms it. 1 slot.
On prototypes/chip-top the fine delay is not built, so FINE has no effect on the pins there.

### CNTA — `cnta`

cnt ← acc (zero-extended to 12 bits). 1 slot.

### LDB — `ldb`, STB — `stb`, BANK — `bank V`

LDB: acc ← bank[bp], then bp ← bp + 1. STB: bank[bp] ← acc, then bp ← bp + 1. The bank pointer
wraps at 1,024. BANK V: bp ← {V[1:0], acc}: any address in two words (`lda LOW; bank HIGH`).
1 slot each.

```asm
; check: bank pointer, store and load, post-increment
start:
    lda 0xFF
    bank 3                   ; slot 1: bp <- 0x3FF
    lda 0x11
    stb                      ; slot 3: bank[0x3FF] <- 0x11, bp wraps to 0
    lda 0x22
    stb                      ; slot 5: bank[0] <- 0x22, bp <- 1
    lda 0xFF
    bank 3                   ; slot 7: bp <- 0x3FF
    ldb                      ; slot 8: acc <- 0x11
    ldb                      ; slot 9: acc <- 0x22
    halt
; expect: at slot 10: acc=0x22
```

### CFG — `cfg V`

cfg ← V. Bit 7 turns on **round-latched inputs** for the thread: WAITP, SHI (not quad) and SHO's
capture then see the pins as they were on the clock where thread 0 executed in this round of
four clocks, so all threads that set the bit see one consistent value per round. Bits 6..0 are
exported to the chip and not used by the core (prototypes/chip-top leaves them unconnected; its
flag selects are host registers). 1 slot.

## Edge cases, in one place

- **Every slot counts dl down**, not only waits: `ldd 10` followed by ten other instructions
  leaves dl = 0, and a WAITD then proceeds at once.
- **Waits branch only at dl = 0.** A WAITP, WAITC, SEND or RECV with dl ≠ 0 stays; it jumps to
  its fail address only in the slot where dl is 0.
- **cnt wraps**: a SHO or SHI with cnt = 0 leaves 4,095. JNZ does not count.
- **pc wraps at 256** within the page: there is no instruction that changes page; the host sets
  pages ([host-link.md](host-link.md)).
- **LDD is 12 bits**: a computed `ldd N - k` with N - k negative is an assembly error, not a
  wrap to 4,095 (the deadline-sequencer compiler's SPI at period 8 had exactly that bug, found by
  prototypes/formal).
- **IN has no deadline.** WAITC host with a fail address is the bounded form.
- **SEND sets lsend even when it fails**, so `send ch, f` timing out followed by `waitc space`
  waits for room in the same channel. lsend is 0 after reset (inbox 0).
- **Pin writes from several threads**: only one thread executes per clock, so writes never
  collide; the last write to a pin wins. The static verifier checks that a thread's channel
  pins are written by no other thread ([tutorial.md](tutorial.md)).

```asm
; check: every slot counts dl down
start:
    ldd 3                    ; slot 0
    nop                      ; slot 1: dl 3 -> 2
    nop                      ; slot 2: dl 2 -> 1
    nop                      ; slot 3: dl 1 -> 0
    waitd                    ; slot 4: dl = 0: proceeds
    setp 0x01, 1, 1          ; slot 5
    halt
; expect: pin0 edges at slots 5
```

```asm
; check: cnt wraps at 4096
start:
    ldc 0
    sho 0, lsb               ; slot 1: cnt 0 -> 4095
    halt
; expect: at slot 2: cnt=4095
```
