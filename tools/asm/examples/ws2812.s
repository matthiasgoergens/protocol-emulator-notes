; ws2812.s: drive a string of WS2812 RGB LEDs ("NeoPixels"). The protocol of docs/tutorial.md,
; which builds this file step by step.
;
; The line carries one bit per pulse; the width of the high part says the bit (WS2812B
; datasheet): a 0 is high 0.40 us then low 0.85 us, a 1 is high 0.80 us then low 0.45 us, each
; within +-150 ns; a low of at least 50 us (280 us for the newer WS2812B-V5) latches the colours.
; Each LED takes 24 bits, green, red, blue, most significant bit first, and passes the rest on.
;
; One slot is 4 clocks, 66.7 ns at 60 MHz, so every bit is three fixed parts:
;   HIGH = 6 slots   always high                        400 ns
;   DATA = 6 slots   high for a 1, low for a 0          400 ns
;   LOW  = 7 slots   always low                         467 ns
; A 0 is then high 400 ns and low 867 ns, a 1 high 800 ns and low 467 ns: all four inside the
; datasheet's windows. The data part is one SHO, so the bit's value needs no branch.

.include "std.inc"

.equ LED, 0                 ; the logical pin
.equ LEDS, 2
.equ BITS, 24 * LEDS
.equ HIGH, 6
.equ DATA, 6
.equ LOW, 7
.equ RESET, 4500            ; slots of low before and after a frame: 300 us

.thread 0, frame
.thread 1, idle
.thread 2, idle
.thread 3, idle

.page 0
frame:
    setp 1 << LED, 0, 1     ; slot 0: drive the line low
    delay 4097              ; the latch time, in two parts (LDD holds at most 4095)
    delay RESET - 4097
    lda 0
    bank 0                  ; bank pointer <- 0: the colours, three bytes an LED
    ldb                     ; the first byte
    ldc BITS                ; count every bit of the frame
bit:
    setp 1 << LED, 1, 1     ; s: rise
    delay HIGH - 1          ; s+1 .. s+5
    sho LED, msb            ; s+6: the data part: stays high for a 1, falls for a 0
    delay DATA - 1          ; s+7 .. s+11
    setp 1 << LED, 0, 1     ; s+12: fall
    waitc byte, same        ; s+13: a whole byte sent (cnt[2:0] = 0)? dl is 0 here
    ldb                     ; s+14: yes: the next byte
    jmp tail                ; s+15
same:
    nop                     ; s+14: no
    nop                     ; s+15
tail:
    nop                     ; s+16
    nop                     ; s+17
    jnz bit                 ; s+18; the next rise is at s+19
    delay 4097              ; latch
    delay RESET - 4097
    halt

.page 1
idle:
    halt

; the pin: sequencer pin 0 on uo_out[0], low before the programme drives it
.pad 0, seq0, undriven=0

; the colours, green-red-blue per LED
.bankdata 0, 0x12, 0x34, 0x56, 0x9A, 0xBC, 0xDE

; The timing the LEDs need, proved by asm --verify: the line low first, then for every bit a
; rise, the data part exactly HIGH slots later, the fall exactly DATA slots after that, and the
; next rise exactly LOW slots after the fall. The colours come from the data bank, which the
; verifier treats as input (any value), so it proves the timing for every colour.
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
