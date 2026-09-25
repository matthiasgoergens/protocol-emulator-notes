# Prior art: machines that were hard to program, and the Forth chips (note, 2026-09-25)

Our chip deliberately trades ease of programming for capability. It pairs a small CPU with a
systolic array and gain-cell memory whose stored 1s leak away (`gain-cell-compiler.md`,
`../prototypes/gain-cell/`, `../prototypes/systolic-storage/`), and it expects demoscene-level
programming. This note collects what happened to earlier machines that made the same trade. Part
1 covers designs that failed or struggled, part 2 Chuck Moore's Forth chips, and part 3 the
lessons for us.

The goal is inspiration, not a verified history, so sources are mixed. Each claim carries a label.
- **[P]** primary: the designer's or vendor's own document, a paper, a manual, an SEC filing.
- **[S]** secondary: a well-sourced retrospective, reputable press, or a named user's blog.
- **[F]** folklore: a forum post, an anecdote, or a claim repeated widely without a source found.
- **[inference]** my own reasoning, not a sourced claim.

The sources I relied on were downloaded to `/var/tmp/hard-to-program/{A,B,C,D,E1,E2}/`, each
directory with a `findings.md` that has fuller quotes. The load-bearing quotes and numbers below
were grep-checked against those saved files. The main exception is the Tera DTIC report, a
fax scan without a text layer, whose quotes were transcribed by eye.

---

## Part 1: crazy designs that failed or struggled

### The honest headline

**"Too hard to program" was rarely the whole story.** Most of these machines died of money,
timing or a commodity curve they could not ride. Where programming difficulty did bite, it
usually showed as a tax rather than a death sentence: the customer quietly used a fraction of the
machine, or only a few studios mastered it. The cleanest cases where the programming model was
the problem are Itanium, the i860, Raw's general-purpose ambitions and TRIPS. In each of those the
*compiler* could not do what the hardware assumed.

### Summary table

| machine | what was crazy | what happened | was programming THE cause? | what made it work, if anything |
|---|---|---|---|---|
| Intel iAPX 432 (1981) | hardware objects and capabilities, hardware GC, 5 associative caches | slow; abandoned | no: the object model itself was slow ("1/4 to 1×" contemporaries even if redone) [P] | "composites" to batch small objects [P] |
| Intel i860 (1989) | exposed FP pipelines, no interlocks, dual-instruction mode with 9 rules | shipped in 2 generations; niche | largely yes: Intel said ordinary compilers could use it only "as a scalar machine" [P] | hand-scheduled assembly kernels [P, manual examples] |
| Itanium / EPIC (2001) | bundles, predication, compiler speculation | niche; HP took 95% of shipments by 2008; dead 2021 | partly: Knuth said the compilers were "basically impossible to write" [P]; x86-64 and delays also [S] | Intel's icc; hand-tuned enterprise code [F] |
| Multiflow TRACE (1987) | VLIW, 7–28 ops/instr, trace scheduling | ~140 sold; folded 1990 [P, memoir] | no: "killer micros" and business [P, memoir] | the compiler worked, was licensed widely, and fed into IA-64 [S] |
| Cydrome Cydra 5 (~1987) | rotating registers, predication, modulo scheduling | a handful built; folded ~1988 [F] | not shown; the minisupercomputer market collapsed [S] | its ideas became IA-64's software pipelining [S] |
| Transputer / occam (1985) | CSP in silicon, links, no shared memory, `PLACED PAR` | sold well in niches; T9000 late; Inmos sold 1989 | mixed; business and T9000 delays at least as much [S] | the occam discipline itself |
| Thinking Machines CM-1/2 (1985–) | 64K 1-bit PEs, *Lisp, hypercube | 7 CM-1 sold, DARPA-subsidised; Chapter 11 in 1994 [S] | no, but users "ignor[ed] the 64,000 single-bit processors" [S] | CM-2's floating-point units |
| MasPar MP-1/2 (1990) | 16K-PE SIMD, cheaper CM | ~200 systems; left hardware 1996 [S] | no: the MPP market collapsed [S] | — |
| Cell BE / PS3 (2006) | 8 SPEs, 256 KB local stores, explicit DMA, no cache [P] | sold in the hundreds of millions; Roadrunner hit 1 PF [S] | directly blamed for costs ("a total disaster", Newell) [S], but not fatal | data-oriented design, double-buffered DMA, first-party heroes [P, Acton] |
| MIT Raw (2002) | on-chip networks routed by the compiler, cycle by cycle [P] | research chip; spun off Tilera | yes for sequential code; the team pivoted to StreamIt [P] | a stream DSL; Tilera "de-crazed" to coherent SMP [S] |
| UT TRIPS (2006) | EDGE: 128-instruction dataflow blocks placed on a grid | silicon worked; 60% of a Core 2 on SPEC [P] | yes, the compiler could not form big blocks in control-heavy code [P] | hand-coded kernels ran 3× a Core 2 [P] |
| Stanford Imagine / SPI Storm-1 | StreamC + KernelC, no memory access inside kernels [P] | SPI shut 2009 [S] | mostly economics; the model "somewhat specific to media processing" [P] | the ideas went into GPUs [S] |
| Ambric Am2045 (2007) | 336 cores; Kahn process network with self-synchronising FIFOs | IP sold in the 2008 crash [S] | no: praised as easy to program; died of the credit crunch [S] | the programming model |
| MathStar FPOA | 400 coarse "silicon objects" | $588K revenue in 2007 against a $126.5M deficit; closed 2008 [P, 10-K] | market, plus tool immaturity it admitted [P] | — |
| picoChip picoArray | ~250–300 tiny VLIW DSPs, network fixed at compile time | ~70% of HSPA femtocells (claimed); bought 2012, then by Intel 2013 [S] | a success | deterministic, cycle-accurate simulator; a narrow niche [S] |
| Tabula (2010s) | FPGA fabric reconfigured up to 8× per user clock | shut 2015 after $215M raised [S] | unknown [F] | — |
| Tera MTA (1997) | 128 hardware threads per CPU, full/empty bit on every word | first system late 1997; bought Cray 2000 [P] | no: GaAs yield [P, 10-K]; Tera sold it as *easier* to program | the compiler auto-parallelised; futures [P] |
| Adapteva Epiphany / Parallella | mesh of tiny RISC cores, 1024 in Epiphany-V [P] | Kickstarter raised $898,921 but cost >$1.5M to deliver [P] | no: pricing and volume [P] | — |
| Intel Larrabee (2009) | x86 cores rendering graphics in software | GPU cancelled Dec 2009; became Xeon Phi [P] | no: "time and politics" (Forsyth) [P] | ran 300+ Steam titles; its ISA became AVX-512 [P] |
| The Mill | belt instead of registers, 30-wide static issue | no silicon after 20+ years [P] | no: money and headcount [P] | LLVM toolchain; CoreMark per MHz "on par" in simulation [P] |

### Notes per machine (only what the table cannot carry)

**iAPX 432.** Colwell, Gehringer and Jensen's 1988 retrospective is decisive. Its abstract says
"Even with these modifications, however, the 432 would still have only one-fourth to one times
the speed of its contemporaries. These figures may represent the real cost of the 432's style of
object-based programming environment." [P; ACM TOCS 6(3), DOI 10.1145/45059.214411; full text
paywalled, abstract via CrossRef]. The lesson is about granularity. The hardware's natural unit
(the object) was too fine to track cheaply, and the fix was to batch objects into "composites"
[P; Organick 1983, p. 301].

**i860.** Intel's own manual says it plainly: "Conventional programs and conventional compilers
can use the i860 Microprocessor as a scalar machine … New instruction-scheduling technology for
compilers can … take maximum advantage of its dual-instruction mode, pipelining, and caching" [P;
*i860 Programmer's Reference Manual* 240329-002, §1.7]. Each pipelined FP result lands one, two or
three operations later, depending on the unit, and software has to track which is which. The
manual's worked examples are hand-scheduled assembly. The one redeeming feature is that the
hazards form a closed, enumerable list (nine dual-mode rules plus the delay-slot rule), so a tool
could check them.

**Itanium.** Knuth, 2008: "…worse than the 'Itanium' approach that was supposed to be so
terrific—until it turned out that the wished-for compilers were basically impossible to write."
[P; InformIT interview,
https://web.archive.org/web/20210223015337/https://www.informit.com/articles/article.aspx?p=1193856].
There are two further sufficient causes. AMD's binary-compatible x86-64 removed Itanium's reason
to exist, and it shipped years late [S; NYT Bits, 9 Feb 2009]. By 2008 HP made 95% of Itanium
server shipments [S, same]. Torvalds marked it orphaned in 2021: "It's dead, Jim" [S quoting the
commit; https://www.theregister.com/2021/02/01/linux_pulls_itanium_support/].

**Multiflow and Cydra 5.** Both are counter-examples to "the compiler bet always fails". Elizabeth
Fisher's memoir gives Multiflow's end as business: "It was 'the attack of the killer micros' …
that made the computers Multiflow produced … unnecessary" [P-ish memoir, multiflowthebook.com]. It
also gives "about 140 machines at an average price of around $350,000", against ~125 in other
accounts. Cydra 5's compiler invented much of modulo scheduling: an iterative search for the
smallest initiation interval II ≥ max(ResMII, RecMII). It also invented register allocation over
*vector lifetimes* on rotating register files, with modulo variable expansion as the fallback
when a lifetime outran the rotation window [P; Rau & Fisher, "Instruction-Level Parallel
Processing", J. Supercomputing 1993 / HPL-92-132]. **That is the closest existing theory to our
"a value may occupy row r only if its interval fits L(r, T)" constraint** [inference].

**Transputer.** occam made the programmer write the process network first and place it on
processors last: "This allocation is performed by replacing PAR with PLACED PAR" [P; *A Tutorial
Introduction to Occam Programming*, http://www.transputer.net/obooks/72-occ-046-00/tuinocc.pdf].
Algorithm and placement are separate phases. David May's 2017 keynote still argues that
*shared memory* is what makes programming hard [P;
https://www.icpp-conf.org/2017/files/keynote-david-may.pdf]. There is also a nice anecdote. A
batch of transputers was packaged the wrong way round, working but unsaleable, so May had ~2000
written off and built 42-transputer boards from them. Southampton assembled a 1260-processor
machine from those boards [P; May's transputer page].

**Connection Machine.** Hillis's thesis warns that "Many of our assumptions about what is
difficult and what is easy do not apply" [P; MIT thesis 1985, https://dspace.mit.edu/handle/1721.1/14719].
Taubes's post-mortem supplies the key fact: "Many of Thinking Machines' first customers … did
most of their computing on the floating-point processors, ignoring the 64,000 single-bit
processors." [S; Inc., Sept 1995]. That is programming difficulty as **silent value loss**. The
machine still sold, but its crazy part sat idle. The company itself died of DARPA dependence and
management [S, same].

**Cell / PS3.** IBM kept a conventional PowerPC core "to provide a conventional entry point for
programmers" [P; Kahle et al., IBM J. R&D 49(4/5), 2005]. Gabe Newell called learning the SPEs
worthless: "You're not going to gain anything except a hatred of the architecture they've
created." [S; CVG via Wayback]. Mike Acton of Insomniac took the opposite line in his GDC 2008
slides: "The SPU is not a magical beast only tamed by wizards. It's just a CPU." He added
"Everything is local. Think streams of data." and "never, ever try to use a dynamic memory
allocator. Malloc for dedicated 256K would be ridiculous." [P; original .ppt via archive.org].
His recipe was data-oriented design. Lay out the destination data first and work backwards,
batch synchronisation per system rather than per object, use DMA lists, double- or triple-buffer,
and lay out memory offline. Late PS3 titles showed it paid off [F for the specific studios].

**Raw → StreamIt, and TRIPS.** Raw's ISA "exposes these on-chip networks, requiring the
programmer or compiler to directly program the wiring resources … much like the routing in a
full-custom … ASIC" [P; Taylor et al., IEEE Micro 2002]. Its authors' retrospective says the
ILP-from-sequential-code bet did not pay, so they "started developing a language, StreamIt, that
could be used to express streaming computations at a higher level, and paradoxically, make the
task of automatic parallelization even easier" [P]. The TRIPS evaluation is the most candid
self-assessment in the set. On SPEC it reached "60% of the performance of a Core 2", and "this
level of performance does not support the hypothesis that EDGE processors could outperform
leading industrial designs". Meanwhile hand-optimised kernels averaged a 3× cycle-count speedup
[P; Gebhart et al., ASPLOS 2009].

**Ambric vs picoChip vs MathStar.** Three spatial arrays of the same era that met different
fates. Ambric's Kahn-process-network model (sequential objects joined by self-synchronising,
back-pressured FIFOs) was praised as easy to program, and the company still died in the 2008
credit crunch [S; Microprocessor Report 2006]. That MPR article also named the failure mode in
advance: "Mastering the interaction between software and hardware is usually the biggest
challenge for any extreme microprocessor architecture." picoChip succeeded with 250+ tiny VLIW
cores whose communication was fixed at compile time. Its tools were "deterministic: simulation of
code is cycle-accurate to hardware execution", and it targeted a narrow, naturally static domain,
femtocell baseband [S]. MathStar's 10-K shows a company that never found customers: revenue of
"$134,000, $53,000 and $588,000" for 2005–07 [P; SEC 10-K FY2007].

**Tera MTA.** It hid latency with 128 hardware streams per processor and "zero switching
overhead" [P; Tera 10-K FY1997], and it put a full/empty bit on every memory word so that
producer–consumer synchronisation happens in memory [P; DTIC ADA324541, transcribed from a scan].
The earlier Horizon design had the compiler stamp every operation with a lookahead count *H*
("the next *H* instructions are independent"), so the hardware needed a counter instead of a
scoreboard [P; cited in Rau & Fisher 1993]. Tera's own risk factors blame GaAs yields, not
programmability.

**Larrabee and the Mill.** Both are reminders that an unusual model can be made to compile. Tom
Forsyth on Larrabee: "we failed mainly for reasons of time and politics", with "over 300 titles
running perfectly" on the software renderer [P; Forsyth, "Why didn't Larrabee fail?", 2016]. The
Mill's team reports a working LLVM toolchain, and Godard blames funding: "Mill is not stalled,
but is nowhere where we hoped and intended it to be" [P; Mill forum]. One structural cost is
visible, though. A simulator for an exposed, phase-separated pipeline is hard to build, because
it must model instructions in flight across branches [P; Godard, forum 2023].

### Machines whose memory ran on a clock: drums and delay lines

This is the part closest to our problem. On a drum or delay-line machine a word could be read
only when it passed the head. The programmer placed each instruction and operand so it arrived
just as it was needed ("optimum" or "minimum-latency" coding).

| machine | timing constraint | what programmers did | tool |
|---|---|---|---|
| LGP-30 (1957) | drum at ~3700 rpm, "once every 17 milliseconds"; 3 recirculating registers at "about .26 milliseconds" [P; *LGP-30 Programming Manual*, Apr 1957] | placed code so the next word arrived under the head; used the drum's rotation as a delay for the Flexowriter | hand placement |
| IBM 650 (1954) | each instruction names its successor ("one-plus-one"); a bad placement costs up to a revolution (Knuth: "a 49-word-time delay") [P] | SOAP chose drum locations automatically | **SOAP**, SOAP II/III, SuperSoap, HAND SOAP |
| RPC-4000 | drum, next-address field; track 127 holds 8 words repeated 8× per revolution [S; e-basteln.de reconstruction] | Mel hand-placed code | the "optimizing assembler", which Mel beat [F] |
| Bendix G-15 | drum with long lines and short fast lines (figures not verified) [S] | hot variables on fast lines | POGO (manual not fetched) [S] |
| Pilot ACE / DEUCE, UNIVAC I | mercury delay lines; Turing's designs relied on optimum coding [S, not fetched] | minimum-latency coding | — |
| EDSAC | mercury delay lines; Wilkes reportedly did *not* ask for optimum coding [F, unverified] | ordinary coding | Initial Orders |

Knuth's account is the best primary source [P; "The IBM 650: An Appreciation from the Field",
IEEE Annals 8(1), 1986]:
- "The name SOAP stood for Symbolic Optimal Assembly Program, and optimal meant that the machine
  would choose drum locations so that at least one reference to that location would involve no
  delay."
- His SuperSoap (1959) got "a factor of roughly 3:1 in running time over Soap 3" from better
  latency scheduling alone, on the same hardware.
- He wrote HAND SOAP (1958) so that he could hand-place hot code without losing symbolic assembly.
- For fun he built SHOAP, the "Symbolic Horribly Optimizing Assembly Program", which ran SOAP's
  algorithm in reverse so that one reference to each location hit a 49-word-time delay. It took
  seven extra cards.
- He formalised the problem as "Minimizing drum latency time", J. ACM 8 (1961).

Ed Nather's "Story of Mel" (Usenet, 1983) is folklore, but its technical claims hold against the
RPC-4000's documentation [F, corroborated by an S reconstruction]. Mel "wrote the innermost parts
of his program loops first, so they would get first choice of the optimum address locations on the
drum". He never wrote delay loops, and instead placed each instruction just *past* the head.
And: "Mel called the maximum time-delay locations the 'most pessimum'."

**The crucial difference from us** [inference]: on a drum, a word placed badly is merely *late*,
because it comes round again. A gain-cell 1 read too late is *gone*: it reads as 0, which is a
silent wrong answer, not a stall. So drum-era tools optimised speed, and ours must first
guarantee correctness. The timescales match remarkably well, though. An LGP-30 revolution was
about 65 add-times (17 ms / 0.26 ms). A worst-case thin-oxide row (≥1.2 µs at ff/85 °C) lasts 60
cycles at 50 MHz. The typical thin-oxide row (120 µs at tt/27 °C) lasts 6,000 cycles, and a
thick-oxide row (≥3 ms) 150,000. Mel's world is our worst-case corner.

Some later memories also forgot, all [S, not fetched]:
- Williams tubes had to re-read and rewrite every spot every few milliseconds.
- The Intel 1103 (1970) needed refresh every ~2 ms, but a controller did it, invisibly to the
  programmer.
- CCD memory shifted charge past a sense point.

**Every one of them ended with refresh hidden in hardware; no living programming culture has had
to see this since the 1960s** [inference]. Our chip reopens it on purpose.

---

## Part 2: the Forth chip lineage

### Summary table

| chip (year) | word | instructions per word | stacks / memory | clock | speed, power, size | fate |
|---|---|---|---|---|---|---|
| Novix NC4016 (1985) | 16 | one 16-bit instruction, but *unencoded* fields fuse several Forth primitives, and a return bit rides free on ALU ops [P; Koopman §4.4] | 256-deep data and return stacks *off chip*, on their own buses | 8 MHz max | < 4000 gates, 3 µm gate array [P] | licensed to Harris |
| Harris RTX 2000 / 2010 (1988) | 16 | same five formats, retuned | 256-deep stacks on chip, 16×16 multiplier [P; Koopman §4.5] | 10 MHz | 2 µm standard cell [P] | RTX2010 flew as Philae's two 8 MHz CDMS processors, chosen as "the lowest power budget processor available that is radiation hardened" [S; CPU Shack 2014] |
| Sh-Boom / PSC1000 / IGNITE (1985, then 1990s) | 32 | up to 4 instructions per 32-bit "instruction group"; "micro-loops" re-execute a group without fetching [P; PSC1000 manual] | 18-deep operand stack, 16-deep return stack, 52 registers | on-chip PLL runs the core 2–4× the bus [P] | — | chips failed; the patents earned $230,161,956 in licences by May 2008 [P; Patriot 10-K] |
| MuP21 (1994) | 20-bit memory, 21-bit internal (the extra bit is carry) | 4 × 5-bit; 24 of 32 opcodes used; no subtract, no OR, no SWAP [P; Ting & Moore 1995] | on chip; DRAM main memory | 10 ns per instruction | 100 MIPS peak, ~80 sustained [P]; 1.2 µm; ~7000 transistors [S]; video coprocessor makes NTSC in software; $25 [P] | small hobby market |
| F21 (1998) | 21 / 20 as MuP21 | 4 × 5-bit; 27 opcodes; jump field size depends on slot [P] | data stack 18, return stack 17 | self-timed: "All F21 instructions execute in 2ns" (500 MIPS internal, 111 from DRAM) [P] | 0.8 µm; ~15,000 transistors [S]; ~50 mW [P] | prototypes; the thermal bug below |
| i21 (1996) | 21 | as F21 | | | set-top box peripherals [S] | iTV Corp. |
| c18 core (2001) | 18 | 4 slots of 5+5+5+3 bits; jump address "either 10, 8 or 3 bits depending on slot" [P; Moore, inst.htm] | — | async | — | became the SEAforth and F18A cores |
| IntellaSys SEAforth-24A/B (2006) | 18 | as c18 | 64+64 words (24A) or 512+512 (24B) RAM+ROM per core [P] | async | "one billion instructions per second" per core, 150 mW typical [P, press release; never matched by a measured datasheet] | TPL laid off the team in Jan 2009 [P; Moore] |
| SEAforth-40 / S40 (2008) | 18 | as c18 | 40 cores × 128 words [P; Moore] | async | "700 Mips" each [P] | "the status and future of S40 chips is unclear" [P; Moore] |
| **GreenArrays GA144** (2010–) | 18 | 4 slots, 5+5+5+3 bits; slot 3 takes only the 8 opcodes whose low 2 bits are 0 (details below) [P; DB001] | **64 words RAM + 64 ROM per node**, 10-deep data stack, 9-deep return stack; 144 nodes, 9216 words each of RAM and ROM in total [P] | async, no clock | 1.4 ns typical per opcode (≈ 700 MIPS/node); 6.8 mW per node running, 90 nW suspended; 972 mW for all nodes [P; DB002]; ~7 pJ per ALU op [P; PB001]; 180 nm, 88-pin QFN | EVB002 at $1295; "several hundred chips" shipped by 2012 [P] |

### What the GA144 actually is (verified against GreenArrays' own PDFs)

- **Encoding.** An 18-bit word holds up to four opcodes in bits 17–13, 12–8, 7–3 and 2–0.
  Opcodes are 5 bits. The 3-bit slot 3 holds the top three bits of an opcode, so only opcodes
  that are multiples of 4 fit there: `;` 00, `unext` 04, `@p` 08, `!p` 0C, `+*` 10, `+` 14,
  `dup` 18 and `.` (nop) 1C. I read this from the shading in DB001's Figure 3, rendered from the
  PDF. The text says only "The shaded opcodes may be used in slot 3". The choice is clever: it
  lets a word end on a return, a micro-loop, a literal fetch, an add or a nop.
- **Jumps.** A jump uses the rest of the word as its address, 10, 8 or 3 bits depending on its
  slot. Code is XORed with `x15555` before storing, the same value the `io` register resets to.
  A node can run `unext` loops inside a single instruction word without fetching at all.
- **Ports.** They are blocking rendezvous with no buffers: "the operating node suspends, waking
  up when the other node connected to that port is performing the complementary operation"
  [P; DB001 §3.3]. Reading several ports at once waits for whichever answers first.
  - Most unusual of all: "An F18 may execute instruction streams directly from a comm port. When
    the F18 fetches an instruction word from a comm port, P is not incremented". So a neighbour
    can push a program straight into a node.
- **No clock.** "When a node is suspended the power used by its computer is nil, on the order of
  100 nanowatts" [P; DB001 §3.2]. A memory access takes ~5 ns against 1.4 ns for an ALU op,
  which is why four opcodes per fetched word matter.

### Programming experience

- **Chlorophyll** (Phothilimthana et al., PLDI 2014) [P; https://mangpo.net/papers/chlorophyll-pldi14.pdf]
  is the best evidence.
  - The obstacles: "To communicate with distant cores, the programmer must intersperse
    communication code with the computation code of a core, carefully avoiding deadlocks and
    race conditions", in "fewer than 100 18-bit words of storage per core". The GA144's MD5
    needs 10 cores.
  - "A graduate student spent one summer … He managed to learn arrayForth … However, he was able
    to implement only 2 benchmarks: FIR and a simple pedometer application."
  - Their synthesising compiler still produced code "46% slower, 44% less energy-efficient, and
    47% longer than the experts'" on single-core kernels. On MD5 it was "65% slower, 70% less
    energy-efficient and uses 2.2x more cores".
  - With a sketch as a hint, the synthesiser beat the experts' general division 6×.
  - The paper also notes that the GA144 "shares many characteristics with systolic arrays".
- **Users.** Hobbyists found the chip daunting but charming.
  - Documentation is scattered and out of date [S; bitlog.it 2014].
  - The IDE has an "archaic feel". The chip "doesn't find quite as much use as it might if nodes
    had slightly more memory and could be programmed in, say, C" [S; Andrew Back, DesignSpark].
- **Moore on his own chip.** On his own language colorForth he admitted "John and Bill have
  gotten eForth running on the GA144. This is the first high-level language to be implemented,
  beating out colorForth, which I have neglected." [P; Moore's blog, Jan 2012].
- **Jeff Fox, on learning Moore's Machine Forth**: "It took me [a] year[s] to begin to appreciate
  the page of Machine Forth that Chuck had written." [P; ultratechnology.com/mfp21.htm].
- **Real deployments.** They exist, all driven by GreenArrays' app notes [P]:
  - a 1080p LED-sign design for Sunrise Systems with about one GA144 per module, ~2000 per sign
    (AN020);
  - Charley Shattuck's 10-node MD5 (AN001);
  - a coin-cell SensorTag demo at an average of 363 µW (AN012);
  - a software 10BASE-T NIC (AN007).
- **Why it did not catch on** [S + inference]: 64 words per node, no C, a Windows-only
  colorForth toolchain, a one-company supplier, and a $1295 evaluation board. There is no sign
  that the asynchronous design or the energy per operation was the problem. Those were what
  people admired.

### Why these sizes, and Moore's philosophy

**Word sizes.** The 20-bit MuP21 word came from the package: "MuP21 is a 20-bit microprocessor,
constrained by the 40-pin DIP package … There would not be enough I/O pins to support a
processor with wider data and address buses", and "four instructions can be packed in each
20-bit word … This is a natural instruction pipeline" [P; Ting & Moore]. Moore's own sources call
it both 20-bit and "21-bit". The 21st bit is an internal carry and address bit. For 18 bits I
found no statement from Moore of *why*. The arithmetic 5+5+5+3 and the 9-bit multiples common in
SRAM make it natural [inference, unverified].

**In his own words** [P; 1998 Fireside Chat, https://www.ultratechnology.com/fsc98.htm]:
- "the world does not want another microprocessor … Don't design your own microprocessor. But we
  have a shot at it because we are very fast, we are very small, we are very low power and we are
  very cheap. If you are not all of those things you haven't a prayer."
- "I do not have a subtract … If you are doing comparisons you use exclusive or."
- On leaving decisions to the compiler: "decisions that I can make at, we don't have a name for
  it, programming time are cheaper than decisions that are made at compile time which are cheaper
  than decisions made at runtime."
- Fox, paraphrasing: "Where other people are thinking megatransistors Chuck is thinking
  kilotransistors" [P; cm-misc.html].

**Two cautionary stories from the same sources:**
1. **Heat.** On F21, four instructions packed in one word failed where four separate words worked:
   "after four of these steps you are twenty degrees above ambient". Twelve of sixteen thousand
   transistors had to be enlarged [P; Fireside Chat 1998]. A 2000 status page recommended three
   nops per word until the fix landed [P].
2. **Process corners.** An LG-fabbed i21 showed ~50% hot/cold differences in its IV curves, which
   explained chips that "would work at three volts or four volts but not at five volts" [P].

Both stories are timing that depends on temperature and corner, and unclocked designs have no
margin set by a clock period to absorb it. That is our gain-cell problem in another costume
[inference].

---

## Part 3: lessons for us

### Which failure modes apply

- **Mostly not: economics.** Most machines above died of the market: killer micros, DARPA, the
  2008 crash, the MPP collapse. A Tiny Tapeout entry has no market to lose, so the classic
  killer does not apply. What remains is whether *we*, and a few demo authors, can write code
  that uses the chip.
- **Yes: silent value loss** (CM-2, the i860 "as a scalar machine"). The crazy part sits idle
  because nobody can target it. For us that would be a systolic array or thin-oxide rows that the
  tools use only conservatively.
- **Yes, and worse than history: correctness, not speed.** Drum programmers who got placement
  wrong lost time. We lose data, silently, and the loss depends on temperature and corner. The
  thin-oxide lifetime varies 100-fold between tt/27 °C and ff/85 °C (`gain-cell-compiler.md`),
  just as Moore's chips misbehaved only at some voltages.
- **Yes: hand code beats the compiler 2–3×.** This held for GA144 against Chlorophyll, SOAP
  against Knuth and Mel, and TRIPS kernels against the TRIPS compiler. A first compiler will lose
  to hand scheduling. That is acceptable if it is *safe*.
- **Yes: exposed-pipeline tooling cost.** The Mill had trouble even building a simulator for
  in-flight state. Our array plus expiring rows has the same shape.

### What worked historically

| mitigation | who | fits us? |
|---|---|---|
| an automatic scheduler that guarantees no worst case, not optimality | SOAP ("at least one reference … no delay") | yes: guarantee no read past its deadline; let humans optimise |
| a hand-placement escape hatch inside the symbolic tool | HAND SOAP | yes |
| a deterministic, cycle-exact simulator identical to silicon | picoChip, S21 for MuP21/F21, GA softsim | essential |
| an enumerable, lintable hazard list | i860 manual | yes: expiry rules as a checker |
| cheap hardware checking of compiler guesses | Itanium NaT/ALAT, Tera full/empty, Horizon's lookahead count | yes: see below |
| a narrow stream language instead of general C | Raw → StreamIt, StreamC/KernelC, Ambric | yes: video pipelines are streams |
| app notes and idioms as the API; a killer demo | GreenArrays app notes, Acton's GDC talk, late-PS3 games | yes: demoscene |
| a conventional core beside the crazy part | Cell's PPE, Tilera | yes: our small CPU |
| publish the technique, not only the chip | Multiflow → IA-64, LRBni → AVX-512 | yes |

### Recommendations

1. **Make correctness a checker, not a hope.** The compiler emits each value's interval and each
   row's deadline. A separate verifier re-derives both from the emitted schedule and fails the
   build on any read past `t_write + L(r, T_max)`. This is the i860 lesson (enumerable rules) and
   the SOAP lesson (guarantee the bound, not the optimum).
2. **Detect late reads in hardware cheaply.** `gain-cell-compiler.md` already proposes a Berger
   check. Only 1s decay, so decay is a one-directional error, which a Berger code detects in
   full. `../prototypes/systolic-storage/README.md` already costs the columns. History supports
   keeping them: they are our Tera full/empty bit and Itanium NaT bit. A wrong "still alive"
   guess by the compiler becomes a flag instead of a silent wrong pixel. **Keep them in the
   tapeout even though they cost area.** Also expose the flag to software, so the demo authors
   can see how close to the edge they are running.
3. **Borrow modulo scheduling wholesale.** Rau's machinery maps directly onto our problem:
   - II is the search for the tightest repetition rate;
   - vector lifetimes are value intervals;
   - rotating registers are row rotation;
   - modulo variable expansion is the fallback when a lifetime is too long.

   The constraint "interval ≤ L(r, T)" is a register-pressure constraint with deadlines. Start
   the allocator from Cydra 5's published approach, not a blank page.
4. **Build a "fast line" tier, as every drum machine did.** The LGP-30's recirculating registers,
   the RPC-4000's track 127 and the G-15's fast lines were a few words of storage with no timing
   constraint, reserved for loop variables. Ours is the per-PE latch register file (46 µm²/bit).
   Give the compiler an explicit budget for it, and make "inner loop gets first pick", Mel's
   rule, the allocation order.
5. **Ship a SHOAP.** Build a deliberately pessimising scheduler that places every value as close
   to expiry as the rules allow, and a corner mode that evaluates schedules at ff/85 °C lifetimes.
   Run both in the simulator as a test oracle. A schedule that survives the most pessimum
   placement at the worst corner is trustworthy, and the pessimiser costs little, as SHOAP cost
   seven cards.
6. **Keep a safe slow mode.** Offer a mode that runs any program correctly: everything on
   thick-oxide rows or latches, with refresh inserted everywhere. This is the i860's scalar mode
   and Cell's PPE. The crazy fast path should be an optimisation over a correct baseline, never
   the only way to run.
7. **Express programs as streams, place them later.** Write kernels as Kahn/occam-style process
   networks (a video line flows through; values have lifetimes by construction). Keep placement
   onto PEs and rows as a separate pass, like `PLACED PAR`. Raw's authors found the DSL made
   scheduling *easier*, and our workload (PAL video racing the beam) is already a stream.
8. **Invest in the simulator before the compiler.** It must be deterministic and cycle-exact, and
   it must model decay per row and per corner. Every success above (picoChip, S21, softsim,
   Acton's profiling) had one. The Mill shows it is harder than it looks when state is in flight.
9. **Treat expiry as a feature too.** Mel used rotation as a free delay and never wrote delay
   loops. A value that is *meant* to vanish (a timeout, a self-clearing flag, a per-frame scratch
   that needs no clearing) costs nothing on our memory. Name that idiom in the tools.
10. **Borrow from the F18A where it is cheap:**
    - 18-bit words with 5+5+5+3 slots, the short slot holding return, micro-loop, literal, add or
      nop;
    - `unext`-style loops inside one fetched word;
    - blocking neighbour ports with no handshake code;
    - executing directly from a port, which lets the CPU stream code into a PE and also lets a
      neighbour re-inject code that has decayed.

    All of this suits a CPU with a narrow instruction fetch. Skip what hurt adoption: a
    colorForth-only toolchain and 64 words of code per node.

### Things I could not verify

- The reasons for Cydrome's and Tabula's shutdowns.
- EDSAC's stated rejection of optimum coding; the Pilot ACE, UNIVAC I and G-15 timing figures
  (their manuals were image-only scans).
- The Intel 1103 refresh period.
- The RTX2010's rad-hard process details.
- Why Moore chose 18 bits.
- Whether an "X18" name exists apart from c18.
- The SEAforth "1 GIPS per core" claim against measured silicon.
- The GreenArrays–TPL settlement terms beyond GreenArrays' own summary.
- Whether any WHTS-1 home-theatre product shipped.
- MasPar's own programming-model papers (paywalled).
- A first-person Olofsson account of Epiphany programming difficulty.
- Microsoft's E2 EDGE follow-up to TRIPS.

The per-group `findings.md` files list the rest.
