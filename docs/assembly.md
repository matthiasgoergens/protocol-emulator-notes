# The assembly language and the toolchain

`tools/asm` is the chip's toolchain: an assembler for the sequencer's ISA v2 with directives for
the rest of the chip, a disassembler, a driver for the static timing verifier, and a runner that
executes an image on the ISA interpreter and on the chip's specification and RTL. This page is
the manual. The instruction set is in [isa.md](isa.md), the configuration directives in
[configuration.md](configuration.md), and [tutorial.md](tutorial.md) walks through a new
protocol from its datasheet to a verified, running image.

## Building and running

    cd tools/asm
    opam exec --switch=5.3.0 -- dune build --root .     # Hardcaml v0.17
    _build/default/bin/asm.exe examples/uart_tx.s -o uart_tx.hlk --listing - --verify
    _build/default/bin/run.exe uart_tx.hlk --clocks 2500 --vcd uart_tx.vcd --sr uart_tx.sr

`asm FILE.s` writes the image (default `FILE.hlk`), the exact byte stream a host sends over the
host link ([host-link.md](host-link.md)). Options:

- `-o IMAGE`; `-I DIR` adds an include directory (`tools/asm/lib` is always searched);
- `--listing FILE` writes every word with its page, address, encoding, disassembly and source
  line (`-` for standard output);
- `--verify` proves every `.timing` block with the static verifier and prints the verdicts;
  `--certs DIR` also writes each timing certificate; the exit status is 1 if a block is not
  proved;
- `--disasm IMAGE [--layout A,B,C,D]` prints an image as source that reassembles to the same
  bytes; `--roundtrip FILE.s` checks that for one source.

`run IMAGE` runs the image on the ISA v2 interpreter and on the chip (the chip's executable
specification and its RTL in lockstep, compared on every pad on every clock), and requires the
two to put the same levels on the pins, clock for clock, and to execute the same OUTs at the same
clocks. Options: `--isa` or `--chip` for one of them, `--no-rtl`, `--clocks N`, the outside world
(`--peer`, `--stimulus`, `--hostin`, below), and waveforms: `--vcd FILE` (Surfer, GTKWave),
`--sr FILE` (a sigrok session that PulseView opens), `--sigrok FILE` (raw: one byte per clock,
bit *k* = net *k*, as `tools/sigrok-judge` reads).

## Lines

    label:  mnemonic operand, operand, key=value   ; comment

A line has optional labels, then one statement: an instruction, a macro call, a directive
(`.name`) or an assignment `NAME = expression`. Comments run from `;` to the end of the line.
Names are letters, digits and `_`, not starting with a digit. A label is the address of the next
instruction in the current page; in expressions it stands for that pc (0-255).

Numbers: `42`, `0x2A`, `0b101010`, `0o52`, `'*'`, with `_` separators allowed. Expressions use
`+ - * / % << >> & | ^ ~ !`, the comparisons `== != < <= > >=`, `&& ||`, parentheses, `.` (the
current pc), and the functions `lo(x)`, `hi(x)` (bytes), `bit(n)` (1 << n), `min`, `max`,
`page(label)`, `pc(label)` and `addr(label)` (page × 256 + pc).

Constants: `.equ NAME, VALUE` or `NAME = VALUE`, defined once. Labels may be used before they are
defined; constants, `.org`, `.rep` counts and `.if` conditions must be known when they are
reached.

## Instructions

Every ISA v2 instruction, with the operands of [isa.md](isa.md):

| instruction | operands |
|---|---|
| `nop`, `waitd`, `in`, `cnta`, `ldb`, `stb`, `halt` | none |
| `setp` | MASK, VAL, OE [, q=Q] |
| `ldc`, `ldd` | 0..4095 |
| `lda`, `skne`, `skeq`, `fine`, `bank`, `cfg` | a byte (-128..255) |
| `waitp` | PIN, VAL [, FAIL] |
| `sho` | PIN, msb or lsb [, od] [, pair] [, psel] [, cap] [, q=Q] |
| `shi` | PIN, msb or lsb [, quad] |
| `jmp`, `jnz` | a target |
| `out` | [tag=T] |
| `outi` | a byte [, tag=T] |
| `send`, `recv` | a channel (inbox0..inbox3, port0..port3, or 0..7) [, FAIL] |
| `waitc` | a condition (acc0..acc7, byte, host, inbox, space, flag0..flag3, or 0..15) [, FAIL] |
| `ext` | SUB, IMM (any EXT word, including the reserved ones) |
| `.word` | any 16-bit values |

A target or FAIL is a label on the same page, `.` (the instruction itself), or a number; a FAIL
left out is `.`, so `waitp 3, 1` waits for ever. Every operand's range is checked: `ldd 5000` is
an error, not a wrap.

## Placing code

- `.page P` switches to page P (0-3); each page has its own fill pointer, starting at 0.
- `.org PC` moves the fill pointer within the page.
- `.thread T, LABEL` (or `.thread T, page=P, pc=ADDRESS`) says where thread T starts. Every
  thread needs one; an idle thread starts at a `halt`.

Two words at the same address are an error, as is a page past 256 words.

## Macros, repetition and conditions

    .macro name param, param=default
        ... \param ... \@ ...
    .endm

A macro call is its name with arguments, positional or `param=value`. In the body, `\param` is
replaced by the argument's text and `\@` by a number unique to the expansion, for labels:

```asm
; check: a macro with a local label
.macro blink pin, times
    ldc \times
again\@:
    setp 1 << (\pin), 1, 1
    setp 1 << (\pin), 0, 1
    sho 7, lsb                 ; counts cnt down
    jnz again\@
.endm
start:
    blink 2, 3
    halt
; expect: pin2 edges at slots 1, 2, 5, 6, 9, 10
```

`.rep COUNT [, VAR]` ... `.endr` repeats its lines COUNT times, with `\VAR` replaced by 0, 1,
... . `.if EXPR` ... `.elif EXPR` ... `.else` ... `.endif` assembles one branch. Blocks nest.

```asm
; check: .rep with a counter, and .if
start:
    .rep 4, k
    .if \k % 2 == 0
    setp 1 << \k, 1, 1
    .else
    nop
    .endif
    .endr
    halt
; expect: pin0 edges at slots 0
; expect: pin2 edges at slots 2
; expect: pin1 edges at slots
```

`.include "FILE"` reads FILE relative to the including file, then the `-I` directories, then
`tools/asm/lib`, which has:

- `std.inc`: `delay N` (exactly N slots, N ≥ 2), `drive MASK, LEVEL`, `release MASK`,
  `wait_pin PIN, LEVEL, LIMIT, TIMEOUT`, `bnot COND, TARGET` (branch if the condition does not
  hold, one word), `bif COND, TARGET` (branch if it holds, two words), `bne` and `beq` (branch
  on the accumulator);
- `proto.inc`: UART, SPI and I2C controller macros, word for word the sequences of
  prototypes/deadline-sequencer's compiler.

```asm
; check: delay N lasts exactly N slots
.include "std.inc"
start:
    setp 1, 1, 1               ; slot 0
    delay 10                   ; slots 1..10
    setp 1, 0, 1               ; slot 11
    halt
; expect: pin0 edges at slots 0, 11
```

## Timing specifications

A `.timing T` ... `.endtiming` block states what thread T must do on its pins, and `asm
--verify` proves it for every input with the repository's static verifier
(`prototypes/verifier`). Inside:

- `.channel PIN, ...`: the pins the thread owns;
- `.bytes B, ...`: the bytes that data declarations refer to;
- `.expect pN=EVENT ..., gap=G [, byte=I, bit=B] [, to=STATE] [, "label"]`: the next event on
  the channel, which must come G slots after the previous one (`N` exactly, `A..B`, or `A..` at
  least A). EVENT is `0` or `1` (a SETP driving that level), `z` (a SETP releasing), `data` (a
  push-pull SHO), `data_od` (an open-drain SHO), `seen0`/`seen1` (a WAITP that saw that level),
  `timeout0`/`timeout1` (a WAITP for that level that gave up), `sample` (a SHI). With `byte=` and
  `bit=` the SHO must write that bit of that byte. Several `pN=` in one `.expect` are one slot's
  event on several pins;
- `.state NAME` names the current state; `.from NAME` continues from a named state (for the other
  outcome of a WAITP); `to=NAME` goes to a named state (loops, joins).

Each `.expect` adds one transition of the verifier's automaton; a state with no transitions is
final. The verifier then proves that every execution makes exactly these events, with every gap
inside its interval, and never stays longer in a state than its largest gap. `examples/` has the
specifications of the compiler's UART, SPI and I2C (equal, as automata, to the verifier's own,
`test/examples.ml` checks) and of the WS2812 driver.

The verifier analyses a thread from pc 0 of its page (its assumption A3), so a thread with a
`.timing` block must start at pc 0; `--verify` refuses one that does not. It also checks that no
other thread that starts at pc 0 writes the channel's pins, and says when another thread could
not be checked.

## Errors

Every error names the file and line, and for code from a macro or `.rep`, where it was expanded:

    examples/dac.s:41 (in .rep iteration 0 at examples/dac.s:39): error: undefined symbol port0

Operand ranges, unknown names, labels on another page, words assembled twice, registers set
twice, `.timing` problems and missing `.thread` directives are all errors; a thread starting
where no word was assembled is a warning.

## The runner's board

The runner joins each logical pin's output pad and input pad into one **net**: net *k* is driven
by the pad that shows sequencer pin *k* (the bidirectional pad, if pin *k* reads one) and read by
pin *k*'s input pad. A net is a wired AND with a pull-up: whoever drives 0 wins, and a net nobody
drives reads 1. A push-pull pad always drives its net, so a pin used only as an input should have
no output pad (`.pad P, zero` for the pad that shows it by reset, see
`examples/uart_rx.s`).

The outside world, on the nets, with clocks counted from the run's start:

- `--stimulus FILE`: lines `CLOCK NET LEVEL` (LEVEL 0, 1, or z to stop driving);
- `--peer uart_tx:net=N,bit=CLOCKS,start=CLOCK,bytes=HEX[,gap=CLOCKS]`: a UART transmitter;
- `--peer i2c_target:sda=N,scl=N,addr=A[,stretch=CLOCKS][,mem=HEX]`: an I2C target with a
  256-byte register file (a write sets the pointer, then writes; a read returns bytes from the
  pointer), optionally stretching SCL after every falling edge;
- `--peer wire:src=N,dst=N`: net dst follows net src;
- `--hostin FILE`: bytes the host streams into HOSTIN during the run.

On the chip the image is loaded through the host link first (several hundred to a few thousand
clocks), and the run starts when the image sets run; on the interpreter it starts at once. The
host then polls HOSTOUT and tops HOSTIN up for the rest of the run.
