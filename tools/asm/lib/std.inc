; std.inc: macros for the common waits and branches of ISA v2. Include with
;     .include "std.inc"
; Each macro says how many words it takes and how many slots it lasts. A slot is one
; instruction of one thread: 4 clocks.

; delay N: N slots in all, the two words included (N >= 2). LDD loads the deadline register in
; its own slot; WAITD then stays until it reaches 0, which takes N - 2 + 1 slots.
.macro delay n
    ldd (\n) - 2
    waitd
.endm

; drive MASK, LEVEL: drive the pins of MASK to LEVEL (push-pull or open-drain low). 1 word.
.macro drive mask, level
    setp \mask, \level, 1
.endm

; release MASK: stop driving the pins of MASK (a pull-up or the other side sets the level). 1 word.
.macro release mask
    setp \mask, 0, 0
.endm

; wait_pin PIN, LEVEL, LIMIT, TIMEOUT: wait until PIN reads LEVEL, at most LIMIT slots after the
; LDD; on a timeout, continue at TIMEOUT. 2 words; proceeds 1 to LIMIT + 1 slots after the LDD.
.macro wait_pin pin, level, limit, timeout
    ldd \limit
    waitp \pin, \level, \timeout
.endm

; bnot COND, TARGET: branch to TARGET if COND does not hold. 1 word, 1 slot. Needs dl = 0 (a
; WAITC only branches once its deadline has run out); use "ldd 0" first if a deadline may be
; pending.
.macro bnot cond, target
    waitc \cond, \target
.endm

; bif COND, TARGET: branch to TARGET if COND holds. 2 words: 1 slot when not taken, 2 when taken.
; Needs dl = 0, as bnot.
.macro bif cond, target
    waitc \cond, skip\@
    jmp \target
skip\@:
.endm

; bne VALUE, TARGET / beq VALUE, TARGET: branch if the accumulator differs from / equals VALUE.
; 2 words: 1 slot when not taken (the skip), 2 when taken.
.macro bne value, target
    skeq \value
    jmp \target
.endm
.macro beq value, target
    skne \value
    jmp \target
.endm
