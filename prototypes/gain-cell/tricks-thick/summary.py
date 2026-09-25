# Worst-case lifetime (over tt/ff/ss x 27/85 C) of each combination, by life.py, for an inverter
# read at 10 and 20 ns and a latch with a matched reference column (fixed reference, margin VM)
# at 5 and 20 ns. Usage (in results/): python3 ../summary.py [VM]
import re, subprocess, sys
VM = sys.argv[1] if len(sys.argv) > 1 else "0.07"
rows = [
    ("thin MS (today's cell)", "read-lv.txt", "ret-lv-base.txt"),
    ("thin MS + CSN 1 fF", "read-lv.txt", "ret-lv-csn1.txt"),
    ("thin MS + WWL 2.0 V", "read-lv.txt", "ret-lv-wwl2.0.txt"),
    ("thin MS + WWL 2.2 V", "read-lv.txt", "ret-lv-wwl2.2.txt"),
    ("thin MS + WWL 2.2 V + CSN 1 fF", "read-lv.txt", "ret-lv-wwl2.2-csn1.txt"),
    ("thin MS + CC 0.25 fF", "read-lv-cc0.25.txt", "ret-lv-csn0.25.txt"),
    ("thin MS + CC 0.5 fF", "read-lv-cc0.5.txt", "ret-lv-csn0.5.txt"),
    ("thick MS, thin MR", "read-hv-lvMR.txt", "ret-hv-base.txt"),
    ("all thick", "read-hv-hvMR.txt", "ret-hv-base.txt"),
    ("all thick + CSN 1 fF", "read-hv-hvMR.txt", "ret-hv-csn1.txt"),
    ("all thick + WBL idle 0.6", "read-hv-hvMR.txt", "ret-hv-base-wblhalf.txt"),
    ("all thick + CC 0.5 fF", "read-hv-hvMR-cc0.5.txt", "ret-hv-csn0.5.txt"),
    ("all thick + CC 1 fF", "read-hv-hvMR-cc1.txt", "ret-hv-csn1.txt"),
    ("all thick + WWL 1.6 V", "read-hv-hvMR.txt", "ret-hv-wwl1.6.txt"),
    ("all thick + WWL 2.0 V", "read-hv-hvMR.txt", "ret-hv-wwl2.0.txt"),
    ("all thick + WWL 2.2 V", "read-hv-hvMR.txt", "ret-hv-wwl2.2.txt"),
    ("all thick + WWL 2.4 V", "read-hv-hvMR.txt", "ret-hv-wwl2.4.txt"),
    ("all thick + WWL 2.2 V + WBL 0.6", "read-hv-hvMR.txt", "ret-hv-wwl2.2-wblhalf.txt"),
    ("all thick + WWL 2.2 V + CSN 0.5 fF", "read-hv-hvMR.txt", "ret-hv-wwl2.2-csn0.5.txt"),
    ("all thick + WWL 2.2 V + CSN 1 fF", "read-hv-hvMR.txt", "ret-hv-wwl2.2-csn1.txt"),
    ("all thick + WWL 2.2 V + CSN 1 fF + WBL 0.6", "read-hv-hvMR.txt", "ret-hv-wwl2.2-csn1-wblhalf.txt"),
    ("thick MS thin MR + WWL 2.2 V", "read-hv-lvMR.txt", "ret-hv-wwl2.2.txt"),
    ("all thick + CC 0.5 fF + WBL idle 0", "read-hv-hvMR-cc0.5.txt", "ret-hv-csn0.5-wbl0.txt"),
    ("all thick + WWL 2.2 V + CC 0.5 fF", "read-hv-hvMR-cc0.5.txt", "ret-hv-wwl2.2-csn0.5.txt"),
    ("all thick + WWL 2.2 V + CC 0.5 fF + WBL idle 0", "read-hv-hvMR-cc0.5.txt", "ret-hv-wwl2.2-csn0.5-wbl0.txt"),
    ("all thick + WWL 2.2 V + CSN 1 fF + WBL idle 0", "read-hv-hvMR.txt", "ret-hv-wwl2.2-csn1-wbl0.txt"),
]
print(f"worst-case lifetime (ms) and corner; latch margin {float(VM) * 1e3:.0f} mV each side")
print(f"{'cell':48s} {'inv 10 ns':>18s} {'inv 20 ns':>18s} {'latch 5 ns':>18s} {'latch 20 ns':>18s}")
for label, rd, rt in rows:
    cols = []
    for t, kind in ((10, "inverter"), (20, "inverter"), (5, "fixed reference"), (20, "fixed reference")):
        try:
            out = subprocess.run(["python3", "../life.py", rd, rt, str(t), VM], capture_output=True, text=True).stdout
            m = [l for l in out.splitlines() if l.startswith(kind) or kind in l.split(":")[0]]
            w = re.search(r"worst (>?[\d.]+) ms at mos_(\w+) (\d+)C", m[0])
            cols.append(f"{w[1]:>9s} {w[2]}{w[3]:>3s}")
        except Exception:
            cols.append(f"{'n/a':>18s}")
    print(f"{label:48s} " + " ".join(f"{c:>18s}" for c in cols), flush=True)
