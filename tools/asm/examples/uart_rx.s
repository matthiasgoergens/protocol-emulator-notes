; uart_rx.s: a UART receiver, 8N1, least significant bit first, 16 slots (64 clocks) a bit,
; sending every byte it receives to the host (OUT, tag 0), and a byte with a bad stop bit with
; tag 1.
;
; Not in the repository's compiler: written for this toolchain. test/examples.ml drives it from
; a stimulus file made by Alex Forencich's verilog-uart transmitter (tools/peers/vendor, run in
; Icarus Verilog by examples/peers/uart_tx_stim.sh) and from the runner's own UART peer, and
; compares what the host receives with the bytes sent.
;
; Sampling. The WAITP sees the start bit's falling edge in slot w (at most one slot, 4 clocks,
; after it reaches the core). The middle of the start bit is then about BIT/2 slots on, and the
; middle of data bit k (k = 0..7) at w + BIT/2 + BIT (k + 1); the stop bit's middle at
; w + BIT/2 + 9 BIT. Each SHI shifts the pin into bit 7 and the byte down, so after eight, the
; first bit received is bit 0.

.include "std.inc"

.equ RX, 0
.equ BIT, 16
.equ HALF, BIT / 2

.thread 0, rx
.thread 1, idle
.thread 2, idle
.thread 3, idle

.page 0
rx:
    waitp RX, 0, .                  ; w: wait (for ever) for the start bit's falling edge
    ldc 8                           ; w+1
    delay HALF + BIT - 2            ; w+2 .. w+HALF+BIT-1
bit:
    shi RX, lsb                     ; w+HALF+BIT(k+1): the middle of data bit k
    delay BIT - 2
    jnz bit
    waitp RX, 1, bad                ; w+HALF+9 BIT: the stop bit (dl = 0: no wait)
    out                             ; the byte to the host, tag 0
    jmp rx
bad:
    out tag=1                       ; framing error: the byte with tag 1
    waitp RX, 1, .                  ; wait for the line to go idle
    jmp rx

.page 1
idle:
    halt

; The receive pin reads ui_in[0]. By reset uo_out[0] shows sequencer pin 0 as a push-pull output;
; the runner's board joins a pin's output pad and input pad into one net, so an input-only pin
; must not have an output pad: uo_out[0] shows the constant 0 instead.
.pinin 0, 0
.pad 0, zero
