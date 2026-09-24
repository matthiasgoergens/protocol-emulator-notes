# Prior art: comparison-coverage, input-to-state, and compound conditions in fuzzing

Context: hwfuzz instruments Hardcaml circuits by treating every mux select
and every comparison (eq/lt) as a coverage probe, with input-to-state
mutation (dictionary + byte-pattern replacement) on comparison operands. It
stalled on a USB device where a request is decoded only when two comparisons
hold simultaneously (`bmRequestType == 0x00 AND bRequest == 0x05`), and we
suspect comparator coverage saturates at reset (`setup[0] == 0x00` is
already true when `setup` is all-zero) before the moment it matters. This
surveys prior art on (a) input-to-state/value-profile mechanisms, (b)
compound conditions in fuzzing and search-based testing, and (c) hardware
fuzzers' coverage metrics. Claims below come from sources actually opened
and read (quoted/paraphrased), except where marked "not opened"/"secondary
only".

Written by a research subagent; four load-bearing claims were re-checked against the primary sources on 2026-09-24:
- libFuzzer's `HandleCmp` (current LLVM `compiler-rt/lib/fuzzer/FuzzerTracePC.cpp`);
- Angora's `&&` splitting (arXiv 1803.01307);
- McMinn's "breaks off early" passage on short-circuit conjunctions (mcminn2004.pdf);
- HyPFuzz's 1.524×10⁻⁵ and 2.323×10⁻¹⁰ figures (arXiv 2304.02485).

All four hold. The rest is as reported.

## 1. libFuzzer value profile

Read directly from `FuzzerTracePC.cpp`
(https://llvm.googlesource.com/libfuzzer/+/8c09d8efcdf61e9f92e08ee3ac3a8c1916722a35/FuzzerTracePC.cpp;
docs: https://llvm.org/docs/LibFuzzer.html). `TracePC::HandleCmp<T>(PC, Arg1,
Arg2)` computes:

```
ArgXor = Arg1 ^ Arg2
HammingDistance = popcount(ArgXor)
AbsoluteDistance = (Arg1==Arg2) ? 0 : clz(Arg1-Arg2) + 1
ValueProfileMap.AddValue(PC*128 + HammingDistance)
ValueProfileMap.AddValue(PC*128 + 64 + AbsoluteDistance)
```

Each executed `CMP` contributes two feature bits, keyed by PC mixed with (a)
bit-level Hamming distance and (b) a leading-zero-count-based magnitude
distance — a coarse "how close" signal, not just equal/not-equal.
`memcmp`/`strcmp` use common-prefix length plus the first differing byte's
Hamming distance as the index (progress through a byte string is itself a
feature, similar in spirit to Steelix, §3); `switch` lowers to synthetic
`HandleCmp` pairs per case. Small tables of recent operand pairs (`TORC4`/
`TORC8`) drive dictionary-style mutation — the same idea as CmpLog/RedQueen
below, but separate from the coverage feature. Each `CMP` gets its own
independent feature slot, so two ANDed comparisons show up as two
independently-rewarded features: reward is per-comparison, not per-path;
conjunctions are not addressed.

## 2. AFL++ laf-intel / CompareCoverage / CmpLog / RedQueen

**laf-intel / split-compares** (docs read:
https://github.com/AFLplusplus/AFLplusplus/blob/stable/instrumentation/README.laf-intel.md).
At compile time it rewrites `>=`/`<=` into chains of `>`/`==`, signed
comparisons into a sign-check plus unsigned comparison, and 64/32/16-bit
unsigned comparisons into chains of 8-bit comparisons (`transform-compares`
does the same for `strcmp`/`memcmp`/`strncmp`). Each resulting 8-bit compare
is its own edge in AFL's bitmap, turning an all-or-nothing 2³² search into
up to four sequential 2⁸ searches. QEMU-mode `compcov` does the same at
runtime, with levels 1 (immediate-only), 2 (all comparisons), 3 (plus
experimental floating-point) — search-snippet level, not source-verified.

**CmpLog/RedQueen**: full NDSS'19 paper read
(https://www.ndss-symposium.org/wp-content/uploads/2019/02/ndss2019_04A-2_Aschermann_paper.pdf).
Every compare-like instruction is hooked once per new input; both operands
are logged, and if one looks input-derived, a mutation `<pattern↦repl>` is
built. Encodings/transforms explicitly enumerated: Zero/Sign Extend(n)
(little-endian, plus "Reverse" for big-endian), C-String, Memory(n) for n∈
{4,5,…,32} (memcmp-style), ASCII (decimal digits); plus ±1 "variations" to
infer `<`/`<=` from an observed `==`. **Colourisation** replaces as many
*other* bytes as possible with random values without changing the path hash,
before applying a replacement — both raising the chance a match is real
(candidate positions drop by orders of magnitude) and substituting for taint
tracking, via a binary-search-like algorithm (their Algorithm 1).

**Compound conditions — addressed, but only for nested checksums, not
general conjunctions.** RedQueen's own example needs two comparisons at
once: a checksum *and* `input[16]=='R' && input[17]=='Q'`. Their fix
(§III.B, Algorithm 2): identify checksum-like comparisons; **patch** one at a
time to always evaluate true (`cmp al,al` via VM breakpoints) and validate;
if patches conflict (nested checksums), build a dependency graph and
**topologically sort** the patches so each is fixed without disturbing
earlier ones; re-run unpatched to confirm. This is **sequential
patch-and-validate**, not a joint objective over a conjunction, and needs
instruction-level output forcing with no obvious analogue for a black-box
packet mutator. Limitations listed instead concern no one-to-one
input↔state correspondence at all: compressed data, hash-map indexing,
base64. **No mention of hardware, per-cycle evaluation, or context-/
enable-gated comparisons.** AFL++'s CmpLog README (read directly) adds
nothing further on conjunctions.

## 3. Angora, Steelix, VUzzer, and compound conditions

**Angora** (Chen & Chen, IEEE S&P 2018; full paper read,
https://arxiv.org/pdf/1803.01307). Byte-level taint tracking
(DataFlowSanitizer-based) finds which input bytes flow into a predicate;
Angora treats it as scalar `f(x)` over just those bytes and does **gradient
descent**, numerically approximating the directional derivative by
re-running with each byte perturbed by ±δ, then `x ← x − ε∇f(x)`. Relational
operators reduce to canonical forms (their Table 2, same shape as Tracey's,
§4): `<`↦`f=a−b,f<0`; `==`↦`f=|a−b|,f==0`; etc. Shape/type inference groups
consecutive bytes into one correctly-sized/signed integer; input-length
exploration extends the input when a `read`-like call wanted more bytes.

**Compound conditions: addressed by static desugaring, not by the search.**
Quoting directly: *"If the predicate of a conditional statement contains
logical operators `&&` or `||`, Angora splits the statement into multiple
conditional statements. For example, it splits `if (a && b) { s } else { t
}` into `if (a) { if (b) {s} else {t} } else {t}`."* A two-comparison AND
becomes two separate, sequentially nested branches, each independently
gradient-descended and separately coverage-tracked — never a joint
`f_a(x)∧f_b(x)`. This works because software's short-circuit `&&`/`||`
already compiles to nested control flow, so hitting the inner comparison at
all is new coverage once the outer is satisfied — turning "solve two at once"
into "solve sequentially", exactly what hwfuzz's always-evaluated per-cycle
comparators do not give for free (§6 returns to this).

**Steelix** (Li et al., ESEC/FSE 2017; pages 1–5 read,
https://wcventure.github.io/FuzzingPaper/Paper/FSE17_Steelix.pdf) targets
comparison *progress*, not distance: for an n-byte compare, instrumentation
records how many bytes match from front/back, collapsing 2ⁿ states to `n+1`
"situations." A mutation that extends the matched-byte count is kept as an
"intermediate step" and neighbouring bytes get *local exhaustive mutation* —
reducing a wide magic-bytes search from 2^(8n) to n·2⁸. This targets a
**single** multi-byte comparison; the paper doesn't discuss several
independent magic checks needing to jointly hold.

**VUzzer** (Rawat et al., NDSS 2017; pages 1–6 read,
https://www.ndss-symposium.org/wp-content/uploads/2017/09/ndss2017_10-2_Rawat_paper.pdf)
combines data-flow features (taint back to input offsets, extract immediates
into a dictionary, infer comparison *order*) with control-flow features
(Markov-model reachability probability per basic block → weight `w_b=1/p_b`,
so hard-to-reach blocks score higher; fitness = weighted sum of executed
block frequencies). VUzzer **explicitly names "nested conditions"** as a
challenge distinct from magic bytes, fixed by reward-shaping (favour inputs
that get deeper), not a joint solve — a hand-built SBST *approach level*
(§4).

No paper found beyond these (and RedQueen's checksum patching) poses an
explicit reward function for a *conjunction* of independent comparisons;
T-Fuzz also patches/removes hard checks rather than solving them jointly,
and no Angora-derived paper was found revisiting the `&&` splitting.

## 4. Search-based software testing: branch distance and approach level

Tracey et al., "An Automated Framework for Structural Test-Data Generation"
(ASE 1998) — full paper read
(https://kar.kent.ac.uk/21595/1/An_Automated_Framework_for_Structural_Test-data_Generation.pdf).
Their Table 1, quoted directly, is the field's canonical branch-distance
function (K>0 a fixed penalty, keeping the function strictly positive when
false and exactly zero when true):

```
a==b: |a-b|==0 ? 0 : |a-b|+K       a!=b: |a-b|!=0 ? 0 : K
a<b:  a-b<0 ? 0 : (a-b)+K          a<=b: a-b<=0 ? 0 : (a-b)+K
a>b:  b-a<0 ? 0 : (b-a)+K          a>=b: b-a<=0 ? 0 : (b-a)+K
a∨b:  min(cost(a), cost(b))        a∧b:  cost(a) + cost(b)
```

**AND=sum, OR=min is settled, independently derived twice**: Tracey's own
table, and McMinn's survey (below) notes Gallagher & Narasimhan derived the
identical rule independently for Ada. It traces to Korel's "Automated
Software Test Data Generation" (IEEE TSE 1990) — not opened directly
(paywalled); McMinn's reproduction of Korel's table gives the same
per-operator distances, feeding an "alternating variable" local search and a
goal-oriented branch classification that is the direct ancestor of approach
level.

McMinn, "Search-Based Software Test Data Generation: A Survey" (*STVR*
14(2), 2004) — full open-access preprint read
(https://philmcminn.com/publications/mcminn2004.pdf). Canonical fitness
(attributed to Wegener et al.): `approach_level + normalise(branch_distance)`
— approach level counts unsatisfied control-dependent nodes between the
executed path and the target, branch distance supplies the local gradient at
the last divergence point. This additive form replaced Pargas et al.'s
control-only metric (flat between levels) and Tracey's own multiplicative
`(executed/dependent)×branch_distance` (spurious local optima).

**Short-circuit conjunctions are named explicitly as an open problem,
matching hwfuzz's exact case.** Quoting McMinn, on `if (a==b && b==c &&
c<0)`: "the evaluation of the overall predicate breaks off early if the end
result has already been determined. Therefore... the individual conditions
have to be attempted one after the other... A solution here might be to
apply a side-effect removal program transformation first. Alternatively,
variables' values could be saved into temporary variables inserted
immediately before the branching statement, and restored after [if] the
condition would not normally have been evaluated." The fix is
architectural — force every conjunct to evaluate every time, side-effect
safely — not a cleverer search. McMinn also documents the related **flag
problem** (`flag=(d==0); if(flag)` gives zero gradient either side of the
boundary), fixed by "chaining": retarget the search at the statement that
assigns the flag. EvoSuite (Fraser & Arcuri) is widely reported to implement
the same per-branch fitness in its whole-suite genetic search — not
independently verified this round, flagged secondary/inferred.

## 5. Targeted property-based testing

**PropEr/TARGET** (Löscher & Sagonas, ISSTA 2017; full paper read,
http://proper.softlab.ntua.gr/papers/issta2017.pdf). A property returns a
numeric utility value (UV) via `?MAXIMIZE`/`?MINIMIZE`. **Hill Climbing**
keeps the best of {current, one random neighbour} — no worse-move
acceptance, so it can stick at local optima (their example: 17,666 tests to
falsify a graph property vs 100,000+ unsuccessful under random PBT).
**Simulated Annealing** accepts a worse neighbour with probability
`exp(-(u_n-u_{n+1})/t_{n+1})` (Metropolis), `t` following a temperature
function (linear-decreasing, or "re-heating" to escape local optima).
Neighbourhood functions are ordinary generators parameterised by a distance
that shrinks with temperature.

**Hypothesis `target()`** (docs read,
https://hypothesis.readthedocs.io/en/latest/reference/api.html): *"the
initial implementation in Hypothesis uses hill-climbing search via a
mutating fuzzer, with some tactics inspired by simulated annealing to avoid
getting stuck and endlessly mutating a local maximum."* It maximises
whatever score is reported; an optional `label` "distinguish[es] between and
therefore separately optimise[s] distinct observations" — several scores
*independently*, never jointly; effect is "noticeable above
`max_examples=1000`". A closely related mechanism for multiple simultaneous
*shrink* targets (MacIver,
https://drmaciver.com/2016/07/fuzzing-through-multi-objective-shrinking/,
read directly) found that picking one label **uniformly at random** each
iteration beats always prioritising the best or worst label — evidence
against summing or ranking multiple objectives into one score. Both PropEr
and Hypothesis mirror SBST fitness (§4) with a user-supplied rather than
structural function, and neither has a primitive for a *conjunctive* target
(two things that must both be true at once) — only independent per-label
optimisation.

## 6. Hardware/RTL fuzzers

**RFUZZ** (Laeufer et al., ICCAD 2018; full paper read,
https://people.eecs.berkeley.edu/~ksen/papers/rfuzz.pdf). **Mux control
coverage**: every 2:1 mux select (wider muxes decomposed into 2:1 trees) is
a cover point, held in two 1-bit registers; *"For a mux control condition to
be fully covered, we require it evaluates to true as well as to false during
a single test."* Conjunctions: not discussed, each mux scored independently.
Reset: not discussed; "MetaReset" force-resets undriven registers purely for
simulation determinism.

**"Fuzzing Hardware Like Software"** (Trippel et al., USENIX Security 2022;
read, https://www.usenix.org/system/files/sec22-trippel.pdf) compiles HDL
via Verilator to a cycle-accurate C++ model and points an unmodified
software fuzzer at it. Inferred, not stated: Verilator lowers combinational
logic to short-circuiting C++ `if`/`else`, so an AND of two RTL comparisons
gets *re-decomposed* into sequential branches — the same effect as Angora's
static splitting (§3) — whereas a fuzzer instrumenting the netlist directly
(RFUZZ, hwfuzz) sees the AND evaluated in one parallel step. Neither
conjunctions nor reset bias are discussed.

**DifuzzRTL** (Hur et al., IEEE S&P 2021; read in full,
https://lifeasageek.github.io/papers/jaewon-difuzzrtl.pdf) traces every mux
select back to its nearest register (static backward data-flow) to find
"control registers," then XOR-hashes all their current values together each
cycle (modelled on AFL's edge hash) into one joint state, recording
first-seen hashes. Since the hash is over the *joint* tuple, a decision
gated on two registers changing together does shift it — but the paper
never frames this as solving conjunctions, and has no reset-bias or
consumption-gating discussion. **ProcessorFuzz** (Canakci et al., 2022,
https://arxiv.org/pdf/2209.01789) instead finds this coverage **misleading**:
a 130-bit `remainder` register in Rocket's MulDiv gates 98 mux selects and
dominates coverage (62% after 24h) via arithmetic churn alone, "without
providing meaningful information related to the current FSM state" — the
opposite failure to hwfuzz's (too much apparent progress from a
meaningless register, rather than none from one already matched at reset).
Its fix, **CSR-transition coverage**, counts only architecturally-meaningful
CSR changes.

**TheHuzz** (Kande et al., USENIX Security 2022,
https://www.usenix.org/system/files/sec22-kande.pdf) uses conventional EDA
coverage from Synopsys VCS — "statement, toggle, branch, expression,
condition, and FSM" — not a custom metric; no conjunction or reset-bias
discussion.

**HyPFuzz** (Chen et al., USENIX Security 2023,
https://arxiv.org/pdf/2304.02485) — **the standout hit, naming and
quantifying hwfuzz's exact problem.** Its motivating case, CVA6's interrupt
handler, is a two-CSR-bit AND: `if (mie[S_EXT_INTERRUPT] &&
(mip[S_EXT_INTERRUPT] | irq[SupervisorIrq]))`. Triggering it "requires
simultaneously [setting] the bits of both `mie` and `mip` registers"; via
Spike's instruction probabilities, one bit's chance is `1.524×10⁻⁵`, so the
joint probability is `2.323×10⁻¹⁰` — and TheHuzz, after 72h/200K+ tests,
*"did not cover any of the branch coverage points of all three interrupts."*
HyPFuzz's fix leaves heuristic fuzzing entirely for such points: a formal
tool (JasperGold, SAT/BDD) proves an auto-generated `cover` property, and
any satisfying assignment becomes a fuzzer seed.

**Cascade** (Solt et al., USENIX Security 2024,
https://www.usenix.org/system/files/usenixsecurity24-solt.pdf) sidesteps
mutation entirely: "asymmetric ISA pre-simulation" generates long,
deliberately-entangled RISC-V programs so nearly every instruction actually
executes; 28–97× more coverage than prior fuzzers. **TargetFuzz** (Saravanan
& Sai Manoj, arXiv:2509.26509, 2025, read in full) takes HyPFuzz's escape
hatch one level lower: given target nodes/states, it builds a CNF over a
gate-level netlist and solves `⋀ᵢ(f(tᵢ)=vtᵢ)` for one input hitting several
targets at once, reporting 90× better target-state coverage than plain
fuzzing.

This is the strongest evidence found that pure coverage-guided mutation is
not expected, in this literature, to solve compound conditions without
either (i) short-circuit decomposition (Angora/Trippel), or (ii) an outside
solver (RedQueen, HyPFuzz/TargetFuzz). **On reset-value/consumption-gated
coverage: searched hard across nine primary sources — RFUZZ, DifuzzRTL,
TheHuzz, HyPFuzz, ProcessorFuzz, Cascade, Trippel et al., TargetFuzz, and
VGF (arXiv:2312.06580) — and found nothing.** None discounts a comparator's
coverage for being trivially satisfied at reset, or for its result going
unconsumed; a SoK (ARCUS, arXiv:2608.23933, rendered-HTML summary only)
independently surveys the field and names a different gap (oracle quality
via microarchitectural side channels), not this one. Tentative — several
other titles (GenHuzz, INSTILLER, FuSS, GoldenFuzz, ReFuzz, TurboFuzz,
BugsBunny) were checked by abstract only.

## What to borrow for hwfuzz

1. **RedQueen-style sequential patch-and-fix, adapted to per-cycle forcing**
   (high confidence it transfers). For comparators C1∧C2 gating an effect,
   force C1's *inputs* (not output) to the logged value that makes it true,
   hold that fixed, then run input-to-state search on C2's operand as if C1
   no longer varied — RedQueen's dependency-graph/topological-sort
   discipline (§2), without needing instruction patching. Replaces hwfuzz's
   ad hoc "multi-replacement" (random small subsets) with a
   fix-and-validate-one-at-a-time order. Where more than two conjuncts or no
   clean ordering exists, HyPFuzz/TargetFuzz's fallback (§6) generalises
   this: hand the conjunction `⋀ᵢ(cᵢ)` to a small SAT/SMT solver over just
   the signals feeding the gate, rather than searching for it.

2. **VUzzer/SBST-style approach-level reward on the mux/comparator graph**
   (high confidence, cheap). Weight each comparator probe by how deep it
   sits behind other gating conditions (VUzzer's `1/p_b`), so a mutant that
   satisfies one conjunct of a multi-comparator gate — without yet flipping
   the gated effect — is rewarded and retained instead of discarded as "no
   new coverage". Directly targets the task's failure mode: getting
   `bRequest==0x05` right without `bmRequestType==0x00` currently looks like
   zero progress.

3. **Context-/enable-gated coverage as a first-class axis** — this looks
   genuinely unaddressed (tentative; the search was not exhaustive). Every
   hardware source read scores a mux/comparator covered once its output has
   taken both values — none scores *whether the result was actually
   consumed* (fed to an enabled register write, a taken mux path) versus
   computed-but-ignored. hwfuzz's own diagnosis — `setup[0]==0x00` already
   true at reset, before it matters — is exactly an always-true comparator
   whose truth is coverage-irrelevant until something downstream looks at
   it. ProcessorFuzz's CSR-transition metric addresses the adjacent problem
   (a register that changes constantly but uninformatively) with a
   *value-transition* filter, not a *consumption* filter. Software
   input-to-state literature doesn't need this axis at all, because a `CMP`
   that executes but whose result is discarded essentially doesn't happen —
   control flow depends on it by construction. That structural difference
   (hardware evaluates unconditionally every cycle; a software `CMP`
   executing already implies its result is used) looks like the real reason
   this hasn't surfaced elsewhere, rather than the field having solved it.
