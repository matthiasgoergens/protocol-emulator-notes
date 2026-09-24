# Prior art: correlating edits at more than one place in a single mutant

Written by a research subagent. Checked at source on 2026-09-24:
- the five Hypothesis passes, at `shrinker.py`:1017, 1379, 1408, 1486 and 1519 of the local 6.152.9 copy;
- the Nautilus citation in `engine.py`:1414;
- AFL++ v4.40c's `CMPLOG_COMBINE`, which appears only as `#ifdef` blocks in `afl-fuzz-redqueen.c` with no `#define`, so it is compiled out by default.

One stale detail: on the `hwfuzz-distance` branch (commit 007f2fb), multi-replacement is occasional by default (2 mutants per new entry), not off.


Question: hwfuzz's multi-replacement input-to-state (`hwfuzz.ml`, `queue_i2s_bytes`,
around line 666 in the `prototypes/hwfuzz` worktree) occasionally applies 2-3 logged
comparison-operand replacements in one mutant, chosen independently at random from
the sources currently present in the input. Who else edits several places at once,
and — the point of this note — how do they *correlate* those edits, rather than just
stacking independent ones? Sections 2-5 were gathered by delegated research passes
(web search and paper/source fetches) rather than read by me directly; individual
claims inside them are marked "reported in a summary, unverified" where the
delegate could not fetch a primary source. Section 1 and the hwfuzz code were read
directly, at the file/line cited.

## 1. Hypothesis (read directly: `hypothesis-python/src/hypothesis/internal/conjecture/{shrinker,engine,optimiser}.py`, v6.152.9)

Hypothesis's shrinker is a library of named passes, most single-place, several
explicitly multi-place and correlated:

- **`redistribute_numeric_pairs`** (`shrinker.py:1408`) — *same-sum*. Picks two
  numeric nodes within 4 choice-indices and searches k with `node1 -= k, node2 += k`
  simultaneously. Docstring: "If there is a sum of generated numbers that we need
  their sum to exceed some bound, lowering one of them requires raising the other."
- **`lower_integers_together`** (`shrinker.py:1486`) — *same-delta*. Subtracts the
  same n from two nearby integers at once; explicitly does not require the second to
  be non-trivial, since only the shrink order of the first matters.
- **`lower_common_node_offset`** (`shrinker.py:1017`) — the general case: tracks
  every integer node changed since the last successful shrink and, if they share a
  common non-zero offset from their `shrink_towards`, shrinks that offset across all
  of them at once. Motivation is a performance fix, not semantics: without it,
  `m, n = draw(...), draw(...); assert abs(m-n) > 1` zig-zags for O(m) steps because
  "changes to one part of the choice sequence unlock changes to other parts."
- **`minimize_duplicated_choices`** (`shrinker.py:1379`, using `duplicated_nodes` at
  1333) — *same edit at every occurrence*. Groups nodes by `(type, value)` and
  shrinks every occurrence of a duplicated value together, because lowering only one
  occurrence of a value that must appear twice (e.g. `y not in ls` with `y in ls`)
  breaks the failure.
- **`lower_duplicated_characters`** (`shrinker.py:1519`) — the character-level
  analogue across two nearby strings; lowers *every* instance of one shared
  character in *both* strings via a single search. Its docstring admits the same
  combinatorial trade-off hwfuzz faces picking a subset of logged pairs: "This may
  fail to shrink some cases where only certain character indices are correlated
  ... we would need good safeguards because it could get very expensive to try all
  combinations."
- **`reorder_spans`** (`shrinker.py:1810`) — permutes a group of same-labelled
  sibling sub-trees as a batch (via `Ordering.shrink`), not independently.
- **`generate_mutations_from`** (`engine.py:1325`, *generation*-phase, not
  shrinking) — groups sub-spans of a prior test case by strategy label
  (`data.spans.mutator_groups`) and either duplicates one span's bytes into
  another same-label span's position, or replaces both spans with one shared
  replacement. The comment at line 1414 states this is "the same as Example IV.4 in
  Nautilus (NDSS '19) ... except we do not repeat the replacement additional times,"
  and deliberately skips the reverse direction (shrinking the tree) as something
  ordinary generation could already produce by chance.
- Contrast: `target()`'s hill climbing (`optimiser.py`, `Optimiser.hill_climb`,
  lines 84-205) perturbs exactly **one** node per step (`attempt_replace`), with no
  cross-node correlation — a deliberate negative data point from the same codebase.

## 2. AFL / AFL++ and libFuzzer (subagent research, AFL++ `stable` and llvm-project `main`, fetched)

**AFL++ havoc stacking**: `use_stacking = 1 + rand_below(afl, stack_max)` draws of an
operator index from `mutation_array`, chained blindly and executed once
(`src/afl-fuzz-one.c:2347-3786`; default up to 16 stacked ops per `HAVOC_STACK_POW2`,
`include/config.h:264`). Classification: **independent-stacked** — later edits see
earlier edits' output positionally, but selection is i.i.d.

**Splicing** is now inlined as ordinary havoc ops (`MUT_SPLICE_OVERWRITE`/`INSERT`,
`afl-fuzz-one.c:3611-3760`): borrows a contiguous run from a different queue entry.
**Structure-aware** in the sense of donating real bytes, but donor choice is
uncorrelated with other stacked ops.

**MOpt** (Lyu et al., USENIX Security 2019) runs particle-swarm optimisation over the
*marginal selection probability* of each havoc operator (AFL++:
`afl-fuzz-mopt-adaptive.c`), then feeds a reweighted `mutation_array` back into the
same independent per-step draw. It learns *which operators pay off on average*, not
*which operators co-occur usefully in one mutant* — reported gains (170% more bugs
found, 350% more crashes, 100% more paths than AFL, 13 programs) are about
scheduling, not correlation.

**CmpLog/RedQueen**: AFL++'s default path (`src/afl-fuzz-redqueen.c`,
`cmp_extend_encoding`) tests and reverts one replacement at a time. There is a
compile-time-disabled `#ifdef CMPLOG_COMBINE` path that accumulates every
individually-successful replacement into a scratch buffer and tests the combined
result once if more than one succeeded — the one confirmed place in the AFL family
that jointly applies several input-to-state edits in one mutant, matching hwfuzz's
multi-replacement almost exactly, but it ships **off** by default. The original
RedQueen paper's body was not fetched by the subagent (NDSS 2019, unverified beyond
title/abstract).

**libFuzzer** (`FuzzerMutate.cpp`) applies exactly one mutator per `Mutate()` call
(`MutateImpl`, lines 541-559); the apparent "stacking" lives one layer up in
`Fuzzer::MutateAndTestOne` (`FuzzerLoop.cpp:724-774`), which re-tests coverage after
*every* step and stops chaining the moment new coverage appears — a materially
different scheme from AFL's batch-then-test-once. `Mutate_AddWordFromTORC`
(comparison-table replacement, lines 259-291) and `Mutate_CrossOver` (lines 440-467)
each apply one replacement/one donor per call; `MutateWithMask` restricts the *site*
of a single ordinary mutation to data-flow-relevant bytes, not correlated edit count.

## 3. Joint multi-byte search (subagent research, papers fetched)

**Angora** (Chen & Chen, IEEE S&P 2018) treats a branch predicate as scalar f(x)
over the *whole vector* of tainted bytes feeding it, normalises comparisons into
f(x)<0 / <=0 / ==0 forms, and runs gradient descent moving all relevant bytes at
once; a type/shape-inference step first detects multi-byte fields so they move as
one dimension rather than several. LAVA-M results: e.g. 8x the bugs of the next-best
fuzzer on `who`; 103 bugs LAVA's own authors couldn't trigger.

**Eclipser** (Choi et al., ICSE 2019) is weaker on joint correlation than the task
assumed: it grows a *single* field (1→2→4→8 bytes at one offset) via binary search
over an assumed-monotonic relationship, but the paper concedes multi-*field*
predicates are solved sequentially, field by field, not jointly (§III-A, subagent
quote).

**Matryoshka** (Chen, Liu, Chen, CCS 2019) is the sharpest joint mechanism found:
it collects the target branch's constraint plus every taint-sharing "prior"
branch's constraint along the path, sums them through a rectifier into one scalar
objective, and gradient-descends to a single input satisfying the whole chain at
once — directly the "search jointly over several separated comparisons" case.

**QSYM/Driller** are the solver-based limit: an SMT solver's model spans every byte
in a path constraint simultaneously, exact rather than heuristic, at the classic
cost of path explosion and solve time — the reason the gradient-based heuristics
above exist.

## 4. Structure-aware correlation (subagent research, papers fetched except where noted)

**Weizz** (Fioraldi et al., ISSTA 2020) tags bytes by which comparison instruction
consumes them (no taint tracking, pure bit-flip probing), groups matching tags into
fields/chunks, and for checksums specifically re-derives and rewrites the dependent
checksum field after the covered data changes, validating by re-running with the
patch disabled and checking the execution path matches. This is the clearest
"fix the dependent field after mutating the field it covers" mechanism, and it is
automatic rather than needing a supplied grammar.

**AFLSmart** (Pham et al., ICSE/TSE) uses a Peach-Pit grammar to build a chunk tree
and applies whole-chunk deletion/addition/splicing while renumbering every other
chunk's boundaries — correlates chunk *boundaries*, but the paper itself says
checksum/length *value* consistency is left to external "Peach fixups," making
Weizz's automatic inference strictly stronger on that axis.

**FuzzFactory** is a weak fit: its "waypoints" preserve domain-progress inputs even
without new coverage, which is about *survival*, not about correlating two edit
sites in one mutation step.

**Grammar fuzzers**: Nautilus (Aschermann et al., NDSS 2019) swaps a subtree for a
new one rooted in the *same nonterminal* (keeping surrounding context valid by
construction), and its "Random Recursive Mutation" repeats one recursive production
2^n times in one step — a batch of correlated repeats, not independent edits.
Superion does the AST analogue (reported in a summary, not fully fetched). Gramatron
(ISSTA 2021, not ASPLOS as originally guessed) encodes the grammar as an automaton
so legal-continuation is a property of automaton state rather than a post-hoc check,
letting mutations be reported as "6.4x more aggressive" while staying valid.

## 5. Property-based testing beyond Hypothesis (subagent research, sources fetched)

Classic **QuickCheck** list-shrinking (`shrinkList`, Hackage source) deletes
contiguous chunks of size n, n/2, n/4… — multi-position but mechanical, not
relationship-preserving. No built-in QuickCheck-family combinator for "shrink two
values keeping their difference/sum" was found — a confirmed gap, not an inferred
one. A 2019 Well-Typed blog post (informal, cited as such) shows both classic manual
shrinking and Hedgehog's integrated shrinking fail to preserve cross-position
relationships, each in a different, worked-example way (`x<y` shrinks to a biased
fixed point either way).

**QuickChick/FuzzChick** (Lampropoulos, Hicks, Pierce, OOPSLA 2019) is explicit
about the same limitation in its own text: its mutator type recurses into exactly
one subterm at a time and the paper states outright that this design "precludes ...
splicing using multiple seeds," left as future work.

**Zest** (Padhye et al., ISSTA 2019) is architecturally the most relevant hit here,
though it correlates through *generator structure* rather than through logged
comparisons: it mutates a fixed sequence of "parameters" that a QuickCheck-style
generator consumes in order, so mutating one early parameter (e.g. a
`nextInt(MAX_CHILDREN)` call) changes what later parameters in the same sequence
mean or whether they get consumed at all — one edit provably reaches many downstream
generated values, by construction rather than by search.

## What to try in hwfuzz

Current state (`hwfuzz.ml:666-694`, `multi_i2s`/`multi_count`): pick k=2-3 distinct
logged `(width, value)` sources independently at random from those present in the
input; each source is then replaced at *every* occurrence of its byte pattern. So
hwfuzz already does candidate (b) per-source and (a) across sources. It is off by
default as of commit `5e9b183`: its only evidence so far is one seed on one design
(USB SET_ADDRESS), and it costs up to 16 executions per new queue entry against
mechanisms (value profile, branch distance) that may already cover the same ground.
That caution carries over to everything below: none of it is validated yet.

1. **Same-delta on two logged operands** (Hypothesis `lower_integers_together`/
   `redistribute_numeric_pairs`; candidate (c)). If two comparison sites in the same
   design look related — e.g. a length field and a cursor, or counters that must
   stay `count_a - count_b` bounded — shift both by the same k, or move mass between
   them keeping the sum fixed, instead of picking each replacement's target value
   independently. Cheapest way to try: when two logged pairs share a width and their
   values differ by a common small delta across several observations, treat that
   delta as a first-class dictionary entry alongside the raw operand pair.
2. **CmpLog's `CMPLOG_COMBINE` pattern**: test-and-revert each replacement
   individually first, and only pay for the combined mutant when more than one
   candidate replacement *individually* looked promising (e.g. individually reached
   new coverage even if not accepted). This turns hwfuzz's current "always spend up
   to `multi_count` executions on a blind combination" into "only combine
   replacements that already showed independent promise," which is exactly the
   asymmetry the commit note flags as the current design's weakness.
3. **Checksum/length re-derivation, Weizz-style** — *if* any hwfuzz target
   (protocol harness) has a length or checksum field, tag which comparison consumes
   it (hwfuzz already has the comparison log) and, after any other logged
   replacement lands, re-run the transducer/oracle far enough to read back what the
   design would compute for that field, and write that back rather than leaving a
   now-inconsistent checksum. Uncertain how much of hwfuzz's current target set
   (USB, Ethernet) has this shape — worth checking before investing here.
4. **Nautilus-style same-label duplication** at the unit level: hwfuzz's existing
   "next-unit" input-to-state (commit `728c9a1`) already appends a unit holding one
   operand with the other substituted; a direct extension per Hypothesis's
   `generate_mutations_from` / Nautilus's Example IV.4 would duplicate a whole
   *logged-interesting* unit (not just a bare pair) into a second position when two
   units currently produce the same coverage-relevant label, on the theory that
   protocol state machines often want the same transaction shape repeated (e.g. two
   IN tokens in a row).
5. **MOpt-style learned weighting of which operators to stack**, applied to
   hwfuzz's own `op_names` array — cheaper than any of the above, and the least
   specific to "correlation" as asked; relevant mainly if profiling shows some of
   the 13 existing operators are being wasted.
6. **Angora/Matryoshka-style joint gradient search** over several logged operands —
   almost certainly not worth the engineering budget here: it needs a
   differentiable-ish proxy and per-byte taint, and pays off mainly on deeply nested
   numeric conditions, which does not obviously describe USB/Ethernet targets fuzzed
   so far. Listed for completeness, marked low-priority and uncertain.

Everything under items 1-4 is a design suggestion, not a measured result; the repo's
own multi-replacement commit history (`99a6456`, `4da4b16`, `5e9b183`) is a caution
that even the currently-implemented, simpler version of this idea has not yet earned
its keep against alternatives on more than one seed.
