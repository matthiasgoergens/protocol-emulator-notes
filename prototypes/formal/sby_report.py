#!/usr/bin/env python3
"""Per-property report of SymbiYosys runs, in the shape of Bmc.verdict_line (README.md,
"Per-property report"; after smprather's PROVED / REACHABLE / VACUOUS summary, credits there).

Usage: sby_report.py SOURCE.sv PROOF_LOG COVER_LOG [SCOPE]
  SOURCE.sv   the file with the labelled assertions (label: assert ...) and, for each, a cover
              labelled <label>_ante: the condition under which the assertion says something
  PROOF_LOG   the sby output of the proof (mode prove or bmc)
  COVER_LOG   the sby output of the cover task (or of a BMC of the negated antecedents,
              asserted as <cover>_reach)
  SCOPE       how to describe a pass, e.g. "unbounded (abc pdr)" or "to 440 clocks (abc bmc3)"

Verdicts: an assertion is FAILED if the proof names it; otherwise PROVED if the proof passed and
its antecedent cover was reached, VACUOUS if the cover task reports it unreached, and UNDECIDED
if the proof did not finish or the antecedent's reachability is unknown. An assertion without an
antecedent cover is reported as an error: every assertion must have one. Other covers are
listed as REACHABLE or UNREACHABLE."""
import re
import sys


def main():
    src, proof, cover = sys.argv[1:4]
    scope = sys.argv[4] if len(sys.argv) > 4 else ""
    text = open(src).read()
    asserts = [a for a in re.findall(r"(\w+)\s*:\s*assert\b", text) if not a.endswith("_reach")]
    covers = re.findall(r"(\w+)\s*:\s*cover\b", text)
    plog, clog = open(proof).read(), open(cover).read()
    done = re.search(r"DONE \((\w+)", plog)
    status = done.group(1) if done else None
    failed = {m.group(1): m.group(2) for m in re.finditer(r"failed assertion \w+\.(\w+) .* step (\d+)", plog)}
    # the engine's own lines: sby's summary lists only some of the reached covers (on 2026-10-05
    # it listed 5 of 7), so reading the summary alone reported two reachable covers as undecided
    reached = {m.group(2): m.group(1) for m in re.finditer(r"Reached cover statement in step (\d+) at \w+: (\w+)", clog)}
    reached.update({m.group(1): m.group(2) for m in re.finditer(r"(?<!un)reached cover statement \w+\.(\w+) .* step (\d+)", clog)})
    unreached = set(re.findall(r"[Uu]nreached cover statement (?:at \w+: |\w+\.)(\w+)", clog))
    # an antecedent checked as a negated assertion <cover>_reach (for a bit-level BMC): its
    # failure at step n is the cover reached at step n; a pass to the depth is unreachable there
    for m in re.finditer(r"failed assertion [\w.]*?(\w+)_reach .* step (\d+)", clog):
        reached[m.group(1)] = m.group(2)
    # without a trace replay (aigsmt none) only abc's own line names the step; it identifies the
    # assertion only when the source has exactly one <cover>_reach
    reach_asserts = re.findall(r"(\w+)_reach\s*:\s*assert\b", text)
    m = re.search(r"asserted in frame (\d+)", clog)
    if m and len(reach_asserts) == 1 and reach_asserts[0] not in reached:
        reached[reach_asserts[0]] = m.group(1)
    if re.search(r"DONE \(PASS", clog):
        unreached |= {c[: -len("_reach")] for c in re.findall(r"(\w+_reach)\s*:\s*assert\b", text)} - set(reached)
    cover_done = re.search(r"DONE \((\w+)", clog)
    bad = 0
    for a in asserts:
        ante = a + "_ante"
        if ante not in covers:
            print(f"PROPERTY {a}: ERROR, no antecedent cover {ante} in {src}")
            bad += 1
            continue
        if a in failed:
            print(f"PROPERTY {a}: FAILED at step {failed[a]}")
        elif status == "PASS" and ante in reached:
            print(f"PROPERTY {a}: PROVED {scope}; antecedent {ante} reachable (step {reached[ante]})")
        elif status == "PASS" and ante in unreached:
            print(f"PROPERTY {a}: VACUOUS {scope}; antecedent {ante} unreachable (to the cover task's depth)")
        elif status == "FAIL":
            print(f"PROPERTY {a}: UNDECIDED (the proof stopped at another assertion's failure)")
        else:
            print(f"PROPERTY {a}: UNDECIDED (proof status {status}, antecedent "
                  f"{'reachable' if ante in reached else 'unreachable' if ante in unreached else 'not decided'})")
    for c in covers:
        state = ("REACHABLE (step %s)" % reached[c] if c in reached else "UNREACHABLE (to the cover task's depth)" if c in unreached
                 else "UNDECIDED (cover task %s)" % (cover_done.group(1) if cover_done else "unfinished"))
        print(f"COVER {c}: {state}")
    sys.exit(1 if bad else 0)


main()
