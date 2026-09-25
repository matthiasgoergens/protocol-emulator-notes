# 100BASE-TX receive channel model: the RTL transmitter's MLT-3 line (from `main.exe txgen`)
# through magnetics, Cat5e cable, an optional passive equaliser and two CMOS input pads used as
# slicers, sampled n = 2 x osr times per 16 ns clock. Writes the sampled levels for
# `main.exe txrx` and prints eye openings. Run: uv run --with numpy python3 tx_channel.py ...
#
# Model, and what it leaves out:
# - transmitter: the MLT-3 levels with amplitude A (V peak, differential, into 100 ohm) and a
#   Gaussian edge of 10-90 % rise time TR (from the pad simulation, spice/eye_tx);
# - magnetics: a first-order high-pass per transformer, 350 uH against 50 ohm (22.7 kHz), which
#   is what makes baseline wander;
# - cable: Cat5e insertion loss per TIA-568 (dB per 100 m) 1.967 sqrt(f) + 0.023 f + 0.05/sqrt(f),
#   f in MHz; the sqrt(f) term as exp(-k sqrt(j f)) so that it is causal, the other two as
#   magnitude only; no crosstalk, no return loss, no noise other than NOISE (V rms, white);
# - equaliser: a passive RC shelf (1 + j f/fz) / (1 + j f/fp) x fz/fp, flat above fp;
# - receive magnetics ratio G (1 for a normal MagJack, 2 for an extra 1:2 transformer) and the
#   centre tap biased so each pad sits DELTA = G x TH / 2 below its switching threshold: pad P
#   switches when the line is above +TH, pad N when it is below -TH;
# - each IOPadIn as a slicer with a dead zone +-VMIN around its threshold (it needs that much
#   overdrive to toggle at 62.5 MHz: spice/in_ac shows +-75 mV fails at tt 27 C, +-150 mV fails at
#   ss, +-300 mV works everywhere) and a threshold offset DP / DN (V) from the bias point
#   (the pad threshold varies 0.55-0.63 V over corners and temperature);
# - sampling at n per clock, clock 16 ns x (1 + PPM), Gaussian sampling jitter RJ (ns rms).
import sys, numpy as np

def arg(name, default):
    for a in sys.argv[1:]:
        if a.startswith(name + "="):
            return type(default)(a.split("=", 1)[1])
    return default

LINE = arg("line", "/var/tmp/fast-eth/tx/stream.line")
OUT = arg("out", "/var/tmp/fast-eth/tx/samples.txt")
LEN = arg("len", 1.0)          # cable metres
EQ = arg("eq", "none")         # none | shelf
FZ = arg("fz", 3.0)            # MHz, equaliser zero
FP = arg("fp", 60.0)           # MHz, equaliser pole
A = arg("amp", 1.0)
TR = arg("tr", 2.0)            # ns
G = arg("g", 1.0)
TH = arg("th", 0.5)            # V differential, slicer threshold (before G)
VMIN = arg("vmin", 0.1)
DP = arg("dp", 0.0)
DN = arg("dn", 0.0)
OSR = arg("osr", 4)
PPM = arg("ppm", 0.0)
RJ = arg("rj", 0.2)
NOISE = arg("noise", 0.005)
SEED = arg("seed", 1)
SUB = 32                        # fine samples per UI
UI = 8.0

rng = np.random.default_rng(SEED)
chars = open(LINE).read().strip()
lv = np.frombuffer(chars.encode(), dtype=np.uint8)
levels = np.where(lv == ord('+'), 1.0, np.where(lv == ord('-'), -1.0, 0.0))
nui = len(levels)
dt = UI / SUB
x = np.repeat(levels, SUB) * A
N = len(x)
nfft = 1 << int(np.ceil(np.log2(N + 4096)))
f = np.fft.rfftfreq(nfft, d=dt * 1e-9) / 1e6          # MHz
jf = 1j * np.maximum(f, 1e-9)
H = np.ones_like(jf)
# transmit edge: Gaussian with 10-90 % rise TR
sig = TR / 2.563
H = H * np.exp(-0.5 * (2 * np.pi * f * 1e6 * sig * 1e-9) ** 2)
# two transformers, 22.7 kHz high-pass each
fc = 50.0 / (2 * np.pi * 350e-6) / 1e6
H = H * (jf / (jf + fc)) ** 2
# cable
L = LEN / 100.0
k1 = 1.967 / 8.686 * np.sqrt(2)
fs = np.maximum(f, 1e-6)
H = H * np.exp(-L * k1 * np.sqrt(jf)) * 10 ** (-L * (0.023 * fs + 0.05 / np.sqrt(fs)) / 20)
if EQ == "shelf":
    H = H * (1 + jf / FZ) / (1 + jf / FP) * (FZ / FP)
    H = H / np.abs(H[np.argmin(np.abs(f - 30.0))]) * np.abs(np.exp(-L * k1 * np.sqrt(1j * 30.0)))  # keep 30 MHz gain as the cable's
y = np.fft.irfft(np.fft.rfft(x, nfft) * H, nfft)[:N]
y = y + NOISE * rng.standard_normal(N)

# eye openings at the best sampling phase (known levels, after 20 000 UI of start-up)
start = 20000
best = None
delay_ui = 0
for ph in range(SUB):
    idx = np.arange(start, nui - 2) * SUB + ph
    v = y[idx]
    lvl = levels[start:nui - 2]
    if not ((lvl == 1).any() and (lvl == -1).any()):
        continue
    up = v[lvl == 1].min() - v[lvl == 0].max()
    lo = v[lvl == 0].min() - v[lvl == -1].max()
    # also against the slicer thresholds: margins of each level to TH
    m = min(v[lvl == 1].min() - TH, TH - v[lvl == 0].max(), v[lvl == 0].min() + TH, -TH - v[lvl == -1].max())
    if best is None or m > best[3]:
        best = (ph, up, lo, m)
ph, up, lo, m = best
print(f"len {LEN} m eq {EQ} amp {A} tr {TR} | best phase {ph * dt:.2f} ns: eye upper {1000*up:.0f} mV lower {1000*lo:.0f} mV, "
      f"worst margin to +-{TH} V thresholds {1000*m:.0f} mV")

# slicers with dead zone, evaluated on the fine grid (state machine), then sampled
vp = G * y / 2 - G * TH / 2 - DP          # pad P input minus its threshold
vn = -G * y / 2 - G * TH / 2 - DN         # pad N
def slicer(v):
    out = np.zeros(len(v), dtype=np.int8)
    s = 0
    # vectorised hysteresis: positions where the state is forced
    force = np.where(v > VMIN, 1, np.where(v < -VMIN, 0, -1)).astype(np.int8)
    # forward fill of the last forced value
    idx = np.where(force >= 0, np.arange(len(v)), 0)
    np.maximum.accumulate(idx, out=idx)
    out = force[idx]
    out[out < 0] = 0
    return out
P = slicer(vp)
Nn = slicer(vn)
level = P.astype(np.int8) - Nn.astype(np.int8)
# sampling: n per clock, jittered
n = 2 * OSR
tclk = 16.0 * (1 + PPM * 1e-6)
tend = (N - SUB) * dt
ns = int(tend / tclk * n) - 2
t = 0.37 + np.arange(ns) * (tclk / n) + RJ * rng.standard_normal(ns)
t = np.clip(t, 0, tend)
si = np.clip(np.round(t / dt).astype(np.int64), 0, N - 1)
smp = level[si]
open(OUT, "w").write(''.join(np.where(smp > 0, '+', np.where(smp < 0, '-', '0'))))
# how often the two slicers both fire (should be never)
print(f"samples {ns}, both-slicer conflicts {int(((P == 1) & (Nn == 1)).sum())}")
