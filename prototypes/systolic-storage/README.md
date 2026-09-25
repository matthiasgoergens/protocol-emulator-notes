# Storage inside the systolic array, and an allocator for memory that forgets (2026-09-25)

Two questions. What does a systolic array gain from small amounts of storage inside it, possibly
uneven? And how would a compiler place values on gain-cell rows that expire
(`../gain-cell/`, `../../notes/gain-cell-compiler.md`)? Each number below points to a file
here or to a cited source. Areas are for IHP SG13G2; times are at 50 MHz unless stated.

## 1. What storage costs per bit

Source: `storage_options.py` → `results/storage_options.txt`, with LEF areas in
`results/lef_areas.txt`. Flop, latch and SRAM areas come from the PDK LEF. Gain-cell bit cells
are the drawn, DRC-clean ones. **Their periphery is an estimate from standard cells, not a
drawing:** per row, two word-line buffers and a decode gate; per column, a write driver, a sense
inverter and a latch.

| option | µm²/bit | lifetime of a stored 1 | fits which values |
|---|---|---|---|
| flop delay line (`dfrbpq_1`, 48.99 µm²; the library has no flop without reset) | 49.0 | static | pipeline registers, delays of a few cycles |
| flop register file, 8–64 words | 80 | static | not worth it: 8 words cost 10.2k µm², about two PEs |
| latch register file (`dlhq_1`, 30.84 µm²), 8–64 words | 45.6–46.3 | static | per-PE coefficients and config, where they must drive logic continuously |
| thick 3T gain cell, bank of 16×16 / 32×32 / 128×32 | 10.0 / 6.0 / 4.4 | ≥ 3.1 ms at ff/85 °C; 12 ms at tt | anything that dies within a frame's worth of lines; resident data with 0.01–0.4 % refresh |
| thin 3T gain cell, same banks | 9.3 / 5.3 / 3.7 | 118.8 µs at tt/27 °C; about 8 µs at tt/85 °C; ≥ 1.2 µs at ff/85 °C | values dying within a line at room temperature; register-like values (< 1 µs) everywhere |
| smallest SRAM macro, `1P_256x8` (2 kbit) / `1P_256x16` (4 kbit) | 8.57 / 6.87 | static | edge buffers of ≥ 2 kbit; one port per macro |

The thin-oxide lifetimes come from `../gain-cell/retention/results/v6-3T-lv-w0.15-l0.13.txt`,
the level reached at the 10 ns sense threshold. The thick-oxide ones come from
`lifetimes-3t.txt`, line `v5-3T-w0.15-l0.45`. The ff figures are lower bounds, because the
readable level there lies below the sweep's floor.

**The main result of the table:** per-PE storage in standard cells costs 46–80 µm²/bit. A
16-bit PE is about 5,000 µm² (estimate, below), so an 8-word register file costs more than the
PE. Gain-cell banks are 5–13× denser at the sizes a PE wants. Unlike SRAM they come in any size,
with no 2 kbit, 17.5k µm² minimum. At 4 kbit and above, a gain-cell bank beats the SRAM macro
only by 1.3–1.9×, or 1.4× once it carries Berger columns (`results/candidates.txt`).

## 2. What the workloads need

| workload | storage | longest value life | fits without refresh |
|---|---|---|---|
| systolic matcher, sorting network, horizontal FIR | pipeline flops, 2 per cell | 1–16 cycles | flops; any gain cell |
| sequencer registers (acc, cnt; trace below) | 13 live words of ≤ 12 bits | 14.9 µs (I2C at 100 kHz); ≤ 0.1 µs for 99.3 % of values | thin rows, except at 85 °C |
| vertical 2-tap / 3-tap filter, 256 × 8-bit lines | 64 / 128 words of 32 bits | 63.4 / 127.4 µs | 2-tap: thin at 27 °C; 3-tap: thick only (it misses thin tt/27 °C by 7 %) |
| Ethernet-fed line buffer before the semiring ring, 3 / 5 / 20 lines per packet | 84 / 117 / 296 words | 0.47 / 0.60 / 1.56 ms | thick, at every condition |
| USB FS packet, wave-engine line packet (512–528 bits) | 16–17 words | ≤ 64 µs | thin at 27 °C, thick otherwise |
| sequencer programme (4×64×16), weights, next-frame config | 0.8–4 kbit | resident | thick with 0.01–0.4 % of one port for refresh (`results/resident.txt`) |

Lifetimes come from the traces (`results/summary.txt`). At 10 Mbit/s one or two lines per
packet cannot keep up, since 116 or 164 bytes are on the wire per 64 or 128 µs of lines
(`gen_traces.py`). The line buffer's depth is therefore forced by the link, not chosen.

## 3. Candidate arrays at 200k µm² (PEs + storage)

Source: `candidates.py` → `results/candidates.txt`. **The PE area is an estimate:** 5,000 µm²
for a 16-bit PE, scaled from the semiring ring's measured 10,603 µm² per 24-bit cell.

Each design gets one port per storage block, one access of the block's width per cycle.
- **Traffic:** workload traffic is spread over the blocks, and refresh adds to it on the same
  port.
- **Reach:** storage beside other PEs is reachable through the array at 16 bits per cycle.
  Above that rate, a workload can use only the storage beside its own PEs.

| design | PEs | storage | what it enables that D0 cannot |
|---|---|---|---|
| D0 uniform, no storage | 40 | 32 flop bits per PE | streaming kernels only |
| D1 8×16 latch RF in every PE | 18 | 2,304 bits, 18 × 16-bit ports | **the only design that feeds weights to 8 PEs every cycle** (8×8 product, 128 bits per cycle). Too small for any line buffer or the programme |
| **D2** edge column, 2 thick banks of 128×32 | **31** | 8,192 bits, 2 × 32-bit ports | line filters, Ethernet line buffer up to 5 lines per packet, USB packets, programme store (0.1 % refresh), a 16-PE merge at 64 bits per cycle (its ports at 100 %, no headroom) |
| D2s the same bits in 2 SRAM `1P_256x16` | 28 | 8,192 bits, 2 × 16-bit ports | the same without refresh, but half the port width, so no merge; 3 fewer PEs |
| **D3** graded: thin 32×16 bank per 4 PEs, 2 thick banks at the edge | 26 | 11,776 bits, 7 × 16 + 2 × 32-bit ports | as D2, plus the 20-lines-per-packet buffer: the thin banks take the overflow, with refresh at 1.3 % of the busiest bank's port at tt/27 °C, 20 % at tt/85 °C, and not at all at ff/85 °C |
| D4 the array as its own delay line | 40 | 32 bits per PE given up | short buffers (a 64-byte packet costs 16 PEs) |

The honest reading:
- **D2 against D2s:** the gain-cell edge column buys 3 more PEs (31 against 28) and twice the port
  width for the same bits. It costs refresh logic that only resident data uses.
- **D3's thin banks do not earn their area** on these workloads. The only thing D3 does that D2
  cannot is the 20-line buffer, and there only at 27 °C or with heavy refresh. Local bandwidth
  would matter for a kernel needing more than the edge's 64 bits per cycle across more than
  8 PEs; none of ours does except the weight product. There, D3's two local banks per 8 PEs give
  32 bits per cycle, not the 128 needed.
- **D1 is not dominated.** It is the only design for weight-stationary products, at a cost of
  22 PEs. A cheaper version would put an 8-word gain-cell bank with Berger columns in each PE:
  about 2,340 µm² (18.3 µm²/bit, periphery estimated) against 5,835 µm² of latches. It is not
  evaluated here.
- **Refresh helps only where D3's thin banks overflow.** No workload needs refresh of a thick
  bank except resident data.

## 4. The allocator (`allocator.py`)

- **Rows have a lifetime:** by row type and operating condition, times a per-row profile factor
  (weak rows), times a guard of 0.8.
- **Placement is best fit:** a value goes to the shortest-lived free row that covers its
  interval, otherwise to the longest-lived free row.
- **At a row's deadline:** the value migrates to a free, longer-lived row, or is refreshed in
  place. Either costs a read and a write, two port cycles.
- **Feasibility is exact:** a mix fits exactly when it has at least as many rows as the peak
  number of live values, because refresh and migration never change how many rows are occupied
  (checked in the tests).
- **Every word carries a Berger check,** and a per-bit decay model applies the *true* lifetimes.

Traces (`traces/`, from `gen_traces.py` and `seqtrace/`):
- **Sequencer, instrumented:** the deadline sequencer's own interpreter, unchanged. It runs the
  demo's three compiled protocols at 115200 baud, 1 MHz SPI and 100 kHz I2C. `seqtrace/check.sh`
  verifies the copied sources.
- **Line buffer, a model:** the Ethernet-fed buffer in front of the semiring ring, with 100 µs
  margin and 0–200 µs of host jitter.
- **Vertical filters, a model:** 2- and 3-tap vertical filters at 10 clocks per pixel.

Cheapest row mix per condition, with refresh bandwidth ≤ 10 % of one bank's port cycles
(`results/mixes.txt`). The search tries every thin-row count, with 0, peak/8 and peak/4 spare
thick rows. The all-thick mix never needs a refresh.

| trace | all thick | tt/27 °C | tt/85 °C | ff/85 °C |
|---|---|---|---|---|
| seq-regs (13 rows × 12 bit) | 2,338 µm² | 0+13, 0 %, −6 % | 0+13, 1.2 %, −6 % | 1+12, 6.7 %, −6 % |
| seq-imem (165 × 16) | 16,711 | 0+165, 1.2 %, −14 % | 57+108, 9.9 %, −9 % | 105+60, 9.7 %, −5 % |
| linebuf-P5 (117 × 32) | 18,991 | 0+117, 2.6 %, −16 % | 63+54, 9.8 %, −7 % | 87+30, 9.3 %, −4 % |
| linebuf-P20 (296 × 32) | 44,170 | 0+296, 7.7 %, −18 % | 215+81, 9.7 %, −5 % | 254+42, 9.5 %, −2 % |
| vfir2 (64 × 32) | 11,535 | 0+64, **0 %**, −15 % | 44+20, 9.7 %, −5 % | 61+3, 9.1 %, −1 % |
| vfir3 (128 × 32) | 20,538 | 0+128, 3.5 %, −16 % | 109+19, 9.7 %, −2 % | 125+3, 9.1 %, −0.4 % |

Entries are thick+thin rows, refresh bandwidth, and area against all thick. The seq-imem trace
covers only the 349 µs run, so its values are not resident here. Kept for ever, it is the
resident case in `results/resident.txt`.

- **Liveness pays against a blind controller.** A controller refreshing every row of the same
  mix does 1.6–2.0× the operations on the video traces at 27 °C, and 1.4–18× at ff/85 °C. vfir2
  at 27 °C needs none against the blind controller's 23,780. For linebuf-P5 at ff/85 °C it is
  82,527 against 1,113,540.
- **The planted weak row is caught** (`test_allocator.py`, `results/test_allocator.txt`). The
  row lives 25 % of nominal but was profiled as nominal. Of 6,000 reads, 94 were corrupt and all
  94 were flagged: no silent corruption and no false alarms, and every flag came from that row.
  After promoting the row, 0 reads were corrupt, at a cost of 248 refresh or migration
  operations.
- **The Berger code is tested exhaustively on 8 bits.** A control test shows that a mixed-direction
  error passes it, so the exhaustive test is not vacuous.

## Review

An adversarial review by codex found ten problems, and the numbers above are after the fixes
(commit "fixes from an adversarial review"):
- **A refresh restored decayed data.** It now writes back what it read, and a test covers this.
- **The allocator reused a row in its value's last read cycle,** unlike the peak-live count.
- **The line buffer was consumed at line start.** It is now consumed when the ring shifts it in,
  at clocks 3240–3287 of the preceding line.
- **Three read-accounting slips in the sequencer trace,** none of which the demo programmes
  exercise.
- **The candidate verdicts ignored port width and per-bank refresh,** and treated D1 and D3
  unevenly. Fixing this reversed two conclusions: D1 is not dominated, and D3's local bandwidth
  is not needed by our kernels.
- **Two README ranges were wrong.**
- **The mix search was coarse.**

## Surprises

- **No trace needs to refresh a thick row, even at ff/85 °C.** The longest-lived value, 1.56 ms,
  is below 3.1 ms × 0.8. Refresh is only for resident data and for thin rows.
- **The thin/thick mix is a second-order knob.** It saves at most 18 %, and only at room
  temperature; hot, it saves 0.4–9 % for close to 10 % of the port in refresh: the cells differ by 2.20 against 2.89 µm², and periphery and Berger columns dilute
  that. The first-order win is gain cells against flops: 8–10× on the video traces and the
  programme store, but only 3.3× on the 13 sequencer registers, where periphery dominates.
- **The vertical 3-tap filter misses thin tt/27 °C by 7 %.** Its line pair lives 127.4 µs against
  118.8 µs, close enough that silicon will decide.

## Open questions

- **The PE area** (5,000 µm²) and **the gain-cell periphery** are estimates. Synthesise a 16-bit
  PE and draw a sense and driver column.
- **Can a Tiny Tapeout digital tile take small hand-drawn macros** placed among the PEs? D3
  depends on it.
- **Thin-oxide Monte Carlo:** a 4σ cell leaks one to two decades more (`../gain-cell` notes).
  That could remove D3's thin banks at 85 °C altogether.
- **Refresh without a spare cycle:** the 3T cell's separate read and write ports would let a
  refresh write back behind an ordinary read, such as an instruction fetch. This is not
  modelled.
- **The allocator is greedy,** and the mix search samples spare thick rows at three levels.
  Its only lower bound (unlimited thick rows) is trivially zero here, so a better bound is
  needed.
- **The candidate verdicts use a simple port model:** traffic spread evenly, and 100 %
  utilisation allowed. Real arbitration and access phasing would tighten D2's merge and D3's
  refresh.

## Prior art (numbers checked against the fetched papers)

- **Warp** (Annaratone et al., IEEE TC 1987): "each cell has 32K words of local data memory".
  Its register files hold 31 words per floating-point unit; the queue depth is 512 words. The
  opposite extreme: big memory in every cell.
- **iWarp** (Borkar et al., SC'88): "A shared, multiported, 128 word register file" per cell;
  larger memory is off-chip.
- **TPU v1** (Jouppi et al., ISCA 2017, arXiv 1704.04760): "The matrix unit holds one 64 KiB tile of
  weights plus one for double-buffering". The weight FIFO is four tiles deep, and a 24 MiB Unified
  Buffer sits outside the array. Storage in the array is only the stationary operand; bulk
  storage is at the edge, like D2.
- **Eyeriss** (Chen, Emer, Sze, ISCA 2016): "RF Size/PE 0.5 kB", a 108 kB global buffer, and a
  normalised access energy of DRAM 200×, buffer 6×, array 2×, RF 1×. The 168-PE count is from
  the JSSC paper, which I did not fetch (unverified).
- **Plasticine** (Prabhakar et al., ISCA 2017): compute units hold only pipeline registers; memory
  units have "16 configurable, 16KB banks, for a total of 256KB per PMU". They are laid out 64 and
  64. Of the fetched papers, it is the closest precedent for storage that is non-uniform by design.
- **Jing et al.** (ISCA 2013), eDRAM register file for a GPGPU: the 3T1D gain cell's retention is
  "at the magnitude of a couple of us", with refresh scheduled around register accesses. That is
  close to our thin-oxide row.
- **DaDianNao** (MICRO 2014): 36 MB of eDRAM per node, per tile rather than per PE.
- **ADRES and HyCUBE** register-file sizes: not verified (no open text found).

Papers were fetched and grepped on 2026-09-25. Copies are in `/var/tmp/systolic-storage-notes/`,
which is scratch and not in the repository.

## Files and how to re-run

    uv run lef_areas.py > results/lef_areas.txt
    uv run storage_options.py > results/storage_options.txt
    (cd seqtrace && ./check.sh && opam exec --switch=5.3.0 -- dune build) && seqtrace/_build/default/trace.exe > traces/seq.csv
    uv run gen_traces.py > results/gen_traces.txt
    uv run allocator.py summary > results/summary.txt
    nice ionice uv run allocator.py mixes > results/mixes.txt     # about 70 s
    uv run allocator.py resident > results/resident.txt
    uv run candidates.py > results/candidates.txt
    uv run --with pytest pytest -q -s test_allocator.py
