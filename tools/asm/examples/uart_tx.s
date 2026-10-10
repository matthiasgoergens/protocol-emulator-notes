; uart_tx.s: a UART transmitter, 8N1, least significant bit first, sending "OK!".
;
; This is the programme prototypes/deadline-sequencer/compiler.ml's uart_tx emits for the
; repository's demo (pin 0, 16 slots a bit, bytes 4F 4B 21), written out by hand in assembly.
; test/examples.ml checks that it assembles to the compiler's words, word for word, after the
; compiler's base-ISA output is translated to ISA v2 (prototypes/sequencer-v2/compat.ml).
;
; Timing. A slot is one instruction of this thread, 4 clocks at 60 MHz. Every instruction takes
; exactly one slot, so the bit time is a count of instructions:
;   start bit   setp(0) ldd(1) waitd(2 .. 2+X) ldc(3+X) | sho  = 4 + X slots
;   data bit    sho ldd waitd(X+1 slots) jnz            = 4 + X slots
;   stop bit    setp ldd waitd(X+1 slots) | lda setp    = 4 + X slots
; With X = BIT - 4 every bit is BIT slots: 16 slots = 64 clocks, 937,500 baud at 60 MHz.

.include "std.inc"

.equ UART, 0                 ; the logical pin
.equ BIT, 16                 ; slots per bit
.equ X, BIT - 4              ; the deadline that pads each bit to BIT slots

; one byte: start bit, eight data bits from the accumulator, stop bit
.macro uart_byte value
    lda \value
    setp 1 << UART, 0, 1     ; start bit: drive the line low
    ldd X
    waitd
    ldc 8                    ; eight data bits
bit\@:
    sho UART, lsb            ; the next bit, least significant first
    ldd X
    waitd
    jnz bit\@
    setp 1 << UART, 1, 1     ; stop bit: drive the line high
    ldd X
    waitd
.endm

.thread 0, uart
.thread 1, idle
.thread 2, idle
.thread 3, idle

.page 0
uart:
    setp 1 << UART, 1, 1     ; idle level: high
    uart_byte 'O'
    uart_byte 'K'
    uart_byte '!'
    halt

.page 1
idle:
    halt

; the pin: sequencer pin 0 on uo_out[0]; before the first SETP the pad shows its undriven level,
; which is set high so that the line idles high from reset
.pad 0, seq0, undriven=1

; the timing this thread must keep, proved by asm --verify: the line goes high within one bit,
; the start bit follows within a bit, and every later cell boundary is exactly BIT slots on. The
; data levels are declared too: data bit j of byte i is bit j - 1 of the byte.
.timing 0
    .channel UART
    .bytes 'O', 'K', '!'
    .expect p0=1, gap=0..BIT, "idle high"
    .rep 3, i
    .if \i == 0
    .expect p0=0, gap=1..BIT, "byte \i start bit"
    .else
    .expect p0=0, gap=BIT, "byte \i start bit"
    .endif
    .rep 8, j
    .expect p0=data, gap=BIT, byte=\i, bit=\j, "byte \i data bit \j"
    .endr
    .expect p0=1, gap=BIT, "byte \i stop bit"
    .endr
.endtiming
