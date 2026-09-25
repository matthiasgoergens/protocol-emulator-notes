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

## Quarter-clock pin timing (`../multiphase`)

The ISA gained three things for the four-phase output and input stage in `../multiphase`, all in
bits that were unused, so every existing programme behaves exactly as before:

- SETP and SHO take a 2-bit sub-slot q (bits 1:0): the new level starts at quarter q of the clock
  instead of at the clock edge. q = 0 is the old behaviour. (Ignored in SHO's open-drain mode.)
- SHI has a quad bit (bit 7): the pin's four quarter-clock samples of the last clock shift into the
  accumulator at once, in time order.
- The core exports `pin_sub`, four bits per pin (the level during each quarter of the clock), and
  takes `pin_in4`, the four samples per pin. `pin_sub` costs 10 flip-flops (the previous pin levels
  and q), not a 32-bit register.

The lockstep test compares `pin_sub` every cycle and feeds random `pin_in4`; three planted faults in
the new logic are caught (`../multiphase/results/isa-controls.txt`). The regenerated
`deadline_sequencer.v` has the new ports; the area and place-and-route figures above are from before
the change.

## What it does not yet have

Programme memory (a 1024x16 SRAM macro is the intended store: 256 words per
thread would be 64 per thread here), a host interface beyond a byte
handshake, per-thread pin ownership checks (the compiler's job), input
synchronisers, any fast-path shifter for USB or Ethernet, and a compiler
for the timing-contract language. The point of the prototype is the
number above: the deterministic core is cheap, so the budget goes to
memory and hardened serialisers.

## Protocol compiler and demo (`compiler.ml`, `decoders.ml`, `demo.ml`)

The point of a deterministic machine is that the difficulty moves into
software. `compiler.ml` turns protocol descriptions into thread programmes
whose every edge time is worked out from the one-slot-per-instruction rule:
a UART transmitter (8N1, any bit period of at least five slots), an SPI
master (mode 0, any even period of at least eight slots) and an I2C master
write (START, bytes with acknowledge clocks whose sampled acknowledge goes
to the host, STOP, with a quarter period of at least four slots). Three
protocols compiled onto three threads use 38, 27 and 63 of the 64 words.

Writing the I2C generator found an ISA gap: an open-drain line must be
released for a one and pulled low for a zero, which the shift-out
instruction could not express. It gained an open-drain mode bit (drive low
for 0, release for 1) in interpreter and RTL; the lockstep test re-verified
the change.

`demo.exe` runs the three programmes on the RTL with an I2C slave model in
the loop and checks them three ways: the interpreter's exact simulation
agrees with the RTL on every cycle, which for a deterministic machine is
the schedule proof; independent decoders in `decoders.ml`, which sample
where a receiver samples and know nothing of the compiler's arithmetic,
recover "OK!" on the UART, 0xA5 0x3C on SPI, and 0xA0 0x5A with
acknowledges and a STOP on I2C; and the measured edge spacings equal the
closed forms with zero deviation (UART bit 64 cycles, SPI period 64, I2C
clock-high 32).

Then misbehaviour on purpose, which costs nothing once timing is compiled:

- Fault injection: data bit 5 of a byte stretched by d slots. A receiver
  that samples mid-bit still decodes up to a cumulative shift of exactly
  half a bit (8 slots, 32 cycles) and breaks with a framing error at 9.
- Timing microscope: the transmitter's bit period swept around a receiver
  fixed at 128 cycles per bit. Decoding survives +-3.1 % and fails at
  +-6.2 %, which is the textbook tolerance of 8N1 framing with mid-bit
  sampling (half a bit over nine and a half bits is about 5 %).

Both are one parameter in the compiler; the hardware is unchanged.
