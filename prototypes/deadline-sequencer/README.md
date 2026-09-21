# Deadline sequencer: a prototype of the timing-contract core

The "safe core" from `synthesis.md`: a small deterministic sequencer whose
primitive is *wait for an event with a deadline*, running four hardware
threads round-robin so that every instruction takes exactly one slot and
timing is exact by construction. Written in Hardcaml, with an OCaml
interpreter as the executable specification and a lockstep differential
test between the two.

## What is here

- `isa.ml`: the ISA (documented at the top of the file), assembler helpers
  and the interpreter. Per thread: a 6-bit pc, an 8-bit shift accumulator,
  a 12-bit loop counter and a 12-bit deadline that counts down once per
  slot. Shared: eight output pins with output enables. Instructions: set
  pins, load counter / deadline / accumulator, wait for a pin level with a
  deadline and a fail address, wait for the deadline, shift a bit out or in
  (counts down the loop counter), jump, jump-if-counter-nonzero, and a
  byte in and out to a host.
- `sequencer.ml`: the RTL. One shared datapath, per-thread register files
  selected by the slot counter; instruction memory is external with one
  cycle of read latency, so the core presents the address for the thread
  that executes next.
- `main.ml`: emits `deadline_sequencer.v`, runs the lockstep test (300
  random programmes, 2000 cycles each, random pin and host inputs,
  comparing pins, output enables, host handshake and all four pcs every
  cycle), a UART transmitter programme checked by sampling the pin, and a
  deadline programme checked on both the event and the timeout path.

Build and run: `opam exec --switch=5.3.0 -- dune build && dune exec ./main.exe`
(Hardcaml v0.17).

## Results

Tests: all pass. A mutation check with the loop-branch condition inverted
in the RTL produces 514,694 mismatching cycles and a failing UART test, so
the lockstep test does detect RTL bugs; the harness's own memory-latency
bug was also caught by it before the RTL was right.

Area (Yosys, area-mode abc, sg13g2 typical liberty, flattened, instruction
memory external): 1,052 cells, 17,300 um2, of which 179 flip-flops are
8,770 um2. For comparison, one fpga_pio state machine measured the same
way is 4,713 cells and 61,638 um2, and one FABulous LUT4AB tile is 36,322
um2.

Place and route (LibreLane 3.0.14 in its container, IHP sg13g2, 15 ns
clock, 65 % target utilisation, `librelane.json`, metrics and flow log in
`pnr-metrics/seq15ns/`):

| Die um2 | Final util | Timing buffers | Wirelength | Route DRC | Setup slack fast / typ / slow | Hold slack worst |
| --- | --- | --- | --- | --- | --- | --- |
| 36,663 | 88 % | 4,596 | 49,358 | 0 | +8.2 / +7.8 / +7.3 ns | +0.17 ns |

The core closes the competition's 66 MHz with 7 ns to spare at the slow
corner, so its worst path is under 8 ns there, against about 45 ns for a
FABulous LUT tile. The die is about 1.2 Tiny Tapeout tiles.

## What it does not yet have

Programme memory (a 1024x16 SRAM macro is the intended store: 256 words per
thread would be 64 per thread here), a host interface beyond a byte
handshake, per-thread pin ownership checks (the compiler's job), input
synchronisers, any fast-path shifter for USB or Ethernet, and a compiler
for the timing-contract language. The point of the prototype is the
number above: the deterministic core is cheap, so the budget goes to
memory and hardened serialisers.
