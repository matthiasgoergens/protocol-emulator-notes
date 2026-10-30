# Edge placement on the half-clock grid, from edges-<corner>.txt (arrival times in ns from the rising edge at 0).
import re, sys
T = 16.67; H = T / 2
for corner in ("slow", "typ", "fast"):
    a = {}
    for line in open(f"{sys.argv[1]}/edges-{corner}.txt"):
        m = re.match(r"(\S+) launch=(\w+) out=(\w+) (\w+) arrival=([\d.]+)", line)
        pad, launch, out, pd, t = m.groups()
        a[(pad, launch, out, pd)] = float(t) - (H if launch == "fall" else 0.0)
    pads = sorted({k[0] for k in a})
    worst_err, worst_pulse = 0.0, (T, None)
    rows = []
    for p in pads:
        # placement error of a falling-edge-launched edge relative to the rising-launched one, same transition
        errs = [a[(p, "fall", o, pd)] - a[(p, "rise", o, pd2)] for o in ("rise", "fall") for pd in ("max", "min") for pd2 in ("max", "min")]
        err = max(errs, key=abs)
        # narrowest high pulse: output rises on one edge, falls on the next half-clock edge
        pulses = []
        for l1, l2 in (("rise", "fall"), ("fall", "rise")):
            pulses.append(H + a[(p, l2, "fall", "min")] - a[(p, l1, "rise", "max")])  # high pulse
            pulses.append(H + a[(p, l2, "rise", "min")] - a[(p, l1, "fall", "max")])  # low pulse
        mp = min(pulses)
        rows.append(f"  {p:10s} clk-to-pad rise-launched {a[(p,'rise','rise','min')]:.2f}-{a[(p,'rise','rise','max')]:.2f} ns, fall-launched (from fall edge) {a[(p,'fall','rise','min')]:.2f}-{a[(p,'fall','rise','max')]:.2f} ns; worst offset {err:+.2f} ns; narrowest half-clock pulse {mp:.2f} ns")
        worst_err = max(worst_err, abs(err)); worst_pulse = min(worst_pulse, (mp, p))
    print(f"{corner}: worst |offset| {worst_err:.2f} ns ({worst_err / (T/4) * 100:.0f}% of a quarter clock), narrowest pulse {worst_pulse[0]:.2f} ns of an ideal {H:.2f} on {worst_pulse[1]}")
    print("\n".join(rows))
