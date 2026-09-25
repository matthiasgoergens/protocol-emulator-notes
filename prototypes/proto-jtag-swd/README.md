# JTAG and SWD hosts as firmware on the deadline sequencer

The post lists JTAG and SWD among "other interesting protocols to consider". Both are here as
sequencer firmware. They are checked end to end against independent target models, with the
pins wired clock by clock, including SWDIO as one bidirectional line with contention detection.
Every run goes through both the interpreter and the RTL.

- **JTAG runs on the stock sequencer, unchanged.** `stock/` symlinks `isa.ml`, `sequencer.ml`
  and `harness.ml` from `../deadline-sequencer`.
- **SWD needs one ISA change: a wider programme counter.** The pc and the address fields grow
  from 6 to 8 bits, giving 256 words per thread, the store the sequencer README already plans.
  The variant is in `wide/`; the proposal is at the end of this file.

Build and run, in each of `stock/` and `wide/`:
`opam exec --switch=5.3.0 -- dune build --root . ./main.exe && ./_build/default/main.exe`.
`wide/main.exe` takes `lockstep`, `jtag` and `swd` to run parts. The shared sources are in
`common/` and are symlinked into both.

## JTAG (`common/jtag_host.ml`)

A thread has one 8-bit accumulator, and both SHO and SHI shift it. So one thread cannot shift
TDI out and TDO in on the same clock: interleaved, the two instructions shift twice per bit.
The work is therefore split across two threads.

- **Thread 0, the driver (22 words), is a vector engine.** Each host byte carries four TCK
  cycles as (TMS, TDI) pairs. Per cycle the driver sets TCK low, shifts out TMS, shifts out
  TDI, and sets TCK high. The driver knows nothing about the TAP. Navigation, IR and DR scans,
  their lengths and their data all come from a vector compiler on the host (`reset`, `scan`,
  `pack`). This is the precompute-on-the-host rule the Ethernet transmitter uses.
- **Thread 1, the sampler (26 words), follows TCK as it appears on the pad.** It waits with
  `WAITP` for low, then for high, then samples TDO one slot later. It sends the host a byte
  every eight TCKs. It has no timing of its own, so a late host byte only stretches TCK. JTAG
  is static, so that is harmless. The random tests stall the host on purpose (189,085 stalled
  clocks) and lose nothing.

Checks, all against expectations computed from the chain configuration and IEEE 1149.1, never
from the models' state:
- the chain's IDCODEs after Test-Logic-Reset, including a device without an IDCODE, which shows
  up as one BYPASS bit;
- the mandated `01` in every IR capture;
- the BYPASS chain test: one captured 0 and one bit of delay per device;
- SAMPLE/PRELOAD and EXTEST on one device with the others in BYPASS, of boundary registers up to
  300 bits: the captured pin levels on TDO, and the device's update latch afterwards.

## SWD (`common/swd_host.ml`)

SWD is one thread running a 221-word transaction engine. Each host byte starts one packet, and
the engine makes every decision the protocol needs itself, at pin speed.

- **Branching on data without a branch-on-data instruction.** The sequencer can branch only on
  a pin, using WAITP with the deadline at 0. So the engine drives the bit it needs onto SWDIO
  and reads the pad back:
  - the request's Start bit, which is always 1, so a 0 marks the byte as a command: a line
    reset, or the JTAG-to-SWD switch followed by a line reset;
  - RnW, to choose the read or the write path;
  - each of the three ACK bits.

  A WAIT, a FAULT or no response at all (the pull-up reads 111) leaves the packet before the
  data phase. The same trick works for any protocol whose phases depend on a header bit: the
  R/W bit of I2C, the op code of MDIO.
- **The turnaround is pure firmware.** `SETP` with oe=0 releases SWDIO, and the edge
  conventions of ADIv5 are compiled in. The host changes SWDIO early in the low phase. The
  target samples on the rising edge and changes its output after it. The host samples late in
  the low phase. No hardware assist is needed. The same idiom serves I2C, 1-Wire and
  half-duplex SPI.
- **Parities are the host's.** The host puts the request parity into the request byte and sends
  the write-data parity. It checks the read-data parity itself.
- **Write data always travels with its request.** The engine consumes a write's data bytes
  whatever the ACK, so the host can stream a packet without waiting for its ACK. The host
  retries on WAIT.

The checks cover:
- the JTAG-to-SWD switch, the DPIDR read, the CTRL/STAT power-up handshake, SELECT and CSW;
- MEM-AP writes, and posted reads through RDBUFF;
- the AP's IDR through bank 0xF;
- a write-data parity error, which gives WDATAERR, then FAULT, then recovery through ABORT;
- a request parity error, which gives no response, then recovery through a line reset and a
  DPIDR read;
- random traffic against a shadow memory with random WAITs, with every read value and the
  target's final memory compared.

## Independent targets (`common/jtag_tap.ml`, `common/swd_target.ml`)

A separate agent wrote the target models from its own reading of IEEE 1149.1 and ADIv5. It
worked in a fresh context, never saw the host code, and had only the pin-level interface. Its
notes on every interpretation choice and its own bit-banged self-test are in
`targets-origin/`. The models as delivered are in commit e5e4455.

Wiring the two sides together found five bugs, four of them in the models:

| where | bug | who was right |
| --- | --- | --- |
| SW-DP model | required exactly 50 ones before the select sequence | ADIv5 says at least 50 |
| SW-DP model | took the 51st one of a line reset as a Start bit | same |
| SW-DP model | answered OK after WDATAERR | SW-DP FAULTs on any sticky flag |
| TAP model | kept its data register in an OCaml int, which overflows past 62 bits | a 300-bit boundary register |
| host engine | reused one loop's label on both paths, so the read path jumped into the write loop | the assembler now rejects duplicate labels |

The fixes are marked `FIX 1` to `FIX 4` in the models. The host bug also shows the value of the
models: the RTL and the interpreter agreed on every clock of the broken engine, because
lockstep compares against the specification. Only the device at the other end of the wire could
see the bug.

The limit on independence: the same model family wrote both sides, and I fixed the models.
Each fix follows the text of the standard and not the host, and each is recorded above.

## Results (`results/`, measured at commit 319cfb9)

| | JTAG, stock ISA | SWD, wide ISA |
| --- | --- | --- |
| directed | 3-TAP chain (IDCODE, one without IDCODE, IDCODE; BSR 20/7/100): pass on both cores, 8,914 clocks compared, 0 differ | bring-up, 25 packets: pass; FAULT and recovery: pass; 0 clocks differ |
| constrained random | 60/60 sessions: chains of 1-4 TAPs, IR 2-8, BSR 1-300, random data, synchroniser depth 0-3, target delay 0-3, host stalls. 660,632 clocks compared, 0 differ, 29,760 TCKs | 40/40 sessions: random addresses and data, WAIT with p up to 0.5, synchroniser 0-3, delay 0-3, stalls. 2,293 packets, 829 WAITs retried. 2,312,232 clocks compared, 0 differ |
| controls (must fail) | 4 × 20/20 caught: TMS one bit early; one TMS=1 missing before Shift-IR; TMS and TDI swapped; TDO sampled two slots late | 6 × 10/10 caught: request parity flipped; write parity flipped; no turnaround before ACK (contention); no turnaround after write ACK (FAULT); sampling after the rising edge (contention); one wrong bit in the switch sequence (no response) |

The wide variant's own lockstep against its interpreter ran 300 programmes × 2,000 cycles with 0
mismatches. As a control, the same RTL with the old 6-bit address field gives 561,761
mismatching cycles (`results/lockstep-mutation-control.txt`).

## Clock rates at a 60 MHz core clock

| | fastest | what limits it |
| --- | --- | --- |
| TCK | 3.00 MHz peak (20 clocks: high 8, low 12), 2.86 MHz mean (a 4-TCK group is 21 slots) | issue rate: the driver needs 4 instructions per TCK (TCK low, TMS, TDI, TCK high), one per 4 clocks, plus one IN per 4 TCKs. The sampler needs the high phase to last 2 slots. |
| SWCLK | 3.75 MHz (16 clocks: high 8, low 8) | issue rate: 4 instructions per bit (SWCLK low, data, SWCLK high, loop branch). |

The pins are not the limit. The runs sweep the delay from a clock edge to the target's answer
arriving: target clock-to-out plus board flight (`tco`) and the input synchroniser (`sync`),
both in core clocks.

- **JTAG** passes while tco ≤ low phase + 6 clocks. That is 18 clocks, 300 ns, at 3 MHz; it
  fails at 19. It is 22 at `lo` 1 and 30 at `lo` 3. The sampler follows TCK through the same
  synchroniser as TDO, so the synchroniser depth cancels out.
- **SWD** passes while tco + sync ≤ 10 clocks, about 167 ns: it passes at tco 8 with sync 2 and
  fails at 9. A real target's clock-to-out is tens of nanoseconds.

Going faster would mean spreading one bit's instructions across threads, as the Ethernet
transmitter does, or the shift instruction proposed below.

**Slower SWCLK does not currently fit.** Each padding slot costs a word at about 40 sites, so
`lo` 2 needs 261 words against a store of 256. The fixes are to fold the two not-OK chains
together (about 20 words) or to run the SWD phases on two threads. This is open.

## Proposed ISA change: 8-bit programme counter (implemented in `wide/`)

**What.** `pc_bits` goes from 6 to 8. WAITP's fail field becomes bits 7:0, and JMP/JNZ address
bits 7:0. The diff against the stock files is six lines in `wide/isa.ml` and one in
`wide/sequencer.ml`.

**Why.** A self-contained SWD engine, one that handles ACKs locally and has separate read and
write paths, is 221 words. The stock store holds 64 per thread (`stock/main.exe` reports this).
Squeezing SWD into 64 words means either host round-trips mid-packet, with SWCLK stopped while
the CPU decides, or spare pins used as flags between threads. Both are worse. Nothing else
changes, and it is generic: every programme gets four times the room.

**Cost.**
- 8 more pc flip-flops (4 threads × 2 bits), wider muxes on the pc path, and a 10-bit
  instruction address, which is exactly a 1024×16 macro.
- Compatibility with master's quarter-clock extension: none of its fields collide. It uses
  SETP/SHO bits 1:0 and SHI bit 7, while this change uses WAITP bits 7:6 and JMP/JNZ bits 7:6,
  which were unused in both. Old programmes behave identically, because their addresses are
  below 64.

## Considered, not proposed: a full-duplex shift (SHX)

One more opcode (E is free) would drive acc bit 0 onto pin a and shift pin b into bit 7 in the
same slot. Its fields would be out-pin, in-pin and msb.

**What it would serve:** SPI full duplex (the current compiler's SPI only transmits), JTAG on
one thread instead of two, scan chains, and MDIO read-back.

**Cost:** one more case on the acc_next mux and a second 3-bit pin select.

It is not proposed now. JTAG works on the stock ISA with two threads, and the rule is
firmware-only where it fits. The case for SHX is freeing a thread and SPI full duplex, which
should be measured on SPI before it is decided.

## Open questions

- **No reference outside our own two models.** Neither side has met real silicon or a
  third-party model. Next steps: an FPGA run against a real Cortex-M's SWD, or OpenOCD's
  `jtag_vpi` against a Verilog TAP.
- **Model choices I have not verified in the standard.** The SW-DP model ignores all accesses
  until DPIDR has been read after a line reset. It FAULTs DP accesses (other than the exempt
  ones) when a sticky flag is set. The TAP model keeps driving TDO in Exit1.
- **The host byte interface is assumed to keep up.** The random stalls show that a late host is
  safe. They do not show that the real host interface is fast enough.
