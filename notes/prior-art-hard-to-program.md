# Prior art: machines that were hard to program, and the Forth chips (note, 2026-09-25)

Our chip deliberately trades ease of programming for capability. It pairs a small CPU with a
systolic array and gain-cell memory whose stored 1s leak away (`gain-cell-compiler.md`,
`../prototypes/gain-cell/`, `../prototypes/systolic-storage/`), and it expects demoscene-level
programming. This note collects what happened to earlier machines that made the same trade. Part
1 covers designs that failed or struggled and a section on game consoles, part 2 Chuck Moore's
Forth chips, and part 3 the lessons for us.

The goal is inspiration, not a verified history, so sources are mixed. Each claim carries a label.
- **[P]** primary: the designer's or vendor's own document, a paper, a manual, an SEC filing.
- **[S]** secondary: a well-sourced retrospective, reputable press, or a named user's blog.
- **[F]** folklore: a forum post, an anecdote, or a claim repeated widely without a source found.
- **[inference]** my own reasoning, not a sourced claim.

The sources for Part 1 and Part 2 were downloaded to `/var/tmp/hard-to-program/{A,B,C,D,E1,E2}/`,
each directory with a `findings.md` that has fuller quotes. The load-bearing quotes and numbers
there were grep-checked against those saved files. The main exception is the Tera DTIC report, a
fax scan without a text layer, whose quotes were transcribed by eye. The game-console section was
added afterwards, in a separate session whose web-search budget was exhausted before it could
search; its sourcing (Wikipedia pages fetched directly, plus clearly labelled folklore) is
recorded in `/var/tmp/hard-to-program-2/sources-log.md`, and it is held to the same per-claim
labels but not to the same grep-checking discipline — treat [S] claims in that section as
"Wikipedia attributes this to a named source" rather than "verified against the primary source
itself".

---

## Part 1: crazy designs that failed or struggled

### The honest headline

**"Too hard to program" was rarely the *whole* story, but it was rarely *innocent* either.**
Most of these machines died of money, timing or a commodity curve they could not ride — and
programming difficulty is exactly the kind of thing that turns into a money problem and a timing
problem once a business has to ship on a schedule. A post-mortem records the balance sheet, not
the mechanism underneath it, so "died of economics" and "difficulty caused the economics to fail"
are not competing explanations; the second is usually invisible inside the first. Where programming
difficulty did bite, it usually showed as a tax rather than a death sentence on its own: the
customer quietly used a fraction of the machine, or only a few studios mastered it, or software
arrived late and thin. The cleanest cases where the programming model was *directly and admittedly*
the problem — the sources say so, not just an inference — are Itanium, the i860, Raw's
general-purpose ambitions and TRIPS. In each of those the *compiler* could not do what the
hardware assumed. Everywhere else, the honest reading is indirect: see the causal chain below and
the revised table column.

**The causal chain, where it plausibly applies:** hard hardware → few programmers reach fluency
in the time available → software ships late, thin, or uses only part of the machine → buyers,
reviewers and other developers compare that software (not the silicon) to a rival's → a sales,
funding or timing verdict follows, and the verdict is what the post-mortem records. Any failed
design in the table below can be read for whether this chain plausibly ran, even where the
sources report only its last link. This is why the table's causation column now distinguishes
**direct** (a primary source blames the programming model itself), **indirect** (difficulty
plausibly fed a market failure through late software, a thin developer base, or porting cost, but
did not alone determine it), and **no** (the sources point elsewhere and difficulty is not a
plausible contributor) [inference throughout this paragraph and the column below, since none of
the cited sources quantify the chain directly — they report the end state, and the chain
connecting it to difficulty is my reconstruction, not theirs]. The game-console section further
down is a cleaner test of the same chain, because a console's market is mostly fixed in advance,
which removes some of the confounding a general-purpose machine's market has.

### Summary table

| machine | what was crazy | what happened | direct or indirect cause? | what made it work, if anything |
|---|---|---|---|---|
| Intel iAPX 432 (1981) | hardware objects and capabilities, hardware GC, 5 associative caches | slow; abandoned | no, not even indirectly: the object model itself was slow ("1/4 to 1×" contemporaries even if redone perfectly), so better software could not have saved it [P] | "composites" to batch small objects [P] |
| Intel i860 (1989) | exposed FP pipelines, no interlocks, dual-instruction mode with 9 rules | shipped in 2 generations; niche | direct: Intel itself said ordinary compilers could use it only "as a scalar machine" [P], so most software never reached the advertised speed | hand-scheduled assembly kernels [P, manual examples] |
| Itanium / EPIC (2001) | bundles, predication, compiler speculation | niche; HP took 95% of shipments by 2008; dead 2021 | direct + indirect: Knuth said the compilers were "basically impossible to write" [P] (direct), which left it with nothing to answer AMD's binary-compatible x86-64 and years of delay with [S] (indirect: the software gap compounded a market threat) | Intel's icc; hand-tuned enterprise code [F] |
| Multiflow TRACE (1987) | VLIW, 7–28 ops/instr, trace scheduling | ~140 sold; folded 1990 [P, memoir] | no: the compiler worked; "killer micros" and business ended it [P, memoir] | the compiler worked, was licensed widely, and fed into IA-64 [S] |
| Cydrome Cydra 5 (~1987) | rotating registers, predication, modulo scheduling | a handful built; folded ~1988 [F] | not shown either way; the minisupercomputer market collapsed under it before its programming model was tested at scale [S] | its ideas became IA-64's software pipelining [S] |
| Transputer / occam (1985) | CSP in silicon, links, no shared memory, `PLACED PAR` | sold well in niches; T9000 late; Inmos sold 1989 | indirect at most: occam's discipline kept the customer base to programmers willing to learn CSP, but the T9000's delay and Inmos's business troubles did the visible damage [S] | the occam discipline itself |
| Thinking Machines CM-1/2 (1985–) | 64K 1-bit PEs, *Lisp, hypercube | 7 CM-1 sold, DARPA-subsidised; Chapter 11 in 1994 [S] | indirect: users "ignor[ed] the 64,000 single-bit processors" [S] and ran ordinary code on the FPUs instead, so the machine's distinguishing capability went largely unsold even to people who had bought it; the company itself died of DARPA dependence and management [S] | CM-2's floating-point units |
| MasPar MP-1/2 (1990) | 16K-PE SIMD, cheaper CM | ~200 systems; left hardware 1996 [S] | no: the MPP market collapsed under everyone in it [S] | — |
| Cell BE / PS3 (2006) | 8 SPEs, 256 KB local stores, explicit DMA, no cache [P] | sold in the hundreds of millions; Roadrunner hit 1 PF [S] | indirect, and survivable: directly blamed for extra engineering cost ("a total disaster", Newell) [S], which is real money, but the platform still shipped ~87M PS3 units [S below] — a rare case of the tax being paid rather than fatal | data-oriented design, double-buffered DMA, first-party heroes [P, Acton] |
| MIT Raw (2002) | on-chip networks routed by the compiler, cycle by cycle [P] | research chip; spun off Tilera | direct for sequential code: the ILP-from-sequential-code bet did not pay off, so the team pivoted to StreamIt [P] | a stream DSL; Tilera "de-crazed" to coherent SMP [S] |
| UT TRIPS (2006) | EDGE: 128-instruction dataflow blocks placed on a grid | silicon worked; 60% of a Core 2 on SPEC [P] | direct: the compiler could not form big blocks in control-heavy code, and the paper says so plainly [P] | hand-coded kernels ran 3× a Core 2 [P] |
| Stanford Imagine / SPI Storm-1 | StreamC + KernelC, no memory access inside kernels [P] | SPI shut 2009 [S] | indirect at best: mostly economics, and the model itself was admitted to be "somewhat specific to media processing" [P] — a market-fit problem more than a programmability one | the ideas went into GPUs [S] |
| Ambric Am2045 (2007) | 336 cores; Kahn process network with self-synchronising FIFOs | IP sold in the 2008 crash [S] | no, and this is the clean counter-example: praised as easy to program, died of the credit crunch regardless [S] | the programming model |
| MathStar FPOA | 400 coarse "silicon objects" | $588K revenue in 2007 against a $126.5M deficit; closed 2008 [P, 10-K] | indirect: mainly no customers found it worth the market risk, but the company's own 10-K admits tool immaturity as a contributing factor [P] | — |
| picoChip picoArray | ~250–300 tiny VLIW DSPs, network fixed at compile time | ~70% of HSPA femtocells (claimed); bought 2012, then by Intel 2013 [S] | a success | deterministic, cycle-accurate simulator; a narrow niche [S] |
| Tabula (2010s) | FPGA fabric reconfigured up to 8× per user clock | shut 2015 after $215M raised [S] | unknown [F] | — |
| Tera MTA (1997) | 128 hardware threads per CPU, full/empty bit on every word | first system late 1997; bought Cray 2000 [P] | no: GaAs yield [P, 10-K]; Tera sold it as *easier* to program, and nothing here contradicts that | the compiler auto-parallelised; futures [P] |
| Adapteva Epiphany / Parallella | mesh of tiny RISC cores, 1024 in Epiphany-V [P] | Kickstarter raised $898,921 but cost >$1.5M to deliver [P] | no: pricing and volume killed the delivery, before programmability was the question [P] | — |
| Intel Larrabee (2009) | x86 cores rendering graphics in software | GPU cancelled Dec 2009; became Xeon Phi [P] | no: "time and politics" (Forsyth) [P], and the software side actually worked (300+ titles) | ran 300+ Steam titles; its ISA became AVX-512 [P] |
| The Mill | belt instead of registers, 30-wide static issue | no silicon after 20+ years [P] | no: money and headcount, not the design [P] | LLVM toolchain; CoreMark per MHz "on par" in simulation [P] |

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

## Game consoles: hard hardware under a fixed target

The designs above mostly had to attract an unknown, general-purpose market: whoever might have
bought a Multiflow or a Cydra 5 also had to *choose* to write for it, and could walk away. A game
console removes that choice for one side of the market: a fixed body of studios, already
committed to shipping a title on this box by this date, for a fixed retail public. That is closer
to our own situation than anything above — a fixed target (the tapeout), a fixed occasion (one
competition's judges, plus us), and a small number of programmers who cannot simply go and write
for a different chip instead. Consoles are therefore a useful check on the causal chain proposed
above: with the demand side mostly fixed in advance, does hardware that is hard to program still
cost the platform, and through what mechanism?

Across the nine cases below, the answer is: yes, but almost always as a **multiplier on an
existing weakness**, never as an independent cause on its own. Difficulty shows up as late or
thin launch software, as third parties quietly using less of the machine than advertised, as a
real but rarely decisive porting tax, or as a narrowed developer base — each of which then
interacts with a platform's price, timing and first-party support. The cleanest test pair is
Sega's own Saturn and Dreamcast: one notoriously hard, one praised as easy, and both died. The
difficulty changed *how* each died, not *whether*.

**A caveat on all of this: the signal is small and the noise is large.** Nine platforms, and
each outcome was driven by much besides the computing hardware:
- **Media:** CDs against cartridges. The N64's cartridges were expensive and small, and that is
  why Square took Final Fantasy VII to the PlayStation.
- **Price, launch timing and reputation:** Sega's surprise early US launch of the Saturn, after
  the 32X had already cost it trust.
- **The games library** and exclusive third-party deals.
- **Other factors:** piracy (the Dreamcast), marketing, controllers, and the installed base.

The PS2 "counter-example" is itself confounded. It played DVDs and PS1 games, so developers had
a huge installed base to write for however hard the vector units were. Read the console record as
anecdotes consistent with the causal chain, not as evidence that isolates it [inference]. What
does carry over to us is the mechanism, not the statistics: difficulty costs time-to-fluency, and
anything that shortens that time (agents, simulators, libraries) removes most of the harm.

Sourcing note: this section is built mostly from Wikipedia's own citations (fetched directly, not
via search, since the session's web-search budget was exhausted before this note; see
`/var/tmp/hard-to-program-2/sources-log.md` for the exact pages and what came from each). Quotes
below carry [S] where Wikipedia attributes them to a named person or document, and [F] where a
claim is common retrospective folklore I could not trace to a fetched primary source this
session — the console record is exactly the kind of area where folklore is often right but rarely
citable, so both are kept, labelled.

### Summary table

| console | what was hard | time to mastery | effect on launch/software/sales | direct or indirect cause of the platform's fate? | what made the difference |
|---|---|---|---|---|---|
| Sega Saturn (1994) | dual SH-2s sharing one memory bus, so parallelism needed deliberate partitioning; VDP1 draws quadrilaterals, not triangles, so naïve 3D warped; a third, separate SCU DSP [S] | years: Yu Suzuki said "only 1 in 100 programmers are good enough" to get double-CPU speed [S] | many launch/mid-life 3D titles ran on a single CPU and looked worse than PlayStation's; late titles (Panzer Dragoon Saga, Radiant Silvergun, Dragon Force) are the folklore examples of the hardware finally used well [F] | indirect: it thinned and slowed third-party 3D output against PlayStation, compounding Sega's pricing, licensing terms and 1995 surprise-launch decision [S + inference] | none found in time on Saturn itself; PlayStation's triangle pipeline, $10 licence fee and 7–10-day CD reorder cycle (vs. cartridge's 10–12 weeks) won developers directly instead [S] |
| Atari Jaguar (1993) | Tom/Jerry co-processor pair with a memory-controller bug that broke inter-chip synchronisation [S] | never solved; the bug was structural, not a skill gap | developers routed logic through the slow 68000 against Atari's own advice, capping real performance below the advertised spec [S] | direct: the software many titles shipped could not use the chip's advertised path, because that path was broken, not merely hard [S] | partial workarounds in a few first-party titles; no general fix |
| Nintendo 64 (1996) | SGI's Reality Coprocessor microcode, plus a 4 KB texture cache that forced texture-stretching on small cartridges [S] | months to years: Factor 5 and Rare wrote custom microcode to beat SGI's stock code [S] | most third parties shipped on stock microcode with stretched textures; Factor 5/Rare titles (Rogue Squadron, GoldenEye, Banjo-Kazooie) are cited as using more of the hardware [S] | indirect: cartridge cost and a thin third-party library did more visible damage than the RCP alone, but the RCP raised the entry cost for any studio without SGI-calibre graphics staff [S + inference] | custom microcode, plus first-party/SGI support reaching only a handful of studios |
| Sega 32X (1994) | a dual-SH-2 add-on whose RAM-access contention meant most games used only one CPU; no texture mapping [S] | not enough runway to find out | most of roughly 40 games were rushed Genesis ports that never touched the extra hardware [S] | indirect, nearly moot: Sega's own timeline — rushed out, then abandoned within a year for Saturn — made difficulty almost irrelevant to the outcome [S] | none; the platform was orphaned by its own maker before mastery could matter |
| 3DO (1993) | not a hard instruction set, but hardware still changing under developers up to launch [S] | launch titles slipped to mid-1994 for lack of a stable target to test against [S] | a thin launch line-up (effectively one real game, *Crash 'N Burn*) [S] | indirect: the moving target delayed software, but the fatal wound was the licensing model itself — nobody profited from hardware, so manufacturer support collapsed [S] | — |
| PlayStation 2 (2000) | Emotion Engine's VU0/VU1 vector units plus a microcode-driven Graphics Synthesizer: an asymmetric, multi-language pipeline, not a normal CPU+GPU split [S] | roughly a console generation; many studios never touched VU1 microcode directly | despite the difficulty, PS2 became the best-selling console ever at ~155–160M units [S] | **the clean counter-example**: not a cause of anything, because the platform succeeded overwhelmingly regardless | Sony's installed base and backwards compatibility bought time; middleware absorbed VU complexity for most studios [inference] |
| PlayStation 3 (2006) | Cell's 8 SPEs, 256 KB local stores, explicit DMA, no cache, plus an RSX GPU added late after Sony's own graphics team found Cell-only rendering short of Xbox 360's [S] | widely reported as 1–2 years per studio; early multiplatform ports were "generally considered inferior" to Xbox 360 through 2006–2008, reaching parity or surpassing only later [S] | early multiplatform titles ran worse on PS3 than 360; late-generation first-party work (Naughty Dog's Uncharted/*The Last of Us* line) is the standard example of eventual SPU mastery, though I could not trace a primary source for it this session [F] | direct, but survivable: extra porting cost and worse early third-party performance are attributed specifically to the Cell, yet PS3 still sold ~87M units [S] | first-party tooling and studio time; SPU technique amortised once a studio had paid the cost once |
| Sega Dreamcast (1998) | almost nothing: PowerVR2 was well liked, and an optional Windows CE/DirectX path made PC ports nearly free [S] | fast; developers were productive quickly | a strong launch library by contemporary standards; the console still lost | **no — the control case.** Business timing killed it: Sony's PS2 pre-announcement, Sega's own financial state, a GD-ROM with less capacity than DVD, and an installed base too small to hold third parties, per Peter Moore's own account ("The PlayStation 2 effect that we were relying upon did not work for us") [S] | — (there was nothing to fix; ease of programming was never the constraint) |
| Atari 2600 (1977) and the C64/Amiga demoscene | 2600: no frame buffer, video generated live by racing the scanning beam [S]; C64/Amiga: fixed, idiosyncratic silicon with no upgrade path across a machine's whole commercial life | years, across a console's life and a whole subculture that outlived the hardware's market relevance | the *positive* tail: mastery kept extending what an unchanging box could do, long after launch (*Pitfall!*, *Yars' Revenge*; the demoscene's "bobs"-per-frame and scroller records) [S] | not applicable — no platform failure here; the difficulty became a creative genre in its own right | a target that never changed under the programmer, and (for the demoscene) no shipping deadline at all [inference] |

### What the console record adds to Part 1

**Fixing the market does not remove the tax, but it does cap the damage.** PS2 and Dreamcast
sit at the two ends: PS2 was hard and thrived because the studio base had no real alternative to
wait for (backwards compatibility, an existing DVD-drive cost advantage, and no rival with
comparable install base); Dreamcast was easy and still died because nothing about programming
difficulty was the actual constraint on its business. Saturn sits in the middle and is the most
informative case precisely because it is not extreme in either direction: hard *and* commercially
mediocre *and* not a total failure (9.26M units, real games, a devoted library) — a graded
outcome that a simple "hard hardware kills platforms" story does not predict, but that the causal
chain (hard hardware → thin/late third-party software → unfavourable comparison to a rival →
weaker sales, on top of Sega's own business mistakes) predicts correctly [inference].

**The Saturn/PS1 contrast is the sharpest natural experiment in this whole note.** Both launched
within months of each other, aimed at the same market, sold through the same retailers, at
similar prices. The Saturn's dual-CPU, quad-based pipeline needed real expertise before it beat a
PlayStation game built on a single CPU and triangles; Sony additionally undercut Sega on developer
economics directly (cheap dev kits, a $10 licence fee, days not weeks to reorder discs). Saturn's
9.26M units against PlayStation's 102.49M [S] is not proof that programming difficulty alone
produced an 11× gap — Sega's pricing, timing and licensing mistakes are real and independently
documented — but it is hard to read the gap as *uncorrelated* with which machine third parties
could ship good-looking games for fastest.

**A fixed target changes who pays the tax, not whether it exists.** In Part 1, a hard
general-purpose machine mostly taxed *itself* (fewer sales, because buyers had an easy
alternative). In a console generation, the hardware is chosen once by the platform holder and then
the tax is paid by third-party *studios*, repeatedly, per title — which is why the visible symptom
is "most games use less of the machine" (Saturn, N64, 32X) rather than "nobody bought the
machine". Our situation is closer to the studio's position than the platform holder's: we are the
one shipping a demo on fixed, already-chosen silicon, so the console record's lesson is about
*our* development cost, not about whether the chip finds a market.

**Time-to-mastery is consistently longer than a launch window and shorter than a platform's
life.** Saturn (years), N64 custom microcode (months to years), and PS3 SPUs (1–2 years per
studio, by the widely repeated but not this-session-verified account) all cluster in the same
band: too slow to save a launch, fast enough that a platform with enough runway (PS2, PS3, and
Saturn's own late-life titles) sees its best software only well after release. This matches
Part 1's Multiflow/Cydra 5 compiler timelines and the GA144's "a graduate student managed two
benchmarks in a summer" [P, Chlorophyll] far better than it matches an assumption that mastery is
either instant or never happens.

### The 8-bit baseline machines: built to be easy, mastered into insanity

Five machines make the point sharpest because they were not consoles chasing the crazy edge —
they were designed to be programmable by an ordinary assembly programmer of their era, sold in
the millions on that basis, and only *afterwards*, years into each machine's commercial life,
did a self-selected group of virtuosi find tricks nobody designed in. That gap — ordinary at
launch, extraordinary a decade later — is the cleanest evidence in this whole note that a fixed
target rewards patience, because none of what follows was needed to ship a single title.

- **Atari 2600 (1977).** Baseline: no frame buffer; the whole point of "racing the beam"
  (Part 1's drum-machine section) already applies here, but the tail goes further. `HMOVE`, the
  instruction that repositions sprites and the playfield, has an undocumented side effect: firing
  it mid-scanline "combs" extra colour clocks onto the left edge of the *next* line, visible as a
  ragged strip. Most launch-era games simply hid it behind a black border. Homebrew and late
  commercial developers instead learned to fire `HMOVE` at a controlled moment and use the comb
  deliberately, and to rewrite colour and position registers within single scanlines to fake more
  objects than the TIA has hardware for. None of this shows up in *Combat* or *Pong*; all of it
  shows up a decade later in the demoscene-era homebrew catalogue [F, extending *Racing the Beam*'s own
  account of the machine's later life].
- **Commodore 64 (1982).** Baseline: 8 hardware sprites, one character/bitmap mode, and a VIC-II
  chip that steals CPU cycles on every eighth raster line to refetch character data — a "bad
  line", an intentional but unglamorous hardware detail. The tail turned the bad line itself into
  raw material: **FLI** (Flexible Line Interpretation) retimes writes to the video/colour-RAM
  pointers on every single bad line to get far more colours per row than the mode nominally
  allows; **sprite multiplexing** repositions the 8 hardware sprites mid-frame, faster than the
  eye or the display resolves it, to show dozens of "sprites" from 8 pieces of hardware; **VSP**
  (Vertical Sprite Positioning) and **FLD** (Flexible Line Distance) abuse the sprite
  Y-expansion register to shift exactly when a bad line falls, letting FLI-like effects run down
  the *whole* screen instead of the usual restricted band; and "opening the borders" toggles the
  38/40-column or 24/25-row select registers at the precise raster line the hardware's border
  comparator fires, tricking the chip into never drawing a border that frame at all. Every one of
  these is a documented VIC-II side effect turned into a named, teachable technique [F, standard
  demoscene technical lore, e.g. as catalogued by the C64 scene's own technical wikis].
- **Nintendo Entertainment System / Famicom (1983).** Baseline: a fixed PPU, cartridge ROM mapped
  straight into address space, extended only by mapper chips for bank switching. The tail uses two
  hardware side effects as free interrupt sources for raster effects the PPU was never given a
  register for: the **MMC3 mapper's scanline counter**, which counts PPU-driven address-line
  toggles rather than time, fires an IRQ at a chosen scanline so a game can change scroll position
  or palette partway down the screen (split-screen status bars, parallax); and **sprite-0 hit**, a
  flag meant only to say "sprite 0 has just overlapped an opaque background pixel", gets polled
  or timed instead as a *raster position sensor* on carts whose mapper has no IRQ at all. A few
  games are reported to have (ab)used the DMC audio channel's IRQ purely for its precise timing,
  never for sound [F].
- **ZX Spectrum (1982).** Baseline: one 8×8 colour-attribute pair per character cell (the source
  of "colour clash"), and a ULA that generates video from the same RAM the CPU uses, delaying CPU
  accesses to that RAM in a fixed, hardware-determined pattern ("contended memory"). The tail
  rewrites the colour attribute on *every* raster line, timed against that fixed contention
  pattern rather than against any documented raster register, to fake smoothly multicoloured
  graphics the mode was never meant to have ("multicolour" effects); times `OUT` instructions to
  the border colour port to draw stripes or crude images in what is normally a plain border strip;
  and reads back the "floating bus" — what the ULA itself is about to display — as a free,
  hardware-synchronised clock with no raster-counter register to consult [F].
- **Commodore Amiga (1985).** The interesting counter-case. Its designers gave programmers a
  small coprocessor, the **Copper**, built for exactly the job the other four machines' tricks
  fake against a side channel: changing a hardware register synchronised to the video beam. Even
  with a *sanctioned* mechanism, demosceners still pushed well past its intended use — "copper
  bars" chain `WAIT`/`MOVE` pairs to rewrite the palette every raster line for smooth colour
  gradients, and other copper lists repoint bitplane addresses mid-frame to fake more resolution
  or more simultaneous colours than any single display mode supports [F].

**The lesson these five machines teach together, and it is the whole point of this section**
[inference]: every one of them shipped tens of millions of units on hardware an *ordinary*
assembly programmer of the day could use competently from day one. The insane tricks above —
a bad line turned into a feature, register writes timed to a single clock cycle, a floating bus
read as a clock, a copper list gymnastics routine — were found years into each machine's life,
by a self-selected few, and were never a precondition for a single title shipping. If any of
these five machines had *needed* FLI, sprite multiplexing, an HMOVE comb or a copper-bar routine
just to draw a title screen, none of them would have sold as they did. **That is the test our
chip fails on purpose.** We are deliberately building a machine whose *baseline* is what these
five treat as their demoscene tail: an ordinary program on our chip already requires the kind of
timing discipline that the 2600, C64, NES, Spectrum and Amiga only ever demanded from their most
obsessive virtuosi, decades after launch. That trade is viable in 2026 for one reason neither of those machines had: the demoscene
tail no longer needs demosceners. Tireless agents make exhaustive, superoptimising, cycle-exact
work routine rather than exceptional, and good simulators (cycle-exact models, verifiers,
visualisers) keep that work honest and make it legible. The narrowness of our audience (one
competition's judges, plus us) is not what makes it viable; if the bet is right, it holds for
any market, which is the more interesting claim (see below).

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
- **Confirmed by the console record: a fixed target changes who pays the difficulty tax, not
  whether it exists.** Saturn/PlayStation and PS3/Xbox 360 both show a real cost from difficulty
  even where the platform survived it (PS3, handsomely) or only partly failed from it (Saturn,
  9.26M units, not zero). For us, with no rival platform for a demo author to defect to, the same
  tax lands entirely on us — there is no competitor quietly picking up the games we didn't finish.

### One more difference from every case above: tireless agents instead of scarce experts

Every mitigation catalogued in this note so far was rate-limited by scarce human expert time.
Saturn and PS3 mastery took years because only a handful of programmers per studio ever reached
fluency, and a studio could spare only a few of them for it. Knuth's SuperSoap was one person's
project, not a search over the space of schedules. The GA144's own evaluation is explicit about
the same limit: a graduate student "spent one summer" on arrayForth and shipped two working
benchmarks, and a synthesising compiler with no human hint still lost to the experts by 44-70%
on single-core kernels [P, Chlorophyll, cited above]. In every case above, the bottleneck was
never insight in the abstract — it was calendar time against a small number of people able to
supply it.

We do not have that bottleneck in the same way [inference]. An agent can run exhaustive or
superoptimising search over schedules, hand-place every value the way Mel hand-placed code, run
a worst-case-corner pessimiser (recommendation 5) as a matter of routine rather than as a special
one-off project, and try many candidate schedules in parallel instead of the one a human has time
to write before a deadline. That plausibly shrinks three of the failure modes this note keeps
finding: **slow mastery** (an agent does not need a year of exposure before it is useful, and
does not forget what it learned between projects); **a small developer base** (the chip only
needs to be legible to whichever agents and humans are actually asked to program it, not to a
market of freelance experts who might or might not bother); and **porting cost** (the tax PS3 and
N64 both paid once per studio, an agent can in principle pay once and generalise from).

It does **not** remove the failure modes that are dangerous rather than merely slow. A
silent-wrong-value hazard — an expired row reading back as 0 — is exactly as silent to an agent
as it was to Mel or to Knuth's SOAP; nothing about "the agent tried harder" makes a schedule
self-report a violation, so recommendations 1 and 2 below (a verifier that re-derives intervals
and deadlines, and a hardware flag on a late read) matter *more*, not less, once the thing
proposing schedules is fast enough to generate many of them without a human reviewing each one by
hand. Agents also confabulate: a fluent, confident, wrong claim that a schedule is safe is a
known failure mode of the tool doing the work here, not a hypothetical risk borrowed from
elsewhere, so a cycle-exact simulator that agents cannot argue their way around and can only be
measured against (recommendation 8) is load-bearing in a way it would not need to be if a single
careful senior engineer were the only source of proposed schedules. And two constraints sit
entirely outside software, agent or human: the hardware still has to be physically buildable
within a Tiny Tapeout-scale budget, and the design still has to be *explained* — in the demo and
the write-up — to judges who will not run their own search over our schedules. That is the same
explainability job the simulator does for one schedule (recommendation 8), now asked of the whole
design [inference throughout this subsection].

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
8. **Invest in the simulator before the compiler — it is also what makes the magic explainable.**
   It must be deterministic and cycle-exact, and it must model decay per row and per corner. Every
   success above (picoChip, S21, softsim, Acton's profiling) had one. The Mill shows it is harder
   than it looks when state is in flight. A good simulator does a second job that is easy to
   undervalue: it is what turns a trick into something a sceptical outsider can verify rather than
   take on faith. The 8-bit demoscene tricks above only became legible to people who did not
   discover them personally once cycle-exact emulators and visualisers existed for each machine —
   VICE for the C64, Stella for the 2600, Mesen for the NES, visual6502's transistor-level
   simulation for the 6502 itself — all of which let a viewer step through *why* a bad-line
   exploit or a copper trick works, not just watch the result. Our judges are in the position of
   that viewer, not the position of whoever wrote the trick. A visualiser that shows row
   lifetimes, corner margins and near-expiry flags alongside the running program, the same way a
   VICE raster-time view lets someone see a bad line happen, is the difference between "trust us,
   it's correct" and a judge seeing the deadline the schedule is riding.
9. **Treat expiry as a feature too — hazards become idioms once they are named.** Mel used
   rotation as a free delay and never wrote delay loops. Demosceners did the same with quirks
   nobody designed in: the VIC-II's bad-line cycle-steal became FLI and sprite multiplexing; the
   2600's HMOVE comb and mid-scanline register writes became deliberate raster effects; the
   Spectrum's contended-memory floating bus became a free, hardware-synchronised clock. None of
   these started as features — each was a side effect of a real constraint, exactly like our
   decaying rows — and each ended up as something a competent programmer, not only its
   discoverer, could reach for on purpose once it had a name. Ours: a value that is *meant* to
   vanish (a timeout, a self-clearing flag, a per-frame scratch that needs no clearing) costs
   nothing on our memory, and a Berger-flagged near-expiry read is a free "how close to the edge
   am I running" signal, not only a bug detector. Name both idioms in the tools, the way FLI and
   sprite multiplexing now have names.
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
