# Architecture v0: one programmable chip (note, 2026-09-25)

The prototypes so far are mostly special-purpose hardware: a sprite pipeline, a USB engine, an
Ethernet receiver, a semiring ring, a wave engine. This note converges them into **one chip made of
a few generic programmable blocks**, on which every protocol and every demo is a programme or a
configuration. Jane Street's post asks for exactly that: "The goal isn't to put a UART block, an
SPI block, and an I2C block on one die" (`notes/jane-street-alignment.md`).

The special-purpose prototypes are used twice: as workloads that must map onto the generic blocks,
and as **evidence for which blocks to have** (section 1 counts which primitive operations they
needed). Numbers point to files. Paths without a prefix are in this repository at this branch;
paths marked "(master)" are on master at commit 623cc7c, from work that landed while this note was
being written. New area probes made for this note are in `prototypes/unified-pe/` (its README
says what they are: synthesised, not verified). "est" marks an estimate.

Contents: 1 how the blocks were chosen; 2 the blocks; 3 the mapping table; 4 workload mixes,
and what the array buys (the premise check); 5 gaps; 6 area budget; 7 determinism;
8 verification; 9 open decisions.

```
                    host (RP2040/RP2350 on the demo board)
                                 | host link: programme and config loading, streams
   +-----------------------------+------------------------------------------------+
   | sequencer: 4 barrel threads, deadline waits, ISA v1 ---- programme SRAM 512x16 |
   |    | push/pull bus (one per clock)  | pin writes/reads, virtual pins  | mailbox |
   |    v                                v                                          |
   | PE array: 16 unified PEs,         pin stage: four-phase out/in, open drain,    |
   | segments 2|2|4|8, loop-backs,     complementary pairs, streamer, sampler,      |
   | feed/tap per segment  <------->   pin NCO, fine delay (2 pins)                 |
   |    ^                               ^  assists on the bit path: edge-tracking    |
   |    | fixed ports                   |  sampler, stuff tracker, line coder,       |
   | gain-cell banks 2 x 4 kbit (Berger, allocator)   systolic matcher with enable |
   +--------------------------------------------------------------------------------+
            one clock, 60.000 MHz, four phases derived on chip
```

## 1. How the blocks were chosen: primitives counted across the prototypes

For each prototype, the primitive operations it needed, then how many prototypes needed each. The
rule applied: a primitive needed by many prototypes becomes a generic block or a PE mode; one
needed by a single prototype goes to firmware, the host or memory, unless its instance count per
use is high (then it is a cheap PE mode) or it is the chip's reason to exist (debugging). The PE
mode costs are measured (`prototypes/unified-pe/results/areas.txt`).

Short names: seq `deadline-sequencer`, mph `multiphase`, str `pin-streamer`, smp `pin-sampler`,
mat `systolic-matcher`, ring `semiring-ring`, wave `wave-engine`, crazy `crazy-network` (parked),
con `retro-console`, cv `composite-video`, pale `pal-ethernet`, eth `ethernet-10base-t`, seqe
`sequencer-ethernet`, usb `usb-fs-device`, 1bit `one-bit-synth`, sort `sorting-search`, sto
`systolic-storage`; from master: e10 `eth10-node`, gps `gps-hotcold`, jtag `proto-jtag-swd`, can
`sequencer-ps2-can`.

| # | primitive | needed by | n | decision |
|---|---|---|---|---|
| P1 | pin write or read in an exact slot; wait with a deadline | seq, seqe, e10, jtag, can, gps (UART RX), mph; video line timing in con, wave, ring, crazy | 11 | **sequencer** |
| P2 | more than 64 programme words per thread | jtag (SWD 221 words), can (PS/2 147–161, CAN RX 209) | 2 | 8-bit pc; decisive for real firmware |
| P3 | branch on data | can (JC), jtag (pin read-back trick), e10 (WAITP at deadline 0), ps2 (parity in the pc) | 3 | JC instruction |
| P4 | edges and samples between clock edges | mph (FM, 4× receive), e10 (legs at q=3/q=0; 4× receive), usb (4 samples/bit), pale (1× fails from ±4 ns) | 4 | **four-phase pin stage** |
| P5 | programmable delay and time-to-digital | mph (shmoo, runts, FM DTC rows) | 1 | option on 2 pins: the debugging use case |
| P6 | serialise or deserialise a FIFO at a fixed period, CPU-free | str, smp, cv, seqe, e10 (feeder, byte packer), 1bit | 6 | **streamer and sampler** |
| P7 | bit recovery that resynchronises on edges | e10 (edge sampler: Manchester, biphase mark, NRZ), eth, usb, mph (eth_rxn), can (firmware SJW), smp (UART start edge) | 6 | **edge-tracking sampler** (assist) |
| P8 | line coding (NRZI, Manchester) | usb, eth, seqe, e10, str (precomputed) | 5 | line coder (assist, 477 µm²) |
| P9 | bit stuffing with a run length | usb (6 ones), can (5 equal) | 2 | stuff tracker (assist, 813 µm²) |
| P10 | CRC with a programmable polynomial | usb (5, 16), eth (32), e10 (CRC unit), can (15); str (host-precomputed) | 4 | **GF(2) PE mode** (section 2.3) |
| P11 | LFSR, m-sequence, PRBS | gps (G1/G2); planned PRBS for margin tests | 1+ | same GF(2) mode |
| P12 | sync-word correlation with a threshold | mat, e10 (SFD, with enable), usb (SYNC), eth (SFD) | 4 | **systolic matcher** (assist, one instance); popcount in every PE measured at 1,798 µm² per PE, rejected |
| P13 | negate an operand by a data bit (±1 correlation) | gps (wipe-off, correlators); planned PDM decimation | 1+ | tag lane (cheap) |
| P14 | phase accumulator (wrapping add, MSB out) | 1bit, mph (4 points per clock), wave, con (u, v), gps (carrier and code NCOs) | 5 | PE mode; **pin NCO** assist for the four-point version |
| P15 | saturating add/sub, min/max | ring, crazy, sort, wave (sum), 1bit (integrators) | 5 | **PE base** |
| P16 | multi-word add (carry between cells) | gps (32-bit NCOs: 16-bit could not lock) | 1 | tag-lane carry (cheap) |
| P17 | position window, pattern bit, overwrite a passing value | con (16 sprites per line); planned platformer and text overlays | 1+3 | PE WIN mode: one use, but 8–16 instances per use |
| P18 | XOR/AND/OR on words | crazy, con (bit-12 XOR), usb, eth, e10, can (CRCs), mat (xnor) | 6 | PE LOGIC |
| P19 | table lookup | wave, 1bit (sine), ring (colour LUT), usb (descriptors), eth (frame), e10 (reply templates) | 6 | **memory banks as tables**; a per-PE LUT measured at 241 µm², rejected |
| P20 | reload cell state per line through a byte chain | con, ring, wave, crazy | 4 | PE init chain |
| P21 | records circulating in a ring | wave (10 records), ring, crazy | 3 | segment loop-back |
| P22 | count and compare with a threshold | mat, eth, usb, smp, e10 | 5 | PE flag; inside the edge sampler |
| P23 | buffers with a known lifetime | sto, pale, usb, con, e10 (256/512-byte buffers), gps (4 kbit sample banks) | 6 | **gain-cell banks** |
| P24 | sigma-delta modulation | 1bit, cv, gps (tier 1 volume) | 3 | PE wrapping add with carry out |
| P25 | multiply | none: con is multiplier-free, gps uses ±1 | 0 | **no multiplier** (a MAC PE is 2.6–3.6× an add PE, `pe-synth/README.md`) |
| P26 | popcount of a word | mat | 1 | inside the matcher only |
| P27 | match-and-rewrite of byte streams | e10 (engine, not synthesised) | 1 | a PE segment plus a thread plus a bank |
| P28 | heavy host precomputation | str, cv, seqe, e10, jtag (vector compiler), gps (loops, fix), con (game logic) | 7 | host link bandwidth matters |
| P29 | signalling between threads | e10 (flag pins), can (TX→RX flag pin), ps2 (doorbell pin) | 3 | **mailbox** and virtual pins |
| P30 | a pin and its complement in one slot | e10 (TD+/TD−), usb (D+/D−) | 2 | SHO complementary-pair bit |
| P31 | open drain, wired-AND | seq (I2C), smp, can, ps2, jtag (SWD turnaround) | 5 | exists (SHO od, SETP oe) |
| P32 | all threads see one input value per round | e10 | 1 | round-latched inputs, a mode bit |

What the table says. The **sequencer** (P1–P3, P29) and the **pin stage** (P4–P6, P30–P31) are
used by nearly everything. Bit-level stream work (P7–P9, P12) recurs in every serial protocol
but is needed once or twice at a time, so it is cheap assists on the bit path. Word arithmetic
(P13–P18, P20–P22, P24) is the **PE array**. Lookup and buffering (P19, P23) is **memory**. No
prototype needs a multiplier, and only the matcher needs a popcount.

## 2. The blocks

### 2.1 Sequencer: four threads, ISA v1

The deadline sequencer stays as it is in principle: four hardware threads in a barrel, one
instruction per clock, every instruction one slot, timing exact by construction
(`prototypes/deadline-sequencer/README.md`: 1,052 cells, 17,300 µm², closes 66 MHz with 7 ns
slack at the slow corner). Four threads, not more: every measured workload mix in section 4 fits
in four, and each thread issues at 15 M slots/s at 60 MHz whatever the others do
(`sequencer-ps2-can/README.md`, master).

ISA v1 arbitrates every proposal that landed. All encodings checked together (16-bit words,
opcode in 15:12):

| op | v1 fields | origin, and what changed |
|---|---|---|
| 0 NOP | | |
| 1 SETP | mask[11:4] val[3] oe[2] q[1:0] | unchanged (q: quarter-clock sub-slot, `multiphase`) |
| 2 LDC, 3 LDD | imm[11:0] | unchanged |
| 4 LDA | imm[7:0] | unchanged; 11:8 free |
| 5 WAITP | pin[11:9] val[8] fail[7:0] | fail widened to 8 bits (jtag, can: 8-bit pc) |
| 6 WAITD | | unchanged |
| 7 SHO | pin[11:9] msb[8] od[7] cp[6] q[1:0] | **cp: complementary pair** (e10): drives pin and pin+1 inverted in the same slot; 5:2 free |
| 8 SHI | pin[11:9] msb[8] quad[7] | unchanged; 6:0 free |
| 9 JMP, A JNZ | addr[7:0] | widened (8-bit pc) |
| B OUT | src[11] tag[10:8] imm[7:0] | **tagged OUT** (can): the host can tell streams apart |
| C IN, D HALT | | unchanged |
| E JC | cond[11:8] addr[7:0] | **jump on a condition** (can): cond 0–7 acc bit 0–7 set; 8 byte boundary (cnt[2:0] = 0); 9 host_in_valid; 10 own mailbox non-empty; 11 mailbox space free; 12–15 logical pins 4–7 high (which include the virtual pins, below) |
| F EXT | sub[11:8] imm[7:0] | new: 0 FINE (per-edge offset in 1/256 clock, `multiphase` proposed opcode E); 1 CNTA (cnt ← acc, can); 2/3 PUSHL/PUSHH seg (acc into a segment's feed register, high byte marks valid); 4/5 PULLL/PULLH seg (a segment's tap into acc); 6 SEND t / 7 RECV (mailbox); 8/9 LDB/STB (bank byte at the thread's bank pointer, which post-increments); A SHX (jtag's full-duplex shift: out-pin[2:0], in-pin[5:3], msb[6]); B–F reserved |

**Programme counter and store.** The pc and address fields go to 8 bits, as the SWD, PS/2 and
CAN firmware requires (221, 161 and 209 words; `proto-jtag-swd/README.md`,
`sequencer-ps2-can/README.md`, master). The four threads share **one** store: each thread's
instruction address is {page, pc}, with a 2-bit page per thread set by the host. Threads can then
share code and can have unequal sizes. Measured programme sizes of plausible mixes: a CAN node
(209 + 61) plus UART TX (38) plus SPI (27) is 335 words; SWD (221) plus JTAG (48) is 269. Both
exceed a 256-word store. Recommendation: **1P_512x16** (45,309 µm²,
`systolic-storage/results/lef_areas.txt`), with the page bits ready for 1024×16 if area allows.

**Rejected: the per-thread CRC engine and stuff tracker in the sequencer** (can's variant: base
17,266 → 29,428 µm² with shared configuration, 34,046 per-thread). They serve only protocols slow
enough for firmware bit processing (CAN up to 625 kbit/s), only up to 16 bits, and 10BASE-T or
full-speed USB cannot use them. Stuffing moves to the bit-path assist, CRC to the PE array
(section 2.3), and the thread sees "CRC good" as a virtual pin. JC, CNTA, the tagged OUT and the
8-bit pc from that variant are kept.

**WAITP semantics stay.** WAITP branches immediately only while the deadline counter is 0, so a
branch after an early-ending wait needs `LDD 0` first (can). The counting-on is a feature: CAN's
receiver uses it to wait to an absolute time. Immediate branches on a pin go through JC's pin
conditions instead.

**Virtual pins and a pin map.** Each thread addresses 8 logical pins. A per-thread window base
(2 bits) places logical pins 0–7 over the chip's 24 I/Os; logical pins 6 and 7 can instead be
remapped (4 bits each) to one of 16 internal sources: a PE segment's flag, the matcher hit, an edge
sampler's bit-valid, the stuff tracker's error, mailbox full or empty, a TRNG bit. WAITP with a
deadline then waits for "CRC good" or "sync word seen" exactly as for a pin. Cost about 48
configuration bits (est).

**Round-latched inputs** (e10): a mode bit that latches pin_in once per round of four clocks, so
all four threads see the same value. Cost 24 flops (est).

**Mailbox** (backlog; the concurrency work is still running): one 8-bit slot per thread with a
full flag, SEND blocking while full and RECV while empty, both bounded by the deadline register,
so a bridge thread cannot hang. Its full and empty flags are JC conditions. Cost about 40 flops
plus control (est).

Area of v1: the can variant with shared configuration measured 29,428 µm² (Yosys 0.69) with the
8-bit pc, JC, CFG, tagged OUT and the CRC and stuff engines. v1 drops the engines and adds EXT,
the pin map, round latching and the mailbox. The budget uses 29,428 as a proxy (est).

### 2.2 Pin stage

- **Four-phase output and input** (`prototypes/multiphase/`): four toggle lanes per output pin
  XORed, four samplers per input pin with a synchroniser per phase. Sub-slot q on SETP and SHO;
  SHI quad. 2,633 µm² for 2 out + 2 in pins (`multiphase/sta/synth.log`), about 500 µm² per output
  and 750 per input pin.
- **Open drain** (SHO od, SETP oe): I2C, PS/2, CAN, SWD, 1-Wire. Exists.
- **Complementary pair** (SHO cp, new): 10BASE-T TD±, USB D±, RS-485, H-bridges.
- **Streamer and sampler** (`pin-streamer`, `pin-sampler`): the host-fed and host-drained FIFOs
  at a fixed period, with open-drain masks and a 4-bit vector count per word. The sampler doubles
  as the byte packer behind the bit-path assists (its input selects pins or a recovered-bit stream).
- **Pin NCO** (new, generic): a phase accumulator evaluated at the four quarter points of each
  clock, as `multiphase/nco.ml` does for FM, with a phase-offset input. One instance serves FM and
  AM transmit, the colour subcarrier of every video demo (hue as a phase offset), PWM and clock
  outputs at any frequency. 6,678 µm² for 24 bits (`unified-pe/results/areas.txt`).
- **Per-pin output source select**: thread writes, streamer, pin NCO, a line coder, or a segment
  tap (8-way per output pin; about 24 × 3 configuration bits, est).
- **Fine delay option on two pins**: a calibrated delay line per lane (DTC) and a TDC on the same
  line, `multiphase`'s "cheap point" of about 6,500 µm² per pin (est, from `multiphase/README.md`
  and `sta/dtc_area.txt`). The delay chains must be placed as a macro. This is the debugging and
  reverse-engineering feature: shmoo plots, runt and glitch injection, timing fingerprints, and
  equivalent-time sampling (section 7).

### 2.3 Protocol assists on the bit path, and where CRC, stuffing and line coding live

The assists sit between the pin stage and the rest: a received bit stream goes pins → edge
sampler → line decoder → destuffer → packer, with taps to threads (virtual pins), to a PE segment
and to the matcher. Two instances of the chain, because the mixes in section 4 need at most two
bit-level streams at once.

| assist | area µm² | source | serves |
|---|---|---|---|
| edge-tracking sampler, 4 samples per clock / 1 | 9,184 / 2,991 | `eth10-node/synth/area.txt` (master), verified RTL | Manchester (10BASE-T, 1553, DALI, RC5), biphase mark (USB-PD, S/PDIF, DCC), NRZ with resync (UART, CAN, USB, SWD, PS/2) |
| stuff tracker (insert or delete after a programmable run; violation flag) | 813 | `unified-pe`, probe | USB (6 ones), CAN (5 equal), HDLC (5 ones) |
| line coder (NRZI, Manchester, differential Manchester, invert) | 477 | `unified-pe`, probe | USB, 10BASE-T TX, 100BASE-FX |
| systolic matcher with enable, 16 cells | 11,422 | `eth10-node/synth/area.txt` (master) | sync words, SFD, USB SYNC, logic-analyser triggers |

The CAN work asks for a hardware bit-timing front end with programmable SJW for 1 Mbit/s
(`sequencer-ps2-can/README.md`, master): the edge-tracking sampler's NRZ mode is that front end,
with SJW added (gap G6).

**CRC: measured, and decided once for every protocol.** Four candidates:

| option | area | rate | concurrency |
|---|---|---|---|
| CRC engine per thread in the sequencer (can) | +12.2k µm² over the core with shared config (includes JC etc.; measured 29,428 − 17,266) | one bit per SHO/SHI, so CAN ≤ 625 kbit/s in firmware | 4 threads, ≤ 16 bits |
| standalone CRC unit (e10) | 6,956 µm² without its configuration registers (master); 7,127 with poly and state registers, 3,387 for 16 bits (`unified-pe`) | 1 bit per clock | one stream per unit |
| LFSR helper (gps) | "about 3.5k µm²" was an estimate; the measured 32-bit unit with its registers is 7,127 | | |
| **GF(2) mode in every PE** (shift with serial input, XOR/AND/OR, operand gating) | +1,181 µm² per PE on the recommended PE (`upe_v0` against `upe_v0_no_gf2`), 18.9k for 16 PEs | 1 bit per step: 60 Mbit/s | one stream per PE (CRC-32 takes a pair) |

Break-even: 16 × 1,181 / 7,127 = **2.7 concurrent CRC streams**. With at most two, dedicated units
would be about 4k µm² cheaper, a third of a PE. The recommendation is still the **GF(2) PE mode,
and no CRC unit**, for three reasons that are measured or counted, not argued: the same mode is
the LFSR, PRBS, scrambler and Gold-code generator (P11), the word XOR/AND of P18 (six prototypes),
and a sniffer of three buses needs three CRCs, which break-even says the PEs win. One CRC unit per
protocol would also be the "block per protocol" the post argues against.

**Stuffing and line coding stay tiny assists** on the bit path, not PE modes: 813 and 477 µm²
per channel against a PE LUT mode at 241 µm² per PE (3.9k for 16), and, decisively, stuffing
changes the bit rate, which a systolic array stepping in lockstep handles badly while a
FIFO-backed serialiser handles it for free (insert: do not pop; delete: do not push).

**The 10BASE-T match-and-rewrite engine** (e10, not synthesised) becomes a PE segment (field
compare with SUB and the zero flag, ones'-complement add with the tag carry), a thread sequencing
the template steps, and a bank holding the buffer. It is one prototype's need (P27).

### 2.4 The PE array and its one processing element

**One PE, "upe_v0"** (`prototypes/unified-pe/rtl/upe.v`, built with `-DNO_POP -DNO_LUT -DBITSEL`):
**14,311 µm² synthesised, 989 cells, 100 flip-flops** (`prototypes/unified-pe/results/areas.txt`).
In the same flow the PE with every mode is 16,332 µm² and pe16 is 6,586. At the placed/synthesised
ratio of 1.50 measured for a row of pe16s (`pe-synth/README.md`) it would occupy about 21,500 µm²
(est). It is an area probe: no model or lockstep test exists yet (gap G1).

State: S (16-bit state, loadable per line through a byte-wide init chain), P (16-bit pipeline
register towards the right neighbour, with a valid bit), F (flag), a lane bit and a carry bit.
Configuration: 8 bytes on a byte chain (a 48-bit op word and a 16-bit constant K).

Links: A (16 bits + valid) from the left neighbour or the segment feed; P to the right; a one-bit
**lane** (the "tag lane" of gps) from the left neighbour or the segment's broadcast bit; pair
wires (s15, g) from the left and a carry-back bit (the right neighbour's S[15]); a tap of S or P
and the flag towards the segment's tap port.

One step (every clock, or only when A is valid in stream mode):

- operands: X ∈ {S, A, S<<1 with a serial bit, S>>1 with a serial bit}; Y ∈ {K, A, S, 1};
  Y may be gated by g (g ? Y : 0), negated by g (g ? −Y : Y) or negated;
- condition bit g ∈ {1, A[i] (any bit), lane bit, A[0] XOR lane, CRC feedback (S[15] or the
  carry-back, XOR A[0]), F, window, the left neighbour's g};
- ALU: saturating add, wrapping add (carry-in from the lane optional), max, min, XOR, AND, OR;
- writeback: S ← hold | result | X | (g ? result : hold); P ← A | result | the loser of max/min |
  (g ? {A[15:8], K[7:0]} : A); F ← g, or result = 0;
- lane out: the lane register, S[15], the carry out, or g; valid out: A's valid, or A's valid
  and not g (deletion).

| cell the demos need | configuration | status |
|---|---|---|
| sprite (con) | K = {x, colour}; S = the 16-pixel bitmap, per line through the init chain; A = {pixel x, colour}; g = window (A.hi − x < 16 and S[15 − (A.hi − x)]); P ← merge; stream stepping per pixel. Later PEs win. | configuration designed; the console's lockstep reference is the oracle |
| tile (platformer) | the sprite configuration with S and K reloaded every 16 pixels from the segment feed, which a thread fills from a bank | designed |
| background, rotozoomer (con) | 3–4 PEs: pixel counter (wrapping add of 0x0100 on {x, colour A}), u and v accumulators (wrapping add of the step, MSB on the lane), colour merge on the XOR of the two MSBs | designed |
| FIR tap on 1-bit samples, PDM decimation | transposed form: P ← A + (g ? −K : K), g = the broadcast sample bit | designed |
| CIC integrator / comb | integrator S ← S + A; comb P ← A − S, S ← A | designed |
| NCO, 16 / 32 bit | S ← S + K wrapping; lane out = S[15]. 32 bit: low PE lane out = carry, high PE carry-in = lane | designed; gps needs 32 bit to lock (master) |
| mixer, carrier wipe-off | P ← (g ? −A : A), g = the NCO's MSB on the lane | gps's configuration (master), checked on a Python model of the row |
| GPS code correlator | S ← S + (g ? −A : A), g = the broadcast code chip, P ← A (the sample walks one PE per clock, so PE j integrates code offset j) | same |
| sync-word correlator | not a PE configuration: the matcher assist (popcount measured at 1,798 µm² per PE) | |
| min-plus cell | two PEs: P ← A + K (saturating), then S ← min(S, A) | designed; one PE would need a fused add-then-min (est +1.5k) |
| semiring ring cell (ring) | op x y with x = S or A, y = A or K; loop-back closes the ring | designed; ring used 4 neighbour distances (gap G9) |
| sorting (insertion) | S ← max(S, A), P ← the loser | designed |
| CRC-16/15/5, LFSR | S ← (S << 1 with g) XOR (g ? K : 0), g = S[15] XOR A[0] (data bit on A[0]); K = the polynomial without its x⁰ term; residue check by the next PE: result = 0 into F | designed |
| CRC-32 | a pair: low PE takes feedback from the carry-back (high's S[15]) XOR A[0] and shifts its S[15] into the high PE; the high PE takes g from the low PE's pair wire | designed |
| sigma-delta (1 bit) | S ← S + A wrapping; lane out = carry | gps tier 1 (master), model |
| deserialiser | S ← S << 1 with the lane bit; stream mode | designed |

**What pe16 and the semiring cell already did, and what was added.** pe16
(`pe-synth/pe_rtl.ml`): add/sub/max/min with saturation, x from the state or one neighbour, y from
k or the state, a pipeline register, a 3-byte configuration chain. The ring cell: the same ALU,
with x and y from four neighbour distances and a per-line init chain through the state. Added,
each measured as an increment on the recommended PE (`results/areas.txt`, rows `upe_v0*`):

| addition | why | increment µm² |
|---|---|---|
| base generality: Y from A and 1, S ← X, P ← result/loser/merge, the flag, the wider configuration, the init chain | sorting, CIC, deserialising, per-line reload | `upe_none` − pe16 = 4,532 |
| GF(2): shift with serial input, XOR/AND/OR, gating by g | CRC, LFSR, masks | 1,181 |
| window and merge | sprites, tiles | 1,114 |
| lanes: stream stepping, valid, the lane and its broadcast, pair and carry-back wires, carry in and out | GPS, 32-bit NCOs, CRC-32, deletion | 378 |
| bit test A[i] | branchless selects, the rotozoomer, Gold-code taps | 238 |

Increments are `upe_v0` minus the variant without the mode. Abc's mapping moves them by up to
about 300 µm² between runs (the window increment measured 778 before the zero flag was added and
1,114 after), so read them to the nearest few hundred.

Rejected as PE modes, measured: popcount-match (1,798 µm² per PE, the matcher assist does it
once), the 16-entry LUT (241 per PE; lookup goes to the banks), a multiplier (mac16 is 17,004 µm²
with Booth, `pe-synth/results/areas.txt`).

**Rich PE or more PEs.** The recommended PE is about twice pe16. The same area buys either 16 of
these or about 32 lean PEs (pe16 plus the gps tag lane: 6,586 + 510 est = 7.1k µm²). Only GPS
acquisition speed scales with PE count (section 4); sprites, CRCs and CRC-32 pairs need the modes.
Recommendation: the rich PE, 16 of them (open decision D2).

### 2.5 One partitionable array

**Segments.** The 16 PEs form one chain cut into four segments of **2, 2, 4 and 8 PEs** (cut
points after PEs 1, 3 and 7). At each segment start the first PE's A input selects: the previous
segment's end (join), its own segment's end (loop into a ring), the segment's feed register, or a
fixed neighbour (a bank's read port, or the recovered-bit stream), or zero. Each segment end is a
tap: its P word and the flag go to the sequencer's pull mux, to a bank's write port, to a pin
source select. Each segment has a broadcast lane bit driven from its feed.

**The feed is one bus, which is what keeps it small.** The sequencer issues one instruction per
clock, so one 16-bit write bus into the four feed registers and one read mux out of the four taps
serve all four threads. A full crossbar with eight sources and eight destinations was measured and
rejected:

| interconnect (16 PEs, `unified-pe/results/areas.txt`) | 8 segments of 2 | 4 of 4 | 2 of 8 |
|---|---|---|---|
| full: 8 sources and 8 destinations per port | 62,818 | 31,570 | 18,226 |
| lean: feed register or fixed neighbour in, 2 destinations out | 21,472 | 11,090 | 5,312 |

The 2|2|4|8 layout has the same four segment starts as 4|4|4|4, so it costs the same 11,090 µm²
(est: the probe measured equal segments) plus four 18-bit feed registers (about 3,500 µm², est).
Several fixed arrays with the same endpoints would need only a 2-way 17-bit mux per array start
(about 300 µm² each from the LEF mux2 area, est), so partitioning costs about 10k µm² more
synthesised, about 15k placed: under one placed PE.

**Why these cut points, from the mixes in section 4.** Small jobs come in ones and twos (a CRC-32
pair, a CRC-15 PE, a two-PE sigma-delta audio voice, a PRBS generator and its checker); video
wants 8–12 PEs in one chain; GPS wants all 16. Four segments serve every mix in section 4; three
(4|4|8, about 8k µm², est) lose one concurrent small job, for example the console's audio beside
its tiles; eight segments of two cost 21.5k and no mix needs them. Joining segments gives chains
of 4, 8, 12 and 16.

### 2.6 Memory: an SRAM macro for programmes, gain cells for data

**Position.** Programmes live in an IHP SRAM macro (1P_512x16, 45,309 µm²); bulk data lives in
gain-cell banks. Reasons:

- **The safety net.** If our gain cells misbehave in silicon, every protocol still runs, because
  protocols need only programmes, PEs and pins. What degrades is what buffers data: Ethernet-to-TV
  (line buffer), GPS capture and replay, the ARP/ping reply buffers. Jane Street's post itself
  says "For instruction memory, SRAM can be more area-efficient than flip-flops", the macros come
  with BIST variants, and a taped-out IHP shuttle project uses them inside a LibreLane design
  (`notes/tiny-tapeout-ihp-rules.md` §2). The danger in the other direction is concrete: the
  programme store is read every clock, and a silently decayed instruction corrupts a protocol, not
  a pixel.
- **Gain cells where their contract fits.** The data workloads have short, known lifetimes: every
  trace in `systolic-storage` fits the thick cell's ≥3.1 ms without refresh, the longest being
  1.56 ms (`systolic-storage/README.md`, "Surprises"); GPS replays a 1 ms bank and then captures a
  fresh one (the sky supplies more data).
- **Density is not the argument.** At the bank sizes wanted here, the thick gain-cell bank with
  Berger columns is 26,618 µm² per 4 kbit placed against 28,127 for the SRAM macro
  (`systolic-storage/results/candidates-placed.txt`): a tie. Its advantages are port width (32
  bits against 16), any size, and being ours: the verification story (Berger checks, the
  allocator, canaries) is the novelty.

**Banks.** Two banks of 128 × 32 thick-oxide 3T cells with Berger columns, 4 kbit each
(`gain-cell/README.md`: 2.88 µm² per bit, ≥3.1 ms worst corner with a 20 ns sense). Each bank has
one port, fixed to one segment boundary (bank 0 at the start of segment 3, bank 1 at the start of
segment 4) and to the sequencer's LDB/STB. Uses: the Ethernet line buffer (5 lines per packet:
117 words, one bank), the GPS 1 ms capture (3,274 bits, one bank each for capture and replay,
gps), the tile map and patterns, USB and ARP packet buffers, sine and colour tables.
Thin-oxide rows are not used: the thin/thick mix saves at most 18 % and only at room temperature
(`systolic-storage/README.md`). The all-thick cell with a pumped word line (368 ms,
`gain-cell/tricks-thick/README.md`) is the stretch variant, not the plan of record.

### 2.7 Host link

The demo board's RP2040/RP2350 is the host (`notes/tiny-tapeout-ihp-rules.md` §4). A 4-bit
synchronous link on uio[5:0] (4 data, a strobe from the host, a direction) with an address phase
reaches the programme store, the configuration chains, the feed registers, the banks, the
streamer FIFO and each thread's IN/OUT. Rates needed: 0.85 MB/s for console line packets
(`retro-console/README.md`), 0.58 MB/s for Ethernet-fed video (`pal-ethernet/README.md`), 8 MB/s
per pin for host-computed composite video (`composite-video/README.md`). A 4-bit link at 15 MHz
gives 7.5 MB/s (est): enough for everything except one-pin composite playback, which stays a
stretch. Area about 3,000 µm² (est). Not designed beyond this.

### 2.8 Clocks: one clock, 60.000 MHz

**Decision: 60.000 MHz, with the colour subcarrier made by the pin NCO on the quarter-clock
grid.** Not 17 × fsc (60.85 MHz) and not 12 × fsc PAL (53.20 MHz).

- **Transmit needs an integer ratio that no colour multiple gives.** 10BASE-T: a half bit is
  exactly 3 clocks at 60 MHz; at 60.857 MHz it is 1.4 % fast, "far outside the ±100 ppm transmit
  tolerance" (`eth10-node/README.md`, master; `pal-ethernet/README.md`). Full-speed USB: 5 clocks
  per bit at 60 MHz exactly.
- **Receive works at all three,** with the edge-tracking sampler: 20/20 frames at ±100 ppm to
  ±15 % at 60, 60.857 and 53.2 MHz, jitter to ±8 ns at 1 sample per clock and ±10 ns at 4
  (`eth10-node/README.md`, master).
- **Colour without a colour clock.** The pin NCO places the subcarrier's edges on a quarter-clock
  grid (4.17 ns). At PAL's 4.43 MHz that is 6.6° of subcarrier phase per quarter, so ±3.3° of hue
  error (est, arithmetic); the console's hues are 30° apart (`retro-console/README.md`). FM on the
  third harmonic through the same stage decodes at "essentially ideal" quality
  (`multiphase/README.md`: SINAD* 31.5 dB, tone rms 53.2 kHz of 53 ideal). **Not yet measured for
  video** (gap G4): a subcarrier made this way has a phase-quantisation pattern, and the software
  TV must judge it. PAL lines are exactly 3,840 clocks at 60 MHz; NTSC lines alternate 3,813 and
  3,814 (est, arithmetic).
- **The RP2040 makes 60 MHz exactly** (VCO 1,440 MHz / 6 / 4, `eth10-node/README.md`, master;
  `pal-ethernet/README.md`); the sequencer closes 66 MHz and the PE row 114 MHz at the slow
  corner (`pe-synth/README.md`).
- **Other clocks remain board settings.** The chip is synchronous, programmes are compiled per
  clock, and the host sets the clock at run time. A colour-locked console runs at 53.20 MHz (its
  demonstrated build); the GPS front end suggests 65.472 MHz = 4 × 16.368 MHz (gps, master), or
  the sampler's clocked mode on the front end's own clock at 60 MHz.
- **Four phases on chip.** Both clock edges first (free), then the calibrated delay line
  (`multiphase/README.md`, "Phase sources: verdicts"). A quadrature clock from the RP2350's PIO
  would cap the chip at 37.5 MHz.

### 2.9 Who talks to whom

| from → to | path | width, rate |
|---|---|---|
| threads → pins | SETP, SHO (with q, od, cp) through the pin map | one write per clock over all threads |
| pins → threads | SHI (quad), WAITP, JC on logical pins; round latching optional | |
| threads → array | PUSHL/PUSHH into a segment's feed register | 16 bits, one push per clock |
| array → threads | PULLL/PULLH from a segment tap; segment flags as virtual pins | |
| threads ↔ threads | mailbox (SEND, RECV, JC on full/empty) | 8 bits |
| threads ↔ banks | LDB/STB via the bank pointer | 8 bits per slot |
| banks ↔ array | fixed port at a segment start / tap | 32 bits per clock |
| pins ↔ assists ↔ array | edge sampler → line decoder → destuffer → packer → segment feed or thread; segment tap → stuffer → line coder → pin | 1 bit per clock |
| host ↔ everything | host link, addressed | est 7.5 MB/s |
| array → pins | segment tap through the pin source select, pin NCO phase offset | |

Nothing else talks: no PE reaches a pin except through a segment tap, and no thread reaches a PE
except through a feed register. That keeps the verification boundaries small (section 8).

## 3. Mapping: every protocol and demo onto the blocks

Status: **demonstrated** (simulation, with the evidence path), **designed** (a mapping and its
blocks exist, not run on the generic blocks), **unknown** (depends on work not done). "Special
demo" means demonstrated on special-purpose hardware only. PEs are counted per concurrent use.

| use | blocks and configuration | threads | PEs | status, evidence |
|---|---|---|---|---|
| UART TX / RX | TX: compiled programme (any bit period ≥ 5 slots) or the streamer. RX: 16-word programme with mid-bit SHI, or the sampler in timed mode, or the edge sampler's NRZ mode | 1 each | 0 | demonstrated: `deadline-sequencer/README.md`, `pin-streamer`, `pin-sampler`; RX baud sweep ±5 % in `gps-hotcold/README.md` (master); edge sampler UART at ±6 % (`eth10-node`, master) |
| SPI master | programme (mode 0, period ≥ 8 slots); full duplex with the sampler clocked on SCK, or SHX | 1 | 0 | demonstrated TX and full duplex (`deadline-sequencer`, `pin-sampler`); SHX designed |
| I2C master | programme with open-drain SHO; ACK read-back via the sampler or SHI | 1 | 0 | demonstrated (`deadline-sequencer`, `pin-sampler`) |
| JTAG host | vector engine (22 words) plus TDO follower (26 words); SHX would make it one thread | 2 | 0 | demonstrated, 3.0 MHz TCK (`proto-jtag-swd/README.md`, master) |
| SWD host | 221-word transaction engine; parities on the host | 1 | 0 | demonstrated with the 8-bit pc, 3.75 MHz (same) |
| PS/2 device and host | open-drain firmware, parity in the pc (147–161 words) | 1 per role | 0 | demonstrated (`sequencer-ps2-can/README.md`, master) |
| CAN 2.0A | firmware demonstrated to 625 kbit/s with per-thread CRC/stuff engines (can). v1 mapping: edge sampler NRZ with SJW (gap G6), destuffer (run 5, either value, error flag), CRC-15 in one PE (flag as a virtual pin), RX thread for fields, arbitration by WAITP on the own TX pin, TX thread with a host-stuffed stream | 2 | 1 | demonstrated as firmware on a variant; v1 mapping designed |
| USB low speed (1.5 Mbit/s) | edge sampler NRZ; line decoder NRZI; destuffer (6 ones); CRC-5/16 in one PE; SIE in a thread (turnaround 6.5 bits = 260 clocks = 65 slots); TX: stuffer and NRZI coder from a feed; cp for D± (SE0 by SETP) | 1–2 | 1 | designed; the low-speed work is still running |
| USB full speed (12 Mbit/s) | as low speed at 5 clocks per bit; token address compare in a PE (SUB, zero flag); reply chosen late ("branching as select", `PLAN.md`) because the turnaround is 32 clocks = 8 slots per thread | 1–2 | 2 | special demo (`usb-fs-device`, enumerates in simulation); v1 mapping designed, turnaround tight (gap G7) |
| 10BASE-T TX | firmware on four threads with TP_IDL, link pulses, TD± (33 words per thread); or the line coder in Manchester mode fed from a segment or the streamer, freeing the threads | 4, or 1 | 0 (or 2 for an on-chip FCS) | demonstrated as firmware (`eth10-node/README.md`, master; `sequencer-ethernet`); the assist path designed |
| 10BASE-T RX | edge sampler Manchester 4× → matcher (SFD, enable per bit) → packer; CRC-32 in a PE pair on the bit stream; a thread parses into a bank | 1 | 2 | demonstrated with an e10 CRC unit in place of the PE pair (`eth10-node`, master: ARP and ping answered, judged by scapy) |
| 100BASE-FX | 125 MBd 4B5B/NRZI through an SFP: 1.9 samples per bit with four phases at 60 MHz; CRC-32 at 1.67 bits per clock exceeds a PE's 1 per step (2 interleaved pairs, or the 20.9k byte-wise unit) | ? | ≥4 | unknown (the fast-Ethernet work is running; pad speed decides) |
| PAL/NTSC composite, console | line timing in a thread (sync by SETP in exact slots); pixel chain in segments 3+4 joined: counter and background (3–4 PEs), sprites (8), luma pins from the chain's tap; hue as pin-NCO phase offset on 2 chroma pins; line data from the host via the link into the init chains during blanking | 1–2 | 12 | special demo (`retro-console`, lockstep 0 mismatches, software TV); v1 mapping designed |
| tile platformer | tile layer: WIN PEs reloaded per 16 pixels from bank 1 (tile map and patterns); sprites multiplexed per line by the host; split screen by per-line reconfiguration | 2 | 12 | designed (the platformer work is running) |
| sound for the console | one-bit voice: NCO PE and sigma-delta PE (segment 1 or 2), pin output | 0 | 2 | special demo (`one-bit-synth`, 68 dB in-band SNR); gps tier 1 audio on PEs (master, model) |
| Ethernet-to-TV | 10BASE-T RX (above) into bank 0 as a line buffer (5 lines per packet); a thread copies 48 bytes per line into segment 4's init chain in blanking; segment 4 as a ring renderer (8 PEs, loop-back); segment 3 text sprites | 3 | 14 | designed; pieces demonstrated (`pal-ethernet` step 1, `semiring-ring`, `eth10-node`) |
| CAN-to-TV (bus analyser on a television) | CAN RX (above) plus a text overlay: tiles (segment 3) and sprites (segment 4); the RX thread filters with JC | 3 | 1 + 12 | designed |
| FM TX | pin NCO → four-phase stage; a thread (or an NCO PE) writes the frequency word per audio sample | 1 | 0–1 | demonstrated through the RTL stage (`multiphase/README.md`, SINAD* 31.5 dB) |
| FM RX with RDS | 1-bit direct sampling through the four-phase inputs; everything else unknown | ? | ? | unknown (running) |
| TV-in advert detection | composite in through a comparator and the four-phase inputs; black-frame and cut detection in PEs, output on CAN | ? | ? | unknown (running) |
| GPS, tier 1 (NMEA to audio) | UART RX thread (16 words); host parses; 2 PEs per ear (NCO, sigma-delta) | 1 | 4 | demonstrated end to end in simulation (`gps-hotcold/README.md`, master): UART on RTL in lockstep, the audio PEs on a model |
| GPS, tier 2 hot/cold (raw 1-bit) | sampler timed mode (1 of 5 samples) into a bank; replay at one sample per clock through all segments joined: 2 carrier NCOs, 2 wipe-offs, 2 × 5 correlators, 1 code NCO; C/A codes from a bank or a GF(2) PE pair; host loops and fix | 1 | 15 | modelled bit-exactly on pe16 plus the tag lane (master: 9.7 m fix on a synthetic sky); not on RTL |
| margin testing, shmoo | fine-delay DTC on a pin; PRBS from a GF(2) PE; error counter PE (XOR with the expected stream, add); TDC for response times | 1 | 2 | behavioural demo (`multiphase/results/shmoo.txt`); PRBS path designed |
| glitch and runt injection | two lanes of one pin (rise at t, fall at t + w); randomised offsets from a PE LFSR | 1 | 0–1 | behavioural demo (same) |
| hwfuzz-driven debugging | offline: hwfuzz on every block's RTL (`hwfuzz/README.md`: USB, 10BASE-T RX findings). On silicon: the host runs the fuzzer, the chip plays inputs with exact timing (streamer, threads) and observes (sampler, TDC buckets as coverage features) | 1–2 | 0–2 | offline demonstrated; on-chip designed |
| logic analyser / protocol sniffer | sampler capture into banks, matcher trigger, edge samplers decoding up to two buses, CRC PEs | 1–2 | 1–3 | designed |

**Headline.** 26 uses map onto **nine block types** (plus the programme store and the host link):
the sequencer, the pin stage, the streamer and sampler, the pin NCO, the edge-tracking sampler,
the stuff tracker and line coder, the matcher, the PE array, and the banks. 11 uses are
demonstrated in simulation as firmware or on generic blocks (UART, SPI, I2C, JTAG, SWD, PS/2, CAN
on an ISA variant, 10BASE-T TX, 10BASE-T RX with one CRC unit that v1 replaces, FM TX, GPS tier 1);
6 on special-purpose hardware, behavioural models or offline (USB FS, console, sound, shmoo,
glitches, hwfuzz); 6 are designed (GPS tier 2 modelled bit-exactly); 3 are unknown.

## 4. Workload mixes: segment use, PE duty and whether time-sharing keeps up

"Duty" is the fraction of clocks on which a PE steps. At 60 MHz a PE steps at most once per clock.

| mix | segment 1 (2) | segment 2 (2) | segment 3 (4) | segment 4 (8) | threads | PE duty, keeps up? |
|---|---|---|---|---|---|---|
| M1 Ethernet-to-TV | CRC-32 pair | – | text sprites (4) | ring renderer (8, looped) | RX parse, line copy, sync | CRC: 1 bit per 6 clocks = 17 %; video: 1 step per 10-clock pixel = 10 %; 14 of 16 PEs allocated. Yes, 6× and 10× headroom |
| M2 CAN-to-TV plus UART | CRC-15 (1) | – | tiles and background (4) | sprites (8) | CAN RX, CAN TX, UART, line timing | CRC: 1 bit per 120 clocks at 500 kbit/s = 0.8 %; 13 PEs. Yes |
| M3 USB LS plus I2C plus SPI | CRC-16/5 (1) | – | – | – | USB SIE, I2C, SPI, spare | 1 bit per 40 clocks = 2.5 %; 1 PE. Yes |
| M4 GPS tier 2 | all joined: 15 PEs | | | | capture control | 100 % during replay: 3,274 clocks per 1 ms block. Cold start about 121 s (est: gps's 139 s at K = 4 and 65.472 MHz, scaled by 4/5 for K = 5 and by 65.472/60) |
| M5 console with sound | audio voice (2) | – | background and tile (4) | sprites (8) | line timing, pad | 10 %; 14 PEs |
| M6 three-bus sniffer (CAN, USB LS, UART) | CRC-15 | CRC-16 | – | – | 3 decoders | two edge samplers only: the third bus (UART) goes to a thread; 2 PEs |

**Time-sharing.** Every mix leaves most PE clocks idle (duty 1–17 %) yet allocates PEs in space,
because a PE holds one configuration and one state. Time-sharing a PE between streams needs its
state saved and restored per step, which v0 does not have. The backlog's "8-word gain-cell bank
per PE" would give each PE eight contexts; that is the lever if PE count turns out to bind (gap
G11). GPS is the exception: it already time-shares by replaying a bank many times per block.

### 4a. What is the array buying? The chip without it

The question: with the protocols landing as sequencer firmware plus small assists, how much is the
systolic array buying? The array (16 PEs and its interconnect) is 243,593 µm² synthesised, about
365,000 µm² placed at the 1.5 factor: **about half the allocation** (`results/budget.txt`
arithmetic: 16 × 14,311 + 14,617, × 1.5).

**(a) The counterfactual chip with no array.** Without PEs and interconnect the rest places at
about 281,000 µm² (37 %), leaving about 470,000 µm². One way to spend it, all measured blocks:

| addition | placed µm² | gain |
|---|---|---|
| a second sequencer (v1 proxy) with its own 512 × 16 store | 44,000 + 49,800 | 8 threads: two CAN nodes and JTAG and SWD at once |
| three CRC units (7,127 µm² each, `unified-pe`) | 32,000 | CRC needs units once there are no PEs: three concurrent streams |
| two more 4× edge samplers, stuffers and line coders | 31,400 | four bit-level streams at once |
| a 1P_1024x32 SRAM (32 kbit) | 154,000 | deep capture for the logic analyser; packet and line buffers |
| total | about 310,000 | the chip at about 79 % |

Lost or degraded without the array:
- **Ethernet-to-TV loses its point.** Raw 4-bit pixels at 256 × 240 × 50 fields are 12.3 Mbit/s
  (arithmetic), more than 10BASE-T carries; the ring's line descriptions are 4.6 Mbit/s
  (`pal-ethernet/README.md`). At 25 fields per second raw pixels would fit (6.1 Mbit/s), at half
  the frame rate and with a frame buffer the chip does not have (240 × 256 × 4 bits = 246 kbit).
- **Racing-the-beam video from compact line data** (console, platformer, wave, ring, text
  overlays for CAN-to-TV) goes to the host: the RP2350 renders pixels and streams about 3 MB/s
  (arithmetic: 256 × 240 × 50 bytes of hue and luma) over a link estimated at 7.5 MB/s. It works, but the chip is then a
  pixel player, and the host's CPU does the demo.
- **GPS tier 2** becomes capture on the chip and correlation on the host. gps itself estimates
  that the RP2350 could acquire by FFT faster than K = 4 (an estimate, not measured), but
  continuous tracking of 12 channels is about 240 M sign-accumulates per second, "most of its
  cycles" on a Cortex-M33 (`gps-hotcold/README.md`, master).
- **Bit-rate DSP at the pins**: FM receive by 1-bit direct sampling (the four-phase inputs deliver
  240 Mbit/s per pin; decimation must happen on chip), PDM decimation, advert statistics. Without
  PEs each needs its own assist or is lost. These are still unknown (section 3).
- Gained: more threads, more CRC streams, 32 kbit of static memory: a better pure protocol
  analyser.

**(b) The smallest array that keeps most demos.** Eight PEs (segments 2|2|4) place at about
475,000 µm² for the whole chip (63 %; `budget.py` arithmetic with N = 8), 172,000 less than 16.
They keep: two CRC streams (3 PEs), audio (2), a console with about 4 sprites or a 6-PE ring
renderer, GPS acquisition at K = 1–2, about 2–4× slower than K = 4 (est, the 1/K scaling of
`gps-hotcold/results/tier2/acq_timing.txt`), and GPS tracking only by extra replays. Four PEs keep
the CRCs and audio only.

**(c) Which demos genuinely need the array.** Needs it: Ethernet-to-TV at full field rate
(bandwidth), GPS tracking (sustained rate), bit-rate DSP on the pins (rate), CRC at 10–12 Mbit/s
if there is no CRC unit. Could use the host instead: GPS acquisition, console and platformer
graphics (with a pixel stream), NMEA sonification (a thread can beep). Needs neither: every
protocol on Jane Street's list, which is firmware plus bit-path assists.

**(d) Novelty.** The competitor study (private notes, `notes/backlog.md` on master; not checked
here) found no other public entry with a systolic array. The post rewards "unique functionality"
and "anything else your architecture makes possible" (`notes/jane-street-alignment.md`): that is
exactly what the array does, and the protocols do not need it.

**Recommendation.** Keep the array, because it is both the only route to the "anything else"
demos and the entry's most distinctive hardware; and make it earn protocol work too, which the
GF(2) mode does (every CRC stream runs on it). The trade-off, stated plainly: half the floor area
buys the demos and the novelty, and costs a second sequencer, three CRC units and 32 kbit of
capture memory, which would make a better protocol analyser. If placement forces a cut, shrink
the array to 12 or 8 PEs before cutting anything the protocols use.

## 5. Gaps: what each special-purpose prototype must change, and the smallest generic extension

| prototype | what becomes a programme or configuration | gap and smallest generic extension |
|---|---|---|
| retro-console | sprite cells → PE window mode; u/v background → 3–4 PEs; 54-byte double-buffered packet (864 flops) → init chains loaded in blanking; 12 × fsc chroma → pin NCO with hue offset; line timing → a thread | G1: UPE RTL and lockstep against the console's reference (reuse its 720-line test); G4: NCO colour judged through the software TV |
| composite-video | host precomputation unchanged; the chip side is the streamer at width 1–3 | G3: host link at 8 MB/s per pin |
| semiring-ring | cells → PEs in a looped segment; 24 → 16 bits; 4 neighbour distances → 1 | G9: only the cubic wiggle needs 24 bits (32-bit pairs with carry exist); distances by placement or the P-lane delay |
| wave-engine | 10-record ring with one sine table → 8 waves on 16 PEs (NCO PE plus triangle or bank-table PE per wave) | bank as sine table, fed at a segment start; 8 waves instead of 10 |
| crazy-network | parked (`PLAN.md`); not mapped: it needs random long links | none |
| systolic-matcher | kept as the one matcher assist, plus e10's enable | none |
| usb-fs-device | SIE → thread; RX/TX → edge sampler, NRZI, stuffer; CRC-5/16 → PE; descriptors → bank | G7: 8 thread slots for the full-speed turnaround; fall back to a hardened SIE outside the budget if the select-late reply does not fit |
| ethernet-10base-t | TX → firmware or line coder; RX → e10's generic chain; FCS → PE pair | the squelch question is answered by e10's sampler (holds its level while squelched) |
| sequencer-ethernet | kept as the proof of exact timing; production path frees the threads | none |
| pal-ethernet | clock → 60 MHz; line buffer → bank | G4 |
| one-bit-synth | NCO and sigma-delta → PEs; sine → bank table or triangle | none |
| multiphase | stage kept; its NCO → the pin NCO assist | G5: FINE as EXT 0; delay line as a placed macro |
| pin-streamer, pin-sampler | kept; sampler input can be a recovered-bit stream | small: the input select |
| deadline-sequencer | ISA v1 (section 2.1) | G2: v1 RTL and lockstep; the pin map; the mailbox |
| sorting-search | the insertion sorter is a PE configuration (max with the loser onward) | none |
| gain-cell, sram-cut, systolic-storage, pe-synth | memory and PE evidence | G8: bank periphery drawn, Berger and refresh controller, allocator as the programme verifier's memory half |
| eth10-node (master) | its edge sampler, matcher enable and packer are adopted; its CRC unit → PE pair; its engine → PE segment + thread + bank | G6: add SJW and hard/soft sync to the NRZ mode for CAN at 1 Mbit/s |
| gps-hotcold (master) | its tag lane is the PE lane (negate, carry, MSB, broadcast); its LFSR assist → GF(2) PE pair or a bank-held code | G10: bank replay across a bank boundary for tracking (a third bank or a window over two) |
| proto-jtag-swd, sequencer-ps2-can (master) | firmware unchanged on v1 (8-bit pc); CAN's CRC/stuff engines replaced by the bit-path assists and a PE | re-run their suites on v1 (G2) |

Further gaps: **G11** time-sharing PEs (contexts); **G12** the full-speed pad question (TT's only
figure is sky130's 33 MHz output; `notes/tiny-tapeout-ihp-rules.md` §4) gates 100BASE-FX, runts,
and composite at 66 Msps; **G13** a whole-chip place and route (sequencer, four PEs, the
interconnect, one macro) to replace the assumed placement factor of section 6, which decides
between 16 and 12 PEs.

## 6. Area budget against 6 × 4 tiles

Allocation: 24 tiles of 202.08 × 154.98 µm = 751,632 µm² (`notes/tiny-tapeout-ihp-rules.md` §1).
The computation is `prototypes/unified-pe/budget.py` → `results/budget.txt`; every line there
names its source. Standard-cell logic is converted to floor area with the factor 1.5 measured for
a placed row of PEs at 90 % utilisation (`pe-synth/README.md`), and with 2.0 as a pessimistic case
(small blocks placed alone had die/synthesis ratios of 2.1–2.5, e.g. the sequencer's 36,663 µm²
die for 17,300 µm² of cells, but those dies include their own margins). Macros count at their drawn
size plus 10 % (est).

| PEs | programme SRAM | factor 1.5: placed µm², share, slack | factor 2.0 |
|---|---|---|---|
| 12 | 512 × 16 | 560,661, 74.6 %, 190,980 | 705,741, 93.9 %, 45,899 |
| **16** | **512 × 16** | **646,526, 86.0 %, 105,115** | **820,228, 109.1 %, −68,587** |
| 16 | 256 × 16 | 627,626, 83.5 %, 124,015 | 801,327, 106.6 %, −49,687 |
| 16 | 1024 × 16 | 684,327, 91.0 %, 67,313 | 858,029, 114.2 %, −106,389 |
| 20 | 512 × 16 | 732,391, 97.4 %, 19,250 | 934,714, 124.4 %, −183,074 |

The logic other than PEs sums to 118,431 µm² synthesised (the sequencer proxy 29,428; the pin
stage, streamer and sampler 34,530; the bit-path assists and matcher 26,177; the pin NCO 6,678;
the segment interconnect and feed registers 14,617; estimates for the host link, memory control
and reset 7,000). Drawn and macro blocks: the two gain-cell banks 53,236, the fine delay 15,473
(est), the programme SRAM 45,309.

**Verdict.** **Sixteen PEs with a 512 × 16 programme store fit at the measured placement
factor, with 14 % of the allocation left (105k µm²), and do not fit at the pessimistic one (9 %
over).** Twelve PEs fit either way. So: plan for 16, and settle it with the first whole-chip
place and route (the sequencer, four PEs and the interconnect together) before anything else is
built on the count. If the factor comes out near 2, drop to 12 PEs (segments 2|2|8), which loses
the fourth concurrent job and three GPS correlator pairs. Cheaper configuration storage is the
first lever before that: latches instead of flip-flops save about 18 µm² per bit
(`pe-synth/README.md`), 64 bits per PE, about 1.2k µm² per PE (est).

**What had to go** to get here, each with the measurement that sent it: popcount in every PE
(1,798 µm² × 16); a full crossbar (31.6k against 11.1k); per-thread CRC engines in the sequencer
(+12.2k); a 1024 × 16 programme store (79.7k); byte-wise CRC (20.9k); a second matcher; fine delay
on more than two pins (6.5k each, est); the hardened USB SIE (29.7k synthesised,
`usb-fs-device/README.md`); 16 sprites plus a background and a tile layer at once (16 PEs total).

**Cell count check.** Jane Street's guide is about 1K logic cells per tile, 24K in all. The PEs
are about 16 × 1,000 cells (`results/areas.txt`), the sequencer about 1,100–1,850
(`sequencer-ps2-can/synth`, master), the assists and pin stage about 4,000 (sum of their reports):
about 21–22K cells (est).

## 7. Determinism: where the chip is not deterministic, the fences, and deliberate nondeterminism

The sequencer is deterministic by construction; so are the PE array (lockstep stepping, valid
flags computed from data) and the assists (synchronous logic). The chip as a whole is not. Each
source, its fence, what the programme verifier may assume, and how a silicon run is replayed:

| source | fence | verifier may assume | replay |
|---|---|---|---|
| asynchronous pin inputs (metastability, arrival time) | two-flop synchroniser per phase; samples reach the core 2 clocks later (`multiphase`); round latching optional | an edge is seen within ±1 quarter of its arrival and within 2 clocks; nothing about the resolved value of a sample taken in the aperture | record the sampled nibbles; sparse edge logs (time stamp + pins on change) into a bank around a trigger; everything downstream is deterministic given them |
| four-phase output timing (phase skew, lane mismatch) | lanes change only on their own phase; skew ≪ a quarter period (function survives about 3 ns, `multiphase/README.md`) | edge order and quarter positions exact; absolute time to ±(skew + calibration) | nothing to replay: the content is deterministic |
| fine delay and TDC (PVT, INL, supply noise) | calibration by counting taps per clock; TDC readings enter only as data | an edge at k taps is at k × (measured tap) ± INL | log TDC readings |
| host link (the host's clock) | FIFOs with valid flags; IN, RECV and feed reads block with a deadline | the sequence of values is fixed, their arrival slot is not | log arrival slots of host words |
| gain-cell retention (temperature, die, variable retention time) | Berger check on every read; the allocator's guard of 0.8; canary rows; the temperature-bin schedule (`notes/gain-cell-compiler.md`) | a read within 0.8 L(row, bin) returns the written data; otherwise the Berger flag is raised, never silent corruption of 1→0 kind | log Berger flags and canary results |
| analogue board parts (comparators, squelch, front ends) | sampler modes that hold level while squelched (e10) | per protocol, in the transducer's model (hwfuzz ledger entry 7) | the input log |
| power-on configuration | clear and configuration load before any thread starts | | |

A silicon run is therefore replayable in simulation from four logs (input samples, host arrival
slots, TDC readings, memory flags), and the logs are small when kept as edge and event lists.
Metastability injection in simulation (backlog, from Antithesis) exercises the first fence.

**Deliberate nondeterminism, assessed.**

| idea | on our blocks | cost | value | fence | recommend |
|---|---|---|---|---|---|
| self-timed handshakes between PEs (GA144) | replaces lockstep stepping | high: C-elements, no STA, a new verification story | power, rate decoupling | none that keeps the programme verifier | **no**: stream stepping with valid flags gives rate decoupling deterministically |
| TRNG from ring-oscillator jitter or metastability | a few ring oscillators into a synchroniser; a virtual pin and a feed source | about 1k µm² (est); ring oscillators are common on IHP shuttles (`notes/tiny-tapeout-ihp-rules.md` §5) | seeds for on-chip fuzzing, dithering, nonces, PUF helper data | enters as data through a synchroniser; health tests (repetition, proportion) in a PE; logged for replay | **yes**, small |
| gain cells as a PUF | per-row retention profile, already measured by the retention BIST | nothing extra | chip identity; a novelty demo | temperature binning; enrolment with helper data | **yes**, as a demo |
| stochastic computing in the PE | numbers as random bit streams, multiply as AND | nothing: AND and compare exist | cheap error-tolerant scoring or blending; none of our workloads needs it | PRNG-driven streams are deterministic and replayable | **not in v0**; a programme demo if time allows |
| equivalent-time sampling with the TDC | sweep the sampling instant over repeats of a periodic signal | nothing beyond the fine-delay option | a scope far beyond the clock: eye diagrams, edge rates, response-time histograms (the 347 ps data-dependent delay in `multiphase/results/shmoo.txt`) | the sweep is programmed; readings are data | **yes**: it is the point of the fine-delay option |
| dithering and randomised timing | FINE offsets from a PE LFSR; randomised refresh slots | nothing | FM and EMI spur spreading, glitch-campaign coverage, less lock-in in measurements | PRNG by default (replayable), TRNG optional (logged) | **yes**, PRNG-driven |
| approximate storage | let chosen data decay: a lossy class in the allocator, only 1→0 errors | nothing | fading pictures, self-erasing keys, a tile cache that evicts itself | the class declares its error budget; Berger flags are expected there | **yes, as demos**, never for programmes |
| chaotic and oscillator networks | the parked crazy network | a separate array | exploration | none known | **no** (`PLAN.md`: no algebra to design with) |

## 8. Verification plan for the unified chip

Built from what every prototype already has, in this order:

1. **Per block: an executable specification and lockstep.** The sequencer's interpreter
   (`isa.ml`), extended to ISA v1, against its RTL on random programmes (the 300 × 2,000 cycle
   test; the can variant's biased random programmes and hidden-state debug ports, which caught 6 of
   6 planted bugs where uniform programmes missed 2 of 5, master). The UPE: an OCaml model of the
   op word, lockstep on random configurations, as `pe-synth` did for pe16 (`check.txt`), plus each
   demo's own reference (the console's 720 random lines, the ring's 184,320 samples, the gps row
   model's closed form). Assists: e10's lockstep suites as they stand. Every test shown to catch a
   planted bug before it is trusted.
2. **Whole-chip tests per mapped use** (section 3): the programme and configuration on the
   whole-chip RTL, judged by an **independent oracle**, never by the generator: the decoders of
   `deadline-sequencer`, the I2C/SPI reference devices of `pin-sampler`, the TAP and SW-DP models
   of jtag, the CAN reference node and PS/2 models of can, scapy for Ethernet, the bit-level USB
   host model, the software TV for video, the FM receiver of `notes/fm-radio-2026-09-24`, the gps
   fix. sigrok's decoders as a further oracle (`notes/backlog.md`, master). The lesson recorded
   three times: lockstep against one's own specification misses what the specification shares
   (`pin-sampler`, `proto-jtag-swd`, `eth10-node`).
3. **Concurrency and isolation.** Each mix of section 4 run together with each protocol's timing
   compared to its solo run: a non-interference miter (assume equal inputs for a thread, assert
   equal pins; backlog, after umerimran-10xe's arbitration miter) is the formal form.
4. **Formal.** Bounded model checking with hardcaml_verify that every arm of every deadline wait
   meets its deadline (`PLAN.md`), with a planted broken arm that the proof must reject. The
   **programme verifier**: deadlines met; pins, feed registers and bank ports never double-booked;
   every bank read inside its row's lifetime at the chosen temperature bin (the allocator of
   `systolic-storage` as its memory half); segment configurations consistent (no two sources on a
   segment start). MarcosAsh's abstract-interpretation analyser is prior art to read first
   (backlog).
5. **Fuzzing.** hwfuzz on the whole chip with context-gated coverage (`hwfuzz/README.md`), with
   timing offsets and glitch widths as mutation dimensions and metastability injection at the
   synchronisers.
6. **Custom cells.** SPICE and Monte Carlo (done for the thin cell; running for the thick), full
   LVS against a schematic because the precheck has none, the maximal DRC deck ourselves
   (backlog), and the executable lifetime contract used by the digital simulation.
7. **FPGA.** The whole chip minus the analogue parts on the ULX3S (bring-up work running): the
   gain-cell banks replaced by a model that enforces the lifetime contract (decays 1s after L,
   raising Berger flags), the four-phase stage by both clock edges or the FPGA's PLL phases, the
   delay line absent. Real UART, SPI flash, I2C parts, a JTAG and SWD target, a CAN transceiver
   and adapter, a Linux USB host, a switch for 10BASE-T, a TV. Test scripts written for the RP2040
   so they carry over to the chip (`PLAN.md`).
8. **Silicon.** Retention profiling and canaries at start-up; delay-line calibration; the replay
   logs of section 7 so that any silicon misbehaviour becomes a simulation.

## 9. Open decisions, with recommendations

| # | decision | options | recommendation |
|---|---|---|---|
| D1 | CRC placement | per-thread engines in the sequencer; a CRC unit per stream; GF(2) PE mode | **GF(2) PE mode**, no CRC unit (section 2.3: break-even 2.7 streams; the mode also serves LFSR, PRBS, masks) |
| D2 | PE richness | 16 rich PEs (upe_v0) or about 32 lean ones (pe16 + tag lane, est) | **16 rich**: sprites, CRC pairs and the NCO carry need the modes; only GPS cold-start time scales with count |
| D3 | array partitioning | fixed arrays; 2 / 3 / 4 / 8 segments | **one array, 4 segments 2|2|4|8** with loop-backs (about 9k µm² over fixed arrays, est) |
| D4 | programme store | 256 / 512 / 1024 × 16 SRAM macro; gain cells | **SRAM 512 × 16** with page bits (measured firmware sizes exceed 256) |
| D5 | data memory | gain-cell banks; SRAM macros (a tie in area) | **2 thick gain-cell banks** with Berger and the allocator; they are the memory novelty, and the programme store is the safety net |
| D6 | clock | 60.000, 60.857 (17 fsc), 53.20 (12 fsc PAL), 65.472 (GPS) MHz | **60.000 MHz**; colour from the pin NCO (measure it, G4); others as board settings |
| D7 | stuffing and line coding | PE modes; assists | **assists** (813 and 477 µm², and stuffing changes the rate) |
| D8 | sync-word matching | popcount in every PE; one matcher | **one matcher assist** with enable |
| D9 | ISA v1 contents | 8-bit pc, JC, tagged OUT, CNTA, complementary pair, round latching, SHX, FINE, per-thread CRC/stuff | **all but the per-thread CRC/stuff engines**; SHX in EXT (measure on SPI first, as jtag suggests) |
| D10 | WAITP semantics | keep; make it branch whenever the pin fails | **keep** (CAN uses the counting-on); immediate branches via JC |
| D11 | fine delay | none; two pins; every pin | **two pins**, as a placed macro |
| D12 | deliberate nondeterminism | section 7 | **TRNG, PUF demo, equivalent-time sampling, PRNG dithering, approximate-storage demos**; not self-timed PEs |
| D13 | the hardened USB SIE | keep outside the budget as a fallback; drop | **drop** unless G7 fails; the full-speed turnaround is the test |
| D14 | time-shared PEs | none; per-PE context bank | **none in v0**; revisit if a mix runs out of PEs (G11) |
| D15 | have an array at all | none (spend the area on threads, CRC units, SRAM); 8; 12; 16 PEs | **16, shrinking to 12 or 8 before anything protocols use** (section 4a) |

## Review

REVIEW_SECTION
