; proto.inc: macros for UART, SPI and I2C controllers. They are the instruction sequences of
; prototypes/deadline-sequencer/compiler.ml, so a programme built from them assembles to the
; compiler's words (examples/*.s, checked by test/examples.ml). Each comment gives the slot of
; every edge, counted from the macro's first instruction; a slot is one instruction of the thread.
; "ldd N; waitd" lasts N + 2 slots.

; ---------------------------------------------------------------------------------------- UART
; uart_send PIN, X: send the accumulator, 8N1, least significant bit first. Every bit lasts
; X + 4 slots: start bit at 0 (setp), data bits at X+4, 2(X+4), ..., stop bit at 9(X+4); the
; macro ends X + 3 slots into the stop bit, so a following "lda; uart_send" starts the next start
; bit exactly one bit after the stop bit.
.macro uart_send pin, x
    setp 1 << (\pin), 0, 1          ; 0: start bit
    ldd \x
    waitd
    ldc 8
bit\@:
    sho \pin, lsb                   ; X+4, then every X+4 slots: data bits
    ldd \x
    waitd
    jnz bit\@
    setp 1 << (\pin), 1, 1          ; 9(X+4): stop bit
    ldd \x
    waitd
.endm

; ---------------------------------------------------------------------------------------- SPI
; spi_send SCLK, MOSI, CS, A, B: one byte from the accumulator, mode 0 (SCLK idles low, data
; valid on the rising edge), most significant bit first, CS low around the byte. Period
; A + B + 8 slots; SCLK high for B + 3 slots. MOSI changes 2 slots after each SCLK fall.
.macro spi_send sclk, mosi, cs, a, b
    setp 1 << (\cs), 0, 1           ; CS low
    ldc 8
bit\@:
    sho \mosi, msb                  ; MOSI <- the next bit
    ldd \a
    waitd
    setp 1 << (\sclk), 1, 1         ; SCLK rises A + 3 slots after the SHO
    ldd \b
    waitd
    setp 1 << (\sclk), 0, 1         ; SCLK falls B + 3 slots later
    jnz bit\@
    setp 1 << (\cs), 1, 1           ; CS high
.endm

; ---------------------------------------------------------------------------------------- I2C
; SDA and SCL are open drain: "drive low" is setp MASK, 0, 1 and "release" is setp MASK, 0, 0;
; the pull-up (or the target) makes the high level. Q is a quarter of the SCL period in slots
; (Q >= 4). LIMIT is the clock-stretching limit in slots (at most 4095): after every release of
; SCL the controller waits until it reads high, and gives up at FAIL after LIMIT slots.

; i2c_scl_up SCL, LIMIT, FAIL: release SCL and wait (bounded) until it reads high. 3 words; the
; release is in the second slot, and the wait proceeds in the slot after SCL is seen high.
.macro i2c_scl_up scl, limit, fail
    ldd \limit
    setp 1 << (\scl), 0, 0
    waitp \scl, 1, \fail
.endm

; i2c_start SDA, SCL, Q: START (SDA falls while SCL is high), then SCL low Q slots later.
.macro i2c_start sda, scl, q
    setp 1 << (\sda), 0, 1
    ldd (\q) - 3
    waitd
    setp 1 << (\scl), 0, 1
.endm

; i2c_write SDA, SCL, Q, LIMIT, FAIL: send the accumulator, most significant bit first, then
; clock the acknowledge bit in and send it to the host (OUT: 0 = acknowledged, 1 = not). SCL
; high for 2Q slots per bit, measured from the slot SCL is seen high.
.macro i2c_write sda, scl, q, limit, fail
    ldc 8
bit\@:
    sho \sda, msb, od               ; SDA <- the next bit (open drain)
    ldd 2 * (\q) - 6
    waitd
    i2c_scl_up \scl, \limit, \fail
    ldd 2 * (\q) - 4
    waitd
    setp 1 << (\scl), 0, 1          ; SCL low
    jnz bit\@
    setp 1 << (\sda), 0, 0          ; release SDA for the acknowledge
    ldd 2 * (\q) - 6
    waitd
    i2c_scl_up \scl, \limit, \fail
    ldd (\q) - 4
    waitd
    shi \sda, msb                   ; sample the acknowledge
    ldd (\q) - 3
    waitd
    setp 1 << (\scl), 0, 1
    out
.endm

; i2c_stop SDA, SCL, Q, LIMIT, FAIL: STOP (SDA rises while SCL is high). The last word, which
; releases both lines, is labelled FAIL: a timeout anywhere ends here too.
.macro i2c_stop sda, scl, q, limit, fail
    setp 1 << (\sda), 0, 1
    ldd 2 * (\q) - 5
    waitd
    i2c_scl_up \scl, \limit, \fail
    ldd (\q) - 4
    waitd
\fail:
    setp (1 << (\sda)) | (1 << (\scl)), 0, 0
.endm

; i2c_restart SDA, SCL, Q, LIMIT, FAIL: a repeated START after an acknowledge clock (SCL low,
; SDA released). SCL stays low for 2Q slots, is released, and Q slots after it is seen high SDA
; falls; SCL falls Q slots after that.
.macro i2c_restart sda, scl, q, limit, fail
    ldd 2 * (\q) - 5
    waitd
    i2c_scl_up \scl, \limit, \fail
    ldd (\q) - 4
    waitd
    setp 1 << (\sda), 0, 1          ; START: SDA falls while SCL is high
    ldd (\q) - 3
    waitd
    setp 1 << (\scl), 0, 1
.endm

; i2c_read SDA, SCL, Q, LIMIT, FAIL, ACK: read a byte, most significant bit first, sampling SDA
; Q slots after SCL is seen high; then acknowledge it (ACK = 1: drive SDA low) or not (ACK = 0:
; leave SDA released, which tells the target this was the last byte), and send the byte to the
; host with tag 1. SCL period 4Q slots, high for 2Q from the slot it is seen high.
.macro i2c_read sda, scl, q, limit, fail, ack
    setp 1 << (\sda), 0, 0          ; release SDA: the target drives it
    ldc 8
bit\@:
    ldd 2 * (\q) - 5                ; SCL low for 2Q slots from its fall
    waitd
    i2c_scl_up \scl, \limit, \fail
    ldd (\q) - 4
    waitd
    shi \sda, msb                   ; sample the bit
    ldd (\q) - 3
    waitd
    setp 1 << (\scl), 0, 1          ; SCL low
    jnz bit\@
    setp 1 << (\sda), 0, \ack       ; acknowledge: SDA low (ACK) or released (NACK)
    ldd 2 * (\q) - 6
    waitd
    i2c_scl_up \scl, \limit, \fail
    ldd 2 * (\q) - 4
    waitd
    setp 1 << (\scl), 0, 1
    setp 1 << (\sda), 0, 0          ; release SDA
    out tag=1
.endm
