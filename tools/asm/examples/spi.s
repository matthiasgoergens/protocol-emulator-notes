; spi.s: an SPI controller, mode 0, most significant bit first, sending A5 3C.
;
; The programme prototypes/deadline-sequencer/compiler.ml's spi_master emits for the
; repository's demo (SCLK on pin 1, MOSI on 2, CS on 3, period 16 slots), written with the
; spi_send macro of proto.inc; test/examples.ml checks it word for word against the compiler.
;
; Period P = 16 slots = 64 clocks (937.5 kHz at 60 MHz). In the bit loop the SHO is slot 0,
; SCLK rises at A + 3 and falls at A + B + 6, and the next SHO is at A + B + 8 = P. SCLK is
; high for B + 3 = P / 2, so B = P/2 - 3 = 5 and A = P - 8 - B = 3.

.include "proto.inc"

.equ SCLK, 1
.equ MOSI, 2
.equ CS, 3
.equ P, 16
.equ B, P / 2 - 3
.equ A, P - 8 - B

.thread 0, idle
.thread 1, spi
.thread 2, idle
.thread 3, idle

.page 0
spi:
    setp (1 << SCLK) | (1 << MOSI), 0, 1    ; SCLK and MOSI low
    setp 1 << CS, 1, 1                      ; CS high (inactive)
    lda 0xA5
    spi_send SCLK, MOSI, CS, A, B
    lda 0x3C
    spi_send SCLK, MOSI, CS, A, B
    halt

.page 1
idle:
    halt

; SCLK, MOSI, CS on uo_out[1..3]; the pads idle high before the programme drives them
.pad 1, seq1, undriven=1
.pad 2, seq2, undriven=1
.pad 3, seq3, undriven=1

; the verifier's specification of this programme (prototypes/verifier/programmes.ml, spi_spec):
; SCLK high P/2 and low P/2, MOSI changes 2 slots after each fall (P/2 - 2 before each rise),
; CS 2 slots from its neighbours; MOSI's bit j of byte i is bit 8 - j of the byte.
.timing 1
    .channel SCLK, MOSI, CS
    .bytes 0xA5, 0x3C
    .expect p1=0, p2=0, gap=0, "sclk and mosi low"
    .expect p3=1, gap=1, "cs idle"
    .rep 2, i
    .expect p3=0, gap=2, "byte \i cs asserted"
    .rep 8, j
    .expect p2=data, gap=2, byte=\i, bit=7-\j, "byte \i bit \j mosi"
    .expect p1=1, gap=P/2-2, "byte \i bit \j sclk rise"
    .expect p1=0, gap=P/2, "byte \i bit \j sclk fall"
    .endr
    .expect p3=1, gap=2, "byte \i cs released"
    .endr
.endtiming
