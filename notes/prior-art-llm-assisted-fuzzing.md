# Prior art: LLM-assisted fuzzing (survey, 2026-09-24)

Written by a research subagent. Checked against the papers on 2026-09-24:
- ChatAFL's `MaxPlateau` of 512 non-coverage-increasing message sequences;
- LLAMAFUZZ: significant improvement on 11 of 15 targets, which the agent's report to me had given as 10;
- SeedMind asking for generators, not seeds;
- the front-loading in "Beyond Random Inputs": 75% condition coverage in 52 minutes against TheHuzz's roughly 30 hours, but 79.14% against 76.7% after the same 199k test cases.


Context: hwfuzz is a coverage-guided fuzzer for Hardcaml circuits — AFL-style
queue, input-to-state mutation on logged comparison operands, target-supplied
transducers (a USB host model that frames packets and fixes CRCs), and
"islands" that exchange new queue entries. It needs ~200,000 executions to
reach SET_ADDRESS on a USB device (ledger entry 10 in
`prototypes/hwfuzz/README.md`) — a message sequence any LLM can write from
memory. We are considering an LLM as an extra island: on a coverage plateau,
show it state and ask for inputs, keeping only what adds coverage. This
surveys whether that has already been tried, how, and what it cost.

Written from four research passes (subagents), told to read primary sources
(arXiv/ar5iv full text, READMEs, blog posts) over search snippets, and to
flag when a claim rests on an abstract/summary rather than the paper itself.
That flagging is preserved below.

## 1. Protocol fuzzing: ChatAFL and Fuzz4All

**ChatAFL** — Meng, Mirchev, Böhme, Roychoudhury, "Large Language Model
guided Protocol Fuzzing", NDSS 2024. Full 18-page PDF read directly:
<https://mboehme.github.io/paper/NDSS24-chatafl.pdf>. Code:
<https://github.com/ChatAFLndss/ChatAFL>. Built on AFLNet. Three LLM uses,
layered on the AFLNet loop, all via gpt-3.5-turbo:

- **Grammar extraction** — once per protocol, 2-shot prompting with 5
  repetitions and majority vote, restricts mutation to marked "mutable"
  message regions.
- **Seed enrichment** — once before fuzzing, LLM inserts message types
  missing from the seed corpus.
- **Plateau escape** — the only one that recurs. A counter `PlateauLen` of
  consecutive non-coverage-increasing seeds resets on a crash or a new
  state/edge, else increments; at `PlateauLen ≥ MaxPlateau` (512, chosen
  because that took "approximately 10 minutes" in pilot runs) the LLM is
  shown the full request/response history and a demonstration message, and
  asked for the next message likely to open a new state. Calls per plateau
  episode are capped at `MaxPlateau/4` to bound cost.

Output is protocol wire-text, sent straight to the real server; kept only if
`IsInteresting` (crash or new state/code coverage) — validation is empirical,
not syntactic. Results on 6 ProFuzzBench targets, 10×24h runs: +47.6% state
transitions and +5.8% branch coverage over AFLNet on average; 9 zero-day
bugs vs 3 for AFLNet, 7 CVE-requested. No $/token cost reported, only the
call cap and "~1 hour" of manual prompt engineering. The stated limitation
is contamination-shaped in reverse — it works because RFCs are public and
in training data, and the authors say so: "for certain proprietary
protocols, whose RFCs are not included in the LLM training data, ChatAFL
may not perform optimally."

**Fuzz4All** — Xia, Paltenghi, Tian, Pradel, Zhang, ICSE 2024, full text via
ar5iv: <https://arxiv.org/abs/2308.04748>. Two LLMs: a one-shot "distillation"
pass (GPT-4) turns target documentation into a compact system prompt; a
"generation" LLM (StarCoder) then runs continuously — no plateau detection,
called every iteration until the time/input budget (24h or 10k inputs) is
exhausted, picking one of generate-new/mutate-existing/semantic-equivalent
per call. Output is raw code/SMT2 text with no syntax pre-filter; the
compiler or solver is the only validity oracle, and reported validity was low
(23–56%) — an accepted trade-off for diversity. Average +36.8% coverage over
9 language-specific baselines across 6 languages; autoprompting was the
single largest contributor in ablation (127,261 → 185,491 edges on one C
target). Cost: ~120 LLM calls and 2.3 minutes of one-time autoprompting
overhead per campaign; no $/token total reported. Authors flag model drift
(a frozen checkpoint degrading as code shifts away from its training
distribution) but not whether it memorised specific target test suites.

## 2. Generation and mutation with LLMs: library/compiler fuzzers, and LLM+AFL combinations

**TitanFuzz** (Deng et al., ISSTA 2023, arXiv:2212.14834) generates whole
Python programs with Codex zero-shot, then mutates by masking/regenerating
sub-spans with InCoder — no coverage feedback into the prompt, only into
which resulting programs are kept. +30–51% coverage over prior DL-library
fuzzers, 65 bugs (41 new). **FuzzGPT** (Deng et al., ICSE 2024,
arXiv:2304.02014) extends this by fine-tuning on, or few-shotting with,
*historical bug-triggering programs* to bias generation toward rare code —
76 bugs, 49 new. Worth flagging: deliberately training on known-bug code is
close to the contamination question this survey asks elsewhere, except here
it is the stated mechanism, not an accident. Neither abstract discusses cost
or long-run persistence (full text not fetched here).

**WhiteFox** (Yang et al., OOPSLA 2024, arXiv:2310.15991, full text read)
is genuinely white-box: an "analysis agent" reads compiler optimisation
*source code* and derives natural-language trigger conditions; a
"generation agent" writes a test program meeting them; successful triggers
become few-shot examples for further rounds — periodic, not one-shot.
Exercises up to 8× more optimisations than prior fuzzers; bug counts vary
between sources found (96/80/61 vs 101/92 — approximate, pending the
primary text).

**CovRL** (Eom, Jeong, Kwon, ISSTA 2024, arXiv:2402.12222) is the one paper
in this survey that actually fine-tunes an LLM mutator with reinforcement
learning: PPO with a TF-IDF-weighted coverage map as reward (rarer branches
weigh more), acting as a per-iteration mutation operator inside the fuzzing
loop rather than an API call. 48 JS-engine bugs (39 new, 11 CVEs). Training
cost not quantified in the abstract-level material fetched.

**LLM + AFL/AFL++ as a second channel, with genuinely mixed results.**
**LLAMAFUZZ** (Zhang et al., ASE 2024, arXiv:2406.07714, full text read) is
the closest analogue to "LLM as an extra island": a LoRA-fine-tuned
llama-2-7b-chat runs as an *asynchronous second mutation channel* alongside
AFL++'s native mutations, bounded to a max queue depth of 30 so it never
blocks native throughput. On Magma: 47 unique bugs vs AFL++'s 46. On 15
real-world targets: +27.2% branches on average and a statistically significant improvement over AFL++ on 11 of the 15 (checked in the paper), but explicitly mixed — zlib
and openh264 showed "negligible or negative improvement," and poppler (PDF)
lagged because files exceeded the model's 4096-token context and got
truncated. Only 3 repetitions per target (GPU-limited) vs 10 for baselines —
the authors' own statistical-power weakness. **SeedMind** ("Harnessing
Large Language Models for Seed Generation in Greybox Fuzzing," Shi, Zhang,
Xing, Xu, arXiv:2411.18143, full text read) is structurally closer to
hwfuzz's transducer idea: instead of seeds, it asks for a *Python generator
program* that produces them, refined iteratively against coverage feedback
(call graph pruned to fit the context window) for up to 30 minutes per
harness. On 674 OSS-Fuzz harnesses it reaches 72–89% of default-corpus
coverage depending on model, at $0.10 (GPT-3.5) to $0.69 (GPT-4o) average
cost per harness; on Magma with AFL++, 27 bugs vs 24 (default corpus) vs 18
(a prior LLM baseline). No discussion of gains beyond the 30-minute window.

**Explicit negative/mixed results.** MultiFuzz (arXiv:2508.14300, search
snippet only) reports only marginal, statistically-unsupported gains from a
RAG+multi-agent LLM layered on ChatAFL-style fuzzing of RTSP/Live555.
Unverified search-summarised material describes at least one study where
GPT-3.5-based mutation guidance underperformed plain fuzzing, and where more
few-shot examples had "negligible or even negative" effect per-benchmark.
Conversely, "Sow Smarter, Not Harder" (CRITIS 2025, paywalled, abstract
only) reports +14.8% coverage and +56.3% unique crashes across 7 LLMs on
critical-infrastructure targets, uncheckable beyond its abstract.

## 3. OSS-Fuzz-gen

Google's OSS-Fuzz-gen (<https://github.com/google/oss-fuzz-gen>) has **no
backing academic paper** — an arXiv title/author search returned zero hits.
It is documented only in the GitHub README and two Google Security blog
posts (2023, 2024, both read directly). It generates a fuzz *harness* (a
`LLVMFuzzerTestOneInput` driver), not raw inputs, via a repair loop: draft
harness → re-prompt with compiler errors until it builds → re-prompt with
crash logs to filter harness-induced false positives (e.g. a use-after-free
the harness itself introduces) → longer run + crash triage, with an
auto-patch step explicitly **not yet implemented** as of the 2024 post.
Context includes the function-under-test, callers, and same-/cross-project
harness examples ("too many examples yields worse results," per a docs-page
summary, not raw HTML). Kept only on a non-zero coverage-diff vs. existing
harnesses. Reported numbers (README, Jan 2024, extended Nov 2024): 1300+
benchmarks, 297 projects, up to 29–35% relative coverage increase, 26–30
new vulnerabilities including CVE-2024-9143 in OpenSSL — "likely present
for two decades" and undiscoverable by the existing harness. No $/token cost
figure anywhere. As of 2024, human review of crash triage is still required
("confident about not requiring human review" is future work). Critically:
**none of the four primary sources discuss training-data contamination at
all** — an omission on a project whose LLMs plainly saw the exact
open-source target code during training.

An independent empirical study directly informed this project: Zhang et al.,
"How Effective Are They? Exploring LLM-Based Fuzz Driver Generation"
(arXiv:2307.12469, abstract read): 736,430 generated drivers across 5 LLMs
and 6 prompting strategies, reported cost over $8,000 in tokens (secondary
source, not re-verified against the paper's own cost table); found repeat
queries, few-shot examples and iterative querying to be the load-bearing
prompt choices, with drivers still lagging hand-written ones on API coverage
and oracle quality.

## 4. Hardware: LLM4DV, ChatFuzz, and coverage-closure agents

**LLM4DV** (Zhang, Szekely, Gimenes, Chadwick, McNally, Cheng, Mullins, Zhao,
arXiv:2310.04535, full text read; code named `ml4dv`) extracts *stimulus
values* from LLM free text — not testbench code — into an existing DV flow.
Fully iterative: coverage feedback (missed bins, via missed-bin sampling)
is injected each round, and a dialogue scheduler restarts the conversation
if fewer than 3 new bins land within a response budget. Tested on 8 designs
(FIFO up to a full Ibex CPU) across 6 LLMs; Claude 3.5 Sonnet hit 100% on
the Ibex instruction decoder and 89.7% on the full CPU, meeting or beating
naive constrained-random on most designs. No $/token cost, only a
700-message trial cap. Authors state stimulus extraction from free text is
itself unvalidated, and LLMs struggle as complexity grows; no contamination
or persistence discussion.

**"Beyond Random Inputs: A Novel ML-Based Hardware Fuzzing"** (Rostami,
Chilese, Zeitouni, Kande, Rajendran, Sadeghi, DATE 2024, arXiv:2404.06856,
full text read) is the paper matching "ChatFuzz": a GPT-2-family model
trained from scratch on ~500K RISC-V instruction vectors mined from Linux
kernel builds, RL-refined in two PPO phases — first for syntactic validity
(reward penalises invalid instructions 5:1), then for hardware coverage
(reward = coverage delta from the fuzzing loop itself). On RocketCore:
74.96% condition coverage in under an hour vs TheHuzz's ~30 hours for 75% —
but by 199k test cases the margin narrows to 79.14% vs 76.7%, i.e. the
advantage is front-loaded and largely gone by the end. Found all of
TheHuzz's bugs plus two new ones. No contamination discussion despite
training directly on real kernel binaries; no validity rate after RL
cleanup, only "sensibly reduced" errors.

**Coverage-closure agents (mostly abstract-level beyond Spec2Cov).**
Spec2Cov (arXiv:2604.15606, full text read) is a 3-phase agentic loop:
LLM writes constrained-random SystemVerilog from spec text, simulates with
20 seeds, then iterates (up to 20 rounds) on coverage-annotated RTL plus the
full coverage report and any compile/sim errors. Geometric-mean 91.5% code
coverage over 26 designs; statement-coverage only, and its testplan-guidance
feature *degrades* coverage on hard designs without added context-pruning —
a cautionary result against over-specifying the prompt. AgentDV, CovR,
UVMarvel, LLM4Cov and HAVEN are further UVM/coverage agents found only via
search snippets (arXiv:2608.27148, 2609.19189, 2605.04704, 2602.16953,
2604.27643) — unverified. Vendor claims (Cadence JedAI, Synopsys.ai Copilot,
"slashes verification time 5–10×") are marketing, not measured results.
LLM+formal work (STELLAR, AssertionForge, LISA, ProofLoop, NeuroAbs) drafts
SVA properties or RTL abstractions for a solver to check — all found only
via search in this pass, not verified against primary text.

## 5. Evaluation concerns

**Contamination.** Only ChatAFL states it directly, as a boundary of
applicability rather than a discovered flaw. No paper surveyed reports
measuring or controlling for it (e.g. a held-out or synthetic protocol);
FuzzGPT and "Beyond Random Inputs" train on exactly the material — bug
reports, kernel binaries — whose recall they are then credited for. This
matters directly for hwfuzz: SET_ADDRESS is USB-spec public knowledge, so an
LLM reaching it from memory is not evidence the island helps; the planted
fault *behind* it (ledger entry 10) is not public and is the fairer target,
matching the project's own "planting bugs to test the testing" practice
(`notes/plant-bugs.md`).

**Cost accounting.** Reported figures are inconsistent and mostly partial:
SeedMind's $0.10–0.69/harness is the only clean per-unit dollar figure found;
ChatAFL and Fuzz4All report call/time caps, not $; OSS-Fuzz-gen and most
hardware papers report no cost at all. None of the surveyed papers convert
LLM cost into an equivalent number of plain-fuzzer executions for a
same-budget comparison.

**Variance.** LLAMAFUZZ ran only 3 repetitions per target versus 10 for
baselines, citing GPU limits, and flags this itself as a statistical-power
weakness. LLM4DV and Spec2Cov report pass@k over several samples but not
run-to-run variance of the whole campaign. No paper surveyed reports
confidence intervals on coverage-over-time curves.

**Persistence vs front-loading.** Where the data allows a before/after
comparison, gains are front-loaded: "Beyond Random Inputs" shows a large
early lead that narrows to a few points by 199k executions; SeedMind's
improvements come from a bounded 30-minute refinement window, not sustained
calls; LLAMAFUZZ shows continuing but diminishing returns on its own
(self-reported) figure. No paper surveyed ran an LLM-seeded campaign long
enough, against an equal-budget plain-fuzzing control, to settle whether the
LLM's contribution keeps paying for itself or is absorbed by ordinary
mutation after the first plateau.

## What to borrow for hwfuzz

Ranked by how directly each transfers to an LLM island, with the prior work
it comes from:

1. **Plateau-triggered, call-capped invocation (ChatAFL).** Fire the LLM
   island only when an "executions since last new feature" counter crosses a
   threshold, and cap calls per plateau episode so a stuck campaign cannot
   blow an unbounded budget — the task's own proposal, with ChatAFL's numbers
   (512 executions; calls capped at a quarter of that) as a tuning start.
2. **Output through the target's transducer, as a generator, not raw bytes
   (SeedMind).** Instead of a byte string in hwfuzz's packed record format,
   have the LLM call the transducer's own structured interface ("emit a
   SETUP+DATA0+IN sequence for SET_ADDRESS(n)"), as SeedMind writes a Python
   generator against the harness's real interface rather than guessing byte
   layout — sidesteps the swarm-mask/hold-byte encoding entirely.
3. **Show missed coverage bins, not just a coverage number (LLM4DV).**
   LLM4DV's missed-bin sampling and "restart if fewer than N new bins in T
   responses" rule are an already-measured version of "show it the state";
   hwfuzz's decision/register/output features are a ready-made bin list.
4. **One-shot seed/grammar enrichment before the campaign (ChatAFL
   S_A/S_B).** Once, before fuzzing starts, ask the LLM to enumerate USB
   message types and propose a seed sequence exercising several (e.g. a full
   SET_ADDRESS handshake) — cheap, and separate so it does not contaminate
   the per-plateau mechanism's own evaluation.
5. **Async, bounded second channel (LLAMAFUZZ).** Treat the LLM island like
   hwfuzz's existing islands: it proposes queue entries asynchronously,
   native mutation is never blocked on it, and a bounded queue-depth cap
   (LLAMAFUZZ used 30) stops one slow call starving the campaign.
6. **White-box context when cheap (WhiteFox).** If budget allows, show the
   LLM the transducer's own source (it already encodes protocol knowledge)
   rather than only a coverage report — closer to WhiteFox's "read the
   mechanism" than to black-box protocol fuzzing.
7. **RL fine-tuning (CovRL, "Beyond Random Inputs") — not yet.** Both show
   fine-tuning can help, but at a training cost with no measured budget here
   and no evidence prompting alone is insufficient. Revisit only once a
   prompted island has been measured and found wanting.

## Experiments the literature suggests

- **Same seeds, same wall-clock budget, cost counted as executions.** Run
  the LLM-island campaign and a plain-fuzzing control from the same seed
  corpus and budget, converting LLM $ cost into an equivalent number of
  extra plain-fuzzer executions and reporting both curves — no surveyed
  paper does this conversion, and hwfuzz's executions-per-second figures
  make it cheap to compute.
- **Target the planted fault, not the public milestone.** Treat SET_ADDRESS
  as only a sanity check that the LLM is engaging; score the island against
  the planted-fault mutation-score objective (`notes/plant-bugs.md`) so a
  memorised protocol name cannot masquerade as a genuine find.
- **Vary the seed and report the spread.** LLAMAFUZZ's 3-seed weakness and
  hwfuzz's own ledger entry 11 ("three seeds give trends, not settled
  differences") point the same way: use at least as many seeds as hwfuzz's
  other heuristics do before concluding the island helped.
- **Run past the first plateau escape to see if gains persist.** Given
  "Beyond Random Inputs"' narrowing margin and SeedMind's bounded window,
  extend well beyond the first LLM intervention and check whether the
  coverage curve keeps separating from the control or converges back — the
  open question this literature leaves unanswered for every system here.
