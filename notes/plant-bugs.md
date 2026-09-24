# Planting bugs to test the testing (note, 2026-09-24)

A practice that came out of the hwfuzz work, worth generalising beyond this project. It may become a skill later.

## The idea

Before trusting a checker (a test suite, fuzzer, oracle, sanitizer, lockstep comparison), feed it bugs you know are there and confirm it fires. Measure it, too: the fraction of planted bugs caught within a budget is a score, and it is better than an assertion that the checker works.

In this project:
- The USB oracle was checked against a planted address-gated fault.
- The Ethernet checks were run against a corrupted frame.
- The crazy-network lockstep test was checked against planted RTL faults.

A single fault placed by hand is weak evidence, though. It shares the assumptions of whoever placed it: a positive control you designed yourself can only agree with you.

## Two established forms (prior art, from memory; check before relying on details)

- **Mutation testing.** Many small semantic mutants of the program, and a mutation score for the tests. It goes back to DeMillo, Lipton and Sayward, "Hints on test data selection" (1978). Tools include Mull (LLVM, C/C++), Dextool, universalmutator, PIT (Java) and mutmut (Python). In hardware, Synopsys Certitude grades testbenches by mutating RTL. For fuzzers, LAVA (Dolan-Gavitt et al., 2016) injects synthetic bugs at scale.
- **Bugs restored from project history.** Revert the commits that fixed real bugs. Magma (Hazimeh et al., 2020) forward-ports real bugs as a fuzzer benchmark; FixReverter reverts fix patterns; Defects4J and BugsInPy curate them. Synthetic bugs are easier and less realistic than historical ones, so use both.

## For hwfuzz

- Generate mutants automatically from the Hardcaml signal graph:
  - off-by-one constants;
  - `==` turned into `<`;
  - swapped multiplexer inputs;
  - inverted conditions;
  - a dropped clear or enable.
- Revert real fixes from this repository's history:
  - the Ethernet end-of-frame debounce (2026-09-24);
  - the wave engine's `(sum+8)>>4` rounding;
  - the evolve score's precedence bug.
- Use the mutation score per execution budget as the objective for deciding defaults, and for any automatic search over configurations. Validate on held-out designs or mutants, since seed variance is large (ledger entry 11) and a search would otherwise chase luck.

## For agents writing tests

The mutation score of the tests an agent writes is a direct measure of Dan Luu's "encode the output" failure (<https://danluu.com/agentic-testing/>): tests that merely restate the code's behaviour kill few mutants. The same score could be used to tune the prompts or skills that make agents write tests, which is the optimisation that post did not attempt.

## Kernel and security-sensitive code

Planting, say, a use-after-free to check that KASAN or a test catches it looks, taken on its own, like writing a vulnerability. Model safeguards may hesitate, even though this is standard verification practice. What keeps it clearly legitimate, and tends to go smoothly:
- **Mechanical mutants from a mutation tool,** not bugs hand-authored by the model. The model runs the tool and interprets the scores. This is also better methodology.
- **Reverted historical fixes** for known, already-public bugs: nothing new is invented.
- **Local and scoped:** throwaway branches or worktrees, VMs (ktest), mutants never pushed or submitted, and the purpose stated up front.
