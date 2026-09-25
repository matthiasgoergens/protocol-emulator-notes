# /// script
# requires-python = ">=3.11"
# dependencies = ["numpy", "scipy"]
# ///
"""Demo A: FM broadcast receive from one pin sampled at 240 MS/s, one bit per sample.

Transmitter (floating point, the "world"):
  a stereo-pilot FM broadcast: mono audio (a 1 kHz test tone, pre-emphasised), the 19 kHz pilot and
  RDS (57 kHz, 1187.5 bit/s, biphase, differentially encoded, real group 0A/2A data with a PS name
  and RadioText), frequency-modulated onto a carrier in 87.5-108 MHz; optionally other stations;
  thermal noise band-limited to the front end's band-pass filter; sampled by a comparator at
  240 MS/s (the four-phase input stage at a 60 MHz clock) whose clock may be off by some ppm.

Receivers, all on the same samples:
  pe     the chip: integer arithmetic only, every stage one of the generic PE's operations (see
         PE_OPS below and README.md): a 16-bit phase-accumulator NCO per lane, the nibble
         correlator (XOR with the LO quadrant bits and popcount, the one bit-level assist), a
         wrap-around CIC2 decimating by 60, a (1 + z^-1)^N channel filter with a halving shift,
         an octant discriminator built from two quadrature (rotary-encoder) decoders, CIC3 and a
         one-pole shift filter for audio, a 3-level 57 kHz LO and integrate-and-dump for RDS.
  ref    floating point on the same one-bit samples: exact complex LO, long FIR filters, atan2
         discriminator. Separates the loss due to the PE-friendly simplifications.
  ideal  the ref receiver on the unquantised analogue samples (an ideal linear ADC). Separates
         the loss due to one-bit sampling.
The RDS symbol back end (timing loop, differential detection, block sync, CRC) is shared and
integer-friendly: it is what a sequencer thread plus the programmable CRC assist would do.

Usage:  uv run fm_rx.py run --cnr 20 [--scenario single|multi] [--rel-db D] [--seconds 3]
        uv run fm_rx.py sweep            (writes results/fm_sweep.json and .txt)
"""
import argparse, json, math, pathlib, sys, time
import numpy as np
import scipy.signal as sg

HERE = pathlib.Path(__file__).parent
RES = HERE / "results"

CLK = 60e6                 # chip clock
FS = 4 * CLK               # four-phase input stage: 240 MS/s
FMPX = 1e6                 # transmitter's MPX simulation rate
CHUNK = 240 * 8192         # RF samples per chunk: divisible by 240
PS_NAME = "CLASS 95"
RADIOTEXT = "Tiny Tapeout IHP SG13G2: one pin, one bit, 240 MS/s, FM + RDS on a TV".ljust(64)[:64]
PI_CODE = 0xC0DE
PTY = 10

# ---------------------------------------------------------------------------------------------
# RDS encoder (IEC 62106): 26-bit blocks, CRC-10 g(x) = x^10+x^8+x^7+x^5+x^4+x^3+1, offset words
G_POLY = 0b10110111001
OFFSET = {"A": 0x0FC, "B": 0x198, "C": 0x168, "Cp": 0x350, "D": 0x1B4}


def crc10(m16):
    r = m16 << 10
    for i in range(25, 9, -1):
        if r >> i & 1:
            r ^= G_POLY << (i - 10)
    return r & 0x3FF


def block(m16, off):
    return (m16 << 10) | (crc10(m16) ^ OFFSET[off])


def groups():
    """An endless cycle of 0A (PS, 2 chars each) interleaved with 2A (RadioText, 4 chars each)."""
    ps = PS_NAME.encode("latin-1")
    rt = RADIOTEXT.encode("latin-1")
    k = 0
    while True:
        seg = k % 4
        b = (0 << 12) | (0 << 11) | (0 << 10) | (PTY << 5) | (0 << 4) | (1 << 3) | (0 << 2) | seg
        yield [block(PI_CODE, "A"), block(b, "B"), block(0xCDCD, "C"),
               block((ps[2 * seg] << 8) | ps[2 * seg + 1], "D")]
        seg2 = k % 16
        b = (2 << 12) | (0 << 11) | (0 << 10) | (PTY << 5) | (0 << 4) | seg2
        yield [block(PI_CODE, "A"), block(b, "B"),
               block((rt[4 * seg2] << 8) | rt[4 * seg2 + 1], "C"),
               block((rt[4 * seg2 + 2] << 8) | rt[4 * seg2 + 3], "D")]
        k += 1


def rds_bits(nbits):
    out = []
    for g in groups():
        for blk in g:
            out.extend((blk >> (25 - i)) & 1 for i in range(26))
        if len(out) >= nbits:
            return np.array(out[:nbits], dtype=np.int8)


def rds_baseband(nbits, fs, rng):
    """Shaped biphase symbols of the differentially encoded data, peak-normalised, at rate fs."""
    d = rds_bits(nbits)
    e = np.zeros(nbits, dtype=np.int8)
    prev = 0
    for i in range(nbits):
        prev = d[i] ^ prev
        e[i] = prev
    td = 1 / 1187.5
    n = int(math.ceil(nbits * td * fs)) + 1
    imp = np.zeros(n)
    for i in range(nbits):
        a = 1.0 if e[i] else -1.0
        t0 = i * td
        imp[int(round(t0 * fs))] += a
        imp[int(round((t0 + td / 2) * fs))] -= a
    # spectral shaping of IEC 62106: H(f) = cos(pi f td / 4) for f < 2/td, else 0
    L = int(2 * td * fs) | 1
    f = np.fft.rfftfreq(8 * L, 1 / fs)
    H = np.where(f < 2 / td, np.cos(np.pi * f * td / 4), 0.0)
    h = np.fft.irfft(H)
    h = np.roll(h, L // 2)[:L] * np.hanning(L)
    x = sg.oaconvolve(imp, h, mode="same")
    return x / np.max(np.abs(x)), d


# ---------------------------------------------------------------------------------------------
# the broadcast: MPX at 1 MS/s, integrated to phase

TAU = 75e-6        # pre-/de-emphasis: 75 us (Americas, Korea) because one shift gives it on the
                   # chip (EMA k = 3 at 100 kS/s is 74.9 us); 50 us would need a second shift term


def preemph(f, tau=TAU):
    h = 1 + 1j * 2 * np.pi * f * tau
    return abs(h), np.angle(h)


def station_mpx(seconds, rng, kind="test", tone_dev=22.5e3, rds_dev=3.0e3):
    n = int(seconds * FMPX) + 16
    t = np.arange(n) / FMPX
    if kind == "test":
        g, ph = preemph(1000.0)
        mono = np.sin(2 * np.pi * 1000.0 * t + ph) * g
        pilot = np.sin(2 * np.pi * 19e3 * t)
        nbits = int(seconds * 1187.5) + 2
        rds, bits = rds_baseband(nbits, FMPX, rng)
        rds = rds[:n] if len(rds) >= n else np.pad(rds, (0, n - len(rds)))
        sub57 = np.sin(3 * 2 * np.pi * 19e3 * t)
        mpx = tone_dev * mono + 6.75e3 * pilot + rds_dev * rds * sub57
        info = dict(bits=bits)
    else:  # another station: band-limited noise "programme" at 40 kHz rms deviation, plus pilot
        a = sg.lfilter(*sg.butter(4, 15e3, fs=FMPX), rng.standard_normal(n))
        a /= np.std(a)
        mpx = 40e3 * np.clip(a, -2, 2) / 1.0 + 6.75e3 * np.sin(2 * np.pi * 19e3 * t)
        info = {}
    phi = 2 * np.pi * np.cumsum(mpx) / FMPX
    return phi, info


class World:
    """Generates the comparator input chunk by chunk."""

    def __init__(self, seconds, cnr_db, stations, ppm, seed, comparator_offset=0.0, bpf=(87.5e6, 108e6)):
        self.rng = np.random.default_rng(seed)
        self.seconds = seconds
        self.stations = []
        for (fc, rel_db, kind) in stations:
            phi, info = station_mpx(seconds + 0.01, self.rng, kind)
            amp = 10 ** (rel_db / 20)
            self.stations.append(dict(fc=fc, amp=amp, phi=phi, info=info, kind=kind,
                                      ph0=self.rng.uniform(0, 1)))
        # noise: the target (first station, power amp^2/2) has cnr_db in 200 kHz
        tgt = self.stations[0]
        p_sig = tgt["amp"] ** 2 / 2
        n0 = p_sig / 10 ** (cnr_db / 10) / 200e3          # one-sided density, per Hz
        self.noise_rms = math.sqrt(n0 * (bpf[1] - bpf[0]))
        self.bpf = bpf
        self.fs_true = FS * (1 + ppm * 1e-6)                # the chip's real sample rate
        self.offset = comparator_offset
        self.n_total = int(seconds * FS) // CHUNK * CHUNK

    def chunk(self, k):
        n = np.arange(k * CHUNK, (k + 1) * CHUNK, dtype=np.int64)
        t = n / self.fs_true
        x = np.zeros(CHUNK)
        for s in self.stations:
            cyc = n * (s["fc"] / self.fs_true)
            frac = cyc - np.floor(cyc)
            phi = np.interp(t * FMPX, np.arange(len(s["phi"])), s["phi"])
            x += s["amp"] * np.cos(2 * np.pi * (frac + s["ph0"]) + phi)
        if self.noise_rms > 0:
            f = np.fft.rfftfreq(CHUNK, 1 / FS)
            band = (f >= self.bpf[0]) & (f <= self.bpf[1])
            spec = np.zeros(len(f), complex)
            m = int(band.sum())
            spec[band] = self.rng.standard_normal(m) + 1j * self.rng.standard_normal(m)
            w = np.fft.irfft(spec, CHUNK)
            w *= self.noise_rms / np.sqrt(np.mean(w ** 2))
            x += w
        return x


# ---------------------------------------------------------------------------------------------
# PE operations. Every integer stage of the "pe" receiver below is one of these, applied to a
# stream. W = 16-bit words. wrap16 is the W (wrap) extension; >> is the result-shift extension.

def wrap16(v):
    return ((v + 32768) & 0xFFFF) - 32768


class PEChain:
    """The chip's receiver, carrying state across chunks. Integers only."""

    def __init__(self, f_lo, n_chan=4, lo_offset_hz=0.0, lo="tri3"):
        self.lo = lo
        # NCO: per-sample increment in 1/65536 turns; four PEs hold the phases of lanes 0..3,
        # each advancing by 4*k per clock (wrap). Lane p starts at p*k.
        self.k = int(round((f_lo + lo_offset_hz) / FS * 65536)) & 0xFFFF
        self.f_lo_actual = self.k / 65536 * FS
        self.clk = 0                      # clocks elapsed
        self.i1 = np.zeros(2, np.int64)   # CIC integrator states (I, Q) stage 1, 2
        self.i2 = np.zeros(2, np.int64)
        self.c1 = np.zeros(2, np.int64)   # comb previous inputs
        self.c2 = np.zeros(2, np.int64)
        self.n_chan = n_chan
        self.chan_prev = np.zeros((n_chan, 2), np.int64)
        self.out = []

    def process(self, bits):
        """bits: bool array, CHUNK samples (a multiple of 240). Returns I, Q at 1 MS/s (int)."""
        nib = bits.reshape(-1, 4)
        ncl = nib.shape[0]
        c = np.arange(self.clk, self.clk + ncl, dtype=np.int64)
        self.clk += ncl
        # four NCO PEs: phase of lane p at clock c = (c*4k + p*k) mod 2^16
        ph = (c[:, None] * (4 * self.k) + np.arange(4)[None, :] * self.k) & 0xFFFF
        b15 = (ph >> 15) & 1
        b14 = (ph >> 14) & 1
        cos_neg = b15 ^ b14
        sin_neg = b15
        bb = nib.astype(np.int64)
        # nibble correlator assist: popcount of (sample XOR LO bit), minus 2: values -2..2
        if self.lo == "sq":
            # nibble correlator assist: popcount of (sample XOR LO bit), minus 2: values -2..2
            cI = np.sum(bb ^ cos_neg, axis=1) - 2
            cQ = np.sum(1 - (bb ^ sin_neg), axis=1) - 2
        else:
            # 3-level LO: the correlator also takes an enable per lane (LO zero for 22.5 degrees
            # either side of each zero crossing: phase sectors 3, 4, 11, 12 of 16 for the cosine),
            # which cuts the LO's 3rd harmonic from 1/3 to 0.14 of the fundamental. Sum -4..4.
            sec = ph >> 12
            lut_c = np.array([1, 1, 1, 0, 0, -1, -1, -1, -1, -1, -1, 0, 0, 1, 1, 1])
            lut_s = -np.roll(lut_c, 4)
            x = 2 * bb - 1
            cI = np.sum(x * lut_c[sec], axis=1)
            cQ = np.sum(x * lut_s[sec], axis=1)
        out = []
        for j, cx in enumerate((cI, cQ)):
            # CIC2, R = 60: two wrap integrators at 60 MHz (PE: s <- s + nbr), two combs at 1 MS/s
            # (PE: s <- nbr - pipe). int64 cumsum is exact modular arithmetic; wrap to 16 bits.
            a1 = np.cumsum(cx) + self.i1[j]
            self.i1[j] = a1[-1]
            a2 = np.cumsum(a1) + self.i2[j]
            self.i2[j] = a2[-1]
            d = wrap16(a2[59::60])
            prev = np.concatenate([[self.c1[j]], d[:-1]])
            self.c1[j] = d[-1]
            e = wrap16(d - prev)
            prev = np.concatenate([[self.c2[j]], e[:-1]])
            self.c2[j] = e[-1]
            f = wrap16(e - prev)
            out.append(f)
        I, Q = out
        if self.lo != "sq":
            I, Q = I >> 1, Q >> 1          # the last comb's result shift (H): keep CORDIC in 16 bits
        # channel filter: n_chan PEs, each s <- (nbr + pipe) >> 1  (floor shift)
        for s in range(self.n_chan):
            pI = np.concatenate([[self.chan_prev[s, 0]], I[:-1]])
            pQ = np.concatenate([[self.chan_prev[s, 1]], Q[:-1]])
            self.chan_prev[s] = (I[-1], Q[-1])
            I = (I + pI) >> 1
            Q = (Q + pQ) >> 1
        return I, Q


def octant_discriminator(I, Q):
    """Phase in 1/8 turns from two quadrature decoders (on z and on z rotated by -45 degrees).
    Each decoder is a PE with the flag LUT: s <- s + LUT(a, b, a_prev, b_prev), LUT in {-1,0,+1}.
    Returns delta[n] = phase[n] - phase[n-1] in octants (a PE comb)."""
    def decode(x, y):
        a = (x < 0).astype(np.int64)
        b = (y < 0).astype(np.int64)
        ap = np.concatenate([[a[0]], a[:-1]])
        bp = np.concatenate([[b[0]], b[:-1]])
        g = a ^ b
        da = a ^ ap
        db = b ^ bp
        step = (2 * g - 1) * (da - db)
        step[(da == 1) & (db == 1)] = 0            # a 180 degree jump is ambiguous: count nothing
        return step
    u = I + Q            # PE: s <- W + N   (saturating add; |u| <= 2*7200 fits)
    v = Q - I            # PE: s <- N - W
    return decode(I, Q) + decode(u, v)


def pe_audio_octant(delta, state):
    """Octant path only (spatial, no contexts): delta in octants per microsecond -> 50 kS/s.
    CIC3, R = 20: the first integrator is the discriminator's own phase count; two more wrap
    integrators and three combs; then de-emphasis, s <- s + ((x - s) >> 2) (tau about 70 us).
    One LSB of the output = 125 kHz / 8000 = 15.625 Hz of deviation."""
    x = np.cumsum(delta) + state["p0"]; state["p0"] = x[-1]
    x = np.cumsum(x) + state["p1"]; state["p1"] = x[-1]
    x = np.cumsum(x) + state["p2"]; state["p2"] = x[-1]
    d = wrap16(x[19::20])
    for k in ("q0", "q1", "q2"):
        prev = np.concatenate([[state[k]], d[:-1]])
        state[k] = d[-1]
        d = wrap16(d - prev)
    return ema(d, 2) * 15.625


# CORDIC vectoring, 16-bit: angle units of 1/65536 turn
CORDIC_N = 12
ATAN = [int(round(math.atan(2.0 ** -i) / (2 * math.pi) * 65536)) for i in range(CORDIC_N)]


def cordic_phase(I, Q, stats):
    """Per sample: one conditional negation (sign-select PE) into the right half plane, then
    CORDIC_N iterations, each three PE operations with the y-operand shift and the sign-select
    extensions:  x' = x + sgn(y) (y >> i),  y' = y - sgn(y) (x >> i),  z' = z + sgn(y) atan_i.
    All values 16-bit; |x| grows by 1.647, so inputs up to 7,200 stay below 16,800."""
    x = I.astype(np.int64).copy()
    y = Q.astype(np.int64).copy()
    neg = x < 0
    x[neg] = -x[neg]
    y[neg] = -y[neg]
    z = np.where(neg, 32768, 0).astype(np.int64)
    for i in range(CORDIC_N):
        sy = y >= 0
        xs = x >> i
        ys = y >> i
        x, y = np.where(sy, x + ys, x - ys), np.where(sy, y - xs, y + xs)
        z = np.where(sy, z + ATAN[i], z - ATAN[i])
    stats["cordic_x_max"] = int(max(stats.get("cordic_x_max", 0), int(np.abs(x).max())))
    return wrap16(z)


def ema(x, k, s0=0):
    """The EMA mode of the PE: s <- s + ((x - s) >> k), 16-bit state (arithmetic shift, floor)."""
    y = np.empty(len(x), np.int64)
    s = int(s0)
    xl = x.tolist()
    for i in range(len(xl)):
        s = s + ((xl[i] - s) >> k)
        y[i] = s
    return y


AUDIO_EMA = (4, 3)     # anti-alias before 100 kS/s: stages, shift (k = 3: poles near 21 kHz)


def pe_audio(delta, stats):
    """delta: phase differences at 1 MS/s, 1 LSB = 1e6/65536 = 15.26 Hz. Audio: shifted up by 2
    (so the EMA truncation sits at 3.8 Hz), two EMA stages with k = 2 (poles near 46 kHz: the
    anti-alias filter for 100 kS/s, where the pilot, L-R and RDS all alias outside 0-15 kHz),
    take every 10th sample (100 kS/s), de-emphasis EMA with k = 3 (tau 74.9 us). Returns Hz."""
    x = delta.astype(np.int64) << 2
    stats["audio_in_max"] = int(np.abs(x).max())
    for _ in range(AUDIO_EMA[0]):
        x = ema(x, AUDIO_EMA[1])
    x = x[9::10]
    x = ema(x, 3)
    return x * (1e6 / 65536 / 4)


def pe_rds(delta, stats, k57=None):
    """RDS on PEs at 1 MS/s: a 57 kHz NCO (16-bit wrap PE); two mixer-integrators, each
    s <- s + LUT(phase[15:12]) * (delta >> 1) with a 3-level LUT LO (+1, 0, -1; zero for 22.5
    degrees either side of each zero crossing, so the 3rd harmonic falls to 0.38 of a square
    wave's); integrate-and-dump every 53 samples (a wrap integrator and a comb at the dump rate).
    Returns complex int samples at 1e6/53 S/s; counts dumps whose true sum left 16 bits."""
    n = np.arange(len(delta), dtype=np.int64)
    kk = int(round(57e3 / 1e6 * 65536)) if k57 is None else k57
    ph = (n * kk) & 0xFFFF
    sec = ph >> 12
    lut_c = np.array([1, 1, 1, 0, 0, -1, -1, -1, -1, -1, -1, 0, 0, 1, 1, 1])
    lut_s = -np.roll(lut_c, 4)          # Q = -sin (e^{-j wt}); sine is the cosine delayed 90 deg
    d1 = delta.astype(np.int64) >> 1
    out = []
    ovf = 0
    for lut in (lut_c, lut_s):
        m = lut[sec] * d1
        a = np.cumsum(m)
        idx = np.arange(52, len(a), 53)
        true_sum = np.diff(np.concatenate([[0], a[idx]]))
        ovf += int(np.sum(np.abs(true_sum) > 32767))
        d = wrap16(a[idx])
        prev = np.concatenate([[0], d[:-1]])
        out.append(wrap16(d - prev))
    stats["rds_dump_overflows"] = ovf
    stats["rds_dump_peak"] = int(max(np.abs(out[0]).max(), np.abs(out[1]).max()))
    return out[0] + 1j * out[1]


# ---------------------------------------------------------------------------------------------
# floating-point reference receiver

class RefChain:
    def __init__(self, f_lo):
        self.f_lo = f_lo
        self.n = 0
        self.acc = []

    def process(self, x):
        n = np.arange(self.n, self.n + len(x))
        self.n += len(x)
        lo = np.exp(-2j * np.pi * ((n * (self.f_lo / FS)) % 1.0))
        z = x * lo
        # two cascaded boxcars (length 60 then decimate): a CIC2 in floating point -> 4 MS/s
        z = z.reshape(-1, 60).mean(axis=1)
        self.acc.append(z)

    def finish(self):
        z = np.concatenate(self.acc)            # 4 MS/s
        z = sg.resample_poly(z, 1, 4, window=("kaiser", 8.0))          # 1 MS/s
        h = sg.firwin(129, 110e3, fs=1e6)                             # channel filter
        z = sg.oaconvolve(z, h, mode="same")
        return z                                 # complex baseband, 1 MS/s


def ref_mpx(z):
    """atan2 discriminator, MPX in Hz at 1 MS/s."""
    return np.angle(z[1:] * np.conj(z[:-1])) * 1e6 / (2 * np.pi)


def ref_audio(mpx):
    a = sg.resample_poly(mpx, 1, 10)                 # 100 kS/s, with a proper anti-alias FIR
    a = sg.lfilter(*sg.butter(6, 15e3, fs=100e3), a)
    alpha = 1 - math.exp(-1 / (100e3 * TAU))
    return sg.lfilter([alpha], [1, -(1 - alpha)], a)


def ref_rds(mpx, f57=57e3):
    n = np.arange(len(mpx))
    bb = mpx * np.exp(-2j * np.pi * f57 * n / 1e6)
    h = sg.firwin(801, 2.4e3, fs=1e6)
    bb = sg.oaconvolve(bb, h, mode="same")
    return bb[::53]


# ---------------------------------------------------------------------------------------------
# RDS symbol back end (shared): biphase matched filter, timing loop, differential detection,
# block sync with CRC syndromes, PS and RadioText assembly.

def rds_backend(z, rate):
    """z: complex samples at `rate` (about 16 per bit). Returns decoded data bits (0/1)."""
    spb = rate / 1187.5
    h = int(round(spb / 2))                        # half-bit in samples (8)
    # biphase matched filter: sum of a half bit minus the next half bit; y[n] ends at sample n
    c = np.concatenate([[0], np.cumsum(z)])
    y = np.zeros(len(z), complex)
    idx = np.arange(2 * h, len(z) + 1)
    y_valid = (c[idx - h] - c[idx - 2 * h]) - (c[idx] - c[idx - h])
    y[idx - 1] = y_valid
    mag = np.abs(y.real) + np.abs(y.imag)          # |I| + |Q|: two abs PEs and an add
    # acquisition: choose the phase of the bit grid that maximises mean magnitude over the first
    # 64 bits (the firmware tries 16 offsets)
    nb0 = min(64, int(len(z) / spb) - 2)
    best, t = -1, 0.0
    for off in np.arange(0, spb, 1.0):
        pos = (off + np.arange(nb0) * spb).astype(int) + 2 * h
        pos = pos[pos < len(y)]
        m = mag[pos].mean()
        if m > best:
            best, t = m, off + 2 * h
    # tracking: early-late on the magnitude, +-1 sample per bit (the sequencer moves its deadline)
    q = h // 2
    syms = []
    while t + q + 1 < len(y):
        i = int(t)
        e = mag[i - q] if i - q >= 0 else 0
        l = mag[i + q]
        syms.append(y[i])
        t += spb + (0.25 if l > e else -0.25)
    s = np.array(syms)
    # differential detection against the sign of the previous symbol (no carrier recovery):
    # r_k = Re(z_k * conj(sgn(z_{k-1})))  -- two sign-select PEs and an add
    prev = np.concatenate([[1 + 1j], s[:-1]])
    sp = np.sign(prev.real) + 1j * np.sign(prev.imag)
    r = (s * np.conj(sp)).real
    return (r < 0).astype(np.int8)     # a phase flip between symbols is a 1


def syndrome_ok(word, off):
    m = word >> 10
    return (crc10(m) ^ (word & 0x3FF)) == OFFSET[off]


def rds_decode(bits, truth=None):
    """Block sync: find a bit position where two consecutive blocks carry offsets in sequence.
    Then check every following block. Returns stats and decoded PS / RT."""
    seq = ["A", "B", "C", "D"]
    n = len(bits)
    words = None
    b = bits.astype(np.int64)
    # 26-bit words starting at every bit
    pw = np.zeros(n - 25, np.int64)
    for i in range(26):
        pw = (pw << 1) | b[i:n - 25 + i]
    sync = None
    for i in range(0, len(pw) - 26):
        for j, o in enumerate(seq):
            if syndrome_ok(int(pw[i]), o) and syndrome_ok(int(pw[i + 26]), seq[(j + 1) % 4]):
                sync = (i, j)
                break
        if sync:
            break
    res = dict(sync_bit=None, blocks=0, block_errors=0, bler=1.0, ps=None, rt=None,
               ps_time_s=None, false_accepts=None)
    if sync is None:
        return res
    i0, j0 = sync
    res["sync_bit"] = i0
    ps = [None] * 8
    rt = [None] * 64
    nblk = (len(pw) - i0) // 26
    errs = 0
    cur = {}
    ps_done = None
    for k in range(nblk):
        w = int(pw[i0 + 26 * k])
        o = seq[(j0 + k) % 4]
        ok = syndrome_ok(w, o) or (o == "C" and syndrome_ok(w, "Cp"))
        if not ok:
            errs += 1
            cur[o] = None
        else:
            cur[o] = w >> 10
        if o == "D":
            B, C, D = cur.get("B"), cur.get("C"), cur.get("D")
            if B is not None:
                gt = B >> 12
                if gt == 0 and D is not None:
                    seg = B & 3
                    ps[2 * seg], ps[2 * seg + 1] = chr(D >> 8), chr(D & 0xFF)
                    if ps_done is None and all(p is not None for p in ps):
                        ps_done = (i0 + 26 * (k + 1)) / 1187.5
                if gt == 2:
                    seg = B & 15
                    if C is not None:
                        rt[4 * seg], rt[4 * seg + 1] = chr(C >> 8), chr(C & 0xFF)
                    if D is not None:
                        rt[4 * seg + 2], rt[4 * seg + 3] = chr(D >> 8), chr(D & 0xFF)
            cur = {}
    res["blocks"] = nblk
    res["block_errors"] = errs
    res["bler"] = errs / nblk if nblk else 1.0
    res["ps"] = "".join(p if p is not None else "_" for p in ps)
    res["rt"] = "".join(p if p is not None else "_" for p in rt)
    res["ps_time_s"] = ps_done
    if truth is not None:
        # align with the transmitted data bits to count blocks that passed the CRC but were wrong
        tb = truth.astype(np.int64)
        best = None
        for sh in range(-60, 60):
            a = b[max(0, sh):]
            t2 = tb[max(0, -sh):]
            L = min(len(a), len(t2), 3000)
            if L < 200:
                continue
            m = np.mean(a[:L] == t2[:L])
            if best is None or m > best[0]:
                best = (m, sh)
        res["bit_agreement"] = round(float(best[0]), 5)
        sh = best[1]
        fa = 0
        for k in range(nblk):
            i = i0 + 26 * k
            o = seq[(j0 + k) % 4]
            w = int(pw[i])
            if syndrome_ok(w, o) or (o == "C" and syndrome_ok(w, "Cp")):
                ti = i - sh
                if 0 <= ti and ti + 26 <= len(tb):
                    tw = 0
                    for q in range(26):
                        tw = (tw << 1) | int(tb[ti + q])
                    fa += tw != w
        res["false_accepts"] = fa
    return res


# ---------------------------------------------------------------------------------------------
# audio SINAD: least-squares fit of the 1 kHz tone after a 15 kHz band limit (as fm_sim.py)

def sinad(a, fs, skip_s=0.1, ftone=1000.0):
    a = np.asarray(a, float)[int(skip_s * fs):]
    L = int(len(a) // (fs / ftone) * (fs / ftone))
    a = a[:L]
    A = np.fft.rfft(a)
    f = np.fft.rfftfreq(len(a), 1 / fs)
    A[(f > 15e3) | (f < 30)] = 0
    a = np.fft.irfft(A, len(a))
    k = np.arange(len(a)) / fs
    M = np.stack([np.sin(2 * np.pi * ftone * k), np.cos(2 * np.pi * ftone * k)], 1)
    coef, *_ = np.linalg.lstsq(M, a, rcond=None)
    fit = M @ coef
    resid = a - fit
    return 10 * np.log10(np.mean(fit ** 2) / np.mean(resid ** 2)), float(np.sqrt(np.mean(fit ** 2)))


# ---------------------------------------------------------------------------------------------

SCEN = {
    # target first
    "single": lambda rel: [(95.0e6, 0.0, "test")],
    # a crowded band: the target rel dB below the strongest local station (100.3 MHz), with an
    # equally strong neighbour 400 kHz above it and four more stations across the band
    "multi": lambda rel: [(95.0e6, -rel, "test"), (100.3e6, 0.0, "prog"), (89.3e6, -3.0, "prog"),
                          (105.8e6, -5.0, "prog"), (92.4e6, -8.0, "prog"), (97.2e6, -12.0, "prog"),
                          (95.4e6, -rel, "prog")],
}


def run(cnr, scenario="single", rel=0.0, seconds=3.0, ppm=30.0, seed=1, n_chan=4, lo_offset=31.25e3, lo="tri3",
        receivers=("pe", "ref", "ideal"), keep=False):
    t0 = time.time()
    st = SCEN[scenario](rel)
    w = World(seconds, cnr, st, ppm, seed)
    tgt = w.stations[0]
    pe = PEChain(tgt["fc"], n_chan=n_chan, lo_offset_hz=lo_offset, lo=lo)
    ref = RefChain(tgt["fc"]) if "ref" in receivers else None
    ideal = RefChain(tgt["fc"]) if "ideal" in receivers else None
    I_all, Q_all = [], []
    nch = w.n_total // CHUNK
    ones = 0
    for k in range(nch):
        x = w.chunk(k)
        bits = x > w.offset
        ones += int(bits.sum())
        if "pe" in receivers:
            I, Q = pe.process(bits)
            I_all.append(I); Q_all.append(Q)
        if ref is not None:
            ref.process(np.where(bits, 1.0, -1.0))
        if ideal is not None:
            ideal.process(x)
    out = dict(cnr_db=cnr, scenario=scenario, rel_db=rel, seconds=seconds, ppm=ppm, seed=seed,
               n_chan=n_chan, lo_offset_hz=lo_offset, lo=lo, ones_fraction=ones / w.n_total,
               antenna_dbm_nf3=round(cnr - 174 + 10 * math.log10(200e3) + 3, 1))
    truth = tgt["info"]["bits"]
    ftone = 1000.0 / (1 + ppm * 1e-6)     # the tone as the chip's (fast) clock sees it
    keepd = {}
    if "pe" in receivers:
        I = np.concatenate(I_all); Q = np.concatenate(Q_all)
        stats = dict(iq_rms=round(float(np.sqrt(np.mean(I.astype(float) ** 2 + Q.astype(float) ** 2))), 1),
                     iq_peak=int(max(np.abs(I).max(), np.abs(Q).max())))
        # (a) spatial minimum: octant discriminator, audio only
        d8 = octant_discriminator(I, Q)
        aud8 = pe_audio_octant(d8, dict(p0=0, p1=0, p2=0, q0=0, q1=0, q2=0))
        s8, _ = sinad(aud8, 50e3, ftone=ftone)
        z8 = pe_rds((d8 * 8192).astype(np.int64), {})
        r8 = rds_decode(rds_backend(z8.astype(complex), 1e6 / 53), truth)
        out["pe_octant"] = dict(sinad_db=round(s8, 2), rds=r8)
        # (b) CORDIC discriminator (context PE)
        phi = cordic_phase(I, Q, stats)
        delta = wrap16(np.diff(np.concatenate([[phi[0]], phi])))
        aud = pe_audio(delta, stats)
        s, rms = sinad(aud, 100e3, ftone=ftone)
        zr = pe_rds(delta, stats)
        bits = rds_backend(zr.astype(complex), 1e6 / 53)
        r = rds_decode(bits, truth)
        out["pe"] = dict(sinad_db=round(s, 2), tone_rms_hz=round(rms, 1), rds=r, stats=stats)
        if keep:
            keepd["pe_audio"] = aud
            keepd["pe_delta"] = delta
    for name, ch in (("ref", ref), ("ideal", ideal)):
        if ch is None:
            continue
        z = ch.finish()
        mpx = ref_mpx(z)
        aud = ref_audio(mpx)
        s, rms = sinad(aud, 100e3, ftone=ftone)
        zr = ref_rds(mpx)
        bits = rds_backend(zr, 1e6 / 53)
        r = rds_decode(bits, truth)
        out[name] = dict(sinad_db=round(s, 2), tone_rms_hz=round(rms, 1), rds=r)
    out["wall_s"] = round(time.time() - t0, 1)
    if keep:
        return out, keepd, w
    return out


def fmt(o):
    parts = [f"{o['scenario']:6s} cnr {o['cnr_db']:5.1f} dB rel {o['rel_db']:5.1f} dB"]
    for k in ("pe_octant", "pe", "ref", "ideal"):
        if k in o and k == "pe_octant":
            parts.append(f"octant: SINAD {o[k]['sinad_db']:6.1f} BLER {o[k]['rds']['bler']:.3f}")
            continue
        if k in o:
            r = o[k]["rds"]
            parts.append(f"{k}: SINAD {o[k]['sinad_db']:6.1f} dB BLER {r['bler']:.3f} ({r['block_errors']}/{r['blocks']}) PS '{r['ps']}'")
    return " | ".join(parts)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd", choices=["run", "sweep"])
    ap.add_argument("--cnr", type=float, default=30.0)
    ap.add_argument("--scenario", default="single")
    ap.add_argument("--rel-db", type=float, default=0.0)
    ap.add_argument("--seconds", type=float, default=3.0)
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--n-chan", type=int, default=4)
    ap.add_argument("--lo-offset", type=float, default=31.25e3)
    ap.add_argument("--lo", default="tri3")
    ap.add_argument("--receivers", default="pe,ref,ideal")
    ap.add_argument("--out", default=None)
    a = ap.parse_args()
    RES.mkdir(exist_ok=True)
    if a.cmd == "run":
        o = run(a.cnr, a.scenario, a.rel_db, a.seconds, seed=a.seed, n_chan=a.n_chan,
                lo_offset=a.lo_offset, lo=a.lo, receivers=tuple(a.receivers.split(",")))
        print(fmt(o))
        print(json.dumps(o, indent=1))
        if a.out:
            pathlib.Path(a.out).write_text(json.dumps(o, indent=1))
    else:
        sweep()


SWEEP = [("single", c, 0.0) for c in (6, 9, 12, 15, 18, 21, 24, 27, 30, 40)] + \
        [("multi", 30.0, r) for r in (0, 10, 20, 30, 40)]


def sweep(seconds=3.0):
    """Every configuration of SWEEP, appended as JSON lines to results/fm_sweep.jsonl (resumable),
    then the table in results/fm_sweep.txt."""
    path = RES / "fm_sweep.jsonl"
    done = set()
    if path.exists():
        for line in path.read_text().splitlines():
            o = json.loads(line)
            done.add((o["scenario"], o["cnr_db"], o["rel_db"]))
    for sc, c, r in SWEEP:
        if (sc, float(c), float(r)) in done:
            continue
        o = run(float(c), sc, float(r), seconds)
        print(fmt(o), flush=True)
        with path.open("a") as f:
            f.write(json.dumps(o) + "\n")
    table()


def table():
    rows = [json.loads(l) for l in (RES / "fm_sweep.jsonl").read_text().splitlines()]
    L = ["Demo A sweep (fm_rx.py sweep). SINAD: 1 kHz tone at 22.5 kHz deviation, 75 us",
         "pre-emphasis, 15 kHz band. BLER: RDS blocks failing the CRC after block sync (1.000 = never",
         "synchronised). CNR: target carrier to noise in 200 kHz; antenna level assumes 3 dB noise figure.",
         "multi: 7 stations, target 'rel' dB below the strongest, an equal neighbour 400 kHz away, CNR 30 dB.",
         "",
         f"{'scen':6s} {'CNR':>4s} {'rel':>4s} {'dBm':>6s} | {'octant':>6s} | {'pe SINAD':>8s} {'BLER':>6s} {'PS s':>5s} | "
         f"{'ref SINAD':>9s} {'BLER':>6s} | {'ideal SINAD':>11s} {'BLER':>6s} | pe PS / overflows"]
    for o in rows:
        pe, rf, idl, oc = o["pe"], o["ref"], o["ideal"], o["pe_octant"]
        pst = pe["rds"]["ps_time_s"]
        L.append(f"{o['scenario']:6s} {o['cnr_db']:4.0f} {o['rel_db']:4.0f} {o['antenna_dbm_nf3']:6.1f} | "
                 f"{oc['sinad_db']:6.1f} | {pe['sinad_db']:8.1f} {pe['rds']['bler']:6.3f} "
                 f"{(f'{pst:5.2f}' if pst else '    -')} | {rf['sinad_db']:9.1f} {rf['rds']['bler']:6.3f} | "
                 f"{idl['sinad_db']:11.1f} {idl['rds']['bler']:6.3f} | '{pe['rds']['ps']}' "
                 f"{pe['stats']['rds_dump_overflows']} fa={pe['rds']['false_accepts']}")
    (RES / "fm_sweep.txt").write_text("\n".join(L) + "\n")
    print("\n".join(L))


if __name__ == "__main__":
    main()
