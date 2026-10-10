; dac.s: the one-bit DAC: a second-order sigma-delta modulator on the PE array, fed by a pump
; thread from the host, its output bit on a pin. A PE-array example.
;
; This is prototypes/onebit-dac's design as prototypes/chip-top runs it (bin/demos.ml, "dac"):
; the pump programme of onebit-dac/sim/dac.ml (pump_programme) and the order-2 PE configuration
; (run_ops, without its pass-through PEs), on the hardened chip's 4 PEs, one per segment.
; test/examples.ml checks the words against pump_programme and the PE bytes against
; Upe.Spec.bytes_of_op of run_ops, and judges the pin against the modulator's bit-exact model
; and, independently, by low-pass filtering the bit stream and comparing it with the input.
;
; The host streams stereo frames into HOSTIN: left low, left high, right low, right high (the
; right channel is not used on 4 PEs). Every 1,360 clocks (340 slots, 44.1 kHz) the pump reads a
; frame (IN) into bank bytes 0-3, then sends the left word to port 4 (segment 0's feed). The
; segment repeats its word every 10 clocks: the modulator steps at 6 MHz, 136 steps a sample.
; A missing byte is reported to the host (OUT tag 1, the byte's index) and retried at the next
; sample instant, so a frame is delayed, never torn.

.equ SLOTS, 1360 / 4         ; slots per host sample
.equ IDLE, 200               ; where threads 1-3 are parked

.thread 0, pump
.thread 1, idle
.thread 2, idle
.thread 3, idle

.page 0
pump:
    waitd                    ; wait for the sample instant (the deadline loaded at the end)
    lda 0
    bank 0                   ; bank pointer <- 0
    .rep 4, k
byte\k:
    waitc host, under\k      ; dl = 0: a one-slot branch when HOSTIN is empty
    in
    stb                      ; bank[k] <- the byte
    .endr
    lda 0
    bank 0
    .rep 4, k
    ldb                      ; the byte back
    send 4 + \k / 2, .       ; bytes 0, 1 to channel 4 (port0, left), 2, 3 to channel 5 (port1, right)
    .endr
    ldd SLOTS - 26           ; the next sample instant: 340 slots after this one
    jmp pump
    .rep 4, k
under\k:
    outi \k, tag=1           ; underrun: report byte k missing
    ldd SLOTS - 5
    waitd                    ; one sample later ...
    jmp byte\k               ; ... retry byte k at the slot it would have had
    .endr

.org IDLE
idle:
    halt

; the array: four PEs of the order-2 modulator as one run over the four segments.
; One modulator step, with y the previous step's output bit on the lane (g = 1 means y = -1):
;   FB_k: P <- sat((A >>> m_k) + (g ? a_k : -a_k))      K = -a_k, Y negated when g
;   I_k:  S <- sat(S + A); P <- S                        a non-delaying integrator
;   the last I also: lane <- S'[15] (the next y), F <- g (the pin bit)
.layout 1, 1, 1, 1
.pe 0, 0, x=a, ymod=negg, g=lane, p=result, stream, k=-15689            ; FB_1, a_1 = 15689, m_1 = 0
.pe 1, 0, y=a, g=lane, s=result, p=result, stream                       ; I_1
.pe 2, 0, x=a, ashr=1, ymod=negg, g=lane, p=result, stream, k=-7845     ; FB_2, a_2 = 7845, m_2 = 1
.pe 3, 0, y=a, g=lane, s=result, p=result, lane=s15, f=g, stream        ; I_2
.seg 0, src=feed, run, lane_loop, repeat=10      ; fed by port 4, the word every 10 clocks; the lane loops from the run's end
.seg 1, src=join, run
.seg 2, src=join, run
.seg 3, src=join, run

; the pin: segment 3's flag, inverted (F = 1 means y negative), on uo_out[0]
.pad 0, tapflag3, invert

; four frames to start with (a 997 Hz tone at -6 dB: left 0, 394, 780, 1150; right 0), so that
; the pump has data before the host's first top-up
.hostin 0x00, 0x00, 0x00, 0x00, 0x8a, 0x01, 0x00, 0x00, 0x0c, 0x03, 0x00, 0x00, 0x7e, 0x04, 0x00, 0x00
