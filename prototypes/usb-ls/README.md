# Low-speed USB: a hardened block, and firmware on the deadline sequencer

The competition's stretch goal, 1.5 Mbit/s USB, built twice and checked against one independent
host model: once as a hardened block adapted from `../usb-fs-device`, once as firmware on the
deadline sequencer with one small generic assist. The question was how far firmware gets. The
answer: the whole device runs as firmware. The bit layer needs nothing beyond the original
instruction set. The packet layer needs four small, backwards-compatible ISA changes and a
generic CRC unit. Replies are precomputed and fetched through a FIFO in front of the host port.

Both devices are HID boot keyboards: GET_DESCRIPTOR (device, configuration, HID report),
SET_ADDRESS, SET_CONFIGURATION and SET_IDLE on endpoint 0, and STALL for anything else. Endpoint
1 is an interrupt IN endpoint that returns 8-byte reports with data toggles, or NAK. Both
detect a bus reset and ignore keep-alives.

## Verification

- **`ls_host.ml`: an independent host model, written from the specification.**
  - Encoding: sync, NRZI, bit stuffing and EOP.
  - The host clock is off by a chosen amount (up to ±1.5 %), with symbol edges on the nearest
    clock.
  - Decoding is by run length in the host's own bit time. It checks EOP width, stuffing and
    whole bytes.
  - Controls it can generate: a corrupted CRC5 or CRC16, a missing stuff bit, keep-alives and
    bus resets.
- **`ref_device.ml`: a reference keyboard at transaction level.** It says what a correct device
  answers. It shares only the descriptor bytes with the implementations.
- **`bench.ml`: the bus and a transaction-level host.** Every reply is checked for:
  - bytes and CRC equal to the reference;
  - a clean decode;
  - a turnaround of 2 to 6.5 bit times, measured from the SE0-to-J edge of the host's EOP;
  - no bus contention;
  - no reply where none is due.
- **`scenario.ml`: the same scenarios for every device.**
  - Directed: the enumeration a host performs (with a 10 ms reset), reports, packets that must
    be ignored, and a stalled request.
  - Constrained random, 120 transactions per session:
    - requests of random types and lengths;
    - random OUT data;
    - lost ACKs;
    - bad CRC5 and bad CRC16;
    - missing stuff bits;
    - other addresses;
    - SET_ADDRESS changes;
    - bus resets of 5 to 105 µs;
    - keep-alives and gaps at random.
  - Each session runs at a random host clock error within ±1.5 %. The first two firmware
    sessions run at -1.5 % and +1.5 %.

**Firmware, interpreter and RTL in lockstep.** Two complete systems run side by side, fed the
same bus every clock and compared on every clock (pins, output enables, host port, all four
program counters). One is the interpreter with models of the synchroniser and the CRC unit. The
other is the RTL of the sequencer variant, synchroniser and CRC unit. Each has its own
programme memory and its own controller.

Results (`run-hard-8seeds.log`, `run-fw-8seeds.log`; numbers below from those runs):

| | hardened block | firmware (interpreter and RTL in lockstep) |
|---|---|---|
| directed enumeration and reports, host at -1.5 %, 0, +1.5 % | 3 of 3 pass | 3 of 3 pass |
| constrained random sessions (8 seeds, host clock random within ±1.5 %; for firmware seeds 1 and 2 at -1.5 % and +1.5 %) | 8 of 8 pass | 8 of 8 pass, controller latency 20 to 1,100 clocks; one session with 5,000 clocks to prepare each reply (156 NAKs while preparing, all tolerated, none where not allowed) |
| clocks simulated in these 11 runs | 12.1 million | 12.4 million, compared between interpreter and RTL on every clock: 0 mismatches |
| host packets / device replies | 3,029 / 1,485 | 3,169 / 1,626 |
| packets the device had to ignore (bad CRC5, bad CRC16, missing stuff bit, other address) | 214, all ignored | 214, all ignored |
| keep-alives / bus resets | 209 / 64 | 213 / 63 |
| turnaround, all replies | 3.23 to 3.40 bits | 2.51 to 6.00 bits (front padding; see the budget) |
| beyond the specification, directed | not run | -3 % to +3 % pass; -4 % fails |
| bit layer alone on the ORIGINAL sequencer (T0; interpreter and RTL in lockstep) | | 13 host clock errors from -1.5 % to +1.5 %, 60 random packets each (0xFF, 0x00, 0x55, 0xAA heavy): all bit-exact, 2.2 million clocks, 0 mismatches; passes -4 % to +2 %, fails at -5 % and +3 % |
| ISA variant, interpreter against RTL | | 200 random programmes x 4,000 clocks: 0 mismatches |
| CRC assist, model against RTL | | USB CRC16, USB CRC5, CAN CRC15, fixed and programmable: 6 x 200,000 clocks, 0 mismatches (random stimulus never reaches the CRC16 residue, so its good-packet case is checked separately on real packets) |

Controls, each of which must fail and does:

| control | hardened | firmware |
|---|---|---|
| J and K swapped (full-speed polarity) | caught: the host cannot decode the reply's sync | caught: no ACK to SETUP, and a stray transmission 1.8 bits after a host packet |
| reply 4 bit times late | caught: turnaround 7.3 bits | caught: turnaround 6.9 bits |
| reply early | caught: turnaround 1.8 bits | caught: bus contention with the host's EOP |
| CRC16 check disabled | caught: ACKs a corrupted SETUP | caught: ACKs a corrupted SETUP |

Among the stimuli, bad CRC5, bad CRC16 and missing stuff bits must be met with silence. They
are, in every run. They are stimuli, not device mutants.

## The firmware: what it does and how far the original ISA gets

The chip clock is 60 MHz. A low-speed bit is 40 clocks, so one thread gets 10 instructions per
bit. The threads divide the work as follows.

- **T0, the bit layer: original instruction set, 63 of 64 words** (`firmware.ml`).
  - It follows the line with deadline waits: a software DPLL that re-times on every edge.
  - It also decodes NRZI, removes stuff bits, detects EOP (SE0) and bus reset, and treats a
    seventh one as an abort.
  - It publishes each bit as VALUE plus a rising STB on internal pins.
  - The same programme runs on the original sequencer's interpreter and RTL, through the
    original files (symlinked), decoding random packets bit-exact:
    - 13 host clock errors from -1.5 % to +1.5 %, 60 packets each;
    - it keeps working from -4 % to +2 %.
  - Pure firmware therefore covers everything below the byte: clock recovery, line code,
    stuffing, framing.
- **T1: IN tokens and the host's ACK.** 180 words.
  - It reads the PID and the token's two bytes and compares them with precomputed bytes
    (address, endpoint and CRC5 included) using SKNE.
  - It answers with data streamed from the reply FIFO, or with NAK or STALL from immediates.
  - It also arms the CRC assist after every PID and disarms it for anything but DATA0/1, so a
    packet with a bad PID can never pass the CRC check. That is the data PID check, done in
    time.
- **T2: SETUP and OUT.** 186 words.
  - It checks the token, then forwards the data packet to the controller (tagged events plus
    bytes).
  - At the EOP it checks the abort flag and CRC_OK, and answers ACK or STALL.
- **T3 is free** for the application.
- **The controller (`controller.ml`) is off the real-time path.** It stands in for software on
  the chip's host side.
  - It keeps the USB state and precomputes every reply as a symbol stream (`fw_codec.ml`: CRC16,
    stuffing, NRZI, EOP, packed four symbols per byte).
  - It patches the programme: the token bytes after SET_ADDRESS, and per state the reply
    choices (data, NAK or STALL on IN; ACK or STALL after OUT data).
  - It needs to answer an event within the shortest data packet (1,280 clocks). The tests use
    latencies of 20 to 1,100 clocks, plus one session where it takes 5,000 clocks to prepare
    each reply and the firmware NAKs meanwhile.

### What pure firmware could not do, and the smallest fix for each

| gap in the original ISA | measured or counted consequence | fix | cost |
|---|---|---|---|
| no data-dependent branch except on a pin | a token check as a WAITP decision tree over bits costs about 3 words per bit (estimated, not built): about 70 words per 24-bit token path, and the device needs four such paths | **SKNE imm8**: skip next if acc ≠ imm (or = imm) | one 8-bit comparator and pc+2; opcode E (free) |
| 6-bit pc, 64 words per thread | T1 and T2 need 180 and 186 words | **8-bit pc** (256 words per thread, what the README plans for the SRAM); address fields grow into unused bits | 8 flip-flops, wider muxes |
| SETP writes one value to all masked pins; D+ and D- must change together | one thread cannot drive J or K glitch-free; two threads could, with one clock of skew and a pin to coordinate them | **SHO pair mode**: two pins from two acc bits at once | a second output mux; SHO bit 6 |
| OUT sends acc with no framing | the controller cannot tell forwarded bytes from events | **OUT event mode**: an immediate with a tag bit | a tag flip-flop, a mux; OUT bit 8 |
| no CRC | a CRC16 has 65,536 states; no programme can hold them | **the CRC assist** (below) | 1,854 µm² fixed, 3,621 µm² programmable |

Measured area (Yosys, sg13g2 typical, `synth/results.txt`): the original sequencer is 17,266 µm²
and 179 flip-flops; the variant is 19,777 µm² and 188 flip-flops, so the four ISA changes cost
2,510 µm² (+14.5 %). The encodings were checked against master's four-phase extension. Master
uses SETP/SHO bits [1:0] and SHI bit 7. This variant uses SHO bit 6, OUT bit 8, WAITP/JMP/JNZ bits
[7:6] and opcode E, so the two do not collide. The variant here is built on the pre-four-phase
`isa.ml`, and merging the two is left to a deliberate change.

### The generic assist: a programmable CRC unit (`crc_unit.ml`)

The firmware drives three signals on sequencer pins (bit strobe, value, enable) and reads one
back (ok). A frame signal qualifies the strobes. Protocol knowledge is configuration: polynomial,
initial value, residue, bit order (LSB or MSB first) and how many leading bits to skip, at widths
up to 16 (32 for Ethernet is a wider register). The same unit serves:

- USB CRC5 and CRC16;
- CAN CRC15, MSB first;
- SMBus PEC and 1-Wire CRC8;
- HDLC and SD CRC16-CCITT, and SD CRC7;
- at width 32, Ethernet's FCS.

The model and RTL agree over 200,000 random clocks for USB CRC16, USB CRC5 and CAN CRC15, both as
the fixed unit and as the programmable one. It needs no USB-specific logic. The PID skip is done
by the firmware arming it after the PID.

The reply FIFO is the other piece of hardware. It is a 4-byte FIFO in front of the sequencer's
host port, with its non-empty flag on a pin, and it is generic: any protocol with a response
deadline needs its first bytes on chip. It is modelled in OCaml and shared by both systems; there
is no RTL for it yet. The pin streamer's FIFO is the obvious implementation.

### What the other generic pieces would buy

- **Bit stuffing and NRZI unit** (programmable run length and polarity: USB 6 ones, CAN 5 equal
  bits, HDLC 5 ones). It would free T0 and the three pins between T0 and the consumers. At low
  speed firmware does this, so the unit is not needed here. At full speed (4 clocks per bit)
  it is.
- **Pin sampler.** Its timed mode samples every period after a trigger, with no re-timing on
  edges. Over a 100-bit packet at ±1.5 % that slips by more than a bit, so it cannot receive
  USB. Its clocked mode could capture VALUE on STB into a FIFO, for the host. The sequencer
  cannot read that FIFO.
- **Pin streamer.** It could send the precomputed replies (width 2, period 40, idle = released).
  It would need a trigger input so that firmware starts it at the right clock, since today it
  starts when a word arrives, and a choice among queued replies (NAK, STALL, data). SHO pair
  mode in T1/T2 does this with no new block.
- **Systolic matcher** (`matcher_exp.ml`, on its closed-form specification):
  - Fed one sample per decoded bit, with T0's strobe as a clock enable the prototype lacks, a
    16-cell template of the 16 bits after an IN token's PID found all 13 target tokens in
    159,016 bits of random traffic.
  - It also hit 46 OUT/SETUP tokens with the same tail (the PID lies outside the template) and
    1 chance match in data (2.4 expected).
  - So it can recognise tokens, but only framed (right after a PID) and one matcher per endpoint
    (10,015 µm² each). SKNE does the same job for part of 2,510 µm².
  - The matcher's place is sync and delimiter search in raw oversampled streams at higher
    rates. There the offset is unknown and there is no bit clock yet.

## The reply path in clocks

Measured on one SETUP (answered ACK by T2) and one IN (answered with FIFO data by T1). The host
clock is exact. Clocks are counted from the first SE0 clock of the host's EOP; 40 clocks = 1 bit.

| clock | SETUP data, answered ACK by T2 | clock | IN token, answered with FIFO data by T1 |
|---:|---|---:|---|
| 0 | host's EOP begins (SE0) | 0 | host's EOP begins (SE0) |
| 12 | T0 raises IDLE: end of packet seen | 16 | T0 raises IDLE |
| 40 | T0's end-of-packet strobe (after the 6-slot low) | 44 | T0's end-of-packet strobe |
| 46 | T2 has checked abort and CRC_OK and chosen ACK | 65 | T1 has checked the token's end and RDY and chosen the data |
| 80 | host's SE0-to-J (turnaround reference) | 80 | host's SE0-to-J |
| 138 | device drives J (host released at 120) | 141 | device drives J |
| 186 | device's first K: turnaround 2.65 bits | 189 | first K: turnaround 2.73 bits (one pad symbol) |

The window the specification allows is from the SE0-to-J edge (clock 80) plus 2 bits to plus
6.5 bits: first K between clocks 160 and 340.

- **The firmware has decided within 46 to 65 clocks**, before the host's EOP has even ended
  (clock 80).
- It then waits on purpose: the host drives its final J until clock 120, and the device may
  drive J only after that. At 1.5 % slow the host ends at clock 122.
- The rest is symbol timing. The first K lands at 186 to 189 for handshakes, a turnaround of
  2.6 to 2.7 bits.
- Data replies are front-padded with 1 to 4 J symbols to whole bytes. Over all the runs,
  turnarounds measured 2.51 to 6.00 bits, inside the 2 to 6.5 limit.

Of the 340-clock budget the firmware's own work takes under 65 clocks; the constraint that binds
is the host's bus release. Where the firmware spends its time is detection: about 12 to 16
clocks for T0 to see the SE0, through the two-flop synchroniser and a 4-clock poll, plus a
deliberate 6-slot low before the end-of-packet strobe.

## What went wrong on the way (all found by the random and tolerance tests)

- **The sample point walked off the end of the bit.**
  - A one took 7 slots to publish, and an edge arriving meanwhile was timed late. That late
    edge set the next sample point late, and every one-zero pair added more.
  - A later version assumed such an edge was at its nominal place. That kept a late sample point
    late, and 0xFF bytes (stuff bits every 7 bits) then drifted it out of the bit with the host
    1 % fast.
  - The fix: an edge seen during the publication of a one is placed in the middle of the window
    in which it must have happened. That pulls the sample point back.
- **Runs of zeros were never timed.** Coming back from a zero took a full bit (10 slots). With
  the host fast, each edge had already happened when the thread began waiting for it. The zero
  path is now 8 slots (9 from K).
- **Consumers lost the first bit of a byte.** The strobe protocol and the byte loops were
  reworked three times:
  - the consumer waits for the low first;
  - it does only SHI and JNZ per bit;
  - the end of packet is IDLE raised before a 6-slot low, so a consumer busy with a byte still
    sees it.

## Files and running

- **Hardened device:** `ls_rx.ml`, `ls_tx.ml`, `ls_sie.ml`, `ls_dev.ml`, `descriptors.ml`;
  `main_hard.ml` runs it. It writes `usb_ls_device.v`.
- **Firmware:**
  - `isa_ls.ml`, `sequencer_ls.ml`: the ISA variant and its RTL;
  - `crc_unit.ml`, `fw_sys.ml`: the CRC assist and the system;
  - `firmware.ml`: the programmes; `asm.ml`: the assembler;
  - `fw_codec.ml`, `controller.ml`, `dut_fw.ml`;
  - `main_fw.ml` runs the ISA lockstep, the CRC lockstep, T0 on the original sequencer, the
    device, the budget and the controls.
- **The original sequencer** (`isa.ml`, `sequencer.ml`, `harness.ml`) is symlinked, not
  modified.
- **`emit.ml` and `synth_sg13g2.sh`** produce the area figures.
- **`matcher_exp.ml`** is the systolic matcher experiment (`run-matcher-exp.log`).
- **`dbg2.ml`** runs a control read with a per-slot trace of one thread, for debugging.

```
opam exec --switch=5.3.0 -- dune build
_build/default/main_hard.exe 8     # seeds for the random sessions
_build/default/main_fw.exe 8
BUDGET=1 _build/default/main_fw.exe
YOSYS=... LIB=.../sg13g2_stdcell_typ_1p20V_25C.lib ./synth_sg13g2.sh
```

## Not done, and open questions

- **No real host.** The FPGA with a Linux host is the next check. No place and route either.
- **The data turnaround varies with padding (2.6 to 5.9 bits).** The firmware could read a pad
  count from the FIFO and shift its start by it.
- **Some patching is time-bound.** The handshake after OUT/SETUP data is patched on the token's
  event. That holds for controller latency under 1,280 clocks; beyond it, a SETUP arriving while
  endpoint 0 is stalled would be STALLed. With spare words in T2 (70), separate SETUP and OUT data
  paths would remove the bound for SETUP.
- **The reply FIFO has no RTL yet.** The CRC unit's configuration registers are not in its area.
- **Unsupported:** suspend and resume, remote wakeup, string descriptors, SET_REPORT (STALLed),
  and the PRE packet (full-speed hubs).
- **The variant is not merged with master's four-phase ISA.** It should be merged
  deliberately.
