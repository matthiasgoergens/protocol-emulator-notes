"""Diagnostic: acquisition result and tracking loop state against the truth, per satellite.
Usage: diag_track.py (after fix.py). Output: results/tier2/diag_track.txt"""
import json, numpy as np, sys
sys.path.insert(0, '.')
import gpsl1 as g, fix
z = np.load(fix.CACHE); x = z["x"]; truth = json.loads(str(z["truth"]))
rx = np.array(truth["rx"]); t0 = truth["t0"]
found = json.load(open('../results/tier2/fix.json'))["found"]
for f in found:
    eph = [s["eph"] for s in truth["sats"] if s["prn"] == f["prn"]][0]
    fd = lambda t: -g.F_L1 * (g.light_time(eph, rx, t + 0.001) - g.light_time(eph, rx, t)) / 0.001 + fix.LO
    tau0 = g.light_time(eph, rx, t0)
    chip0 = ((t0 - tau0) % 1e-3) * g.F_CHIP
    print(f"PRN {f['prn']}: acq offset {f['code_offset']} -> chip {f['code_offset']*0.3125:.2f}, true chip at s0 {chip0:.2f}; f_fine {f['f_fine']} true {fd(t0):.1f}")
    ch = fix.Channel(f["prn"], f["code_offset"], f["f_fine"], x)
    for i in range(3000):
        ch.step()
    for e in (0, 50, 100, 200, 299, 400, 1000, 2000, 2999):
        S, cp, IP, QP, E, L, fr, cr, eph_ = ch.log[e]
        print(f"   ep {e}: f {fr:9.1f} (true {fd(t0 + S / g.FS):9.1f}) |P| {np.hypot(IP,QP):6.0f} I {IP:6d} Q {QP:6d} E {E:6.0f} L {L:6.0f} code_rate-1.023e6 {cr-1.023e6:7.2f}")
