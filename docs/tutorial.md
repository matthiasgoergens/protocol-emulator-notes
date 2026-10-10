# Write your first protocol: WS2812 LEDs, from datasheet to verified image

This tutorial implements a protocol the repository did not have, the WS2812 RGB LED ("NeoPixel")
line, from its datasheet to an image that is proved to meet the timing, runs on the chip's RTL
and is decoded by independent decoders. The finished programme is
`tools/asm/examples/ws2812.s`; `tools/asm/test/examples.ml` and `test/judge_examples.py` run
every check below.

## 1. The protocol

A WS2812 string is one data line. Each bit is one pulse, and the width of its high part says the
bit (WS2812B datasheet, each value ±150 ns):

| | high | low |
|---|---|---|
| a 0 | 0.40 µs | 0.85 µs |
| a 1 | 0.80 µs | 0.45 µs |

Each LED takes the first 24 bits it sees (green, red, blue, most significant bit first) and
passes the rest along; a low of at least 50 µs (280 µs for the newer WS2812B-V5) latches the
colours.

## 2. From microseconds to slots

The sequencer's unit of time is the slot: one instruction of one thread, 4 clocks, 66.7 ns at
60 MHz. Every instruction takes exactly one slot, so a pulse width is a count of instructions.
Split every bit into three parts of fixed length:

| part | slots | ns | line |
|---|---|---|---|
| HIGH | 6 | 400 | high |
| DATA | 6 | 400 | high for a 1, low for a 0 |
| LOW | 7 | 467 | low |

A 0 is then high 400 ns and low 867 ns, a 1 high 800 ns and low 467 ns: all four inside the
datasheet's ±150 ns. The DATA part is one SHO: it writes the accumulator's top bit to the pin,
so the bit's value needs no branch, and every path through the bit takes the same time.

## 3. One bit, then one byte

The bit cell, with the slot of each instruction counted from the rise at *s*. `delay N` (from
`std.inc`) is `ldd N-2; waitd`, exactly N slots:

```asm
; check: one byte, 0xA5, in the WS2812 bit cell
.include "std.inc"
start:
    lda 0xA5
    ldc 8
bit:
    setp 1, 1, 1             ; s: rise
    delay 5                  ; s+1 .. s+5
    sho 0, msb               ; s+6: stays high for a 1, falls for a 0
    delay 5                  ; s+7 .. s+11
    setp 1, 0, 1             ; s+12: fall
    delay 5                  ; s+13 .. s+17
    jnz bit                  ; s+18: the next rise is at s+19
    halt
; expect: pin0 edges at slots 2, 14, 21, 27, 40, 52, 59, 65, 78, 84, 97, 109, 116, 122, 135, 147
```

A 1 (0xA5's first bit) rises at slot 2 and falls at 14: 12 slots, 800 ns. A 0 (the second)
rises at 21 and falls at 27: 6 slots, 400 ns. Bits are 19 slots apart. (The docs' test runs this
block on the ISA interpreter and checks these slots.)

A string needs 24 bits per LED and a new byte every 8 bits, without disturbing the cell's
timing. The LOW part has room: SHO counts cnt down, so with cnt loaded with the frame's bit count
(a multiple of 8), `waitc byte` (cnt[2:0] = 0) tells whether a byte has just finished. WAITC
branches when its condition does *not* hold, and only with dl = 0, which the `delay` before it
leaves. Both paths take four slots before the JNZ:

```
    setp 1 << LED, 0, 1     ; s+12: fall
    waitc byte, same        ; s+13: a whole byte sent?
    ldb                     ; s+14: yes: the next byte from the data bank
    jmp tail                ; s+15
same:
    nop                     ; s+14: no
    nop                     ; s+15
tail:
    nop                     ; s+16
    nop                     ; s+17
    jnz bit                 ; s+18
```

The colours come from the data bank (LDB reads it and moves the bank pointer on), so the image
preloads them with `.bankdata`, and a host could rewrite them between frames through the BANK
target ([host-link.md](host-link.md)). Before and after the frame the line is held low for
RESET = 4,500 slots (300 µs): `delay 4097` and `delay 403`, because LDD holds at most 4,095.

The pin: `.pad 0, seq0, undriven=0` puts logical pin 0 on uo_out[0], low before the programme
drives it. Every thread needs a `.thread` directive; the three idle ones start at a `halt`. The
whole file is `tools/asm/examples/ws2812.s`.

## 4. Assemble

    $ _build/default/bin/asm.exe examples/ws2812.s -o ws2812.hlk
    examples/ws2812.s: 30 words, 102 image bytes -> ws2812.hlk

`--listing -` prints every word with its address and source line. The image is the byte stream
a host sends to load the chip and start it ([host-link.md](host-link.md)).

## 5. Say what the timing must be, and prove it

The datasheet's timing becomes a `.timing` block in the same file: an automaton over the
thread's pin events, each with the gap in slots since the previous one
([assembly.md](assembly.md)):

```
.timing 0
    .channel LED
    .expect p0=0, gap=0, "line low"
    .expect p0=1, gap=RESET+5, "bit 0 rise"
    .expect p0=data, gap=HIGH, "bit 0 data"
    .expect p0=0, gap=DATA, "bit 0 fall"
    .rep BITS - 1, i
    .expect p0=1, gap=LOW, "bit \i+1 rise"
    .expect p0=data, gap=HIGH, "bit \i+1 data"
    .expect p0=0, gap=DATA, "bit \i+1 fall"
    .endr
.endtiming
```

`asm --verify` runs the repository's static verifier on it: an analyser follows the programme
over every input, and a small trusted kernel checks the result (`prototypes/verifier`). The
colours come from the data bank, which the verifier treats as input, so the proof holds for every
colour. The first version of this block said `gap=RESET+4` for the first rise, and the verifier
answered with the path that breaks it:

    thread 0 (page 0): REJECTED  table entries 638, channel events checked 145
        pc 9: 4505 slots may pass without an event in state line low, whose deadline is 4504
        path (10 instructions from pc 0):
            0  setp mask=01 val=0 oe=1 q=0  state start            dl=0 since=0 due=0 time=0
            ...
            8  ldc 48                       state line low         dl=0 since=4504 due=4504 time=4504
            9  setp mask=01 val=1 oe=1 q=0  state line low         dl=0 since=4505 due=4505 time=4505
        pc 9: event p0:set=1 (bit 0 rise) has gap 4505 slots, declared 4504

The rise comes after the 4,500 slots of the delays and four set-up instructions, so 4,505 slots
after the first SETP, not 4,504. With that fixed:

    $ _build/default/bin/asm.exe examples/ws2812.s --verify --certs certs
    thread 0 (page 0): PROVED  table entries 638, channel events checked 145

The certificate lists every pin event with its pc, its slot and its gap. The verifier also
rejects a programme whose high part is one slot short (`delay HIGH - 2`): the examples test
checks that too.

## 6. Run it

    $ _build/default/bin/run.exe ws2812.hlk --clocks 40000 --vcd ws2812.vcd --sr ws2812.sr

The runner runs the image twice: on the ISA v2 interpreter, and on the chip, where the host
first loads the image over the host link and the chip's specification and RTL run in lockstep,
compared on every pad on every clock. It requires the interpreter and the chip to put the same
levels on the pins on every clock of the run. `ws2812.vcd` opens in Surfer or GTKWave (the nets
at quarter-clock resolution, every thread's pc, the output pads); `ws2812.sr` opens in
PulseView, or decodes from the command line with sigrok's own WS281x decoder:

    $ sigrok-cli -i ws2812.sr -P rgb_led_ws281x:din=net0 -A rgb_led_ws281x=rgb:reset
    rgb_led_ws281x-1: #341256
    rgb_led_ws281x-1: #bc9ade
    rgb_led_ws281x-1: RESET

(sigrok prints red, green, blue; the line carries green 0x12, red 0x34, blue 0x56 for the first
LED.)

## 7. Check it independently

The examples test (`test/examples.ml`, "ws2812") decodes the chip's pin with a WS2812 receiver
written from the datasheet's windows alone: every high pulse must be 250-550 ns or 650-950 ns,
every low 700-1,000 ns after a 0 and 300-600 ns after a 1, and a low of 50 µs ends the frame. It
reads exactly the six bytes of the bank, with no pulse outside its window. `test/judge_examples.py`
runs sigrok's decoder in its pinned container and requires it to fail on two planted faults (a
data part inverted, the trace at the wrong rate). Controls: a programme with a 133 ns high part
is caught by the receiver, and another colour in the bank is read as that colour.

## 8. Where to go from here

- **Colours from the host**: replace LDB by `waitc host, ...; in` and the host streams the
  colours; the verifier then needs a bound on the host (IN has none; a WAITC with a deadline
  does).
- **More LEDs**: `.equ LEDS` and more `.bankdata`; cnt counts up to 4,095 bits (170 LEDs per
  `ldc`).
- **Another thread at the same time**: the other three threads are free; their timing cannot
  disturb this one, and `--verify` checks that they do not write its pin.
