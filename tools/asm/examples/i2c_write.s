; i2c_write.s: an I2C controller writing A0 5A (address 0x50, write; one data byte), with
; clock stretching.
;
; The programme prototypes/deadline-sequencer/compiler.ml's i2c_write emits for the repository's
; demo (SDA on pin 4, SCL on pin 5, quarter period Q = 4 slots, stretch limit 4095 slots),
; written with the I2C macros of proto.inc; test/examples.ml checks it word for word against
; the compiler.
;
; Clock stretching: after every release of SCL the controller waits until SCL reads high (a
; target may hold it low), at most LIMIT slots; on a timeout it jumps to fin, which releases
; both lines and halts, so the host receives fewer acknowledge bytes than bytes were sent.

.include "proto.inc"

.equ SDA, 4
.equ SCL, 5
.equ Q, 4
.equ LIMIT, 4095

.thread 0, idle
.thread 1, idle
.thread 2, i2c
.thread 3, idle

.page 0
i2c:
    i2c_start SDA, SCL, Q
    lda 0xA0                                ; address 0x50, write
    i2c_write SDA, SCL, Q, LIMIT, fin
    lda 0x5A
    i2c_write SDA, SCL, Q, LIMIT, fin
    i2c_stop SDA, SCL, Q, LIMIT, fin
    halt

.page 1
idle:
    halt

; SDA and SCL on uio[6] and uio[7], the open-drain pads, which they also read back
.pad 14, seq4, undriven=0
.pad 15, seq5, undriven=0
.pinin 4, 14
.pinin 5, 15

; the verifier's specification (prototypes/verifier/programmes.ml, i2c_spec): every release of
; SCL is followed by SCL seen high within LIMIT slots, or a timeout at exactly LIMIT after
; which both lines are released one slot later; the high phase is timed from the observation.
.macro scl_up label
    .state up\@
    .expect p5=seen1, gap=1..LIMIT, "\label: scl seen high"
    .state seen\@
    .from up\@
    .expect p5=timeout1, gap=LIMIT, "\label: timeout"
    .expect p4=z, p5=z, gap=1, "\label: released after timeout"
    .from seen\@
.endm

.timing 2
    .channel SDA, SCL
    .expect p4=0, gap=0, "START sda low"
    .expect p5=0, gap=Q, "START scl low"
    .rep 2, i
    .rep 8, j
    .if \j > 0
    .expect p4=data_od, gap=2, "byte \i bit \j sda"
    .elif \i == 0
    .expect p4=data_od, gap=3, "byte \i bit \j sda"
    .else
    .expect p4=data_od, gap=4, "byte \i bit \j sda"
    .endif
    .expect p5=z, gap=2*Q-2, "byte \i bit \j scl released"
    scl_up byte \i bit \j
    .expect p5=0, gap=2*Q-1, "byte \i bit \j scl low"
    .endr
    .expect p4=z, gap=2, "byte \i ack sda released"
    .expect p5=z, gap=2*Q-2, "byte \i ack scl released"
    scl_up byte \i ack
    .expect p4=sample, gap=Q-1, "byte \i ack sampled"
    .expect p5=0, gap=Q, "byte \i ack scl low"
    .endr
    .expect p4=0, gap=2, "STOP sda low"
    .expect p5=z, gap=2*Q-1, "STOP scl released"
    scl_up STOP
    .expect p4=z, p5=z, gap=Q-1, "STOP sda released"
.endtiming
