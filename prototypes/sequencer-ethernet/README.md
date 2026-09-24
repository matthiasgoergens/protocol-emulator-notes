# 10BASE-T transmit as firmware on the deadline sequencer

The competition's stretch goal, done in firmware on the existing deadline sequencer, with no new instructions and no Ethernet hardware.

**Why it looked impossible.** At 60 MHz a Manchester half-bit is 3 clocks, and each of the sequencer's four hardware threads issues once every 4 clocks. No single thread can even toggle a pin once per half-bit.

**Why it works.** The four threads together issue every clock, and timing is exact by construction. Half-bit k starts on clock S + 3k; with S a multiple of 4, that is thread (3k) mod 4's slot. So each thread owns every fourth half-bit, 12 clocks apart, with two spare slots in between.

**Precomputation does the rest.**
- The host sorts the frame's half-bits by owning thread, inverts the first halves (Manchester sends a 1 as low then high), and packs 8 per byte.
- Each thread runs the same 24-slot loop: `(SHO; NOP; NOP) x 7, SHO, IN, JMP`.
- A generator (`program` in `main.ml`) computes each thread's prologue, so its first `SHO` lands exactly on its first half-bit.
- Program sizes are 28–30 of 64 slots per thread, with 37 precomputed bytes per thread for a 73-byte frame on the wire.

**Assumption, stated plainly.** The host presents each thread's next byte in the slot where that thread executes `IN`. The schedule is deterministic, so a host clocked alongside can do this; a per-thread input FIFO would be the hardware alternative.

## Checks (`dune exec ./main.exe`)

- **Interpreter against the Ethernet model's own encoder** (`eth_model.ml`, via a symlink): 0 mismatching clocks of 3,504. The frame is preamble, SFD, a UDP frame and the FCS.
- **Controls, which must fail:**
  - one flipped bit in one thread's stream: exactly 3 wrong clocks, one half-bit;
  - thread streams rotated: 1,536 wrong clocks;
  - one thread one slot late: 835 wrong clocks, from its first half-bit.
- **The same firmware on the RTL** (`sequencer.ml` through the prototype's own `harness.ml`, via symlinks): 0 clocks differing from the model, and 0 differing from the interpreter.

## What it means, and what it does not cover

- The sequencer is fast enough for 10BASE-T transmit timing. But all four threads are fully occupied speaking the protocol, which is exactly what a good design should avoid: the CPU should be free for protocol logic and application work. So this is a feasibility result that argues *for* offloading bit timing: a serialiser with a programmable rate, pattern tables, and the systolic array. It is not the intended way to run Ethernet.
- Not yet covered:
  - TP_IDL at the end of the frame (a small addition);
  - link pulses;
  - receiving, which is harder: sampling in rotation and merging bits across threads, with the systolic matcher for the SFD.
