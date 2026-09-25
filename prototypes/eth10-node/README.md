# A complete 10BASE-T node, in simulation

The competition's stretch goal, finished as far as simulation can take it. The chip answers ARP and
ping for a fixed IP address, and a Python host stack built on scapy judges its replies:

- **Transmit** is firmware on the deadline sequencer. It drives two pins differentially and sends
  TP_IDL at the end of each frame, normal link pulses while idle, and its own inter-packet gap.
- **Receive** is assembled from generic blocks: an edge-tracking sampler, the systolic matcher, a
  CRC unit and a byte packer.
- **The replies** come from a small match-and-rewrite engine. Its tables are precomputed.

Every block has a model, a lockstep or independent check, and planted faults that the checks must
catch. `./run_demo.sh` reproduces everything in `results/` in about three minutes. It needs
Hardcaml v0.17 in the 5.3.0 opam switch, and `uv` for scapy.

The design rule from the other prototypes holds here too, so no block is an "Ethernet block":

| Block | File | Other protocols it serves |
|---|---|---|
| Edge-tracking sampler: Manchester, biphase-mark and NRZ-with-resync modes, 1, 2 or 4 samples per clock | `edge_sampler.ml` | 1553, DALI, RC5, EM4100 (Manchester); USB-PD BMC, S/PDIF, DCC (biphase mark); UART, CAN, full-speed USB, SWD, PS/2 (NRZ) |
| CRC unit: any width up to 32, any polynomial, init, xorout and bit order; residue check | `crc_unit.ml` | CRC-5/16 (USB), CRC-15 (CAN), CRC-8 (SMBus, 1-Wire), Modbus, Kermit |
| Systolic matcher, with an enable so that it steps once per received bit | `matcher_en.ml` (a copy of `../systolic-matcher/matcher.ml` plus the enable) | sync words, USB SYNC, logic-analyser triggers |
| Match-and-rewrite engine: byte templates, then a reply programme of CONST, COPY, ADJ (ones' complement add), TAIL | `engine.ml` | any request/response exchange with precomputable answers (UDP echo, Modbus reads of constants, beacons) |
| Sequencer firmware plus transmit feeder (a fixed bit permutation of the transmit buffer) | `tx_fw.ml`, `node.ml` | the same four-thread schedule serialises anything at 3 clocks per symbol |

## 1. Transmit: TP_IDL, link pulses, gap (`tx_fw.ml`, checked by `clause14.ml`)

This extends `../sequencer-ethernet`, which sent one frame on one pin with no TP_IDL.

**Pins.** TD+ is pin 0 and TD- is pin 1. Both are always driven, and idle is both low, so the
differential is +V, -V or 0.

**Why a second leg costs almost nothing.** No instruction can change two pins at once. But clock
S + 3k + 4 is the next slot of the thread that wrote TD+ for half-bit k. That thread writes TD- for
half-bit k+1 there. Per thread and 12 clocks, the slots are one TD+ write, one TD- write and one
free slot.

**The legs are 4.2 ns apart.** TD+ is written at sub-slot q = 3 and TD- at q = 0, which uses the
sub-slot bits master added to the ISA. On the four-phase output stage this puts the two legs a
quarter clock apart. On the plain clock grid they are one clock apart. Either way the zero
crossings lie on an exact grid.

**TP_IDL and the return to idle are data.** The streams carry TD+ high for 6 half-bits after the
last bit, then idle levels, so the firmware needs no end-of-frame timing.

**Leaving the loop.** Each thread tests its own `end_t` input once per byte, with `WAITP` at
deadline 0. That is a one-slot conditional branch.

**Idle.** Each thread waits for `start` in 60 deadline waits of 3,990 slots. When the waits run
out, thread 0 raises TD+ at q = 3 and thread 2 lowers it 6 clocks later, which makes a 100 ns
pulse. The timer restarts after every pulse and every frame. After a frame the firmware waits 113
slots before it will start the next one, so the firmware keeps the 9.6 µs gap, not the feeder.

**Size.** The programme is 33 of 64 words per thread. There are no new instructions (`SHI` serves
as a decrement).

### Limits encoded in `clause14.ml`

The checker is a judge written from the rules, not from the generator.

| Rule | Encoded | Source |
|---|---|---|
| NLP width | a single positive pulse of 60–200 ns (nominal 100 ns) | 802.3 clause 14 via the Wikipedia summary ("nominal 100 ns, maximum 200 ns"). The 60 ns lower bound is ours. |
| NLP spacing | 8–24 ms after the previous activity; no silence longer than 24 ms | "16 ms ± 8 ms", same source |
| Zero-crossing intervals in a frame | 50 or 100 ns, within ±2.5 ns | Manchester at 10 Mbit/s. The tolerance is ours: quantisation only. It is not the clause-14 jitter figure. |
| TP_IDL | positive for at least 250 ns after the last positive-going crossing | clause 14 as I remember it. I could not check it against the text; fpga4fun says "a positive pulse of about 3 bit-times". |
| TP_IDL, upper | at most 400 ns | our own sanity bound, not from the standard |
| Preamble and SFD | exactly 64 bits; FCS correct | 802.3 framing |
| Inter-packet gap | at least 9.6 µs from the end of the last bit cell | 96 bit times |

### Results (`results/tx.txt`)

| Check | Result |
|---|---|
| 70 ms idle | 4 link pulses, each 100.0 ns wide, 15.976 ms apart, 0 violations |
| 4 frames (one of odd length) in 80 ms, one queued behind another | decoded frames equal the frames sent; TP_IDL 297.9–347.9 ns (the lower figure after a 0 bit, the higher after a 1); 0 violations |
| Frames queued back to back | gaps of 9.74 µs, which the firmware keeps; 0 violations |
| 40 random frames of 60–400 bytes at random times | all decoded equal; 0 violations |
| Sequencer RTL (`sequencer.ml`) alongside the interpreter, 20 ms, 2 frames | 0 diverging clocks (pin_sub, output enables, handshakes) |

**Controls: 8 of 8 caught.** The planted faults were:

- TP_IDL of 4 half-bits;
- link-pulse period of 30 ms, and of 6 ms;
- link pulse 233 ns wide;
- one flipped TD+ bit;
- one thread a slot late;
- an inter-packet wait 3 slots short (9.54 µs);
- the two legs swapped.

**A bug the first run found.** The reference feeder cleared the `end_t` flags when it queued the
next frame, before the old frame's threads had checked them. The threads then ran straight into
the next frame with a 1.6 µs gap. The flags now clear on the new frame's first handshake. The same
rule is in the RTL feeder.

## 2. Receive: which path, and why

Four options were weighed:

- **The fixed receiver** (`../ethernet-10base-t/eth_rx.ml`). It works, but it is an Ethernet
  block, which the competition post argues against.
- **Pin sampler plus firmware.** Capturing every clock is 7.5 M words/s. The sequencer changes
  or reads a pin at most once per slot per thread and would have to follow a 6-clock bit with
  edge tracking. So this cannot keep up.
- **Sequencer threads sampling in rotation.** This is fixed-phase sampling. Over a 1,518-byte
  frame at ±100 ppm per end it drifts by more than a bit, and it would occupy all four threads.
- **Chosen: generic blocks in a chain** (`rx_path.ml`):

  ```
  pins (1 or 4 samples per clock) -> edge sampler, Manchester mode -> bits
      -> systolic matcher (enable = bit valid) on the last 16 bits of preamble + SFD
      -> 18-step delay line (the matcher's latency) -> byte packer + CRC unit (CRC-32 residue)
  ```

  Only the configuration is Ethernet's. The delay-line length was found by trying 15–19. Only 18
  works, and 17 is one of the planted faults.

The sampler also holds its idea of the line level while squelched. So what the comparator shows
during a squelch dropout no longer matters, which answers the "board question" left open by the
hwfuzz finding on `eth_rx`. The results were identical both ways (see below).

### Tolerances (`results/rx.txt`)

Frames were 46–245 random bytes plus FCS. The line was generated in continuous time
(`line.ml`), and the frame counts in the table are intact frames with a good CRC.

| Test | Result |
|---|---|
| Clock offset ±100 ppm (the spec's ±0.01 %) up to ±15 %, receiver at 60, 60.857 and 53.2 MHz, 1 or 4 samples per clock | 20/20 in every cell. The sampler resynchronises on every mid-bit edge, so frequency error hardly matters. |
| Jitter, uniform ±j ns on every edge, at ±100 ppm | 60 MHz, 1 sample/clock: all good to ±8 ns, 7/20 at ±10 ns. 60.86 MHz, 1 sample/clock: to ±8 ns. 60 MHz, 4 samples/clock: to ±10 ns, 8/20 at ±12 ns. 60.86 MHz, 4 samples/clock: to ±10 ns. |
| Preamble truncated to p bits before the SFD | works down to p = 9 and fails at 8. The first edge only starts the burst, and the matcher wants 8 preamble bits plus the SFD. |
| Runts of 14–56 bytes | received with the right length and a good CRC; the engine drops them (length < 64) |
| Corrupted frames: 100 with one flipped bit, 100 with 4 random bytes | 200 rejected, 0 accepted |
| Back to back, 10 frames at +100 ppm | all received with gaps of 9.3 µs down to 200 ns |
| Squelch dropout of k clocks every 3,000 clocks | k = 1: 10/10. k ≥ 2: 2–3/10 and 0/10 at 6. Results identical whether the comparator reads 0 or the line while squelched. |
| RTL against model | edge sampler: 300 random configurations over all modes and n = 1, 2, 4, 0 mismatches (a holdoff+1 model differs on 20,475 clocks). Matcher with enable: 0 mismatches against `../systolic-matcher/model.ml` in enabled steps. CRC unit: 8 catalogue plus 200 random configurations, 0 mismatches. |
| Other modes through the same sampler | biphase mark at 300 kbit/s: ±10 % rate with ±50 ns jitter, and ±300 ns jitter, all exact. UART at 1 Mbaud in NRZ mode: ±6 % baud offset exact. |
| CRC catalogue | the model reproduces the check value and residue of all 8 entries |
| Controls | 4 of 4 caught: delay line 17, SFD template bit flipped, sampler holdoff 3, CRC polynomial bit flipped |

**Jitter, stated plainly.** The sampler measures each mid-bit edge against the previous one, so
the jitter of both edges adds. The ceiling is (75 − 50 − resolution) / 2. That is about ±10 ns
with 4 samples per clock (4.2 ns resolution), and about ±8 ns with 1. I recall the 10BASE-T
receiver requirement as ±13.5 ns but have not checked it against the text. If that figure is
right, the receiver falls short under worst-case jitter.

The remedies, in order of cost:

- a phase-averaging anchor: move the anchor halfway towards the predicted edge time, which helps
  random jitter but not the worst case;
- the delay-line TDC from `../multiphase`;
- a genuine DPLL.

**Squelch dropouts, stated plainly.** A dropout of 2 or more clocks delays one mid-bit edge. The
anchor moves with it, and the next mid-bit edge then looks like a boundary. The board's squelch
should hold for at least a bit time after the last edge. That is a front-end requirement.

## 3. The ARP / ping node (`engine.ml`, `node.ml`, `node_demo.ml`, `host_stack.py`)

The line into the node carries frames built by scapy. Their FCS comes from Python's `zlib.crc32`.
The whole node is simulated clock by clock:

- the receive path;
- the engine;
- the transmit feeder (RTL);
- the sequencer RTL running the firmware above, through `harness.ml`.

**How the node's output is judged.** The node's differential output goes through `clause14.ml` and
is decoded. Each reply is compared with the engine's OCaml model. The replies are also written out
for `host_stack.py check`, which parses them with scapy and checks all of the following:

- MACs and IP addresses swapped;
- ARP opcode, sender and target;
- ICMP type 0 with the same id, sequence number and payload;
- IP and ICMP checksums, recomputed from scratch by scapy;
- the FCS, via zlib;
- no reply at all to anything that must not be answered.

**The replies are precomputed where possible.**

- **ARP:** 60 bytes, of which 16 are copied from the request and the rest are constants.
- **ICMP echo:** the request with MACs and IP addresses swapped, type 8 changed to 0, and the ICMP
  checksum updated by ones' complement +0x0800 (RFC 1624). That addition is the only arithmetic.
- **IP header checksum:** unchanged, because swapping source and destination does not change the
  sum. TTL and identification are kept.

**Requests the templates reject:**

- IP options;
- fragments (MF set or a non-zero offset);
- another IP or MAC;
- ARP replies;
- ICMP echo replies;
- UDP.

**The feeder** is a fixed bit permutation of the transmit buffer: preamble and SFD generated, the
frame and FCS read, handed to each thread at its IN. It raises `start` only on round boundaries,
and only after 9.6 µs without carrier on the receive side (half-duplex deferral).

| Run (`results/demo.txt`) | Result |
|---|---|
| Seed 1: 19 directed requests plus 20 random ones | 29 of 29 expected replies correct; 10 of 10 correctly unanswered (bad FCS 1, runt 1, no match 8); 0 clause-14 violations; model agrees request by request |
| Seed 2: the directed requests plus 100 random ones (random sizes 0–199, ids, TTL, DF, TOS, source addresses) | 109 of 109 correct; 10 of 10 correctly unanswered |
| Latency, from the end of a request to the start of its reply | 10.3–37.2 µs: 9.6 µs of deferral, plus the bit-serial FCS pass for long replies |
| Busy: requests 20 µs apart | 15 replies, 14 dropped as busy and counted; every reply sent is the model's reply to a request |
| Controls, judged by the host stack | 5 of 5 fail as they must: ICMP adjust 0x0801; no IP swap; ARP template ignoring the target IP (answers `arp-other-ip`); FCS bytes reversed; firmware thread one slot late |

## Area (Yosys, sg13g2 typical, same recipe as `../pin-sampler`; `synth/area.txt`)

| Block | µm² | Cells |
|---|---|---|
| Edge sampler, 1 sample per clock, run-time configuration | 2,991 | 229 |
| Edge sampler, 4 samples per clock | 9,184 | 1,111 |
| CRC unit, any configuration (config registers are inputs, so not counted) | 6,956 | 597 |
| Matcher with enable | 11,422 | 313 |
| Whole receive path, 4 samples per clock, Ethernet constants | 19,959 | 893 |

The engine and feeder were not synthesised. Their 256- and 512-byte buffers are SRAM or
systolic-storage material, not flip-flops.

## ISA and hardware proposals (for deliberate merging; nothing here changes shared sources)

Encodings are checked against master's `isa.ml`. SHO uses pin[11:9], msb[8], od[7] and q[1:0], so
bits 6..2 are free.

1. **Complementary pair on SHO** (bit 6). It would drive `pin` with the bit and `pin+1` with its
   complement in the same slot, at sub-slot q.
   - Gain: differential transmit then needs one write per half-bit, not two, with zero leg skew.
     That halves the stream to 4 bits per thread per 12 clocks and frees one slot in three per
     thread.
   - Cost: a second write path in the pin register, about 10 cells.
   - Also serves: RS-485 and LVDS-style pins, and H-bridge drives.
2. **Round-latched inputs.** An option bit (or a SETP-style configuration) to latch `pin_in` once
   every 4 clocks, so all four threads see the same value in a round. Today the feeder has to
   promise that `start` changes only on round boundaries. That promise suits hardware but is a
   trap for anything external.
3. **An enable on the systolic matcher's datapath** (`matcher_en.ml`), one enable on the register
   spec. It lets the array step per recovered bit instead of per clock.

Not proposed: a decrement instruction. `SHI` on an unused pin already decrements `cnt`, at the
cost of clobbering `acc`.

## What an FPGA or real-switch test needs (bring-up is another agent's job)

**Clock.** 60 MHz exactly. The RP2040's PLL gives it from a 12 MHz crystal (VCO 1,440 MHz, divided
by 6 and 4). The node's transmitter needs this clock. At the NTSC-friendly 60.857 MHz a 3-clock
half-bit is 1.4 % fast, far outside the ±100 ppm transmit tolerance. Receive works at both.

**Magnetics.** An RJ45 jack with integrated 1:1 magnetics, for example the widely used
HR911105A-class parts. Use a 10/100 part, not a gigabit one, and wire the centre taps as its
datasheet says.

**Transmit resistor network.** Two 3.3 V pins through series resistors into the TX winding.

- With both pins driven and idle both low, the differential swing is ±3.3 V × 100 / (100 + 2R)
  into the 100 Ω line. R of 20–30 Ω each gives 2.1–2.4 V peak at 21–24 mA per pin. The target is
  10BASE-T's 2.2–2.8 V peak into 100 Ω, a figure I recall rather than checked.
- Check the FPGA bank's drive strength, and optionally add a small RC low-pass to soften the
  edges.
- The abrupt return to 0 after TP_IDL may overshoot through the transformer. The standard's
  TP_IDL template limits that, so look at it on a scope.

**Receive front end.** The transformer's RX winding, terminated in 100 Ω, into a differential
comparator: an FPGA LVDS input biased to mid-rail, or a fast comparator. Squelch comes from a
second comparator, or from an amplitude threshold of about 300 mV, into `active`.

- The squelch must hold for at least a bit time after the last edge; see the dropout result.
- With 4 samples per clock, feed the comparator into the four-phase input stage.

**RP2040 roles.**

- The exact 60 MHz clock.
- A second, independent 10BASE-T endpoint: an RP2040 PIO implementation such as the
  Pico-10BASE-T projects, to bring the link up against something simpler than a switch.
- A PIO logic analyser on TD± and the comparator outputs, to measure link-pulse period, TP_IDL and
  edge timing against `clause14.ml`'s rules.

**Link partner.** A managed switch or a PC NIC. With link pulses only (no FLP autonegotiation) the
partner will parallel-detect 10 Mbit/s half duplex. On a PC, `ethtool` shows link and error
counters, and `ping` plus Wireshark on 10.0.0.x checks the replies.

## Open questions and gaps

- **Clause-14 numbers.** TP_IDL's 250 ns minimum and the receiver jitter figure are from memory.
  The NLP numbers are from a secondary source. Check them against the 802.3 text before trusting
  the checker's verdicts at the margins.
- **Half duplex.** There is deferral but no collision detection, jam or backoff. The busy test
  shows a request arriving during a reply, which on a real half-duplex link would be a collision.
- **No autonegotiation (FLP bursts).** The switch must accept a 10 Mbit/s half-duplex link partner
  by parallel detection.
- **Latency.** The bit-serial FCS pass adds up to 30 µs for long replies. An 8-bit-per-clock CRC
  step, or computing the FCS during the rewrite pass, removes it.
- **One reply in flight.** A second buffer, or streaming the reply while it is computed, would let
  a burst of pings all be answered.
- **Transmit at the NTSC clock.** It might be possible with quarter-clock edge placement, but the
  thread-ownership schedule breaks, so it was not tried.
