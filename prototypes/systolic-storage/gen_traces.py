"""Value-interval traces from two video kernels, as faithful models of the prototypes' timing.

uv run gen_traces.py        -> traces/linebuf-P{3,5,20}.csv, traces/vfir{2,3}.csv

Row format (all times in cycles at 50 MHz):  kernel,loc,width,value,t_def,t_last

linebuf: the Ethernet-fed line buffer in front of the semiring ring (prototypes/pal-ethernet
  README: "a line number plus 48-byte ring initialisations, about 20 lines per packet";
  prototypes/semiring-ring: the ring loads 48 bytes per visible line during blanking).
  10 Mbit/s, one byte every 0.8 us. P lines per UDP packet; the host aims to finish each packet a
  margin M before its first line is loaded, starting up to J earlier at random (host jitter), and
  packets never overlap on the wire. Each 32-bit word is defined when its last byte arrives and
  used once, when its line is loaded at the start of that line. PAL timing: 64 us lines, 312 lines
  per field, visible lines 40..279 (semiring-ring/model.ml: lpf, first_vis, nvis).
  P = 1 and 2 cannot keep up: 116 or 164 bytes on the wire per 64 or 128 us of lines.

vfir: a vertical k-tap filter on 256 x 8-bit pixels at 10 clocks per pixel (the retro console's
  pixel rate), as a systolic array consuming lines as they are generated. Each 32-bit word of four
  pixels is defined when its fourth pixel is produced and read at the same x in each of the next
  k-1 lines.
"""
import csv, os, random

CLK = 50e6
LINE = 3200                 # 64 us at 50 MHz
LPF, FIRST_VIS, NVIS = 312, 40, 240
BYTE = 0.8e-6 * CLK         # cycles per byte at 10 Mbit/s = 40
HDR = 8 + 14 + 20 + 8       # preamble+SFD, Ethernet, IPv4, UDP headers (bytes)
TAIL = 4 + 12               # FCS + inter-frame gap
FIELDS = 2
VIS_OFF = 662 * 50 // 53    # visible start within the line, scaled from vis_start = 662 at 53.2 MHz


def visible_lines():
    for f in range(FIELDS):
        for y in range(FIRST_VIS, FIRST_VIS + NVIS):
            yield f * LPF + y


def linebuf(P, margin_us=100.0, jitter_us=200.0, seed=1):
    rng = random.Random(seed)
    lines = list(visible_lines())
    rows, wire_free, late = [], 0.0, 0
    for k in range(0, len(lines), P):
        group = lines[k:k + P]
        nbytes = HDR + 2 + 48 * len(group) + TAIL
        dur = nbytes * BYTE
        deadline = group[0] * LINE
        start = deadline - margin_us * 50 - dur - rng.uniform(0, jitter_us * 50)
        start = max(start, wire_free)
        wire_free = start + dur
        if wire_free - TAIL * BYTE > deadline:
            late += 1
        for i, ln in enumerate(group):
            for j in range(12):
                arrive = start + (HDR + 2 + 48 * i + 4 * (j + 1)) * BYTE
                rows.append(("linebuf", f"L{ln}.w{j}", 32, rng.getrandbits(32),
                             int(arrive), ln * LINE))
    return rows, late


def vfir(k, seed=2):
    rng = random.Random(seed)
    rows = []
    for ln in visible_lines():
        for w in range(64):
            t_def = ln * LINE + VIS_OFF + 10 * (4 * w + 3) + 1
            last_line = ln + k - 1
            if (last_line % LPF) >= FIRST_VIS + NVIS or last_line // LPF >= FIELDS:
                continue  # no later visible line reads it
            t_last = last_line * LINE + VIS_OFF + 10 * (4 * w)
            rows.append((f"vfir{k}", f"L{ln}.w{w}", 32, rng.getrandbits(32), t_def, t_last))
    return rows


def write(path, rows):
    with open(path, "w", newline="") as f:
        wr = csv.writer(f)
        wr.writerow(["kernel", "loc", "width", "value", "t_def", "t_last"])
        wr.writerows(rows)


def main():
    os.makedirs("traces", exist_ok=True)
    for P in (3, 5, 20):
        rows, late = linebuf(P)
        write(f"traces/linebuf-P{P}.csv", rows)
        lens = [r[5] - r[4] for r in rows]
        print(f"linebuf P={P:2d}: {len(rows)} words, late packets {late}, "
              f"interval min {min(lens)/50:.1f} us max {max(lens)/50:.1f} us")
    for k in (2, 3):
        rows = vfir(k)
        write(f"traces/vfir{k}.csv", rows)
        lens = [r[5] - r[4] for r in rows]
        print(f"vfir{k}: {len(rows)} words, interval min {min(lens)/50:.1f} us max {max(lens)/50:.1f} us")


if __name__ == "__main__":
    main()
