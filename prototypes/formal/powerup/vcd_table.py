#!/usr/bin/env python3
"""Print chosen top-level signals of a SymbiYosys counterexample (VCD) per step, in hex.
Usage: vcd_table.py TRACE.vcd SIGNAL...   (names as in powerup.sv, e.g. fetched_a imem_addr_b)"""
import sys

def main():
    path, wanted = sys.argv[1], sys.argv[2:]
    ids, scope, values, times = {}, [], {}, []
    cur = None
    with open(path) as f:
        for line in f:
            t = line.split()
            if not t:
                continue
            if t[0] == "$scope":
                scope.append(t[2])
            elif t[0] == "$upscope":
                scope.pop()
            elif t[0] == "$var" and len(scope) == 1 and t[4] in wanted:
                ids.setdefault(t[3], t[4])
            elif t[0].startswith("#"):
                cur = int(t[0][1:]); times.append(cur)
                values[cur] = dict(values[times[-2]]) if len(times) > 1 else {}
            elif t[0][0] == "b" and len(t) == 2 and t[1] in ids:
                values[cur][ids[t[1]]] = t[0][1:]
            elif t[0][0] in "01xz" and t[0][1:] in ids:
                values[cur][ids[t[0][1:]]] = t[0][0]
    # one row per clock: SymbiYosys writes the step's values at even times (0, 10, 20, ...)
    steps = sorted(set(times))
    clock_steps = [s for s in steps if s % 10 == 0]
    print("step " + " ".join(f"{w:>14}" for w in wanted))
    for i, s in enumerate(clock_steps):
        row = []
        for w in wanted:
            v = values[s].get(w, "?")
            row.append(f"{int(v, 2):x}" if set(v) <= {"0", "1"} else v)
        print(f"{i:4} " + " ".join(f"{r:>14}" for r in row))

main()
