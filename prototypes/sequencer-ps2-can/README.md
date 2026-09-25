# PS/2 and CAN as firmware on the deadline sequencer

The competition post lists PS/2 and CAN among the "other interesting protocols to consider". Both
now run as firmware on the deadline sequencer (`../deadline-sequencer`). They are checked end to
end against models I wrote separately from the firmware and in a different style, with the
interpreter and the RTL in lockstep throughout. The last section says what that independence does
and does not cover.

- **PS/2, both roles**, uses only base-ISA instructions. What it needs beyond the base core is
  programme space: 161 words for the device and 147 for the host, against 64 words per thread
  today (256 is the SRAM plan of record).
- **CAN 2.0A** needs a small ISA variant (`isa_v.ml`, `sequencer_v.ml`). The variant adds a CRC
  engine with a programmable polynomial and a bit-stuffing tracker with a programmable run
  length, both generic, plus a conditional jump, a configuration instruction, a tagged OUT and an
  8-bit pc. Bit timing (hard sync, resynchronisation with SJW), arbitration, ACK and error flags
  are firmware. The base files are untouched; the proposed change and its cost are written up
  under "ISA variant" below.

Every number below comes from `logs/2026-09-25/`, which `logs/2026-09-25/run.sh` regenerates
(commit, OCaml and Hardcaml versions in `provenance.txt`).

## Files

| file | what |
|---|---|
| `isa_v.ml`, `sequencer_v.ml`, `harness_v.ml` | the ISA variant: interpreter (executable specification), Hardcaml RTL, Cyclesim harness |
| `lockstep.ml` | variant RTL against variant interpreter on random programmes |
| `sim.ml` | femtosecond-resolution kernel of clocked agents; open-collector line with pull-up and rise time; the lockstep `Machine` (every cycle compares pins, output enables, host output, pcs and the assists' hidden state); an assembler with labels |
| `ps2_fw.ml` | PS/2 device and host firmware generators |
| `ps2_model.ml` | independent PS/2 PC-host and keyboard models |
| `ps2_bench.ml`, `ps2_main.ml` | host-side applications, scenarios, controls, random runs |
| `can_fw.ml` | CAN RX-thread and TX-thread firmware generators; the host driver's frame encoder |
| `can_model.ml` | independent wired-AND bus with delays, reference CAN node, reference encoder |
| `can_bench.ml`, `can_main.ml` | host driver (retransmission, RX decoding), scenarios, controls, random runs, bit-rate sweep |
| `emit_v.ml`, `synth/` | Verilog for synthesis; yosys reports |
| `dbg/` | trace tools used while debugging; `dbg/crc` checks CRC-15 against the published check value |

Build and run: `opam exec --switch=5.3.0 -- dune build`, then `./_build/default/ps2_main.exe [seeds]`
and `./_build/default/can_main.exe [runs] [N SP SJW]`.

## PS/2

**Firmware** (`ps2_fw.ml`). Both lines are open collector. A thread pulls a line low with SETP
value 0 and oe 1, or SHO in open-drain mode, and releases it with oe 0. It reads the lines through
`pin_in`, which is the pad, so it sees the wire. There is no ALU, so odd parity lives in the pc:
each bit loop exists as an "even so far" copy and an "odd so far" copy, and a data bit that reads
back as 1 jumps to the same point in the other copy. Events go to the host as (value, kind) OUT
pairs.

- **Device (keyboard).** Generates a 12.5 kHz clock. Before each falling edge it checks that the
  host has not inhibited the clock, and aborts if it has. It detects a host request to send and
  clocks in the command, with parity and stop checks, then the acknowledge bit. It sends the
  bytes a keyboard application supplies, and that application answers commands (0xFF: FA AA;
  0xED: FA, LEDs, FA; 0xEE: EE; 0xF2: FA AB 83; a parity error: FE) and retransmits aborted bytes.
- **Host.** Receives on falling edges, with parity, start and stop checks and a timeout per edge.
  Sends commands by inhibiting for 110 us, requesting to send and clocking the bits out on the
  device's clock, then checks the acknowledge.
- A doorbell pin tells each thread that the host side has something to send, because IN blocks.
  A non-blocking IN, or a JC condition on `host_in_valid`, would free that pin.

**Models** (`ps2_model.ml`). Written from the protocol description, not the firmware, as a PC
host and a keyboard. Each checks the other side's timing: a 10 to 16.7 kHz clock, each phase 30 to
50 us, data changing only while the clock is high with 5 us of margin on each side, and the host
changing data only while the clock is low. Lines have a finite rise time.

**Results** (`logs/2026-09-25/ps2.txt`):

- **Scenarios, all passing with 0 lockstep mismatches:**
  - our device against the model host: "hello" as 15 make and break codes, four commands (FF,
    ED 02, EE), two inhibits, 1.47 M cycles. The host received every scan code exactly once, in
    order, and the responses FA AA FA FA EE. The device reported 6 aborts, and each byte was
    retransmitted;
  - our host against the model keyboard at 13 kHz (ED, 07, F2), 1.24 M cycles;
  - our device and our host on one sequencer (threads 0 and 1), wired together, 1.26 M cycles.
- **Controls, each caught (6 of 6):**
  - a byte sent with even parity by the model keyboard: the host firmware flags exactly that byte;
  - a command with even parity from the model host: the device firmware flags it, and the
    keyboard replies FE;
  - device firmware mutated to even parity: the model host sees every byte's parity wrong;
  - host firmware mutated to even parity: the model keyboard rejects its commands;
  - device firmware clocked at 25 kHz: the model host reports 20 us clock phases;
  - device firmware without the inhibit check, with host inhibits: the model host reports timing
    violations and lost bytes.
- **Constrained random:** 16 of 16 runs pass (8 seeds per role), with 18.6 M cycles in lockstep
  and 0 mismatches. The runs vary:
  - random scan codes and commands (FF, ED + argument, EE, F2, F4);
  - 0 to 3 host inhibits at random times;
  - line rise times from 0.3 to 5 us;
  - keyboard clocks from 10.5 to 16.5 kHz.
- **In total, about 22.6 M cycles** were compared between the interpreter and the RTL, with 0
  mismatches.

**What the checks found.** The finite rise time exposed two firmware bugs, and the models had
one of their own:
- A released line reads low for its rise time. The device read its own release after the
  acknowledge as a new request to send, and the host read its own clock release as the device's
  first clock edge. The fix is that a condition must persist before it counts, and an edge wait
  must first see the opposite level. The keyboard model had the same bug.
- **WAITP is an immediate branch only while `dl` = 0.** After `LDD n; WAITP ...` ends early,
  `dl` is still counting, so the next "branch" WAITP stalls instead. The host's parity branches
  and the device's idle loop both did this. The assembler now has `br`, which is `LDD 0; WAITP`.
  This is an ergonomic cost of the ISA, and a pin condition in JC (below) would remove it.

## CAN

**Node structure** (`can_fw.ml`). A node is two threads, and one core holds two nodes (all four
threads). Pins per node:
- `rx`, the bus;
- `txd`, the TX thread's bit;
- `txe`, the RX thread's ACK and error flags (the transceiver drives `txd` AND `txe`);
- `flag`, the TX thread telling the RX thread "this frame is ours", so that it does not
  acknowledge it.

- **RX thread (209 words): bit timing and bit-stream processing.**
  - *Hard sync:* WAITP polls the bus every slot, and the slot that sees SOF is the bit start.
  - *Resynchronisation, in firmware:* if the last sampled bit was recessive, `LDD 2·SJW;
    WAITP rx==0` watches a window of ±SJW around the nominal bit start. An edge in the window
    becomes the new bit start (phase error corrected in full). An edge before the window is
    taken at its opening (phase 2 shortened by SJW). With no edge by the window's end, a second
    `WAITP` watches until the sample point: a late edge lengthens phase 1 by SJW, and no edge
    means a recessive bit at the nominal time.
  - *The deadline register does double duty.* After a WAITP ends early, `dl` keeps counting, so
    a WAITD afterwards waits until a fixed absolute time. That is what a late edge's
    "sample SJW later" needs.
  - *Every path is balanced* by the generator, so all of them reach the sample SHI exactly at
    B' + SP.
  - *Destuffing and CRC-15:* the variant's tracker and engine, fed by SHI flags.
  - *DLC dispatch:* a constant-time branch tree on the accumulator (JC). Data and CRC are then one
    field of 8·bytes + 15 bits.
  - *ACK and error flags:* stuff, CRC (after the ACK delimiter) and form errors. After an error
    it waits for 10 recessive bit times.
- **TX thread (61 words): arbitration and bit monitoring.**
  - It drives a stream that the host driver has already stuffed and given a CRC, like the Ethernet
    prototype, and takes its length from the first byte with `cnt <- acc`.
  - At each sample point it branches on its own `txd` pad: a recessive bit that reads dominant
    means arbitration is lost (or a bit error), and it stops driving within that bit.
  - It waits for bus idle (10 recessive bits, then an 11th during which a SOF from another node
    is joined), checks the ACK slot and EOF, and reports to the host driver, which retransmits.
- **Bit timing at 500 kbit/s, 60 MHz:** N = 30 slots (one slot is 4 clocks, 66.7 ns), sample
  point 23 (77 %), SJW 3 slots (10 %).

**Independent models** (`can_model.ml`), deliberately in a different style from the firmware:
- *Bus:* wired-AND, and each node hears node i after `delay_i + delay_j`, so a node hears its own
  bits after twice its delay.
- *Reference node:* a time-quantum bit-timing machine (sync, prop, phase 1 and phase 2 segments;
  16 tq per bit; the standard phase-error rules). Its bit-stream processor stuffs on the fly and
  computes the CRC by its own long division. It transmits, arbitrates, acknowledges, raises error
  flags and retransmits.
- *Oscillators:* every agent has its own clock (ppm offsets are exact to 1 fs per edge).

Before any of this was trusted, the three CRC-15 implementations (the driver's, the reference
model's, and the variant engine left-aligned) were checked against the published CRC-15/CAN check
value for "123456789", 0x059E (`logs/2026-09-25/crccheck.txt`).

**Results at 500 kbit/s** (`logs/2026-09-25/can-500k.txt`):

- **Scenarios, all passing with 0 lockstep mismatches:**
  - *S1, one sequencer, two of our nodes and a reference node at +0.3 %.* A (0x123) and B
    (0x0F0) start together. B wins arbitration, A loses once and retransmits, then the reference
    node sends a remote frame. The bus order is 0F0, 123, 7FF, and every node receives the other
    nodes' frames exactly once.
  - *S2, two sequencer instances at +0.5 % and -0.5 % and the reference at +0.2 %,
    three-way arbitration* on 3A4 (reference), 3A5 and 3A6, which differ only in their last bits.
    The bus order is 3A4, 3A5, 3A6.
  - *S3, the raw sample stream* (below) equals the reference encoder's bits, stuffed, with all 13
    stuff bits marked.
  - *S4, a node does not acknowledge its own frame.* A is alone with a reference node that does
    not acknowledge, and every attempt reports "no ACK". The mutant that ignores `flag` fails this
    check (A then acknowledges itself).
- **Controls, each caught (5 of 5):**
  - *A's stream with its first stuff bit missing:* B reports stuff errors (END 1), the reference
    node reports stuff errors, and A's TX thread sees the error flags (status 3).
  - *A's CRC with its last bit flipped:* B reports CRC error (END 2) with no ACK, and the
    reference reports a CRC error.
  - *B's RX firmware without resynchronisation,* the reference at +0.5 % and our clock at -0.5 %,
    a long frame with few edges: B receives nothing correctly. The same frame with
    resynchronisation is received.
  - *B with the wrong CRC polynomial:* CRC errors on good frames.
  - *No arbitration check* (A and B start together and neither backs off): the reference sees
    stuff errors and no good frame.
- **Constrained random:** 20 of 20 runs pass. Each run has:
  - two sequencer instances holding one or two nodes each, plus the reference node;
  - every clock drawn within ±0.5 %;
  - propagation delays of 10 to 150 ns per node;
  - 3 to 7 random frames (random IDs, DLC 0 to 8, remote frames), often submitted simultaneously.

  Across the runs, 36 arbitration losses were resolved. Every frame reached every other node
  exactly once, every transmitter saw its ACK, and no node reported an error.
- **In total at 500 kbit/s:** 109 frames on the bus, and 2.95 M cycles compared between the
  interpreter and the RTL, with 0 mismatches. With shared configuration: 8 of 8 random runs pass
  (`can-500k-shared-cfg.txt`).

**Interface for other consumers** (for example a bus analyser). The RX thread reports through
tagged OUT (tag, value). `Can_bench.rx_event` decodes this into `rx_frame` records, and
`Can_bench.decode_bytes` recovers the frame:

| tag | meaning |
|---|---|
| 1 SOF | a frame starts (value 0) |
| 0 DATA | destuffed bits, msb first: 3 bits (SOF ID10 ID9), 8 (ID8..ID1), 8 (ID0 RTR IDE r0 DLC), then data and CRC as 7 bits followed by 8-bit chunks |
| 2 CRC | 1 matched, 0 CRC error |
| 3 ACK | bit 0 = bus level in the ACK slot (0 = acknowledged) |
| 4 END | 0 ok, 1 stuff error, 2 CRC error, 3 form error, 5 extended frame (unsupported) |
| 6 RAW | with `~raw:true`: every sampled data bit (bit 0) |
| 7 STUFF | with `~raw:true`: a stuff bit was sampled here |
| 5 TX | TX thread: 1 acknowledged, 2 no acknowledge, 3 lost arbitration or bit error, 4 error in EOF |

The raw stream costs one slot per bit, so the sample point moves one slot earlier. A scenario
checks that it equals the reference encoder's bits, stuffed by a third, minimal stuffer, with
every stuff bit marked.

**Maximum bit rate at 60 MHz.** Every thread issues once every 4 clocks (15 M slots/s) whatever
the other threads do. A node's rate therefore does not depend on how many nodes share the core,
and two nodes use all four threads. The firmware's own constraints are:
- the header's pre-sample slack must hold the bookkeeping and the DLC tree: SP >= SJW + 16;
- the post-sample path must fit before the window opens: N - SP >= SJW + 4;
- the TX thread needs N - SP >= 6;

so N >= 2·SJW + 20. Sweep results (the full suite; 20 random runs at 500 kbit/s, 12 at the
other rates):

| N slots | kbit/s | SP | SJW | RX words | result |
|---|---|---|---|---|---|
| 30 | 500 | 23 (77 %) | 3 | 209 | all pass (20 random runs) |
| 27 | 556 | 20 (74 %) | 3 | 209 | all pass |
| 24 | 625 | 18 (75 %) | 2 | 208 | all pass (the raw stream does not fit) |
| 23 | 652 | 17 (74 %) | 1 | 208 | random runs pass; the worst-case tolerance control fails *with* resynchronisation |
| <= 22 | >= 682 | | | | the generator refuses: no slack for the DLC tree |

- **The fastest usable rate is 625 kbit/s** (N = 24, SJW 2, sample point 75 %). "Usable" means
  it passes everything, including the worst-case tolerance control at ±0.5 % per node. It is the
  maximum of this firmware structure, not a bound for every possible programme.
- At 652 kbit/s the only possible SJW is 1 slot. The random runs pass there, but the worst-case
  control (clocks 1 % apart, a long frame with few edges) fails even *with* resynchronisation, so
  that rate is not usable at ±0.5 % tolerance.
- 1 Mbit/s (N = 15) is out of reach for a per-bit firmware receiver. The fixed per-bit path is
  already about 13 slots before any timing slack: sample, stuff check, last-bit check, window
  set-up, a window of 2·SJW + 1 slots, bookkeeping, jump.

**What needs more than firmware.** For CRC-15 and destuffing this is an argument, not a proof;
no size search over alternative encodings was done.
- **CRC-15.** The base ISA has no ALU. Its only data state is the 8-bit accumulator, which can
  only be filled by shifting in pin levels (even levels the thread drives itself on a spare pin),
  plus the pc and the counters. A 15-bit CRC state therefore needs at least 7 bits held in the pc,
  and each of those 128 states needs its own code for every bit step. That is far beyond 256
  words. This needs the generic CRC engine.
- **Destuffing.** A run-length state machine in the pc needs 10 states (last bit times run
  length) replicated for every field and every field exit, which is again far beyond 256 words.
  This needs the generic stuff tracker.
- **Branching on data** (DLC, RTR, IDE). This needs JC. Otherwise it is firmware, as a
  constant-time tree.
- **Length from data** (TX stream length). This needs `cnt <- acc`.
- **Separating streams at the host.** This needs the tagged OUT: without it the host cannot tell
  data bytes from status codes.
- **Pure firmware, no hardware:** hard sync, resynchronisation with SJW, arbitration, bit
  monitoring, ACK, error flags, bus-idle detection and retransmission (with the host driver).
- **To go faster:**
  - A *length-from-data assist* (for example `cnt <- (acc & 15) · 8 + 15`, or a general
    `cnt <- (acc << s) + imm`) would remove the DLC tree. The header constraint becomes
    SP >= SJW + 9, which allows about 750 kbit/s with a sample point of at least 70 %.
  - *1 Mbit/s* needs a *hardware bit-timing front end*: an edge-tracking sampler with a
    programmable bit period, sample point and SJW, hard and soft sync, that shifts bits through
    the stuff tracker into a per-thread register and raises a condition per bit or per byte. That
    is generic: CAN, UART receive (hard sync only), USB (NRZI plus stuffing), 10BASE-T
    (Manchester). It would also improve the time resolution from one slot (66.7 ns) to one clock.
  - *ID acceptance filtering* is not done: the host gets every frame. It could be done in firmware
    as a JC tree on the header, at a cost in words, or by the systolic matcher on the destuffed
    stream.

## ISA variant: the proposed change

The variant is `isa_v.ml` (interpreter and specification) with `sequencer_v.ml` (RTL). Its
lockstep (`lockstep.exe`) runs 300 random programmes of 2,000 cycles, half of them biased towards
the new instructions, and compares the assists' hidden state through debug ports: 0 mismatches,
in both the per-thread and the shared configuration. Pairing the shared interpreter with the
per-thread RTL gives 343,743 mismatching cycles, so the test does distinguish the two.
Without the bias and the debug ports, uniform random programmes missed two of five planted RTL
bugs (the CRC feedback and the stuff-run rule). With them, 6 of 6 non-equivalent planted bugs
are caught; the seventh is equivalent (0+1 = 1).

| change | encoding | why, and which protocols it serves |
|---|---|---|
| 8-bit pc (256 words per thread) | WAITP fail, JMP and JNZ address fields widen to [7:0] (bits 7..6 were unused) | the SRAM plan of record; PS/2 roles are 147 to 161 words, CAN RX 209 |
| CRC engine, per thread: `crc` (16), `poly` (16) | SHO/SHI bit 6 feeds the driven or sampled bit; CFG 1/2 load `poly`; CFG 0 clears; JC 8 on `crc = 0` | any CRC up to 16 bits, left aligned: CAN CRC-15, USB CRC-5 and CRC-16, CRC-8 buses; 32 bits (Ethernet) would double it |
| stuff tracker, per thread: `last`, `run` (3), `limit` (3), `mode` | SHO/SHI bit 5 feeds it; SHI bit 4 (`norec`) consumes a stuff bit without recording it; JC 9 on `run >= limit`; JC 11 on `last` | CAN (5 equal bits), USB (6 ones, with NRZI), HDLC (5 ones) |
| JC: jump on a condition | opcode E: cond[11:8], addr[7:0]; acc bit 0..7, crc = 0, stuff, byte boundary (`cnt[2:0] = 0`), last | branching on received data at all (DLC, RTR, flags); byte boundaries in bit loops |
| CFG | opcode F: sub[11:10] | polynomial, stuff mode and limit; `cnt <- acc` (a length from the data stream) |
| tagged OUT | OUT src[11] tag[10:8] imm[7:0]; `host_out_tag` port | lets the host tell streams apart (data, status, raw samples, threads) and output a constant without touching acc |

**Compatibility with master's extension** (SETP and SHO sub-slot `q[1:0]`, SHI `quad[7]`): no
clash. The variant's SHO flags use bits 6..5 and its SHI flags bits 6..4, SETP is untouched,
opcodes E and F are NOP on master, and OUT's fields were unused. A merged ISA can carry both.

**Cost** (yosys 0.69, sg13g2 typical liberty, flattened, the same flow as the base core's number;
`synth/*.stat.txt`):

| core | cells | area um2 | flip-flops |
|---|---|---|---|
| base (`../deadline-sequencer`) | 1,072 | 17,266 | 179 |
| variant, configuration per thread | 2,055 | 34,046 | 350 |
| variant, configuration shared by the four threads | 1,845 | 29,428 | 290 |

The per-thread assists double the core. Sharing `poly`, `limit` and `mode` (both configurations
pass lockstep and the full CAN suite) brings the increase down to 70 %; what remains is the
per-thread `crc`, `run` and `last` and their muxing. Cheaper points, not built:
- engines on two threads only (a core then holds two CAN nodes, not four protocol engines);
- one engine owned by a thread.

My recommendation is shared configuration plus the 8-bit pc, JC and the tagged OUT. The engine
count should follow how many threads will run CRC-protected protocols at once.

**Proposed, not built:**
- a JC condition on an input pin, which removes the `LDD 0` a branch after a timed wait needs;
- a JC condition on `host_in_valid`, which replaces the doorbell pins;
- `cnt <- (acc << s) + imm`, which removes the DLC tree;
- the bit-timing front end above.

## Limitations and open questions

- **CAN transmitter.** On a bit error outside arbitration the TX thread stops and reports, but
  sends no error flag of its own; the receivers' error frames carry the error. The TX thread does
  not resynchronise while transmitting (it is the timing source while it is winning). There are no
  error counters, no bus-off and no overload frames. Extended (29-bit) frames are reported as
  unsupported. There is no SOF glitch filter in the firmware.
- **The TX stream relies on a ready host,** as in the Ethernet prototype. IN must find the next
  byte ready in its slot, because a stall would delay a bit. The bench's host has the whole frame
  ready. A per-thread input FIFO is the hardware answer.
- **Quantisation.** Edges are seen at slot resolution (66.7 ns at 60 MHz). A late edge detected in
  the very last slot of its window leaves WAITD one slot late. That costs one slot, once, in a
  corner case.
- **PS/2 race.** If the host inhibits in the one slot between the device's check and its clock
  pull, the byte is reported as sent while the host voids it. Real PS/2 has the same window. The
  random runs have not hit it.
- **Shared assumptions.** Every encoder, stuffer and CRC here is mine. The CRC catalogue value, the
  three separately written stuffers and the time-quantum reference node reduce the risk of a
  shared misreading. A test against a real CAN controller would remove it, for example on the FPGA
  board with a transceiver and a USB-CAN adapter.
- **What the reference node does not cover.** It is a cross-check, not a complete CAN
  conformance oracle. It has no error counters or error-passive behaviour, no overload frames, and
  no extended frames, and the malformed-frame cases tested are the five controls above. Its
  resynchronisation follows the ISO phase-error rules in time quanta. The firmware's discrete
  window is exact to one slot for phase errors up to SJW, and is tested (not proved) against it
  under ±0.5 % clocks.
