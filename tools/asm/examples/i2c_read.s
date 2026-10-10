; i2c_read.s: an I2C controller reading two bytes from register 0x10 of a target at address
; 0x50, as a serial EEPROM is read: a write of the register pointer, a repeated START, then a
; read; the controller acknowledges the first byte and not the second, then STOP.
;
; Not in the repository's compiler: written for this toolchain with the macros of proto.inc
; (the write half is the compiler's I2C byte). The host receives the three acknowledge bits
; (tag 0, 0 = acknowledged) and the two bytes read (tag 1). test/examples.ml runs it against
; the runner's I2C target (an EEPROM model written from the I2C specification, with and
; without clock stretching) and judges the bus with the repository's decoder and sigrok's.

.include "proto.inc"

.equ SDA, 4
.equ SCL, 5
.equ Q, 4
.equ LIMIT, 4095
.equ TARGET, 0x50
.equ REGISTER, 0x10

.thread 0, idle
.thread 1, idle
.thread 2, i2c
.thread 3, idle

.page 0
i2c:
    i2c_start SDA, SCL, Q
    lda TARGET << 1                         ; address, write
    i2c_write SDA, SCL, Q, LIMIT, fin
    lda REGISTER                            ; the register pointer
    i2c_write SDA, SCL, Q, LIMIT, fin
    i2c_restart SDA, SCL, Q, LIMIT, fin
    lda (TARGET << 1) | 1                   ; address, read
    i2c_write SDA, SCL, Q, LIMIT, fin
    i2c_read SDA, SCL, Q, LIMIT, fin, 1     ; first byte: acknowledge
    i2c_read SDA, SCL, Q, LIMIT, fin, 0     ; last byte: no acknowledge
    i2c_stop SDA, SCL, Q, LIMIT, fin
    halt

.page 1
idle:
    halt

.pad 14, seq4, undriven=0
.pad 15, seq5, undriven=0
.pinin 4, 14
.pinin 5, 15
