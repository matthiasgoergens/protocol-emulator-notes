; bridge.s: a UART-to-SPI bridge on two threads that talk through a mailbox.
;
; Thread 0 receives bytes on a UART (uart_rx.s's receiver) and SENDs each to thread 1's inbox
; (inbox 1). Thread 1 RECVs from its inbox and sends the byte on SPI (spi.s's controller, one
; byte per CS pulse). Neither thread waits for the other except at the mailbox: SEND blocks
; while the inbox is full, RECV while it is empty, each in its own slot, so the UART's sampling
; times do not move. An SPI byte takes 8 x 16 + 6 slots, under the 160 slots of a UART byte, so
; the inbox (one byte deep) never holds the receiver up.
;
; test/examples.ml sends bytes on the UART pin with the runner's UART peer and checks the SPI
; pins with the repository's SPI decoder and with sigrok's.

.include "std.inc"
.include "proto.inc"

.equ RX, 0                  ; UART in: ui_in[0]
.equ SCLK, 1                ; SPI out: uo_out[1..3]
.equ MOSI, 2
.equ CS, 3
.equ BIT, 16
.equ HALF, BIT / 2
.equ P, 16
.equ B, P / 2 - 3
.equ A, P - 8 - B

.thread 0, rx
.thread 1, spi
.thread 2, idle
.thread 3, idle

.page 0
rx:
    waitp RX, 0, .
    ldc 8
    delay HALF + BIT - 2
bit:
    shi RX, lsb
    delay BIT - 2
    jnz bit
    waitp RX, 1, rx                 ; a bad stop bit: drop the byte
    send inbox1, .                  ; to thread 1 (dl = 0: retries until the inbox is empty)
    jmp rx

.page 1
spi:
    setp (1 << SCLK) | (1 << MOSI), 0, 1
    setp 1 << CS, 1, 1
next:
    recv inbox1, .                  ; wait for a byte
    spi_send SCLK, MOSI, CS, A, B
    jmp next

.page 2
idle:
    halt

.pinin 0, 0
.pad 0, zero                ; pin 0 is an input only: no output pad (see uart_rx.s)
.pad 1, seq1, undriven=1
.pad 2, seq2, undriven=1
.pad 3, seq3, undriven=1
